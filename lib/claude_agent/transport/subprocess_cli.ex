defmodule ClaudeAgent.Transport.SubprocessCli do
  @moduledoc """
  Transport implementation using Claude Code CLI subprocess.

  This transport spawns the Claude Code CLI as a subprocess and
  communicates via JSON over stdin/stdout.

  ## Features

  - Automatic CLI discovery (bundled, PATH, common locations)
  - JSON message buffering and parsing
  - Stderr handling with optional callback
  - Configurable buffer size limits
  """

  @behaviour ClaudeAgent.Transport

  require Logger

  alias ClaudeAgent.Errors.{CLIConnectionError, CLINotFoundError, JSONDecodeError, ProcessError}
  alias ClaudeAgent.Options

  @default_max_buffer_size 1024 * 1024
  @minimum_cli_version "2.0.0"
  # 5 minutes
  @default_read_timeout 300_000

  # Platform-specific command line length limits
  # Windows cmd.exe has a limit of 8191 characters, use 8000 for safety
  # Other platforms have much higher limits
  @cmd_length_limit if :os.type() == {:win32, :nt}, do: 8000, else: 100_000

  defstruct [
    :prompt,
    :options,
    :port,
    :cli_path,
    :cwd,
    :buffer,
    :owner_pid,
    ready: false,
    max_buffer_size: @default_max_buffer_size,
    temp_files: []
  ]

  @type t :: %__MODULE__{
          prompt: String.t() | nil,
          options: Options.t(),
          port: port() | nil,
          cli_path: String.t(),
          cwd: String.t() | nil,
          buffer: String.t(),
          ready: boolean(),
          max_buffer_size: pos_integer(),
          owner_pid: pid() | nil,
          temp_files: [String.t()]
        }

  @doc """
  Create a new SubprocessCli transport.

  ## Options

  - `:prompt` - The initial prompt (string or nil for streaming mode)
  - `:options` - ClaudeAgent.Options struct

  ## Examples

      transport = SubprocessCli.new("What is 2+2?", %Options{})
      {:ok, transport} = SubprocessCli.connect(transport)
  """
  @spec new(String.t() | nil, Options.t()) :: t()
  def new(prompt, %Options{} = options) do
    cli_path = options.cli_path || find_cli()

    %__MODULE__{
      prompt: prompt,
      options: options,
      cli_path: cli_path,
      cwd: options.cwd,
      buffer: "",
      max_buffer_size: options.max_buffer_size || @default_max_buffer_size
    }
  end

  @impl true
  def connect(%__MODULE__{} = transport) do
    unless System.get_env("CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK") do
      check_cli_version(transport.cli_path)
    end

    {args, temp_files} = build_command(transport)

    # On Unix systems, wrap CLI with 'script' to allocate a PTY when using --print mode.
    # The Claude CLI requires a TTY to properly write to stdout in print mode.
    # In streaming mode (--input-format stream-json), PTY is NOT needed and causes issues.
    {executable, final_args} = wrap_with_pty(transport, args)
    port_opts = build_port_options(transport, executable, final_args)

    try do
      port = Port.open({:spawn_executable, executable}, port_opts)

      {:ok, %{transport | port: port, ready: true, owner_pid: self(), temp_files: temp_files}}
    rescue
      e in ErlangError ->
        # Clean up temp files on error
        cleanup_temp_files(temp_files)

        case e.original do
          :enoent ->
            if transport.cwd && !File.dir?(transport.cwd) do
              {:error,
               CLIConnectionError.exception("Working directory does not exist: #{transport.cwd}")}
            else
              {:error,
               CLINotFoundError.exception(
                 message: "Claude Code not found",
                 cli_path: transport.cli_path
               )}
            end

          reason ->
            {:error,
             CLIConnectionError.exception("Failed to start Claude Code: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def write(%__MODULE__{ready: false}, _data) do
    {:error, CLIConnectionError.exception("Transport is not ready for writing")}
  end

  def write(%__MODULE__{port: nil}, _data) do
    {:error, CLIConnectionError.exception("Transport is not connected")}
  end

  def write(%__MODULE__{port: port}, data) when is_binary(data) do
    # Note: We don't enforce owner_pid check here because the QueryHandler
    # GenServer legitimately needs to write to the port from a different process
    # than the one that created the transport.
    try do
      Port.command(port, data)
      :ok
    rescue
      ArgumentError ->
        {:error, CLIConnectionError.exception("Failed to write to process: port closed")}
    end
  end

  @impl true
  def read_messages(%__MODULE__{port: nil}) do
    Stream.resource(
      fn -> :not_connected end,
      fn _ -> {:halt, :not_connected} end,
      fn _ -> :ok end
    )
  end

  def read_messages(%__MODULE__{} = transport) do
    Stream.resource(
      fn -> {transport, ""} end,
      &receive_next/1,
      fn _ -> :ok end
    )
  end

  defp receive_next({%__MODULE__{port: port, max_buffer_size: max_size} = transport, buffer}) do
    receive do
      {^port, {:data, data}} ->
        new_buffer = buffer <> IO.iodata_to_binary(data)

        if byte_size(new_buffer) > max_size do
          raise JSONDecodeError,
            message: "JSON message exceeded maximum buffer size of #{max_size} bytes",
            line: String.slice(new_buffer, 0, 100),
            original_error: nil
        end

        {messages, remaining} = parse_json_lines(new_buffer)
        {messages, {transport, remaining}}

      {^port, {:exit_status, 0}} ->
        # Process exited successfully
        {:halt, {transport, buffer}}

      {^port, {:exit_status, code}} ->
        # Process exited with error
        raise ProcessError,
          message: "Command failed",
          exit_code: code,
          stderr: "Check stderr output for details"

      {:EXIT, ^port, reason} ->
        Logger.debug("Port exited: #{inspect(reason)}")
        {:halt, {transport, buffer}}
    after
      # Timeout configurable via env var (default 5 minutes)
      get_read_timeout() ->
        {:halt, {transport, buffer}}
    end
  end

  defp get_read_timeout do
    case System.get_env("CLAUDE_CODE_STREAM_CLOSE_TIMEOUT") do
      nil ->
        @default_read_timeout

      value ->
        case Integer.parse(value) do
          {timeout, ""} when timeout > 0 -> timeout
          _ -> @default_read_timeout
        end
    end
  end

  # Parse JSON messages from buffer using speculative parsing.
  # The CLI outputs JSON objects separated by newlines, but lines can be truncated
  # across Port data chunks. We split on newlines first, but if parsing fails,
  # we accumulate the line into the buffer for the next chunk.
  # Returns {parsed_messages, remaining_buffer}
  defp parse_json_lines(data) do
    lines = String.split(data, "\n")

    case List.pop_at(lines, -1) do
      {"", lines} ->
        # Trailing newline - all lines are complete
        parse_complete_lines(lines, [], "")

      {partial, lines} ->
        # Last line is incomplete - keep it in buffer
        parse_complete_lines(lines, [], partial)
    end
  end

  # Parse lines that should be complete (have trailing newline)
  # If parsing fails, we accumulate into the remaining buffer
  # to handle the case where a single JSON object spans multiple lines
  defp parse_complete_lines([], messages, remaining) do
    {Enum.reverse(messages), remaining}
  end

  defp parse_complete_lines([line | rest], messages, remaining) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        # Skip empty lines
        parse_complete_lines(rest, messages, remaining)

      is_ansi_escape?(trimmed) ->
        # Skip ANSI escape sequences (e.g., cursor show/hide)
        parse_complete_lines(rest, messages, remaining)

      true ->
        # Try to parse as JSON
        text_to_parse =
          if remaining == "" do
            trimmed
          else
            remaining <> trimmed
          end

        case Jason.decode(text_to_parse) do
          {:ok, json} ->
            # Successfully parsed - add to messages, clear remaining
            parse_complete_lines(rest, [json | messages], "")

          {:error, _error} ->
            # Check if this looks like the start of a JSON object
            # If not, discard it (probably stderr or warning message)
            if String.starts_with?(trimmed, "{") or String.starts_with?(remaining, "{") do
              # Keep accumulating - might be partial JSON
              parse_complete_lines(rest, messages, text_to_parse)
            else
              # Discard non-JSON line (warning message, etc.)
              Logger.debug("Discarding non-JSON output: #{String.slice(trimmed, 0, 100)}")
              parse_complete_lines(rest, messages, remaining)
            end
        end
    end
  end

  # Check if a string is an ANSI escape sequence
  # Common ones from CLI: \e[?25h (show cursor), \e[?25l (hide cursor)
  defp is_ansi_escape?(str) do
    String.starts_with?(str, "\e[") or String.starts_with?(str, "\x1b[")
  end

  @impl true
  def close(%__MODULE__{port: nil, temp_files: temp_files}) do
    # Clean up temporary files
    cleanup_temp_files(temp_files)
    :ok
  end

  def close(%__MODULE__{port: port, temp_files: temp_files}) do
    # Clean up temporary files first
    cleanup_temp_files(temp_files)

    try do
      Port.close(port)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  defp cleanup_temp_files(temp_files) do
    Enum.each(temp_files, fn path ->
      try do
        File.rm(path)
      rescue
        _ -> :ok
      end
    end)
  end

  @impl true
  def ready?(%__MODULE__{ready: ready}), do: ready

  @impl true
  def end_input(%__MODULE__{port: nil}) do
    {:error, CLIConnectionError.exception("Transport is not connected")}
  end

  def end_input(%__MODULE__{port: _port}) do
    # Send EOF by closing stdin - this is done automatically when port closes
    # For now, we don't have a way to close just stdin with Port
    # The actual end of input happens when the stream finishes
    :ok
  end

  # Private helpers

  defp find_cli do
    cond do
      bundled = find_bundled_cli() -> bundled
      system = System.find_executable("claude") -> system
      true -> find_in_common_locations()
    end
  end

  defp find_bundled_cli do
    cli_name = if :os.type() == {:win32, :nt}, do: "claude.exe", else: "claude"

    bundled_path =
      :claude_agent_sdk
      |> :code.priv_dir()
      |> Path.join("bundled")
      |> Path.join(cli_name)

    if File.exists?(bundled_path) do
      Logger.info("Using bundled Claude Code CLI: #{bundled_path}")
      bundled_path
    else
      nil
    end
  end

  defp find_in_common_locations do
    home = System.user_home()

    locations = [
      Path.join([home, ".npm-global", "bin", "claude"]),
      "/usr/local/bin/claude",
      Path.join([home, ".local", "bin", "claude"]),
      Path.join([home, "node_modules", ".bin", "claude"]),
      Path.join([home, ".yarn", "bin", "claude"]),
      Path.join([home, ".claude", "local", "claude"])
    ]

    Enum.find(locations, fn path ->
      File.exists?(path) && File.regular?(path)
    end) ||
      raise CLINotFoundError,
        message: """
        Claude Code not found. Install with:
          npm install -g @anthropic-ai/claude-code

        If already installed locally, try:
          export PATH="$HOME/node_modules/.bin:$PATH"

        Or provide the path via Options:
          %Options{cli_path: "/path/to/claude"}
        """
  end

  defp check_cli_version(cli_path) do
    case System.cmd(cli_path, ["-v"], stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.run(~r/(\d+\.\d+\.\d+)/, output) do
          [_, version] ->
            if Version.compare(version, @minimum_cli_version) == :lt do
              Logger.warning("""
              Warning: Claude Code version #{version} is unsupported in the Agent SDK.
              Minimum required version is #{@minimum_cli_version}.
              Some features may not work correctly.
              """)
            end

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  # Returns {args, temp_files}
  defp build_command(%__MODULE__{} = transport) do
    opts = transport.options

    args =
      ["--output-format", "stream-json", "--verbose"]
      |> add_system_prompt_args(opts.system_prompt)
      |> add_tools_args(opts)
      |> add_permission_args(opts)
      |> add_session_args(opts)
      |> add_model_args(opts)
      |> add_mcp_args(opts)
      |> add_agent_args(opts)
      |> add_misc_args(opts)
      |> add_prompt_args(transport.prompt)

    # Check if command line is too long (Windows limitation)
    # and optimize by moving large values to temp files
    maybe_optimize_cmd_length(args, opts)
  end

  # Check if command line is too long and use temp files for large values
  # Returns {args, temp_files}
  defp maybe_optimize_cmd_length(args, opts) do
    cmd_str = Enum.join(args, " ")

    if String.length(cmd_str) > @cmd_length_limit and opts.agents do
      # Command is too long - use temp file for agents
      optimize_agents_arg(args)
    else
      {args, []}
    end
  end

  defp optimize_agents_arg(args) do
    case find_arg_index(args, "--agents") do
      nil ->
        {args, []}

      idx ->
        agents_json = Enum.at(args, idx + 1)

        # Create a temporary file
        temp_path = create_temp_file(agents_json, "agents", ".json")

        if temp_path do
          Logger.info(
            "Command line length exceeds limit (#{@cmd_length_limit}). " <>
              "Using temp file for --agents: #{temp_path}"
          )

          # Replace agents JSON with @filepath reference
          new_args = List.replace_at(args, idx + 1, "@#{temp_path}")
          {new_args, [temp_path]}
        else
          {args, []}
        end
    end
  end

  defp find_arg_index(args, flag) do
    Enum.find_index(args, &(&1 == flag))
  end

  defp create_temp_file(content, prefix, suffix) do
    temp_dir = System.tmp_dir!()
    random_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    temp_path = Path.join(temp_dir, "#{prefix}_#{random_id}#{suffix}")

    case File.write(temp_path, content) do
      :ok ->
        temp_path

      {:error, reason} ->
        Logger.warning("Failed to create temp file: #{inspect(reason)}")
        nil
    end
  end

  defp add_system_prompt_args(args, nil), do: args ++ ["--system-prompt", ""]

  defp add_system_prompt_args(args, prompt) when is_binary(prompt) do
    args ++ ["--system-prompt", prompt]
  end

  defp add_system_prompt_args(args, %{type: :preset, append: append}) when not is_nil(append) do
    args ++ ["--append-system-prompt", append]
  end

  defp add_system_prompt_args(args, %{type: :preset}), do: args

  defp add_tools_args(args, %{tools: nil}), do: args

  defp add_tools_args(args, %{tools: tools}) when is_list(tools) do
    if tools == [] do
      args ++ ["--tools", ""]
    else
      args ++ ["--tools", Enum.join(tools, ",")]
    end
  end

  defp add_tools_args(args, %{tools: %{type: :preset}}), do: args ++ ["--tools", "default"]

  defp add_permission_args(args, opts) do
    args
    |> maybe_add("--allowedTools", opts.allowed_tools, &Enum.join(&1, ","))
    |> maybe_add("--disallowedTools", opts.disallowed_tools, &Enum.join(&1, ","))
    |> maybe_add("--permission-mode", opts.permission_mode, &permission_mode_to_string/1)
    |> maybe_add("--permission-prompt-tool", opts.permission_prompt_tool_name)
  end

  defp add_session_args(args, opts) do
    args
    |> maybe_add_flag("--continue", opts.continue_conversation)
    |> maybe_add("--resume", opts.resume)
    |> maybe_add_flag("--fork-session", opts.fork_session)
    |> maybe_add_flag("--include-partial-messages", opts.include_partial_messages)
  end

  defp add_model_args(args, opts) do
    args
    |> maybe_add("--model", opts.model)
    |> maybe_add("--fallback-model", opts.fallback_model)
    |> maybe_add("--max-turns", opts.max_turns, &to_string/1)
    |> maybe_add("--max-budget-usd", opts.max_budget_usd, &to_string/1)
    |> maybe_add("--max-thinking-tokens", opts.max_thinking_tokens, &to_string/1)
    |> maybe_add("--betas", opts.betas, &Enum.join(&1, ","))
  end

  defp add_mcp_args(args, %{mcp_servers: nil}), do: args

  defp add_mcp_args(args, %{mcp_servers: servers}) when is_binary(servers) do
    args ++ ["--mcp-config", servers]
  end

  defp add_mcp_args(args, %{mcp_servers: servers}) when is_map(servers) do
    # Filter out SDK server instances and convert to JSON
    servers_for_cli =
      servers
      |> Enum.map(fn {name, config} ->
        case config do
          %{type: :sdk} = sdk_config ->
            {name, Map.delete(sdk_config, :instance)}

          config ->
            {name, config}
        end
      end)
      |> Map.new()

    if map_size(servers_for_cli) > 0 do
      config_json = Jason.encode!(%{"mcpServers" => servers_for_cli})
      args ++ ["--mcp-config", config_json]
    else
      args
    end
  end

  defp add_agent_args(args, %{agents: nil}), do: args

  defp add_agent_args(args, %{agents: agents}) when is_map(agents) do
    agents_json = Jason.encode!(agents)
    args ++ ["--agents", agents_json]
  end

  defp add_misc_args(args, opts) do
    args
    |> add_settings_args(opts)
    |> add_dirs_args(opts.add_dirs)
    |> add_setting_sources_args(opts.setting_sources)
    |> add_plugins_args(opts.plugins)
    |> add_extra_args(opts.extra_args)
    |> add_output_format_args(opts.output_format)
  end

  # Build settings value, merging sandbox settings if provided.
  # Returns the settings value as either:
  # - A JSON string (if sandbox is provided or settings is JSON)
  # - A file path (if only settings path is provided without sandbox)
  # - nil if neither settings nor sandbox is provided
  defp add_settings_args(args, %{settings: nil, sandbox: nil}), do: args

  defp add_settings_args(args, %{settings: settings, sandbox: nil}) when not is_nil(settings) do
    # If only settings path and no sandbox, pass through as-is
    args ++ ["--settings", settings]
  end

  defp add_settings_args(args, %{settings: settings, sandbox: sandbox}) do
    # If we have sandbox settings, we need to merge into a JSON object
    settings_obj = load_settings_object(settings)

    # Merge sandbox settings
    merged = if sandbox, do: Map.put(settings_obj, "sandbox", sandbox), else: settings_obj

    if map_size(merged) > 0 do
      args ++ ["--settings", Jason.encode!(merged)]
    else
      args
    end
  end

  defp load_settings_object(nil), do: %{}

  defp load_settings_object(settings) when is_binary(settings) do
    settings_str = String.trim(settings)

    cond do
      # Check if settings is a JSON string
      String.starts_with?(settings_str, "{") and String.ends_with?(settings_str, "}") ->
        case Jason.decode(settings_str) do
          {:ok, obj} when is_map(obj) ->
            obj

          _ ->
            # If parsing fails, treat as file path
            Logger.warning(
              "Failed to parse settings as JSON, treating as file path: #{settings_str}"
            )

            load_settings_from_file(settings_str)
        end

      # It's a file path - read and parse
      true ->
        load_settings_from_file(settings_str)
    end
  end

  defp load_settings_from_file(path) do
    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, obj} when is_map(obj) ->
              obj

            _ ->
              Logger.warning("Failed to parse settings file as JSON: #{path}")
              %{}
          end

        {:error, reason} ->
          Logger.warning("Failed to read settings file: #{path} - #{inspect(reason)}")
          %{}
      end
    else
      Logger.warning("Settings file not found: #{path}")
      %{}
    end
  end

  defp add_dirs_args(args, []), do: args

  defp add_dirs_args(args, dirs) do
    Enum.reduce(dirs, args, fn dir, acc ->
      acc ++ ["--add-dir", dir]
    end)
  end

  defp add_setting_sources_args(args, nil), do: args ++ ["--setting-sources", ""]

  defp add_setting_sources_args(args, sources) do
    sources_str =
      sources
      |> Enum.map(&setting_source_to_string/1)
      |> Enum.join(",")

    args ++ ["--setting-sources", sources_str]
  end

  defp add_plugins_args(args, []), do: args

  defp add_plugins_args(args, plugins) do
    Enum.reduce(plugins, args, fn
      %{type: :local, path: path}, acc ->
        acc ++ ["--plugin-dir", path]
    end)
  end

  defp add_extra_args(args, extras) when map_size(extras) == 0, do: args

  defp add_extra_args(args, extras) do
    Enum.reduce(extras, args, fn
      {flag, nil}, acc -> acc ++ ["--#{flag}"]
      {flag, value}, acc -> acc ++ ["--#{flag}", to_string(value)]
    end)
  end

  defp add_output_format_args(args, nil), do: args

  defp add_output_format_args(args, %{"type" => "json_schema", "schema" => schema}) do
    args ++ ["--json-schema", Jason.encode!(schema)]
  end

  defp add_output_format_args(args, _), do: args

  defp add_prompt_args(args, nil) do
    # Streaming mode
    args ++ ["--input-format", "stream-json"]
  end

  defp add_prompt_args(args, prompt) when is_binary(prompt) do
    # String mode with --print
    args ++ ["--print", "--", prompt]
  end

  defp maybe_add(args, _flag, nil), do: args
  defp maybe_add(args, _flag, []), do: args
  defp maybe_add(args, flag, value) when is_binary(value), do: args ++ [flag, value]
  defp maybe_add(args, _flag, nil, _transform), do: args
  defp maybe_add(args, flag, value, transform), do: args ++ [flag, transform.(value)]

  defp maybe_add_flag(args, _flag, false), do: args
  defp maybe_add_flag(args, _flag, nil), do: args
  defp maybe_add_flag(args, flag, true), do: args ++ [flag]

  defp permission_mode_to_string(:default), do: "default"
  defp permission_mode_to_string(:accept_edits), do: "acceptEdits"
  defp permission_mode_to_string(:plan), do: "plan"
  defp permission_mode_to_string(:bypass_permissions), do: "bypassPermissions"

  defp setting_source_to_string(:user), do: "user"
  defp setting_source_to_string(:project), do: "project"
  defp setting_source_to_string(:local), do: "local"

  # PTY wrapping is only needed for --print mode (when prompt is not nil).
  # In streaming mode (--input-format stream-json), PTY is NOT needed and causes
  # problems because it makes the CLI think it's running interactively.
  defp wrap_with_pty(%__MODULE__{prompt: nil, cli_path: cli_path}, args) do
    # Streaming mode - no PTY needed
    {cli_path, args}
  end

  defp wrap_with_pty(%__MODULE__{cli_path: cli_path}, args) do
    # Print mode - needs PTY for CLI to write to stdout properly
    case :os.type() do
      {:unix, :darwin} ->
        # macOS: script -q /dev/null <command> <args...>
        script_path = find_script_command()

        if script_path do
          {script_path, ["-q", "/dev/null", cli_path | args]}
        else
          Logger.warning("'script' command not found - CLI may not work properly without TTY")
          {cli_path, args}
        end

      {:unix, _} ->
        # Linux: script -q -c "<full command>" /dev/null
        script_path = find_script_command()

        if script_path do
          # Build the full command string for -c option with proper escaping
          full_cmd = shell_escape_command([cli_path | args])
          {script_path, ["-q", "-c", full_cmd, "/dev/null"]}
        else
          Logger.warning("'script' command not found - CLI may not work properly without TTY")
          {cli_path, args}
        end

      {:win32, _} ->
        # Windows doesn't need PTY wrapping
        {cli_path, args}
    end
  end

  defp find_script_command do
    paths = ["/usr/bin/script", "/bin/script"]
    Enum.find(paths, &(File.exists?(&1) and File.regular?(&1)))
  end

  @doc """
  Escapes a list of command arguments for safe execution in a shell.

  This function wraps each argument in double quotes and escapes special
  characters to prevent shell interpretation issues when passing commands
  to `script -c` on Linux systems.

  ## Escaping Rules

  - All arguments are wrapped in double quotes
  - Escaped characters: `\\`, `"`, `$`, `` ` ``, newlines
  - Single quotes (`'`) are preserved as-is (no escaping needed inside double quotes)

  ## Examples

      iex> SubprocessCli.shell_escape_command(["/bin/claude", "--prompt", "What's up?"])
      ~s("/bin/claude" "--prompt" "What's up?")

      iex> SubprocessCli.shell_escape_command(["/bin/claude", "--json", "{\\"key\\": \\"value\\"}"])
      ~s("/bin/claude" "--json" "{\\\\"key\\\\": \\\\"value\\\\"}")

  """
  def shell_escape_command(args) when is_list(args) do
    args
    |> Enum.map(&shell_escape_arg/1)
    |> Enum.join(" ")
  end

  # Escape a single argument for shell execution
  # Uses double quotes and escapes: ", \, $, `, and newline
  defp shell_escape_arg(arg) do
    escaped =
      arg
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("$", "\\$")
      |> String.replace("`", "\\`")
      |> String.replace("\n", "\\n")

    "\"#{escaped}\""
  end

  defp build_port_options(%__MODULE__{} = transport, _executable, args) do
    opts = [
      :binary,
      :exit_status,
      :use_stdio,
      {:args, args}
    ]

    opts = if transport.cwd, do: [{:cd, transport.cwd} | opts], else: opts

    env_list =
      transport.options.env
      |> Map.put("CLAUDE_CODE_ENTRYPOINT", "sdk-elixir")
      |> Map.put("CLAUDE_AGENT_SDK_VERSION", ClaudeAgent.version())
      |> maybe_put_env(
        "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING",
        transport.options.enable_file_checkpointing
      )
      |> maybe_put_env("PWD", transport.cwd)
      |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    # Only add env if we're using the CLI directly (not through script wrapper on macOS)
    # The script command on macOS passes through environment automatically
    [{:env, env_list} | opts]
  end

  defp maybe_put_env(env, _key, false), do: env
  defp maybe_put_env(env, _key, nil), do: env
  defp maybe_put_env(env, key, true), do: Map.put(env, key, "true")
  defp maybe_put_env(env, key, value) when is_binary(value), do: Map.put(env, key, value)
end
