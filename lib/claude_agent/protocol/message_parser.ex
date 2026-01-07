defmodule ClaudeAgent.Protocol.MessageParser do
  @moduledoc """
  Parser for Claude SDK messages from CLI output.

  Converts raw JSON maps from the CLI into typed message structs.

  ## Examples

      iex> data = %{"type" => "assistant", "message" => %{"content" => [...], "model" => "claude-3"}}
      iex> MessageParser.parse(data)
      {:ok, %AssistantMessage{...}}

      iex> MessageParser.parse(%{"type" => "unknown"})
      {:error, %MessageParseError{...}}
  """

  alias ClaudeAgent.Errors.MessageParseError
  alias ClaudeAgent.Types.ContentBlocks

  alias ClaudeAgent.Types.Messages.{
    AssistantMessage,
    ResultMessage,
    StreamEvent,
    SystemMessage,
    UserMessage
  }

  @type message :: ClaudeAgent.Types.Messages.message()

  @doc """
  Parse a message from CLI output into a typed struct.

  ## Parameters

  - `data` - Raw map from JSON decoding

  ## Returns

  - `{:ok, message}` on success
  - `{:error, %MessageParseError{}}` on failure

  ## Examples

      iex> MessageParser.parse(%{"type" => "user", "message" => %{"content" => "Hello"}})
      {:ok, %UserMessage{content: "Hello"}}
  """
  @spec parse(map()) :: {:ok, message()} | {:error, MessageParseError.t()}
  def parse(data) when is_map(data) do
    case Map.get(data, "type") do
      nil ->
        {:error, MessageParseError.exception(message: "Message missing 'type' field", data: data)}

      "user" ->
        parse_user_message(data)

      "assistant" ->
        parse_assistant_message(data)

      "system" ->
        parse_system_message(data)

      "result" ->
        parse_result_message(data)

      "stream_event" ->
        parse_stream_event(data)

      type ->
        {:error, MessageParseError.exception(message: "Unknown message type: #{type}", data: data)}
    end
  end

  def parse(data) do
    type_name =
      cond do
        is_nil(data) -> "nil"
        is_binary(data) -> "string"
        is_list(data) -> "list"
        is_atom(data) -> "atom"
        is_struct(data) -> data.__struct__ |> to_string()
        true -> "unknown"
      end

    {:error,
     MessageParseError.exception(
       message: "Invalid message data type (expected map, got #{type_name})",
       data: data
     )}
  end

  @doc """
  Parse a message from CLI output, raising on error.

  ## Examples

      iex> MessageParser.parse!(%{"type" => "user", "message" => %{"content" => "Hello"}})
      %UserMessage{content: "Hello"}
  """
  @spec parse!(map()) :: message()
  def parse!(data) do
    case parse(data) do
      {:ok, message} -> message
      {:error, error} -> raise error
    end
  end

  # Private parsers

  defp parse_user_message(data) do
    try do
      message = Map.fetch!(data, "message")
      content = Map.fetch!(message, "content")
      parent_tool_use_id = Map.get(data, "parent_tool_use_id")
      uuid = Map.get(data, "uuid")

      parsed_content =
        if is_list(content) do
          Enum.map(content, &parse_content_block!/1)
        else
          content
        end

      {:ok, UserMessage.new(parsed_content, uuid: uuid, parent_tool_use_id: parent_tool_use_id)}
    rescue
      e in KeyError ->
        {:error,
         MessageParseError.exception(
           message: "Missing required field in user message: #{e.key}",
           data: data
         )}
    end
  end

  defp parse_assistant_message(data) do
    try do
      message = Map.fetch!(data, "message")
      content = Map.fetch!(message, "content")
      model = Map.fetch!(message, "model")
      parent_tool_use_id = Map.get(data, "parent_tool_use_id")
      error = AssistantMessage.parse_error(Map.get(message, "error"))

      parsed_content = Enum.map(content, &parse_content_block!/1)

      {:ok,
       AssistantMessage.new(parsed_content, model,
         parent_tool_use_id: parent_tool_use_id,
         error: error
       )}
    rescue
      e in KeyError ->
        {:error,
         MessageParseError.exception(
           message: "Missing required field in assistant message: #{e.key}",
           data: data
         )}
    end
  end

  defp parse_system_message(data) do
    try do
      subtype = Map.fetch!(data, "subtype")
      {:ok, SystemMessage.new(subtype, data)}
    rescue
      e in KeyError ->
        {:error,
         MessageParseError.exception(
           message: "Missing required field in system message: #{e.key}",
           data: data
         )}
    end
  end

  defp parse_result_message(data) do
    try do
      {:ok,
       ResultMessage.new(
         subtype: Map.fetch!(data, "subtype"),
         duration_ms: Map.fetch!(data, "duration_ms"),
         duration_api_ms: Map.fetch!(data, "duration_api_ms"),
         is_error: Map.fetch!(data, "is_error"),
         num_turns: Map.fetch!(data, "num_turns"),
         session_id: Map.fetch!(data, "session_id"),
         total_cost_usd: Map.get(data, "total_cost_usd"),
         usage: Map.get(data, "usage"),
         result: Map.get(data, "result"),
         structured_output: Map.get(data, "structured_output")
       )}
    rescue
      e in KeyError ->
        {:error,
         MessageParseError.exception(
           message: "Missing required field in result message: #{e.key}",
           data: data
         )}
    end
  end

  defp parse_stream_event(data) do
    try do
      {:ok,
       StreamEvent.new(
         Map.fetch!(data, "uuid"),
         Map.fetch!(data, "session_id"),
         Map.fetch!(data, "event"),
         parent_tool_use_id: Map.get(data, "parent_tool_use_id")
       )}
    rescue
      e in KeyError ->
        {:error,
         MessageParseError.exception(
           message: "Missing required field in stream_event message: #{e.key}",
           data: data
         )}
    end
  end

  defp parse_content_block!(block) do
    case ContentBlocks.from_map(block) do
      {:ok, parsed} -> parsed
      {:error, message} -> raise ArgumentError, message
    end
  end
end
