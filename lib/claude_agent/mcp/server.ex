defmodule ClaudeAgent.Mcp.Server do
  @moduledoc """
  In-process MCP server for SDK tools.

  SDK MCP servers run directly in your Elixir application, providing better
  performance than external MCP servers (no IPC overhead) and simpler deployment
  (single process).

  ## Quick Start

      alias ClaudeAgent.Mcp.Tool

      # Define tools
      add_tool = Tool.from_spec("add", "Add two numbers",
        %{a: :number, b: :number},
        fn args -> {:ok, "\#{args["a"] + args["b"]}"} end,
        required: [:a, :b]
      )

      # Create server
      server = ClaudeAgent.create_sdk_mcp_server("calculator",
        tools: [add_tool],
        version: "1.0.0"
      )

      # Use with Claude
      ClaudeAgent.query_text("Calculate 5 + 3",
        mcp_servers: %{"calc" => %{type: :sdk, instance: server}},
        allowed_tools: ["mcp__calc__add"]
      )

  ## Complete Calculator Example

      alias ClaudeAgent.Mcp.Tool

      # Define multiple tools
      add_tool = Tool.from_spec("add", "Add numbers",
        %{a: :number, b: :number},
        fn args -> {:ok, "\#{args["a"] + args["b"]}"} end,
        required: [:a, :b]
      )

      subtract_tool = Tool.from_spec("subtract", "Subtract numbers",
        %{a: :number, b: :number},
        fn args -> {:ok, "\#{args["a"] - args["b"]}"} end,
        required: [:a, :b]
      )

      multiply_tool = Tool.from_spec("multiply", "Multiply numbers",
        %{a: :number, b: :number},
        fn args -> {:ok, "\#{args["a"] * args["b"]}"} end,
        required: [:a, :b]
      )

      divide_tool = Tool.from_spec("divide", "Divide numbers",
        %{a: :number, b: :number},
        fn args ->
          if args["b"] == 0 do
            {:error, "Cannot divide by zero"}
          else
            {:ok, "\#{args["a"] / args["b"]}"}
          end
        end,
        required: [:a, :b]
      )

      # Create server with all tools
      calculator = ClaudeAgent.create_sdk_mcp_server("calc",
        tools: [add_tool, subtract_tool, multiply_tool, divide_tool],
        version: "2.0.0"
      )

      # Use with streaming client for multi-turn conversation
      {:ok, client} = ClaudeAgent.Client.start_link(
        mcp_servers: %{"calc" => %{type: :sdk, instance: calculator}},
        allowed_tools: [
          "mcp__calc__add",
          "mcp__calc__subtract",
          "mcp__calc__multiply",
          "mcp__calc__divide"
        ]
      )

      ClaudeAgent.Client.query(client, "Calculate (15 + 27) * 3")
      client |> ClaudeAgent.Client.receive_response() |> Enum.to_list()

  ## Multiple Servers

  You can run multiple SDK MCP servers simultaneously:

      # Create specialized servers
      calculator = ClaudeAgent.create_sdk_mcp_server("calc", tools: [add_tool, ...])
      weather = ClaudeAgent.create_sdk_mcp_server("weather", tools: [weather_tool])
      database = ClaudeAgent.create_sdk_mcp_server("db", tools: [query_tool, ...])

      # Use all servers in one query
      ClaudeAgent.query_text("...",
        mcp_servers: %{
          "calc" => %{type: :sdk, instance: calculator},
          "weather" => %{type: :sdk, instance: weather},
          "db" => %{type: :sdk, instance: database}
        },
        allowed_tools: [
          "mcp__calc__add",
          "mcp__weather__get_weather",
          "mcp__db__query_users"
        ]
      )

  ## MCP Protocol

  The server implements the MCP 2024-11-05 protocol and handles:

  - `initialize` - Returns server info and capabilities
  - `tools/list` - Lists available tools with schemas
  - `tools/call` - Invokes a tool handler
  - `notifications/initialized` - Acknowledges initialization

  All communication follows JSON-RPC 2.0 format.

  ## Tool Naming

  Tools are exposed to Claude with the naming convention:
  `mcp__<server_name>__<tool_name>`

  Example:
  - Server name: "calculator"
  - Tool name: "add"
  - Full name: "mcp__calculator__add"

  ## Performance

  SDK MCP tools run in your application process with zero IPC overhead,
  making them significantly faster than external MCP servers.

  ## Best Practices

  1. **Group related tools** - Put related tools in the same server
  2. **Use descriptive names** - Server and tool names should be clear
  3. **Handle errors gracefully** - Tools should return `{:error, message}`
  4. **Version your servers** - Use semantic versioning for changes
  5. **Test tools independently** - Tools are functions, easy to unit test

  ## See Also

  - `ClaudeAgent.Mcp.Tool` - Tool definition and creation
  - `ClaudeAgent.create_sdk_mcp_server/2` - Convenient server creation
  """

  alias ClaudeAgent.Mcp.Tool

  defstruct [:name, :version, :tools]

  @type t :: %__MODULE__{
          name: String.t(),
          version: String.t(),
          tools: [Tool.t()]
        }

  @doc """
  Create a new SDK MCP server.

  ## Options

  - `:tools` - List of `Tool` structs (default: [])
  - `:version` - Server version (default: "1.0.0")

  ## Examples

      server = Server.new("my-server", tools: [tool1, tool2])
  """
  @spec new(String.t(), keyword()) :: t()
  def new(name, opts \\ []) when is_binary(name) do
    %__MODULE__{
      name: name,
      version: Keyword.get(opts, :version, "1.0.0"),
      tools: Keyword.get(opts, :tools, [])
    }
  end

  @doc """
  Add a tool to the server.
  """
  @spec add_tool(t(), Tool.t()) :: t()
  def add_tool(%__MODULE__{} = server, %Tool{} = tool) do
    %{server | tools: server.tools ++ [tool]}
  end

  @doc """
  Handle an MCP request.

  ## Parameters

  - `server` - The server struct
  - `request` - JSONRPC request map

  ## Returns

  A JSONRPC response map.
  """
  @spec handle_request(t(), map()) :: map()
  def handle_request(%__MODULE__{} = server, request) do
    method = Map.get(request, "method")
    params = Map.get(request, "params", %{})
    id = Map.get(request, "id")

    result =
      try do
        case method do
          "initialize" ->
            handle_initialize(server)

          "tools/list" ->
            handle_list_tools(server)

          "tools/call" ->
            handle_call_tool(server, params)

          "notifications/initialized" ->
            # Just acknowledge
            %{}

          _ ->
            {:error, -32601, "Method '#{method}' not found"}
        end
      rescue
        e ->
          {:error, -32603, Exception.message(e)}
      end

    build_response(id, result)
  end

  # Private handlers

  defp handle_initialize(%__MODULE__{} = server) do
    %{
      "protocolVersion" => "2024-11-05",
      "capabilities" => %{
        "tools" => %{}
      },
      "serverInfo" => %{
        "name" => server.name,
        "version" => server.version
      }
    }
  end

  defp handle_list_tools(%__MODULE__{} = server) do
    tools =
      Enum.map(server.tools, fn tool ->
        %{
          "name" => tool.name,
          "description" => tool.description,
          "inputSchema" => tool.input_schema
        }
      end)

    %{"tools" => tools}
  end

  defp handle_call_tool(%__MODULE__{} = server, params) do
    tool_name = Map.get(params, "name")
    arguments = Map.get(params, "arguments", %{})

    case Enum.find(server.tools, fn t -> t.name == tool_name end) do
      nil ->
        {:error, -32601, "Tool '#{tool_name}' not found"}

      tool ->
        case tool.handler.(arguments) do
          {:ok, content} when is_list(content) ->
            %{"content" => content}

          {:ok, content} ->
            %{"content" => [%{"type" => "text", "text" => to_string(content)}]}

          {:error, message} ->
            %{
              "content" => [%{"type" => "text", "text" => message}],
              "is_error" => true
            }

          other ->
            %{"content" => [%{"type" => "text", "text" => inspect(other)}]}
        end
    end
  end

  defp build_response(id, {:error, code, message}) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{
        "code" => code,
        "message" => message
      }
    }
  end

  defp build_response(id, result) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => result
    }
  end
end
