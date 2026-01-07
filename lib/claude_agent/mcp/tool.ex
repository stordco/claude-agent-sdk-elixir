defmodule ClaudeAgent.Mcp.Tool do
  @moduledoc """
  Tool definition for SDK MCP servers.

  Tools are functions that Claude can call to perform actions.
  Each tool has a name, description, input schema, and handler function.

  ## Creating Tools

      # Simple tool
      tool = Tool.new("greet", "Say hello",
        %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string"}
          },
          "required" => ["name"]
        },
        fn args -> {:ok, "Hello, \#{args["name"]}!"} end
      )

      # Tool with structured response
      tool = Tool.new("add", "Add numbers",
        %{
          "type" => "object",
          "properties" => %{
            "a" => %{"type" => "number"},
            "b" => %{"type" => "number"}
          }
        },
        fn %{"a" => a, "b" => b} ->
          {:ok, [%{"type" => "text", "text" => "\#{a + b}"}]}
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

  ## Handler Return Values

  Handlers should return:

  - `{:ok, content}` - Success with content (string or list of content blocks)
  - `{:error, message}` - Error with message string

  Content blocks:

      [
        %{"type" => "text", "text" => "Result text"},
        %{"type" => "image", "data" => base64_data, "mimeType" => "image/png"}
      ]
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
