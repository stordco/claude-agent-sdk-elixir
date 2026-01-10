defmodule ClaudeAgent.Mcp.ToolTest do
  use ExUnit.Case

  alias ClaudeAgent.Mcp.Tool

  describe "new/4" do
    test "creates tool with basic schema" do
      tool =
        Tool.new(
          "echo",
          "Echo input",
          %{"type" => "object", "properties" => %{"text" => %{"type" => "string"}}},
          fn args -> {:ok, args["text"]} end
        )

      assert tool.name == "echo"
      assert tool.description == "Echo input"
      assert tool.input_schema["type"] == "object"
      assert is_function(tool.handler, 1)
    end

    test "requires all fields" do
      assert_raise FunctionClauseError, fn ->
        Tool.new("test", "Test", %{}, nil)
      end
    end
  end

  describe "from_spec/5" do
    test "creates tool from type specification" do
      tool =
        Tool.from_spec("add", "Add numbers", %{a: :number, b: :number}, fn args ->
          {:ok, args["a"] + args["b"]}
        end)

      assert tool.name == "add"
      assert tool.description == "Add numbers"
      assert tool.input_schema["type"] == "object"
      assert tool.input_schema["properties"]["a"]["type"] == "number"
      assert tool.input_schema["properties"]["b"]["type"] == "number"
    end

    test "handles required fields" do
      tool =
        Tool.from_spec("greet", "Greet", %{name: :string}, fn _ -> {:ok, "Hi"} end,
          required: [:name]
        )

      assert tool.input_schema["required"] == ["name"]
    end

    test "omits required when empty" do
      tool = Tool.from_spec("test", "Test", %{opt: :string}, fn _ -> {:ok, ""} end)

      refute Map.has_key?(tool.input_schema, "required")
    end

    test "converts all basic types" do
      tool =
        Tool.from_spec(
          "multi",
          "Multi type",
          %{
            str: :string,
            num: :number,
            int: :integer,
            bool: :boolean,
            arr: :array,
            obj: :object
          },
          fn _ -> {:ok, "ok"} end
        )

      schema = tool.input_schema["properties"]
      assert schema["str"]["type"] == "string"
      assert schema["num"]["type"] == "number"
      assert schema["int"]["type"] == "integer"
      assert schema["bool"]["type"] == "boolean"
      assert schema["arr"]["type"] == "array"
      assert schema["obj"]["type"] == "object"
    end

    test "handles custom schema maps" do
      custom_schema = %{"type" => "string", "minLength" => 5}

      tool =
        Tool.from_spec("test", "Test", %{custom: custom_schema}, fn _ -> {:ok, ""} end)

      assert tool.input_schema["properties"]["custom"] == custom_schema
    end
  end

  describe "call/2" do
    test "executes tool handler" do
      tool =
        Tool.from_spec("add", "Add", %{a: :number, b: :number}, fn args ->
          {:ok, args["a"] + args["b"]}
        end)

      assert {:ok, 5} = Tool.call(tool, %{"a" => 2, "b" => 3})
    end

    test "handles error returns" do
      tool =
        Tool.from_spec("fail", "Fail", %{}, fn _ ->
          {:error, "Something went wrong"}
        end)

      assert {:error, "Something went wrong"} = Tool.call(tool, %{})
    end

    test "passes arguments correctly" do
      tool =
        Tool.from_spec("greet", "Greet", %{name: :string}, fn args ->
          {:ok, "Hello, #{args["name"]}!"}
        end)

      assert {:ok, "Hello, Alice!"} = Tool.call(tool, %{"name" => "Alice"})
    end

    test "handles complex return values" do
      tool =
        Tool.from_spec("multi", "Multi", %{}, fn _ ->
          {:ok,
           [
             %{"type" => "text", "text" => "Result:"},
             %{"type" => "text", "text" => "42"}
           ]}
        end)

      assert {:ok, [%{"type" => "text", "text" => "Result:"}, %{"type" => "text", "text" => "42"}]} =
               Tool.call(tool, %{})
    end
  end

  describe "type conversion" do
    test "handles string type" do
      tool = Tool.from_spec("test", "Test", %{param: :string}, fn _ -> {:ok, ""} end)
      assert tool.input_schema["properties"]["param"]["type"] == "string"
    end

    test "handles number type" do
      tool = Tool.from_spec("test", "Test", %{param: :number}, fn _ -> {:ok, ""} end)
      assert tool.input_schema["properties"]["param"]["type"] == "number"
    end

    test "handles integer type" do
      tool = Tool.from_spec("test", "Test", %{param: :integer}, fn _ -> {:ok, ""} end)
      assert tool.input_schema["properties"]["param"]["type"] == "integer"
    end

    test "handles boolean type" do
      tool = Tool.from_spec("test", "Test", %{param: :boolean}, fn _ -> {:ok, ""} end)
      assert tool.input_schema["properties"]["param"]["type"] == "boolean"
    end

    test "handles array type" do
      tool = Tool.from_spec("test", "Test", %{param: :array}, fn _ -> {:ok, ""} end)
      assert tool.input_schema["properties"]["param"]["type"] == "array"
    end

    test "handles object type" do
      tool = Tool.from_spec("test", "Test", %{param: :object}, fn _ -> {:ok, ""} end)
      assert tool.input_schema["properties"]["param"]["type"] == "object"
    end
  end

  describe "real-world examples" do
    test "calculator tool works correctly" do
      add_tool =
        Tool.from_spec("add", "Add two numbers", %{a: :number, b: :number}, fn args ->
          {:ok, "#{args["a"]} + #{args["b"]} = #{args["a"] + args["b"]}"}
        end)

      assert {:ok, "5 + 3 = 8"} = Tool.call(add_tool, %{"a" => 5, "b" => 3})
    end

    test "divide tool handles errors" do
      divide_tool =
        Tool.from_spec("divide", "Divide numbers", %{a: :number, b: :number}, fn args ->
          if args["b"] == 0 do
            {:error, "Cannot divide by zero"}
          else
            {:ok, args["a"] / args["b"]}
          end
        end)

      assert {:error, "Cannot divide by zero"} = Tool.call(divide_tool, %{"a" => 10, "b" => 0})
      assert {:ok, 5.0} = Tool.call(divide_tool, %{"a" => 10, "b" => 2})
    end

    test "greeting tool with optional parameter" do
      greet_tool =
        Tool.from_spec(
          "greet",
          "Greet a person",
          %{name: :string, style: :string},
          fn args ->
            greeting =
              case args["style"] do
                "formal" -> "Good day, #{args["name"]}."
                "casual" -> "Hey #{args["name"]}!"
                _ -> "Hello #{args["name"]}!"
              end

            {:ok, greeting}
          end,
          required: [:name]
        )

      assert {:ok, "Hey Alice!"} = Tool.call(greet_tool, %{"name" => "Alice", "style" => "casual"})
      assert {:ok, "Hello Bob!"} = Tool.call(greet_tool, %{"name" => "Bob"})
    end

    test "tool with stateful closure" do
      counter = Agent.start_link(fn -> 0 end)
      {:ok, agent} = counter

      count_tool =
        Tool.from_spec("increment", "Increment counter", %{}, fn _ ->
          new_count = Agent.get_and_update(agent, fn count -> {count + 1, count + 1} end)
          {:ok, "Count: #{new_count}"}
        end)

      assert {:ok, "Count: 1"} = Tool.call(count_tool, %{})
      assert {:ok, "Count: 2"} = Tool.call(count_tool, %{})
      assert {:ok, "Count: 3"} = Tool.call(count_tool, %{})

      Agent.stop(agent)
    end

    test "tool returning multiple content blocks" do
      chart_tool =
        Tool.from_spec("generate_chart", "Generate a chart", %{title: :string}, fn args ->
          {:ok,
           [
             %{"type" => "text", "text" => "Generated chart: #{args["title"]}"},
             %{"type" => "image", "data" => "base64encodeddata", "mimeType" => "image/png"}
           ]}
        end)

      assert {:ok,
              [
                %{"type" => "text", "text" => "Generated chart: Sales Report"},
                %{"type" => "image", "data" => "base64encodeddata", "mimeType" => "image/png"}
              ]} = Tool.call(chart_tool, %{"title" => "Sales Report"})
    end
  end

  describe "edge cases" do
    test "handles empty arguments" do
      tool = Tool.from_spec("no_args", "No args", %{}, fn _args -> {:ok, "executed"} end)

      assert {:ok, "executed"} = Tool.call(tool, %{})
    end

    test "handles missing optional parameters" do
      tool =
        Tool.from_spec(
          "optional",
          "Optional param",
          %{required_param: :string, optional_param: :string},
          fn args ->
            {:ok, "Required: #{args["required_param"]}, Optional: #{Map.get(args, "optional_param", "N/A")}"}
          end,
          required: [:required_param]
        )

      assert {:ok, "Required: test, Optional: N/A"} =
               Tool.call(tool, %{"required_param" => "test"})

      assert {:ok, "Required: test, Optional: value"} =
               Tool.call(tool, %{"required_param" => "test", "optional_param" => "value"})
    end

    test "tool name with special characters" do
      tool =
        Tool.from_spec("my-tool_v2", "Special name", %{}, fn _ -> {:ok, "ok"} end)

      assert tool.name == "my-tool_v2"
    end

    test "empty description is allowed" do
      tool = Tool.from_spec("test", "", %{}, fn _ -> {:ok, ""} end)
      assert tool.description == ""
    end
  end
end
