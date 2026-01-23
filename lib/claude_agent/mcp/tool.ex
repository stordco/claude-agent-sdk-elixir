defmodule ClaudeAgent.Mcp.Tool do
  @moduledoc """
  Tool definition for SDK MCP servers.

  Tools are functions that Claude can call to perform actions. SDK MCP tools
  run directly in your Elixir application process, providing better performance
  than external MCP servers.

  ## Quick Start

  The easiest way to create a tool is with `from_spec/5`:

      alias ClaudeAgent.Mcp.Tool

      # Simple tool with type inference
      greet_tool = Tool.from_spec("greet", "Greet a person",
        %{name: :string},
        fn args -> {:ok, "Hello, \#{args["name"]}!"} end,
        required: [:name]
      )

      # Calculator tool with error handling
      divide_tool = Tool.from_spec("divide", "Divide two numbers",
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

  ## Creating Tools

  ### Using `from_spec/5` (Recommended)

  Simplifies type definition by automatically converting Elixir types to JSON Schema:

      tool = Tool.from_spec("add", "Add numbers",
        %{a: :number, b: :number},
        fn args -> {:ok, args["a"] + args["b"]} end,
        required: [:a, :b]
      )

  Supported types: `:string`, `:number`, `:integer`, `:boolean`, `:array`, `:object`

  ### Using `new/4` (Advanced)

  For full control with raw JSON Schema:

      tool = Tool.new("greet", "Say hello",
        %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string", "description" => "Person's name"}
          },
          "required" => ["name"]
        },
        fn args -> {:ok, "Hello, \#{args["name"]}!"} end
      )

  ## Handler Return Values

  ### Success Responses

      # Simple string
      {:ok, "The answer is 42"}

      # Structured content (single block)
      {:ok, [%{"type" => "text", "text" => "Result text"}]}

      # Multiple content blocks
      {:ok, [
        %{"type" => "text", "text" => "Here's your chart:"},
        %{"type" => "image", "data" => base64_data, "mimeType" => "image/png"}
      ]}

  ### Error Responses

      {:error, "Invalid input: value must be positive"}

  Errors are displayed to Claude, who can respond appropriately.

  ## Real-World Examples

  ### HTTP API Integration

      weather_tool = Tool.from_spec("get_weather", "Get weather for a city",
        %{city: :string, country_code: :string},
        fn args ->
          response = Req.get!("https://api.weather.com/...",
            params: [city: args["city"], country: args["country_code"]]
          )
          {:ok, "Temperature: \#{response.body["temp"]}°F"}
        end,
        required: [:city, :country_code]
      )

  ### Database Query

      user_tool = Tool.from_spec("get_user", "Get user by ID",
        %{user_id: :integer},
        fn args ->
          case MyApp.Repo.get(User, args["user_id"]) do
            nil -> {:error, "User not found"}
            user -> {:ok, Jason.encode!(user)}
          end
        end,
        required: [:user_id]
      )

  ### Stateful Operations

  Tools can access application state via closures:

      counter = Agent.start_link(fn -> 0 end)
      {:ok, agent} = counter

      increment_tool = Tool.from_spec("increment", "Increment counter", %{},
        fn _ ->
          count = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
          {:ok, "Count: \#{count}"}
        end
      )

  ## Input Schema

  The input schema follows JSON Schema format:

      %{
        "type" => "object",
        "properties" => %{
          "param1" => %{"type" => "string", "description" => "First param"},
          "param2" => %{"type" => "number", "description" => "Second param"}
        },
        "required" => ["param1"]
      }

  ## Best Practices

  1. **Keep handlers simple** - Complex logic should be in separate modules
  2. **Handle errors gracefully** - Return `{:error, message}` for expected failures
  3. **Validate inputs** - Check arguments before processing
  4. **Return structured content** - Use content blocks for rich responses
  5. **Test handlers** - Tools are just functions, easy to test

  ## Performance

  SDK MCP tools run in your application process with zero IPC overhead.
  This makes them significantly faster than external MCP servers that
  require subprocess communication.
  """

  @type handler :: (map() -> {:ok, String.t() | [map()]} | {:error, String.t()})

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          input_schema: map(),
          handler: handler()
        }

  @enforce_keys [:name, :description, :input_schema, :handler]
  defstruct [:name, :description, :input_schema, :handler]

  @doc """
  Create a new tool definition.

  ## Parameters

  - `name` - Tool name (used in tool calls)
  - `description` - Human-readable description
  - `input_schema` - JSON Schema for input validation
  - `handler` - Function that executes the tool

  ## Examples

      Tool.new("echo", "Echo input", %{"type" => "object"}, fn args ->
        {:ok, inspect(args)}
      end)
  """
  @spec new(String.t(), String.t(), map(), handler()) :: t()
  def new(name, description, input_schema, handler)
      when is_binary(name) and is_binary(description) and is_map(input_schema) and
             is_function(handler, 1) do
    %__MODULE__{
      name: name,
      description: description,
      input_schema: input_schema,
      handler: handler
    }
  end

  @doc """
  Create a tool from a simple type specification.

  Builds a JSON Schema from a map of parameter names to types.

  ## Examples

      # Simple types
      Tool.from_spec("add", "Add numbers", %{a: :number, b: :number}, fn args ->
        {:ok, args["a"] + args["b"]}
      end)

      # With required params
      Tool.from_spec("greet", "Say hello", %{name: :string}, fn args ->
        {:ok, "Hello, \#{args["name"]}!"}
      end, required: [:name])
  """
  @spec from_spec(String.t(), String.t(), map(), handler(), keyword()) :: t()
  def from_spec(name, description, type_spec, handler, opts \\ []) do
    properties =
      type_spec
      |> Enum.map(fn {param, type} ->
        {to_string(param), type_to_schema(type)}
      end)
      |> Map.new()

    required =
      opts
      |> Keyword.get(:required, [])
      |> Enum.map(&to_string/1)

    schema = %{
      "type" => "object",
      "properties" => properties
    }

    schema = if required != [], do: Map.put(schema, "required", required), else: schema

    new(name, description, schema, handler)
  end

  defp type_to_schema(:string), do: %{"type" => "string"}
  defp type_to_schema(:number), do: %{"type" => "number"}
  defp type_to_schema(:integer), do: %{"type" => "integer"}
  defp type_to_schema(:boolean), do: %{"type" => "boolean"}
  defp type_to_schema(:array), do: %{"type" => "array"}
  defp type_to_schema(:object), do: %{"type" => "object"}
  defp type_to_schema(schema) when is_map(schema), do: schema

  @doc """
  Invoke the tool with arguments.

  ## Examples

      {:ok, result} = Tool.call(tool, %{"a" => 1, "b" => 2})
  """
  @spec call(t(), map()) :: {:ok, String.t() | [map()]} | {:error, String.t()}
  def call(%__MODULE__{handler: handler}, args) when is_map(args) do
    handler.(args)
  end
end
