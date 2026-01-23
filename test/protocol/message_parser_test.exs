defmodule ClaudeAgent.Protocol.MessageParserTest do
  use ExUnit.Case

  alias ClaudeAgent.Errors.MessageParseError
  alias ClaudeAgent.Protocol.MessageParser
  alias ClaudeAgent.Types.ContentBlocks.{TextBlock, ThinkingBlock, ToolResultBlock, ToolUseBlock}
  alias ClaudeAgent.Types.Messages.{AssistantMessage, ResultMessage, SystemMessage, UserMessage}

  describe "parse/1 user messages" do
    test "parses valid user message with string content" do
      data = %{
        "type" => "user",
        "message" => %{"content" => "Hello"}
      }

      assert {:ok, %UserMessage{content: "Hello"}} = MessageParser.parse(data)
    end

    test "parses user message with text block content" do
      data = %{
        "type" => "user",
        "message" => %{
          "content" => [%{"type" => "text", "text" => "Hello"}]
        }
      }

      assert {:ok, %UserMessage{content: [%TextBlock{text: "Hello"}]}} = MessageParser.parse(data)
    end

    test "parses user message with uuid" do
      data = %{
        "type" => "user",
        "uuid" => "msg-abc123",
        "message" => %{"content" => "Hello"}
      }

      assert {:ok, %UserMessage{uuid: "msg-abc123"}} = MessageParser.parse(data)
    end

    test "parses user message with parent_tool_use_id" do
      data = %{
        "type" => "user",
        "parent_tool_use_id" => "toolu_123",
        "message" => %{"content" => "Hello"}
      }

      assert {:ok, %UserMessage{parent_tool_use_id: "toolu_123"}} = MessageParser.parse(data)
    end

    test "parses user message with tool_use block" do
      data = %{
        "type" => "user",
        "message" => %{
          "content" => [
            %{
              "type" => "tool_use",
              "id" => "tool_1",
              "name" => "Read",
              "input" => %{"path" => "/test"}
            }
          ]
        }
      }

      assert {:ok, %UserMessage{content: [%ToolUseBlock{id: "tool_1", name: "Read"}]}} =
               MessageParser.parse(data)
    end

    test "parses user message with tool_result block" do
      data = %{
        "type" => "user",
        "message" => %{
          "content" => [
            %{
              "type" => "tool_result",
              "tool_use_id" => "tool_1",
              "content" => "result",
              "is_error" => false
            }
          ]
        }
      }

      assert {:ok,
              %UserMessage{content: [%ToolResultBlock{tool_use_id: "tool_1", content: "result"}]}} =
               MessageParser.parse(data)
    end
  end

  describe "parse/1 assistant messages" do
    test "parses valid assistant message" do
      data = %{
        "type" => "assistant",
        "message" => %{
          "content" => [%{"type" => "text", "text" => "Hello"}],
          "model" => "claude-3"
        }
      }

      assert {:ok, %AssistantMessage{content: [%TextBlock{text: "Hello"}], model: "claude-3"}} =
               MessageParser.parse(data)
    end

    test "parses assistant message with thinking block" do
      data = %{
        "type" => "assistant",
        "message" => %{
          "content" => [
            %{"type" => "thinking", "thinking" => "Let me think...", "signature" => "sig-123"}
          ],
          "model" => "claude-3"
        }
      }

      assert {:ok,
              %AssistantMessage{
                content: [%ThinkingBlock{thinking: "Let me think...", signature: "sig-123"}]
              }} =
               MessageParser.parse(data)
    end

    test "parses assistant message with tool_use block" do
      data = %{
        "type" => "assistant",
        "message" => %{
          "content" => [
            %{
              "type" => "tool_use",
              "id" => "tool_1",
              "name" => "Bash",
              "input" => %{"command" => "ls"}
            }
          ],
          "model" => "claude-3"
        }
      }

      assert {:ok,
              %AssistantMessage{content: [%ToolUseBlock{name: "Bash", input: %{"command" => "ls"}}]}} =
               MessageParser.parse(data)
    end

    test "parses assistant message with parent_tool_use_id" do
      data = %{
        "type" => "assistant",
        "parent_tool_use_id" => "toolu_456",
        "message" => %{
          "content" => [%{"type" => "text", "text" => "Done"}],
          "model" => "claude-3"
        }
      }

      assert {:ok, %AssistantMessage{parent_tool_use_id: "toolu_456"}} = MessageParser.parse(data)
    end
  end

  describe "parse/1 system messages" do
    test "parses valid system message" do
      data = %{"type" => "system", "subtype" => "start"}

      assert {:ok, %SystemMessage{subtype: "start"}} = MessageParser.parse(data)
    end
  end

  describe "parse/1 result messages" do
    test "parses valid result message" do
      data = %{
        "type" => "result",
        "subtype" => "success",
        "duration_ms" => 1000,
        "duration_api_ms" => 500,
        "is_error" => false,
        "num_turns" => 2,
        "session_id" => "session_123",
        "total_cost_usd" => 0.01
      }

      assert {:ok, %ResultMessage{subtype: "success", total_cost_usd: 0.01}} =
               MessageParser.parse(data)
    end

    test "parses result message with optional fields" do
      data = %{
        "type" => "result",
        "subtype" => "success",
        "duration_ms" => 1000,
        "duration_api_ms" => 500,
        "is_error" => false,
        "num_turns" => 1,
        "session_id" => "session_456",
        "usage" => %{"input_tokens" => 100, "output_tokens" => 50},
        "result" => "Done",
        "structured_output" => %{"key" => "value"}
      }

      assert {:ok, %ResultMessage{usage: %{"input_tokens" => 100}, result: "Done"}} =
               MessageParser.parse(data)
    end
  end

  describe "parse/1 errors" do
    test "returns error for non-map data" do
      assert {:error, %MessageParseError{}} = MessageParser.parse("not a map")
    end

    test "returns error for missing type field" do
      assert {:error, %MessageParseError{message: msg}} = MessageParser.parse(%{"message" => %{}})
      assert msg =~ "missing 'type'"
    end

    test "returns error for unknown message type" do
      assert {:error, %MessageParseError{message: msg}} =
               MessageParser.parse(%{"type" => "unknown"})

      assert msg =~ "Unknown message type"
    end

    test "returns error for user message missing fields" do
      assert {:error, %MessageParseError{}} = MessageParser.parse(%{"type" => "user"})
    end

    test "returns error for assistant message missing fields" do
      assert {:error, %MessageParseError{}} = MessageParser.parse(%{"type" => "assistant"})
    end

    test "returns error for system message missing fields" do
      assert {:error, %MessageParseError{}} = MessageParser.parse(%{"type" => "system"})
    end

    test "returns error for result message missing fields" do
      assert {:error, %MessageParseError{}} =
               MessageParser.parse(%{"type" => "result", "subtype" => "success"})
    end
  end

  describe "parse!/1" do
    test "returns message for valid data" do
      data = %{
        "type" => "user",
        "message" => %{"content" => "Hello"}
      }

      assert %UserMessage{content: "Hello"} = MessageParser.parse!(data)
    end

    test "raises for invalid data" do
      assert_raise MessageParseError, fn ->
        MessageParser.parse!(%{"type" => "unknown"})
      end
    end
  end
end
