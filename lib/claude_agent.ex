defmodule ClaudeAgent do
  @moduledoc """
  Claude Agent SDK for Elixir.

  This library provides a client for interacting with Claude through the
  Claude Code CLI. It supports both simple one-shot queries and interactive
  multi-turn conversations.

  ## Quick Start

      # Simple query (uses config.exs defaults)
      ClaudeAgent.query("What is 2 + 2?")
      |> Stream.each(fn message ->
        case message do
          %AssistantMessage{content: blocks} ->
            Enum.each(blocks, fn
              %TextBlock{text: text} -> IO.puts(text)
              _ -> :ok
            end)
          _ -> :ok
        end
      end)
      |> Stream.run()

  ## With Options

      # Per-query options (override global defaults)
      ClaudeAgent.query("Tell me a joke",
        system_prompt: "You are a helpful assistant",
        allowed_tools: ["Read", "Write"],
        max_turns: 5
      )

  ## Interactive Client

  For multi-turn conversations and advanced features:

      {:ok, client} = ClaudeAgent.Client.start_link()
      :ok = ClaudeAgent.Client.query(client, "Hello")

      client
      |> ClaudeAgent.Client.receive_response()
      |> Enum.each(&IO.inspect/1)

      ClaudeAgent.Client.disconnect(client)

  ## Structured Outputs

  Get validated JSON responses using JSON Schemas:

      schema = %{
        "type" => "object",
        "properties" => %{
          "summary" => %{"type" => "string"},
          "word_count" => %{"type" => "integer"}
        },
        "required" => ["summary", "word_count"]
      }

      result = ClaudeAgent.query_result("Summarize this text: ...",
        output_format: %{"type" => "json_schema", "schema" => schema}
      )

      # Access validated output
      summary = result.structured_output["summary"]
      word_count = result.structured_output["word_count"]

  ### With Ecto for Type Safety

      defmodule Summary do
        use Ecto.Schema
        import Ecto.Changeset

        @primary_key false
        embedded_schema do
          field(:summary, :string)
          field(:word_count, :integer)
        end

        def changeset(attrs) do
          %__MODULE__{}
          |> cast(attrs, [:summary, :word_count])
          |> validate_required([:summary, :word_count])
        end
      end

      # Validate and get typed struct
      case Summary.changeset(result.structured_output) do
        %{valid?: true} = changeset ->
          summary = Ecto.Changeset.apply_changes(changeset)
          # summary is now a %Summary{} struct with compile-time guarantees

        %{valid?: false} = changeset ->
          {:error, changeset.errors}
      end

  See `ClaudeAgent.Options` for complete documentation and examples.

  ## Message Types

  The SDK returns these message types:

  - `UserMessage` - User input messages
  - `AssistantMessage` - Claude's responses
  - `SystemMessage` - System events
  - `ResultMessage` - Final result with cost info (includes `structured_output` field)
  - `StreamEvent` - Partial updates (when enabled)

  See `ClaudeAgent.Types.Messages` for details.

  ## MCP Servers

  You can provide in-process MCP servers:

      calculator = ClaudeAgent.create_sdk_mcp_server("calculator",
        tools: [add_tool, subtract_tool]
      )

      ClaudeAgent.query("Calculate 2+2",
        mcp_servers: %{"calc" => calculator},
        allowed_tools: ["mcp__calc__add"]
      )
  """

  alias ClaudeAgent.{Options, Query}
  alias ClaudeAgent.Types.Messages.{AssistantMessage, ResultMessage}
  alias ClaudeAgent.Types.ContentBlocks.TextBlock

  @version Mix.Project.config()[:version] || "0.1.0"

  @doc """
  Get the SDK version.
  """
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Get the current configuration from application environment.

  Returns the default options configured in your application's config files
  or set via `Application.put_env/3`. These defaults are applied to all
  queries unless overridden by per-query options.

  ## Examples

      # In your app's config/config.exs
      config :claude_agent_sdk,
        cli_path: "/path/to/claude",
        permission_mode: :bypass_permissions

      # In code
      ClaudeAgent.get_config()
      # => [cli_path: "/path/to/claude", permission_mode: :bypass_permissions, ...]

  ## Configuration

  Configure the SDK in your application's config files:

  - `config/config.exs` - Base configuration
  - `config/dev.exs` - Development overrides
  - `config/test.exs` - Test overrides
  - `config/runtime.exs` - Runtime configuration from environment variables

  See `ClaudeAgent.Options` for available configuration options.
  """
  @spec get_config() :: Options.t()
  def get_config do
    # Get all claude_agent_sdk config and convert to keyword list
    case Application.get_all_env(:claude_agent_sdk) do
      [] -> Options.defaults()
      config -> config
    end
  end

  @doc """
  Execute a one-shot query and return a stream of messages.

  This is the simplest way to interact with Claude. For more control,
  use `ClaudeAgent.Client`.

  ## Parameters

  - `prompt` - The prompt to send to Claude
  - `options` - Optional keyword list of options (see `ClaudeAgent.Options`)

  ## Returns

  A `Stream` of messages that will be evaluated lazily.

  ## Examples

      # Basic query
      ClaudeAgent.query("What is the capital of France?")
      |> Enum.each(&IO.inspect/1)

      # With options
      ClaudeAgent.query("Explain Elixir",
        system_prompt: "Be concise",
        max_turns: 1
      )
      |> Stream.filter(&match?(%AssistantMessage{}, &1))
      |> Enum.each(&print_response/1)

      # Get just the text response
      ClaudeAgent.query("Hello!")
      |> get_text_response()

  ## Error Handling

  The stream may raise:

  - `CLINotFoundError` - Claude Code CLI not installed
  - `CLIConnectionError` - Connection failed
  - `ProcessError` - CLI process failed
  """
  @spec query(String.t(), Options.t()) :: Enumerable.t()
  def query(prompt, options \\ []) when is_binary(prompt) and is_list(options) do
    merged_options = Options.merge(get_config(), options)
    Query.run(prompt, merged_options)
  end

  @doc """
  Execute a query and collect all text responses.

  Convenience function that extracts text from AssistantMessage blocks.

  ## Examples

      text = ClaudeAgent.query_text("What is 2+2?")
      # => "2 + 2 = 4"
  """
  @spec query_text(String.t(), Options.t()) :: String.t()
  def query_text(prompt, options \\ []) when is_list(options) do
    prompt
    |> query(options)
    |> Stream.flat_map(fn
      %AssistantMessage{content: blocks} ->
        Enum.flat_map(blocks, fn
          %TextBlock{text: text} -> [text]
          _ -> []
        end)

      _ ->
        []
    end)
    |> Enum.join("\n")
  end

  @doc """
  Execute a query and return the result message.

  Returns the final `ResultMessage` with session info and cost.

  ## Examples

      result = ClaudeAgent.query_result("Do something")
      IO.puts("Cost: $\#{result.total_cost_usd}")
  """
  @spec query_result(String.t(), Options.t()) :: ResultMessage.t() | nil
  def query_result(prompt, options \\ []) when is_list(options) do
    prompt
    |> query(options)
    |> Enum.find(&match?(%ResultMessage{}, &1))
  end

  # Re-exports for convenience
  defdelegate create_sdk_mcp_server(name, opts \\ []), to: ClaudeAgent.Mcp.Server, as: :new

  @doc """
  Alias for `ClaudeAgent.Subagent` for convenient imports.

  ## Example

      alias ClaudeAgent.Subagent

      agents = %{
        "reviewer" => Subagent.new("Code reviewer", "Review code...")
      }
  """
  defdelegate subagent_new(description, prompt, opts \\ []), to: ClaudeAgent.Subagent, as: :new
end
