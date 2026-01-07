defmodule ClaudeAgent.Mcp.ServerTest do
  use ExUnit.Case

  alias ClaudeAgent.Mcp.{Server, Tool}

  describe "new/2" do
    test "creates server with name" do
      server = Server.new("test-server")
      assert server.name == "test-server"
      assert server.version == "1.0.0"
      assert server.tools == []
    end

    test "creates server with options" do
      server = Server.new("test-server", version: "2.0.0", tools: [])
      assert server.version == "2.0.0"
    end
  end

  describe "add_tool/2" do
    test "adds tool to server" do
      tool = Tool.new("test", "Test tool", %{"type" => "object"}, fn _ -> {:ok, "result"} end)
      server = Server.new("test-server") |> Server.add_tool(tool)
      assert length(server.tools) == 1
    end
  end

  describe "handle_request/2 initialize" do
    test "returns server info" do
      server = Server.new("my-server", version: "1.2.3")

      response = Server.handle_request(server, %{"method" => "initialize", "id" => 1})

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["serverInfo"]["name"] == "my-server"
      assert response["result"]["serverInfo"]["version"] == "1.2.3"
      assert response["result"]["protocolVersion"] == "2024-11-05"
    end
  end

  describe "handle_request/2 tools/list" do
    test "returns empty tools list" do
      server = Server.new("test")
      response = Server.handle_request(server, %{"method" => "tools/list", "id" => 1})

      assert response["result"]["tools"] == []
    end

    test "returns tools list" do
      tool = Tool.new("add", "Add numbers", %{"type" => "object"}, fn _ -> {:ok, "1"} end)
      server = Server.new("test", tools: [tool])

      response = Server.handle_request(server, %{"method" => "tools/list", "id" => 1})

      assert [%{"name" => "add", "description" => "Add numbers"}] = response["result"]["tools"]
    end
  end

  describe "handle_request/2 tools/call" do
    test "calls tool and returns result" do
      tool =
        Tool.new("add", "Add", %{"type" => "object"}, fn args ->
          {:ok, "#{args["a"] + args["b"]}"}
        end)

      server = Server.new("test", tools: [tool])

      response =
        Server.handle_request(server, %{
          "method" => "tools/call",
          "id" => 1,
          "params" => %{"name" => "add", "arguments" => %{"a" => 2, "b" => 3}}
        })

      assert response["result"]["content"] == [%{"type" => "text", "text" => "5"}]
    end

    test "returns error for unknown tool" do
      server = Server.new("test")

      response =
        Server.handle_request(server, %{
          "method" => "tools/call",
          "id" => 1,
          "params" => %{"name" => "unknown", "arguments" => %{}}
        })

      assert response["error"]["code"] == -32601
      assert response["error"]["message"] =~ "not found"
    end

    test "handles tool error" do
      tool = Tool.new("fail", "Fail", %{}, fn _ -> {:error, "Something went wrong"} end)
      server = Server.new("test", tools: [tool])

      response =
        Server.handle_request(server, %{
          "method" => "tools/call",
          "id" => 1,
          "params" => %{"name" => "fail", "arguments" => %{}}
        })

      assert response["result"]["is_error"] == true
      assert [%{"text" => "Something went wrong"}] = response["result"]["content"]
    end
  end

  describe "handle_request/2 unknown method" do
    test "returns method not found error" do
      server = Server.new("test")
      response = Server.handle_request(server, %{"method" => "unknown", "id" => 1})

      assert response["error"]["code"] == -32601
      assert response["error"]["message"] =~ "not found"
    end
  end
end
