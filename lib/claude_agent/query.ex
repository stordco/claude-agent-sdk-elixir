defmodule ClaudeAgent.Query do
  @moduledoc """
  Simple query execution for one-shot interactions with Claude.

  This module provides a straightforward way to execute queries without
  the complexity of the full streaming client. For advanced features like
  multi-turn conversations, interrupts, and hooks, use `ClaudeAgent.Client`.

  ## How It Works

  1. Creates a subprocess transport to the Claude Code CLI
  2. Sends the prompt
  3. Streams back parsed messages
  4. Automatically cleans up when done

  The returned stream is lazy - messages are only received when consumed.
  """

  require Logger

  alias ClaudeAgent.Options
  alias ClaudeAgent.Protocol.MessageParser
  alias ClaudeAgent.Transport.SubprocessCli

  @doc """
  Run a query and return a stream of messages.

  ## Parameters

  - `prompt` - The prompt string to send
  - `options` - `ClaudeAgent.Options` struct

  ## Returns

  A `Stream` of parsed message structs.

  ## Examples

      Query.run("Hello", %Options{})
      |> Enum.each(&IO.inspect/1)
  """
  @spec run(String.t(), Options.t()) :: Enumerable.t()
  def run(prompt, %Options{} = options) when is_binary(prompt) do
    # Validate options
    case Options.validate(options) do
      :ok -> :ok
      {:error, errors} -> raise ArgumentError, "Invalid options: #{inspect(errors)}"
    end

    # Check if streaming mode is required but not available for simple query
    if Options.requires_streaming?(options) do
      raise ArgumentError, """
      This query requires streaming mode because it uses:
      #{if options.can_use_tool, do: "- can_use_tool callback", else: ""}
      #{if options.hooks, do: "- hooks configuration", else: ""}

      Please use ClaudeAgent.Client for these features.
      """
    end

    # Create the transport and connect
    transport = SubprocessCli.new(prompt, options)

    case SubprocessCli.connect(transport) do
      {:ok, connected} ->
        # Stream raw messages, parse each one, filter out parse failures
        connected
        |> SubprocessCli.read_messages()
        |> Stream.map(fn raw_message ->
          case MessageParser.parse(raw_message) do
            {:ok, message} ->
              message

            {:error, parse_error} ->
              Logger.warning("Failed to parse message: #{inspect(parse_error)}")
              nil
          end
        end)
        |> Stream.reject(&is_nil/1)
        |> Stream.transform(connected, fn message, transport_acc ->
          {[message], transport_acc}
        end)
        |> Stream.concat(
          # Cleanup stream that runs after the main stream completes
          Stream.resource(
            fn -> connected end,
            fn _ -> {:halt, nil} end,
            fn transport_to_close ->
              if transport_to_close do
                SubprocessCli.close(transport_to_close)
              end
            end
          )
        )

      {:error, error} ->
        # Return a stream that immediately raises the error
        Stream.resource(
          fn -> error end,
          fn err -> raise err end,
          fn _ -> :ok end
        )
    end
  end
end
