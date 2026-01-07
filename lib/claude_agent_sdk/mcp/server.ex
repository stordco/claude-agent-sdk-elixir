defmodule ClaudeAgentSdk.Mcp.Server do
  @moduledoc """
  In-process MCP server for SDK tools.

  Unlike external MCP servers that run as separate processes, SDK MCP servers
  run directly in your Elixir application. This provides better performance
  and simpler deployment.

  ## Creating a Server

      # Define tools
      add_tool = %Tool{
        name: "add",
        description: "Add two numbers",
        input_schema: %{
          "type" => "object",
          "properties" => %{
            "a" => %{"type" => "number"},
            "b" => %{"type" => "number"}
          },
          "required" => ["a", "b"]
        },
        handler: fn args ->
          result = args["a"] + args["b"]
          {:ok, [%{"type" => "text", "text" => "\#{result}"}]}
        end
      }

      # Create server
      server = Server.new("calculator", tools: [add_tool], version: "1.0.0")

      # Use with options
      opts = %Options{
        mcp_servers: %{"calc" => %{type: :sdk, instance: server}},
        allowed_tools: ["mcp__calc__add"]
      }

  ## Handling Requests

  The server automatically handles these MCP methods:

  - `initialize` - Returns server info and capabilities
  - `tools/list` - Lists available tools
  - `tools/call` - Invokes a tool
  - `notifications/initialized` - Acknowledges initialization
  """

  alias ClaudeAgentSdk.Mcp.Tool

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
