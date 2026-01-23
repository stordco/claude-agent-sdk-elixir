defmodule ClaudeAgent.Types.ContentBlocksTest do
  use ExUnit.Case

  alias ClaudeAgent.Types.ContentBlocks
  alias ClaudeAgent.Types.ContentBlocks.{TextBlock, ThinkingBlock, ToolResultBlock, ToolUseBlock}

  describe "TextBlock" do
    test "creates with text" do
      block = TextBlock.new("Hello")
      assert block.text == "Hello"
    end
  end

  describe "ThinkingBlock" do
    test "creates with thinking and signature" do
      block = ThinkingBlock.new("I'm thinking...", "sig-123")
      assert block.thinking == "I'm thinking..."
      assert block.signature == "sig-123"
    end
  end

  describe "ToolUseBlock" do
    test "creates with id, name, and input" do
      block = ToolUseBlock.new("tool_1", "Read", %{"path" => "/test"})
      assert block.id == "tool_1"
      assert block.name == "Read"
      assert block.input == %{"path" => "/test"}
    end
  end

  describe "ToolResultBlock" do
    test "creates with tool_use_id" do
      block = ToolResultBlock.new("tool_1")
      assert block.tool_use_id == "tool_1"
      assert block.content == nil
      assert block.is_error == nil
    end

    test "creates with content and is_error" do
      block = ToolResultBlock.new("tool_1", "result text", false)
      assert block.content == "result text"
      assert block.is_error == false
    end
  end

  describe "from_map/1" do
    test "parses text block" do
      assert {:ok, %TextBlock{text: "Hello"}} =
               ContentBlocks.from_map(%{"type" => "text", "text" => "Hello"})
    end

    test "parses thinking block" do
      assert {:ok, %ThinkingBlock{thinking: "...", signature: "sig"}} =
               ContentBlocks.from_map(%{
                 "type" => "thinking",
                 "thinking" => "...",
                 "signature" => "sig"
               })
    end

    test "parses tool_use block" do
      assert {:ok, %ToolUseBlock{id: "t1", name: "Read", input: %{}}} =
               ContentBlocks.from_map(%{
                 "type" => "tool_use",
                 "id" => "t1",
                 "name" => "Read",
                 "input" => %{}
               })
    end

    test "parses tool_result block" do
      assert {:ok, %ToolResultBlock{tool_use_id: "t1", content: "result"}} =
               ContentBlocks.from_map(%{
                 "type" => "tool_result",
                 "tool_use_id" => "t1",
                 "content" => "result"
               })
    end

    test "returns error for unknown type" do
      assert {:error, "Unknown content block type: unknown"} =
               ContentBlocks.from_map(%{"type" => "unknown"})
    end

    test "returns error for missing type" do
      assert {:error, "Invalid content block: missing type field"} =
               ContentBlocks.from_map(%{"text" => "hello"})
    end
  end

  describe "from_map!/1" do
    test "returns block for valid data" do
      assert %TextBlock{text: "Hello"} =
               ContentBlocks.from_map!(%{"type" => "text", "text" => "Hello"})
    end

    test "raises for invalid data" do
      assert_raise ArgumentError, fn ->
        ContentBlocks.from_map!(%{"type" => "unknown"})
      end
    end
  end
end
