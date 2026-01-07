defmodule ClaudeAgentSdk.Types.Messages do
  @moduledoc """
  Message type definitions for Claude SDK.

  Messages represent the communication between users, Claude, and the system:

  - `UserMessage` - Messages from the user
  - `AssistantMessage` - Responses from Claude
  - `SystemMessage` - System-level messages (start, init, etc.)
  - `ResultMessage` - Final result with cost and usage information
  - `StreamEvent` - Partial message updates during streaming

  ## Examples

      # Pattern matching on messages
      case message do
        %UserMessage{content: content} ->
          IO.puts("User said: \#{content}")

        %AssistantMessage{content: blocks, model: model} ->
          IO.puts("Claude (\#{model}) responded with \#{length(blocks)} blocks")

        %ResultMessage{total_cost_usd: cost, session_id: session} ->
          IO.puts("Session \#{session} cost $\#{cost}")

        %SystemMessage{subtype: subtype} ->
          IO.puts("System event: \#{subtype}")
      end
  """

  alias ClaudeAgentSdk.Types.ContentBlocks

  defmodule UserMessage do
    @moduledoc """
    Message from the user.

    Content can be a simple string or a list of content blocks
    (for messages that include tool results).
    """

    @type t :: %__MODULE__{
            content: String.t() | [ContentBlocks.content_block()],
            uuid: String.t() | nil,
            parent_tool_use_id: String.t() | nil
          }

    defstruct [:content, :uuid, :parent_tool_use_id]

    @doc "Create a new UserMessage."
    @spec new(String.t() | [ContentBlocks.content_block()], keyword()) :: t()
    def new(content, opts \\ []) do
      %__MODULE__{
        content: content,
        uuid: Keyword.get(opts, :uuid),
        parent_tool_use_id: Keyword.get(opts, :parent_tool_use_id)
      }
    end
  end

  defmodule AssistantMessage do
    @moduledoc """
    Response message from Claude.

    Contains a list of content blocks (text, tool use, thinking, etc.)
    and metadata about the model used.
    """

    @type assistant_error ::
            :authentication_failed
            | :billing_error
            | :rate_limit
            | :invalid_request
            | :server_error
            | :unknown

    @type t :: %__MODULE__{
            content: [ContentBlocks.content_block()],
            model: String.t(),
            parent_tool_use_id: String.t() | nil,
            error: assistant_error() | nil
          }

    @enforce_keys [:content, :model]
    defstruct [:content, :model, :parent_tool_use_id, :error]

    @doc "Create a new AssistantMessage."
    @spec new([ContentBlocks.content_block()], String.t(), keyword()) :: t()
    def new(content, model, opts \\ []) when is_list(content) and is_binary(model) do
      %__MODULE__{
        content: content,
        model: model,
        parent_tool_use_id: Keyword.get(opts, :parent_tool_use_id),
        error: Keyword.get(opts, :error)
      }
    end

    @doc "Parse error string to atom."
    @spec parse_error(String.t() | nil) :: assistant_error() | nil
    def parse_error(nil), do: nil
    def parse_error("authentication_failed"), do: :authentication_failed
    def parse_error("billing_error"), do: :billing_error
    def parse_error("rate_limit"), do: :rate_limit
    def parse_error("invalid_request"), do: :invalid_request
    def parse_error("server_error"), do: :server_error
    def parse_error(_), do: :unknown
  end

  defmodule SystemMessage do
    @moduledoc """
    System-level message with metadata.

    Used for events like session start, initialization, etc.
    """

    @type t :: %__MODULE__{
            subtype: String.t(),
            data: map()
          }

    @enforce_keys [:subtype, :data]
    defstruct [:subtype, :data]

    @doc "Create a new SystemMessage."
    @spec new(String.t(), map()) :: t()
    def new(subtype, data) when is_binary(subtype) and is_map(data) do
      %__MODULE__{subtype: subtype, data: data}
    end
  end

  defmodule ResultMessage do
    @moduledoc """
    Final result message with cost and usage information.

    This message indicates the end of a query response and contains
    metadata about the entire interaction.
    """

    @type t :: %__MODULE__{
            subtype: String.t(),
            duration_ms: non_neg_integer(),
            duration_api_ms: non_neg_integer(),
            is_error: boolean(),
            num_turns: non_neg_integer(),
            session_id: String.t(),
            total_cost_usd: float() | nil,
            usage: map() | nil,
            result: String.t() | nil,
            structured_output: term()
          }

    @enforce_keys [:subtype, :duration_ms, :duration_api_ms, :is_error, :num_turns, :session_id]
    defstruct [
      :subtype,
      :duration_ms,
      :duration_api_ms,
      :is_error,
      :num_turns,
      :session_id,
      :total_cost_usd,
      :usage,
      :result,
      :structured_output
    ]

    @doc "Create a new ResultMessage."
    @spec new(keyword()) :: t()
    def new(opts) when is_list(opts) do
      %__MODULE__{
        subtype: Keyword.fetch!(opts, :subtype),
        duration_ms: Keyword.fetch!(opts, :duration_ms),
        duration_api_ms: Keyword.fetch!(opts, :duration_api_ms),
        is_error: Keyword.fetch!(opts, :is_error),
        num_turns: Keyword.fetch!(opts, :num_turns),
        session_id: Keyword.fetch!(opts, :session_id),
        total_cost_usd: Keyword.get(opts, :total_cost_usd),
        usage: Keyword.get(opts, :usage),
        result: Keyword.get(opts, :result),
        structured_output: Keyword.get(opts, :structured_output)
      }
    end
  end

  defmodule StreamEvent do
    @moduledoc """
    Stream event for partial message updates during streaming.

    Used when `include_partial_messages` is enabled to receive
    real-time updates as Claude generates responses.
    """

    @type t :: %__MODULE__{
            uuid: String.t(),
            session_id: String.t(),
            event: map(),
            parent_tool_use_id: String.t() | nil
          }

    @enforce_keys [:uuid, :session_id, :event]
    defstruct [:uuid, :session_id, :event, :parent_tool_use_id]

    @doc "Create a new StreamEvent."
    @spec new(String.t(), String.t(), map(), keyword()) :: t()
    def new(uuid, session_id, event, opts \\ [])
        when is_binary(uuid) and is_binary(session_id) and is_map(event) do
      %__MODULE__{
        uuid: uuid,
        session_id: session_id,
        event: event,
        parent_tool_use_id: Keyword.get(opts, :parent_tool_use_id)
      }
    end
  end

  # Type alias for any message type
  @type message ::
          UserMessage.t()
          | AssistantMessage.t()
          | SystemMessage.t()
          | ResultMessage.t()
          | StreamEvent.t()
end
