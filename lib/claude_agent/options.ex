defmodule ClaudeAgent.Options do
  @moduledoc """
  Configuration options for Claude Agent SDK queries.

  All functions in the SDK accept options as keyword lists, following standard
  Elixir conventions.

  ## Basic Usage

      # Simple options
      ClaudeAgent.query("Hello",
        system_prompt: "You are a helpful assistant",
        max_turns: 5
      )

      # With tools
      ClaudeAgent.query("Fix this bug",
        allowed_tools: ["Read", "Write", "Bash"],
        permission_mode: :accept_edits
      )

  ## Permission Modes

  - `:default` - CLI prompts for dangerous tools
  - `:accept_edits` - Auto-accept file edits
  - `:plan` - Planning mode
  - `:bypass_permissions` - Allow all tools (use with caution)

  ## System Prompt

  The system prompt can be:

  - A string: `system_prompt: "You are helpful"`
  - A preset: `system_prompt: %{type: :preset, preset: :claude_code}`
  - A preset with append: `system_prompt: %{type: :preset, preset: :claude_code, append: "Be concise"}`

  ## Subagents

  Subagents allow you to delegate tasks to specialized agents with their own prompts,
  tool restrictions, and model configurations. This enables multi-agent workflows where
  different agents handle different aspects of a task.

  ### Basic Agent Definition

  Each agent is defined with:

  - `description` (required) - What the agent does
  - `prompt` (required) - System prompt for the agent
  - `tools` (optional) - List of allowed tools for this agent (nil = all tools)
  - `model` (optional) - Model override (`:sonnet`, `:opus`, `:haiku`, `:inherit`)

  ### Example: Single Agent

      alias ClaudeAgent.Subagent

      ClaudeAgent.query("Review this code",
        agents: %{
          "code-reviewer" => Subagent.new(
            "Code review specialist",
            "You are an expert code reviewer. Focus on correctness, performance, and security.",
            tools: ["Read", "Grep", "Glob"],
            model: :sonnet
          )
        }
      )

  ### Example: Multiple Agents

      alias ClaudeAgent.Subagent

      ClaudeAgent.query("Analyze and test this module",
        agents: %{
          "analyzer" => Subagent.new(
            "Code analysis specialist",
            "Analyze code structure and patterns",
            tools: ["Read", "Grep"],
            model: :sonnet
          ),
          "tester" => Subagent.new(
            "Test generation specialist",
            "Generate comprehensive test cases",
            tools: ["Read", "Write"],
            model: :haiku
          )
        }
      )

  ### Agent Delegation

  When you configure agents, Claude can delegate tasks to them by using tool calls.
  For example, if you have a "code-reviewer" agent configured, Claude might invoke:

      Use tool: Task(subagent_type: "code-reviewer", prompt: "Review auth.ex")

  The subagent executes with its own:
  - System prompt and instructions
  - Tool restrictions (only allowed tools)
  - Model configuration
  - Permission settings

  ### Agent Hierarchy and Tracking

  Messages from subagents include a `parent_tool_use_id` field that links them to the
  delegating agent's tool use. This creates a hierarchy:

      Parent Agent
      └─> Tool: Task(subagent_type: "analyzer")
          └─> Subagent Messages (parent_tool_use_id set)
              └─> Results returned to parent

  ### SubagentStop Hook

  You can hook into subagent completion using the `:subagent_stop` hook event:

      ClaudeAgent.query("Analyze this code",
        agents: %{"analyzer" => %{...}},
        hooks: %{
          subagent_stop: [
            %{
              callback: fn input, _context ->
                IO.puts("Subagent completed")
                %{continue: true}
              end
            }
          ]
        }
      )

  ### Model Inheritance

  The `:inherit` model (or `nil`) makes the agent use its parent's model:

      # Analyzer inherits the query's model (e.g., opus)
      ClaudeAgent.query("Analyze this",
        model: "opus",
        agents: %{
          "analyzer" => %{
            description: "Analyzer",
            prompt: "Analyze code",
            model: :inherit  # or nil
          }
        }
      )

  ### Tool Restrictions

  Agents can be restricted to specific tools for safety and cost control:

      %{
        "research" => %{
          description: "Research specialist",
          prompt: "Find and analyze information",
          tools: ["Read", "Grep", "WebSearch"],  # Only these tools
          model: :haiku
        }
      }

  If `tools` is `nil`, the agent has access to all available tools.

  ## MCP Servers

  Configure MCP servers as a map of name to config:

      mcp_servers: %{
        "calculator" => %{type: :stdio, command: "python", args: ["-m", "calc_server"]},
        "my_tools" => sdk_mcp_server
      }

  ## Hooks

  Configure hooks by event type:

      hooks: %{
        pre_tool_use: [%HookMatcher{matcher: "Bash", hooks: [&check_command/3]}],
        post_tool_use: [%HookMatcher{hooks: [&log_result/3]}]
      }
  """

  alias ClaudeAgent.Hooks.HookMatcher
  alias ClaudeAgent.Types.Permissions

  @type permission_mode :: :default | :accept_edits | :plan | :bypass_permissions
  @type setting_source :: :user | :project | :local

  @type system_prompt_preset :: %{
          type: :preset,
          preset: :claude_code,
          append: String.t() | nil
        }

  @type tools_preset :: %{
          type: :preset,
          preset: :claude_code
        }

  @type mcp_stdio_config :: %{
          type: :stdio,
          command: String.t(),
          args: [String.t()],
          env: %{String.t() => String.t()}
        }

  @type mcp_sse_config :: %{
          type: :sse,
          url: String.t(),
          headers: %{String.t() => String.t()}
        }

  @type mcp_http_config :: %{
          type: :http,
          url: String.t(),
          headers: %{String.t() => String.t()}
        }

  @type mcp_sdk_config :: %{
          type: :sdk,
          name: String.t(),
          instance: term()
        }

  @type mcp_server_config ::
          mcp_stdio_config() | mcp_sse_config() | mcp_http_config() | mcp_sdk_config()

  @type plugin_config :: %{
          type: :local,
          path: String.t()
        }

  @type sandbox_network_config :: %{
          optional(:allow_unix_sockets) => [String.t()],
          optional(:allow_all_unix_sockets) => boolean(),
          optional(:allow_local_binding) => boolean(),
          optional(:http_proxy_port) => pos_integer(),
          optional(:socks_proxy_port) => pos_integer()
        }

  @type sandbox_ignore_violations :: %{
          optional(:file) => [String.t()],
          optional(:network) => [String.t()]
        }

  @type sandbox_settings :: %{
          optional(:enabled) => boolean(),
          optional(:auto_allow_bash_if_sandboxed) => boolean(),
          optional(:excluded_commands) => [String.t()],
          optional(:allow_unsandboxed_commands) => boolean(),
          optional(:network) => sandbox_network_config(),
          optional(:ignore_violations) => sandbox_ignore_violations(),
          optional(:enable_weaker_nested_sandbox) => boolean()
        }

  @typedoc """
  Subagent configuration.

  See `ClaudeAgent.Subagent` for full documentation, examples, and usage patterns.

  Agents are configured in the `:agents` option as a map of name to `Subagent` struct:

      alias ClaudeAgent.Subagent

      ClaudeAgent.query("Review auth module",
        agents: %{
          "code-reviewer" => Subagent.new(
            "Security-focused code reviewer",
            "Review code for security vulnerabilities",
            tools: ["Read", "Grep"],
            model: :sonnet
          )
        }
      )
  """
  @type agent_definition :: ClaudeAgent.Subagent.t()

  @type t :: [
          {:tools, [String.t()] | tools_preset() | nil}
          | {:allowed_tools, [String.t()]}
          | {:system_prompt, String.t() | system_prompt_preset() | nil}
          | {:mcp_servers, %{String.t() => mcp_server_config()} | String.t() | nil}
          | {:permission_mode, permission_mode() | nil}
          | {:continue_conversation, boolean()}
          | {:resume, String.t() | nil}
          | {:max_turns, pos_integer() | nil}
          | {:max_budget_usd, float() | nil}
          | {:disallowed_tools, [String.t()]}
          | {:model, String.t() | nil}
          | {:fallback_model, String.t() | nil}
          | {:betas, [String.t()]}
          | {:permission_prompt_tool_name, String.t() | nil}
          | {:cwd, String.t() | nil}
          | {:cli_path, String.t() | nil}
          | {:settings, String.t() | nil}
          | {:add_dirs, [String.t()]}
          | {:env, %{String.t() => String.t()}}
          | {:extra_args, %{String.t() => String.t() | nil}}
          | {:max_buffer_size, pos_integer() | nil}
          | {:stderr_callback, (String.t() -> any()) | nil}
          | {:can_use_tool, Permissions.can_use_tool_callback() | nil}
          | {:hooks, %{HookMatcher.hook_event() => [HookMatcher.t()]} | nil}
          | {:user, String.t() | nil}
          | {:include_partial_messages, boolean()}
          | {:fork_session, boolean()}
          | {:agents, %{String.t() => agent_definition()} | nil}
          | {:setting_sources, [setting_source()] | nil}
          | {:sandbox, sandbox_settings() | nil}
          | {:plugins, [plugin_config()]}
          | {:max_thinking_tokens, pos_integer() | nil}
          | {:output_format, map() | nil}
          | {:enable_file_checkpointing, boolean()}
          | {:skip_version_check, boolean()}
          | {:stream_close_timeout, pos_integer() | nil}
        ]

  @defaults [
    tools: nil,
    allowed_tools: [],
    system_prompt: nil,
    mcp_servers: nil,
    permission_mode: nil,
    continue_conversation: false,
    resume: nil,
    max_turns: nil,
    max_budget_usd: nil,
    disallowed_tools: [],
    model: nil,
    fallback_model: nil,
    betas: [],
    permission_prompt_tool_name: nil,
    cwd: nil,
    cli_path: nil,
    settings: nil,
    add_dirs: [],
    env: %{},
    extra_args: %{},
    max_buffer_size: nil,
    stderr_callback: nil,
    can_use_tool: nil,
    hooks: nil,
    user: nil,
    include_partial_messages: false,
    fork_session: false,
    agents: nil,
    setting_sources: nil,
    sandbox: nil,
    plugins: [],
    max_thinking_tokens: nil,
    output_format: nil,
    enable_file_checkpointing: false,
    skip_version_check: false,
    stream_close_timeout: nil
  ]

  @doc """
  Returns default options as a keyword list.

  ## Examples

      defaults = ClaudeAgent.Options.defaults()
      defaults[:max_turns]  # => nil
      defaults[:allowed_tools]  # => []
  """
  @spec defaults() :: t()
  def defaults, do: @defaults

  @doc """
  Normalize and validate options.

  Takes a keyword list and:
  1. Merges with defaults
  2. Validates all constraints
  3. Returns normalized keyword list

  ## Examples

      opts = ClaudeAgent.Options.normalize(
        system_prompt: "You are helpful",
        max_turns: 5
      )
  """
  @spec normalize(t()) :: {:ok, t()} | {:error, [String.t()]}
  def normalize(opts \\ []) when is_list(opts) do
    normalized = merge_with_defaults(opts)

    case validate(normalized) do
      :ok -> {:ok, normalized}
      {:error, _} = error -> error
    end
  end

  @doc """
  Normalize and validate options, raising on error.

  Like `normalize/1` but raises `ArgumentError` if validation fails.

  ## Examples

      opts = ClaudeAgent.Options.normalize!(
        system_prompt: "You are helpful",
        max_turns: 5
      )
  """
  @spec normalize!(t()) :: t()
  def normalize!(opts \\ []) do
    case normalize(opts) do
      {:ok, normalized} -> normalized
      {:error, errors} -> raise ArgumentError, "Invalid options: #{Enum.join(errors, ", ")}"
    end
  end

  @doc """
  Merge options with defaults, with provided options taking precedence.

  Only non-nil, non-empty values from the provided options override defaults.

  ## Examples

      merged = ClaudeAgent.Options.merge_with_defaults(
        system_prompt: "Custom prompt",
        max_turns: 3
      )
  """
  @spec merge_with_defaults(t()) :: t()
  def merge_with_defaults(opts) when is_list(opts) do
    Keyword.merge(@defaults, opts, fn _key, default, override ->
      cond do
        is_nil(override) -> default
        is_list(override) and override == [] -> default
        is_map(override) and override == %{} -> default
        true -> override
      end
    end)
  end

  @doc """
  Merge two option keyword lists, with the second taking precedence.

  Only non-nil, non-empty values from the second options override the first.

  ## Examples

      base = [max_turns: 5, system_prompt: "Be helpful"]
      overrides = [max_turns: 10]
      merged = ClaudeAgent.Options.merge(base, overrides)
      # => [max_turns: 10, system_prompt: "Be helpful", ...]
  """
  @spec merge(t(), t()) :: t()
  def merge(base, overrides) when is_list(base) and is_list(overrides) do
    Keyword.merge(base, overrides, fn _key, base_value, override_value ->
      cond do
        is_nil(override_value) -> base_value
        is_list(override_value) and override_value == [] -> base_value
        is_map(override_value) and override_value == %{} -> base_value
        true -> override_value
      end
    end)
  end

  @doc """
  Load options from application environment.

  Reads configuration from `:claude_agent_sdk` application environment and merges
  with provided options, with provided options taking precedence.

  ## Examples

      # In your app's config/config.exs
      config :claude_agent_sdk,
        permission_mode: :bypass_permissions,
        max_turns: 10

      # In code - application config values are used as defaults
      opts = ClaudeAgent.Options.from_app_env(system_prompt: "Be concise")
      # => [permission_mode: :bypass_permissions, max_turns: 10, system_prompt: "Be concise", ...]

      # Query-specific options override application config
      opts = ClaudeAgent.Options.from_app_env(max_turns: 5)
      # => [permission_mode: :bypass_permissions, max_turns: 5, ...]
  """
  @spec from_app_env(t()) :: t()
  def from_app_env(query_options \\ []) when is_list(query_options) do
    app_config =
      case Application.get_all_env(:claude_agent_sdk) do
        [] -> []
        config -> config
      end

    # Merge: defaults < app_config < query_options
    @defaults
    |> merge(app_config)
    |> merge(query_options)
  end

  @doc """
  Get a value from options with a default fallback.

  ## Examples

      opts = [max_turns: 5]
      ClaudeAgent.Options.get(opts, :max_turns)  # => 5
      ClaudeAgent.Options.get(opts, :model)  # => nil
      ClaudeAgent.Options.get(opts, :model, "sonnet")  # => "sonnet"
  """
  @spec get(t(), atom(), any()) :: any()
  def get(opts, key, default \\ nil) when is_list(opts) and is_atom(key) do
    Keyword.get(opts, key, default)
  end

  @doc """
  Check if streaming mode is required based on options.

  Streaming is required when using:
  - `can_use_tool` callback
  - `hooks` configuration

  ## Examples

      ClaudeAgent.Options.requires_streaming?(can_use_tool: &my_callback/2)
      # => true

      ClaudeAgent.Options.requires_streaming?(max_turns: 5)
      # => false
  """
  @spec requires_streaming?(t()) :: boolean()
  def requires_streaming?(opts) when is_list(opts) do
    not is_nil(Keyword.get(opts, :can_use_tool)) or
      not is_nil(Keyword.get(opts, :hooks)) or
      has_sdk_mcp_servers?(opts)
  end

  # Check if options contain SDK MCP servers (which require control protocol)
  defp has_sdk_mcp_servers?(opts) when is_list(opts) do
    case Keyword.get(opts, :mcp_servers) do
      nil -> false
      servers when is_map(servers) ->
        Enum.any?(servers, fn {_name, config} ->
          is_map(config) && Map.get(config, :type) == :sdk
        end)
      _ -> false
    end
  end

  @doc """
  Validate options, returning errors if invalid.

  ## Validations

  - `can_use_tool` cannot be used with `permission_prompt_tool_name`
  - `max_turns` must be positive if set
  - `max_budget_usd` must be positive if set
  - `max_thinking_tokens` must be positive if set
  - `max_buffer_size` must be positive if set

  ## Examples

      ClaudeAgent.Options.validate(max_turns: 5)
      # => :ok

      ClaudeAgent.Options.validate(max_turns: -1)
      # => {:error, ["max_turns must be a positive integer, got: -1"]}
  """
  @spec validate(t()) :: :ok | {:error, [String.t()]}
  def validate(opts) when is_list(opts) do
    errors =
      []
      |> validate_can_use_tool_exclusivity(opts)
      |> validate_positive_integer(:max_turns, Keyword.get(opts, :max_turns))
      |> validate_positive_float(:max_budget_usd, Keyword.get(opts, :max_budget_usd))
      |> validate_positive_integer(:max_thinking_tokens, Keyword.get(opts, :max_thinking_tokens))
      |> validate_positive_integer(:max_buffer_size, Keyword.get(opts, :max_buffer_size))

    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  defp validate_can_use_tool_exclusivity(errors, opts) do
    can_use_tool = Keyword.get(opts, :can_use_tool)
    permission_prompt_tool_name = Keyword.get(opts, :permission_prompt_tool_name)

    if not is_nil(can_use_tool) and not is_nil(permission_prompt_tool_name) do
      ["can_use_tool callback cannot be used with permission_prompt_tool_name" | errors]
    else
      errors
    end
  end

  defp validate_positive_integer(errors, _field, nil), do: errors

  defp validate_positive_integer(errors, _field, value) when is_integer(value) and value > 0,
    do: errors

  defp validate_positive_integer(errors, field, value) do
    ["#{field} must be a positive integer, got: #{inspect(value)}" | errors]
  end

  defp validate_positive_float(errors, _field, nil), do: errors

  defp validate_positive_float(errors, _field, value) when is_number(value) and value > 0,
    do: errors

  defp validate_positive_float(errors, field, value) do
    ["#{field} must be a positive number, got: #{inspect(value)}" | errors]
  end
end
