defmodule ClaudeAgentSdk do
  @moduledoc """
  Claude Agent SDK for Elixir.

  This library provides a client for interacting with Claude through the
  Claude Code CLI. It supports both simple one-shot queries and interactive
  multi-turn conversations.

  ## Quick Start

      # Simple query
      ClaudeAgentSdk.query("What is 2 + 2?")
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

      alias ClaudeAgentSdk.Options

      opts = %Options{
        system_prompt: "You are a helpful assistant",
        allowed_tools: ["Read", "Write"],
        max_turns: 5
      }

      ClaudeAgentSdk.query("Tell me a joke", opts)

  ## Interactive Client

  For multi-turn conversations and advanced features:

      {:ok, client} = ClaudeAgentSdk.Client.start_link()
      :ok = ClaudeAgentSdk.Client.query(client, "Hello")

      client
      |> ClaudeAgentSdk.Client.receive_response()
      |> Enum.each(&IO.inspect/1)

      ClaudeAgentSdk.Client.disconnect(client)

  ## Message Types

  The SDK returns these message types:

  - `UserMessage` - User input messages
  - `AssistantMessage` - Claude's responses
  - `SystemMessage` - System events
  - `ResultMessage` - Final result with cost info
  - `StreamEvent` - Partial updates (when enabled)

  See `ClaudeAgentSdk.Types.Messages` for details.

  ## MCP Servers

  You can provide in-process MCP servers:

      calculator = ClaudeAgentSdk.create_sdk_mcp_server("calculator",
        tools: [add_tool, subtract_tool]
      )

      opts = %Options{
        mcp_servers: %{"calc" => calculator},
        allowed_tools: ["mcp__calc__add"]
      }
  """

  alias ClaudeAgentSdk.{Options, Query}
  alias ClaudeAgentSdk.Types.Messages.{AssistantMessage, ResultMessage}
  alias ClaudeAgentSdk.Types.ContentBlocks.TextBlock

  @version Mix.Project.config()[:version] || "0.1.0"

  @doc """
  Get the SDK version.
  """
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Execute a one-shot query and return a stream of messages.

  This is the simplest way to interact with Claude. For more control,
  use `ClaudeAgentSdk.Client`.

  ## Parameters

  - `prompt` - The prompt to send to Claude
  - `options` - Optional `ClaudeAgentSdk.Options` struct

  ## Returns

  A `Stream` of messages that will be evaluated lazily.

  ## Examples

      # Basic query
      ClaudeAgentSdk.query("What is the capital of France?")
      |> Enum.each(&IO.inspect/1)

      # With options
      opts = %Options{system_prompt: "Be concise", max_turns: 1}
      ClaudeAgentSdk.query("Explain Elixir", opts)
      |> Stream.filter(&match?(%AssistantMessage{}, &1))
      |> Enum.each(&print_response/1)

      # Get just the text response
      ClaudeAgentSdk.query("Hello!")
      |> get_text_response()

  ## Error Handling

  The stream may raise:

  - `CLINotFoundError` - Claude Code CLI not installed
  - `CLIConnectionError` - Connection failed
  - `ProcessError` - CLI process failed
  """
  @spec query(String.t(), Options.t() | nil) :: Enumerable.t()
  def query(prompt, options \\ nil) when is_binary(prompt) do
    Query.run(prompt, options || %Options{})
  end

  @doc """
  Execute a query and collect all text responses.

  Convenience function that extracts text from AssistantMessage blocks.

  ## Examples

      text = ClaudeAgentSdk.query_text("What is 2+2?")
      # => "2 + 2 = 4"
  """
  @spec query_text(String.t(), Options.t() | nil) :: String.t()
  def query_text(prompt, options \\ nil) do
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

      result = ClaudeAgentSdk.query_result("Do something")
      IO.puts("Cost: $\#{result.total_cost_usd}")
  """
  @spec query_result(String.t(), Options.t() | nil) :: ResultMessage.t() | nil
  def query_result(prompt, options \\ nil) do
    prompt
    |> query(options)
    |> Enum.find(&match?(%ResultMessage{}, &1))
  end

  # Re-exports for convenience
  defdelegate create_sdk_mcp_server(name, opts \\ []), to: ClaudeAgentSdk.Mcp.Server, as: :new
end
