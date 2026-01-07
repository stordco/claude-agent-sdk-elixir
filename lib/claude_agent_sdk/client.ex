defmodule ClaudeAgentSdk.Client do
  @moduledoc """
  Stateful client for bidirectional conversations with Claude.

  This GenServer provides a full-featured client supporting:

  - Multi-turn conversations
  - Interrupts
  - Dynamic permission mode changes
  - Tool permission callbacks (via `can_use_tool`)
  - Hooks for tool use events
  - SDK MCP servers

  ## Basic Usage

      # Start client
      {:ok, client} = Client.start_link()

      # Send query
      :ok = Client.query(client, "Hello!")

      # Receive response
      client
      |> Client.receive_response()
      |> Enum.each(&IO.inspect/1)

      # Disconnect when done
      Client.disconnect(client)

  ## Multi-turn Conversation

      {:ok, client} = Client.start_link()

      Client.query(client, "What is Elixir?")
      Client.receive_response(client) |> Enum.each(&print/1)

      Client.query(client, "How does it handle concurrency?")
      Client.receive_response(client) |> Enum.each(&print/1)

      Client.disconnect(client)

  ## With Options

      opts = %Options{
        system_prompt: "You are helpful",
        allowed_tools: ["Read", "Bash"],
        hooks: %{
          pre_tool_use: [%HookMatcher{matcher: "Bash", hooks: [&check_cmd/3]}]
        }
      }

      {:ok, client} = Client.start_link(opts)

  ## Interrupts

      Client.query(client, "Count to 100 slowly")

      # Start receiving in a task
      task = Task.async(fn ->
        Client.receive_response(client) |> Enum.to_list()
      end)

      # Interrupt after 2 seconds
      Process.sleep(2000)
      Client.interrupt(client)

      Task.await(task)
  """

  use GenServer

  require Logger

  alias ClaudeAgentSdk.Options
  alias ClaudeAgentSdk.Protocol.{MessageParser, QueryHandler}
  alias ClaudeAgentSdk.Transport.SubprocessCli

  @type t :: pid()

  defstruct [
    :options,
    :transport,
    :query_handler,
    :server_info,
    connected: false
  ]

  # Public API

  @doc """
  Start a new Client GenServer.

  ## Options

  - `options` - `ClaudeAgentSdk.Options` struct (default: empty options)
  - GenServer options like `name`, `timeout`, etc.

  ## Examples

      {:ok, client} = Client.start_link()
      {:ok, client} = Client.start_link(%Options{max_turns: 5})
      {:ok, client} = Client.start_link(%Options{}, name: :my_client)
  """
  @spec start_link(Options.t(), keyword()) :: GenServer.on_start()
  def start_link(options \\ %Options{}, opts \\ []) do
    GenServer.start_link(__MODULE__, options, opts)
  end

  @doc """
  Connect to Claude Code CLI.

  This is called automatically when needed, but can be called
  explicitly for early connection setup.
  """
  @spec connect(t()) :: :ok | {:error, term()}
  def connect(client) do
    GenServer.call(client, :connect, :infinity)
  end

  @doc """
  Send a query to Claude.

  The query can be a string or an enumerable of message maps
  (for streaming input mode).

  ## Examples

      # Simple string query
      Client.query(client, "What is 2+2?")

      # Streaming input (advanced)
      messages = [%{type: "user", message: %{role: "user", content: "Hello"}}]
      Client.query(client, messages)
  """
  @spec query(t(), String.t() | Enumerable.t()) :: :ok | {:error, term()}
  def query(client, prompt) do
    GenServer.call(client, {:query, prompt}, :infinity)
  end

  @doc """
  Receive messages until a ResultMessage is received.

  Returns a stream of messages for the current response.
  Use this after calling `query/2`.

  ## Examples

      Client.query(client, "Hello")

      client
      |> Client.receive_response()
      |> Enum.each(&IO.inspect/1)
  """
  @spec receive_response(t()) :: Enumerable.t()
  def receive_response(client) do
    Stream.resource(
      fn -> {client, false} end,
      fn
        {_client, true} ->
          # Already received result, halt
          {:halt, nil}

        {client, false} ->
          case GenServer.call(client, :receive_message, :infinity) do
            {:ok, %ClaudeAgentSdk.Types.Messages.ResultMessage{} = msg} ->
              # Emit result and mark for halt on next iteration
              {[msg], {client, true}}

            {:ok, message} ->
              {[message], {client, false}}

            :done ->
              {:halt, nil}

            {:error, _reason} ->
              {:halt, nil}
          end
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Receive all messages from the client.

  Returns a stream that yields messages as they arrive.
  Unlike `receive_response/1`, this doesn't stop at ResultMessage.
  """
  @spec receive_messages(t()) :: Enumerable.t()
  def receive_messages(client) do
    Stream.resource(
      fn -> client end,
      fn client ->
        case GenServer.call(client, :receive_message, :infinity) do
          {:ok, message} -> {[message], client}
          :done -> {:halt, client}
          {:error, _reason} -> {:halt, client}
        end
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Interrupt the current operation.

  Sends an interrupt signal to Claude. The current operation will
  be stopped and you can send a new query.
  """
  @spec interrupt(t()) :: :ok | {:error, term()}
  def interrupt(client) do
    GenServer.call(client, :interrupt, :infinity)
  end

  @doc """
  Change the permission mode.

  ## Modes

  - `:default` - CLI prompts for dangerous tools
  - `:accept_edits` - Auto-accept file edits
  - `:plan` - Planning mode
  - `:bypass_permissions` - Allow all tools
  """
  @spec set_permission_mode(t(), Options.permission_mode()) :: :ok | {:error, term()}
  def set_permission_mode(client, mode) do
    GenServer.call(client, {:set_permission_mode, mode}, :infinity)
  end

  @doc """
  Change the AI model.

  Pass `nil` to use the default model.
  """
  @spec set_model(t(), String.t() | nil) :: :ok | {:error, term()}
  def set_model(client, model) do
    GenServer.call(client, {:set_model, model}, :infinity)
  end

  @doc """
  Get server initialization info.

  Returns information about available commands and capabilities.
  Only available after initialization in streaming mode.
  """
  @spec get_server_info(t()) :: {:ok, map()} | {:error, term()}
  def get_server_info(client) do
    GenServer.call(client, :get_server_info, :infinity)
  end

  @doc """
  Rewind files to a specific user message.

  Requires `enable_file_checkpointing: true` in options.
  """
  @spec rewind_files(t(), String.t()) :: :ok | {:error, term()}
  def rewind_files(client, user_message_id) do
    GenServer.call(client, {:rewind_files, user_message_id}, :infinity)
  end

  @doc """
  Disconnect from Claude Code CLI.

  Closes the transport and cleans up resources.
  """
  @spec disconnect(t()) :: :ok
  def disconnect(client) do
    GenServer.call(client, :disconnect, :infinity)
  end

  @doc """
  Stop the client process.
  """
  @spec stop(t()) :: :ok
  def stop(client) do
    GenServer.stop(client, :normal)
  end

  # GenServer Callbacks

  @impl true
  def init(options) do
    state = %__MODULE__{
      options: options,
      connected: false
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:connect, _from, %{connected: true} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:connect, _from, state) do
    case do_connect(state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:query, prompt}, _from, state) do
    state =
      if not state.connected do
        case do_connect(state) do
          {:ok, new_state} -> new_state
          {:error, reason} -> throw({:error, reason})
        end
      else
        state
      end

    case do_query(state, prompt) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  catch
    {:error, reason} -> {:reply, {:error, reason}, state}
  end

  def handle_call(:receive_message, _from, %{query_handler: nil} = state) do
    {:reply, :done, state}
  end

  def handle_call(:receive_message, _from, %{query_handler: handler} = state) do
    case QueryHandler.receive_message(handler) do
      {:ok, raw_message} ->
        case MessageParser.parse(raw_message) do
          {:ok, message} ->
            {:reply, {:ok, message}, state}

          {:error, parse_error} ->
            Logger.warning("Failed to parse message: #{inspect(parse_error)}")
            {:reply, {:error, parse_error}, state}
        end

      :done ->
        {:reply, :done, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:interrupt, _from, %{query_handler: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:interrupt, _from, %{query_handler: handler} = state) do
    result = QueryHandler.interrupt(handler)
    {:reply, result, state}
  end

  def handle_call({:set_permission_mode, _mode}, _from, %{query_handler: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:set_permission_mode, mode}, _from, %{query_handler: handler} = state) do
    result = QueryHandler.set_permission_mode(handler, mode)
    {:reply, result, state}
  end

  def handle_call({:set_model, _model}, _from, %{query_handler: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:set_model, model}, _from, %{query_handler: handler} = state) do
    result = QueryHandler.set_model(handler, model)
    {:reply, result, state}
  end

  def handle_call(:get_server_info, _from, state) do
    {:reply, {:ok, state.server_info}, state}
  end

  def handle_call({:rewind_files, _user_message_id}, _from, %{query_handler: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:rewind_files, user_message_id}, _from, %{query_handler: handler} = state) do
    result = QueryHandler.rewind_files(handler, user_message_id)
    {:reply, result, state}
  end

  def handle_call(:disconnect, _from, state) do
    new_state = do_disconnect(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:EXIT, port, reason}, %{transport: %{port: port}} = state) do
    Logger.debug("Transport port exited: #{inspect(reason)}")
    {:noreply, %{state | connected: false, transport: nil, query_handler: nil}}
  end

  def handle_info(msg, state) do
    Logger.debug("Client received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    do_disconnect(state)
    :ok
  end

  # Private helpers

  defp do_connect(state) do
    # Create transport for streaming mode (nil prompt)
    transport = SubprocessCli.new(nil, state.options)

    case SubprocessCli.connect(transport) do
      {:ok, connected_transport} ->
        # Start query handler for control protocol
        # QueryHandler's init will transfer Port ownership to its reader process
        {:ok, handler} =
          QueryHandler.start_link(
            transport: connected_transport,
            options: state.options
          )

        # Initialize the control protocol
        case QueryHandler.initialize(handler) do
          {:ok, server_info} ->
            {:ok,
             %{
               state
               | transport: connected_transport,
                 query_handler: handler,
                 connected: true,
                 server_info: server_info
             }}

          {:error, reason} ->
            QueryHandler.stop(handler)
            SubprocessCli.close(connected_transport)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_query(state, prompt) when is_binary(prompt) do
    # Send user message
    message = %{
      "type" => "user",
      "message" => %{
        "role" => "user",
        "content" => prompt
      }
    }

    case QueryHandler.send_message(state.query_handler, message) do
      :ok -> {:ok, state}
      error -> error
    end
  end

  defp do_query(state, messages) when is_list(messages) do
    # Send multiple messages
    Enum.reduce_while(messages, {:ok, state}, fn message, {:ok, s} ->
      case QueryHandler.send_message(s.query_handler, message) do
        :ok -> {:cont, {:ok, s}}
        error -> {:halt, error}
      end
    end)
  end

  defp do_disconnect(%{transport: nil} = state) do
    %{state | connected: false, query_handler: nil}
  end

  defp do_disconnect(%{transport: transport, query_handler: handler} = state) do
    if handler, do: QueryHandler.stop(handler)
    if transport, do: SubprocessCli.close(transport)
    %{state | transport: nil, query_handler: nil, connected: false}
  end
end
