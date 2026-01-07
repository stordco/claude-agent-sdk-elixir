defmodule ClaudeAgentSdk.Errors do
  @moduledoc """
  Exception definitions for Claude Agent SDK.

  This module defines all error types that can be raised by the SDK:

  - `SDKError` - Base exception for all Claude SDK errors
  - `CLIConnectionError` - Unable to connect to Claude Code
  - `CLINotFoundError` - Claude Code CLI not found
  - `ProcessError` - CLI process failed
  - `JSONDecodeError` - Unable to decode JSON from CLI output
  - `MessageParseError` - Unable to parse a message from CLI output

  ## Examples

      try do
        ClaudeAgentSdk.query("Hello")
      rescue
        e in ClaudeAgentSdk.Errors.CLINotFoundError ->
          IO.puts("Please install Claude Code: \#{e.message}")

        e in ClaudeAgentSdk.Errors.ProcessError ->
          IO.puts("Process failed with exit code: \#{e.exit_code}")
      end
  """

  defmodule SDKError do
    @moduledoc "Base exception for all Claude SDK errors."
    defexception [:message]

    @impl true
    def exception(message) when is_binary(message) do
      %__MODULE__{message: message}
    end

    def exception(opts) when is_list(opts) do
      message = Keyword.get(opts, :message, "Claude SDK error")
      %__MODULE__{message: message}
    end
  end

  defmodule CLIConnectionError do
    @moduledoc "Raised when unable to connect to Claude Code."
    defexception [:message]

    @impl true
    def exception(message) when is_binary(message) do
      %__MODULE__{message: message}
    end

    def exception(opts) when is_list(opts) do
      message = Keyword.get(opts, :message, "Unable to connect to Claude Code")
      %__MODULE__{message: message}
    end
  end

  defmodule CLINotFoundError do
    @moduledoc """
    Raised when Claude Code CLI is not found or not installed.

    ## Fields

    - `:message` - Error message
    - `:cli_path` - The path that was searched (optional)
    """
    defexception [:message, :cli_path]

    @impl true
    def exception(opts) when is_list(opts) do
      message = Keyword.get(opts, :message, "Claude Code not found")
      cli_path = Keyword.get(opts, :cli_path)
      %__MODULE__{message: message, cli_path: cli_path}
    end

    def exception(message) when is_binary(message) do
      %__MODULE__{message: message, cli_path: nil}
    end

    @impl true
    def message(%__MODULE__{message: msg, cli_path: nil}), do: msg
    def message(%__MODULE__{message: msg, cli_path: path}), do: "#{msg}: #{path}"
  end

  defmodule ProcessError do
    @moduledoc """
    Raised when the CLI process fails.

    ## Fields

    - `:message` - Error message
    - `:exit_code` - Process exit code (optional)
    - `:stderr` - Standard error output (optional)
    """
    defexception [:message, :exit_code, :stderr]

    @impl true
    def exception(opts) when is_list(opts) do
      message = Keyword.get(opts, :message, "CLI process failed")
      exit_code = Keyword.get(opts, :exit_code)
      stderr = Keyword.get(opts, :stderr)
      %__MODULE__{message: message, exit_code: exit_code, stderr: stderr}
    end

    @impl true
    def message(%__MODULE__{message: msg, exit_code: nil, stderr: nil}), do: msg

    def message(%__MODULE__{message: msg, exit_code: code, stderr: nil}) when not is_nil(code) do
      "#{msg} (exit code: #{code})"
    end

    def message(%__MODULE__{message: msg, exit_code: nil, stderr: stderr})
        when not is_nil(stderr) do
      "#{msg}\nError output: #{stderr}"
    end

    def message(%__MODULE__{message: msg, exit_code: code, stderr: stderr}) do
      "#{msg} (exit code: #{code})\nError output: #{stderr}"
    end
  end

  defmodule JSONDecodeError do
    @moduledoc """
    Raised when unable to decode JSON from CLI output.

    ## Fields

    - `:message` - Error message
    - `:line` - The line that failed to parse
    - `:original_error` - The underlying JSON decode error
    """
    defexception [:message, :line, :original_error]

    @impl true
    def exception(opts) when is_list(opts) do
      line = Keyword.get(opts, :line, "")
      original_error = Keyword.get(opts, :original_error)
      truncated = String.slice(line, 0, 100)
      message = Keyword.get(opts, :message, "Failed to decode JSON: #{truncated}...")
      %__MODULE__{message: message, line: line, original_error: original_error}
    end
  end

  defmodule MessageParseError do
    @moduledoc """
    Raised when unable to parse a message from CLI output.

    ## Fields

    - `:message` - Error message
    - `:data` - The raw data that failed to parse
    """
    defexception [:message, :data]

    @type t :: %__MODULE__{
            message: String.t(),
            data: term()
          }

    @impl true
    def exception(opts) when is_list(opts) do
      message = Keyword.get(opts, :message, "Failed to parse message")
      data = Keyword.get(opts, :data)
      %__MODULE__{message: message, data: data}
    end

    def exception(message) when is_binary(message) do
      %__MODULE__{message: message, data: nil}
    end
  end
end
