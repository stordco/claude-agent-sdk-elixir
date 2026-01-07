defmodule ClaudeAgentSdk.Hooks.HookMatcher do
  @moduledoc """
  Hook matcher configuration for Claude SDK.

  Defines when and how hooks are invoked during the agent loop.

  ## Hook Events

  - `"PreToolUse"` - Before a tool is executed
  - `"PostToolUse"` - After a tool is executed
  - `"UserPromptSubmit"` - When a user prompt is submitted
  - `"Stop"` - When the agent stops
  - `"SubagentStop"` - When a subagent stops
  - `"PreCompact"` - Before context compaction

  ## Matchers

  The matcher field specifies which tools the hook applies to:

  - `nil` - Match all tools
  - `"Bash"` - Match only Bash tool
  - `"Write|Edit"` - Match Write or Edit tools

  ## Examples

      # Block certain bash commands
      %HookMatcher{
        matcher: "Bash",
        hooks: [&check_bash_command/3],
        timeout: 30_000
      }

      # Add context to all prompts
      %HookMatcher{
        matcher: nil,
        hooks: [&add_context/3]
      }
  """

  @type hook_event ::
          :pre_tool_use
          | :post_tool_use
          | :user_prompt_submit
          | :stop
          | :subagent_stop
          | :pre_compact

  @type hook_callback :: (map(), String.t() | nil, map() -> map())

  @type t :: %__MODULE__{
          matcher: String.t() | nil,
          hooks: [hook_callback()],
          timeout: pos_integer() | nil
        }

  defstruct [:matcher, hooks: [], timeout: nil]

  @doc """
  Create a new HookMatcher.

  ## Options

  - `:matcher` - Tool name pattern to match (nil for all)
  - `:hooks` - List of hook callback functions
  - `:timeout` - Timeout in milliseconds for hook execution
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      matcher: Keyword.get(opts, :matcher),
      hooks: Keyword.get(opts, :hooks, []),
      timeout: Keyword.get(opts, :timeout)
    }
  end

  @doc "Convert hook event atom to string."
  @spec event_to_string(hook_event()) :: String.t()
  def event_to_string(:pre_tool_use), do: "PreToolUse"
  def event_to_string(:post_tool_use), do: "PostToolUse"
  def event_to_string(:user_prompt_submit), do: "UserPromptSubmit"
  def event_to_string(:stop), do: "Stop"
  def event_to_string(:subagent_stop), do: "SubagentStop"
  def event_to_string(:pre_compact), do: "PreCompact"

  @doc "Parse hook event string to atom."
  @spec string_to_event(String.t()) :: {:ok, hook_event()} | {:error, String.t()}
  def string_to_event("PreToolUse"), do: {:ok, :pre_tool_use}
  def string_to_event("PostToolUse"), do: {:ok, :post_tool_use}
  def string_to_event("UserPromptSubmit"), do: {:ok, :user_prompt_submit}
  def string_to_event("Stop"), do: {:ok, :stop}
  def string_to_event("SubagentStop"), do: {:ok, :subagent_stop}
  def string_to_event("PreCompact"), do: {:ok, :pre_compact}
  def string_to_event(event), do: {:error, "Unknown hook event: #{event}"}

  @doc """
  Convert HookMatcher to internal format for control protocol.

  Returns a map with callback IDs instead of function references.
  """
  @spec to_internal_format(t(), (hook_callback() -> String.t())) :: map()
  def to_internal_format(%__MODULE__{} = matcher, register_callback) do
    callback_ids = Enum.map(matcher.hooks, register_callback)

    result = %{
      "matcher" => matcher.matcher,
      "hookCallbackIds" => callback_ids
    }

    if matcher.timeout do
      Map.put(result, "timeout", matcher.timeout)
    else
      result
    end
  end
end
