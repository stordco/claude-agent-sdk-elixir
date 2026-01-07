defmodule ClaudeAgentSdk.Types.ContentBlocks do
  @moduledoc """
  Content block type definitions for Claude SDK messages.

  Content blocks represent the individual pieces of content within messages:

  - `TextBlock` - Plain text content
  - `ThinkingBlock` - Claude's thinking/reasoning content
  - `ToolUseBlock` - A tool invocation request
  - `ToolResultBlock` - The result of a tool invocation

  ## Examples

      # Pattern matching on content blocks
      case block do
        %TextBlock{text: text} ->
          IO.puts("Text: \#{text}")

        %ToolUseBlock{name: name, input: input} ->
          IO.puts("Tool: \#{name} with input: \#{inspect(input)}")

        %ThinkingBlock{thinking: thinking} ->
          IO.puts("Thinking: \#{thinking}")

        %ToolResultBlock{content: content, is_error: true} ->
          IO.puts("Tool error: \#{content}")
      end
  """

  defmodule TextBlock do
    @moduledoc "Plain text content block."

    @type t :: %__MODULE__{
            text: String.t()
          }

    @enforce_keys [:text]
    defstruct [:text]

    @doc "Create a new TextBlock."
    @spec new(String.t()) :: t()
    def new(text) when is_binary(text) do
      %__MODULE__{text: text}
    end
  end

  defmodule ThinkingBlock do
    @moduledoc """
    Thinking/reasoning content block.

    Contains Claude's internal reasoning process and a signature
    for verification.
    """

    @type t :: %__MODULE__{
            thinking: String.t(),
            signature: String.t()
          }

    @enforce_keys [:thinking, :signature]
    defstruct [:thinking, :signature]

    @doc "Create a new ThinkingBlock."
    @spec new(String.t(), String.t()) :: t()
    def new(thinking, signature) when is_binary(thinking) and is_binary(signature) do
      %__MODULE__{thinking: thinking, signature: signature}
    end
  end

  defmodule ToolUseBlock do
    @moduledoc """
    Tool use content block.

    Represents a request from Claude to use a specific tool
    with given input parameters.
    """

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            input: map()
          }

    @enforce_keys [:id, :name, :input]
    defstruct [:id, :name, :input]

    @doc "Create a new ToolUseBlock."
    @spec new(String.t(), String.t(), map()) :: t()
    def new(id, name, input) when is_binary(id) and is_binary(name) and is_map(input) do
      %__MODULE__{id: id, name: name, input: input}
    end
  end

  defmodule ToolResultBlock do
    @moduledoc """
    Tool result content block.

    Contains the result of a tool invocation, which may be
    successful content or an error.
    """

    @type t :: %__MODULE__{
            tool_use_id: String.t(),
            content: String.t() | [map()] | nil,
            is_error: boolean() | nil
          }

    @enforce_keys [:tool_use_id]
    defstruct [:tool_use_id, :content, :is_error]

    @doc "Create a new ToolResultBlock."
    @spec new(String.t(), String.t() | [map()] | nil, boolean() | nil) :: t()
    def new(tool_use_id, content \\ nil, is_error \\ nil) when is_binary(tool_use_id) do
      %__MODULE__{tool_use_id: tool_use_id, content: content, is_error: is_error}
    end
  end

  # Type alias for any content block
  @type content_block :: TextBlock.t() | ThinkingBlock.t() | ToolUseBlock.t() | ToolResultBlock.t()

  @doc """
  Parse a content block from a map.

  ## Examples

      iex> ContentBlocks.from_map(%{"type" => "text", "text" => "Hello"})
      {:ok, %TextBlock{text: "Hello"}}

      iex> ContentBlocks.from_map(%{"type" => "unknown"})
      {:error, "Unknown content block type: unknown"}
  """
  @spec from_map(map()) :: {:ok, content_block()} | {:error, String.t()}
  def from_map(%{"type" => "text", "text" => text}) do
    {:ok, TextBlock.new(text)}
  end

  def from_map(%{"type" => "thinking", "thinking" => thinking, "signature" => signature}) do
    {:ok, ThinkingBlock.new(thinking, signature)}
  end

  def from_map(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}) do
    {:ok, ToolUseBlock.new(id, name, input)}
  end

  def from_map(%{"type" => "tool_result", "tool_use_id" => tool_use_id} = block) do
    content = Map.get(block, "content")
    is_error = Map.get(block, "is_error")
    {:ok, ToolResultBlock.new(tool_use_id, content, is_error)}
  end

  def from_map(%{"type" => type}) do
    {:error, "Unknown content block type: #{type}"}
  end

  def from_map(_) do
    {:error, "Invalid content block: missing type field"}
  end

  @doc """
  Parse a content block from a map, raising on error.

  ## Examples

      iex> ContentBlocks.from_map!(%{"type" => "text", "text" => "Hello"})
      %TextBlock{text: "Hello"}
  """
  @spec from_map!(map()) :: content_block()
  def from_map!(map) do
    case from_map(map) do
      {:ok, block} -> block
      {:error, message} -> raise ArgumentError, message
    end
  end
end
