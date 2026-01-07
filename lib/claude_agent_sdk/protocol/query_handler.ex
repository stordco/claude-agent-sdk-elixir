defmodule ClaudeAgentSdk.Protocol.QueryHandler do
  @moduledoc """
  Handles the bidirectional control protocol for Claude SDK.

  This GenServer manages:

  - Control request/response routing
  - Hook callback invocation
  - Tool permission callbacks
  - SDK MCP server routing
  - Message streaming to clients

  ## Control Protocol

  The control protocol uses JSON messages with these types:

  - `control_request` - Sent from SDK to CLI
  - `control_response` - Response from CLI
  - `control_request` (incoming) - Request from CLI (permissions, hooks, MCP)
  - `control_cancel_request` - Cancel a pending request

  ## Request IDs

  Each control request has a unique ID for correlation.
  Responses include the request ID for matching.
  """

  use GenServer

  require Logger

  alias ClaudeAgentSdk.Hooks.HookMatcher
  alias ClaudeAgentSdk.Transport.SubprocessCli

  alias ClaudeAgentSdk.Types.Permissions.{
    PermissionResultAllow,
    PermissionResultDeny,
    ToolPermissionContext
  }

  @default_timeout 60_000
  @initialize_timeout 60_000

  defstruct [
    :transport,
    :options,
    :owner,
    pending_requests: %{},
    hook_callbacks: %{},
    sdk_mcp_servers: %{},
    message_queue: :queue.new(),
    waiting_receivers: :queue.new(),
    next_callback_id: 0,
    request_counter: 0,
    initialized: false,
    closed: false,
    first_result_received: false
  ]

  # Public API

  @doc """
  Start a new QueryHandler.

  ## Options

  - `:transport` - Connected transport (required)
  - `:options` - ClaudeAgentSdk.Options struct (required)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Initialize the control protocol.

  Sends the initialize request and waits for response.
  Returns server info including available commands.
  """
  @spec initialize(pid()) :: {:ok, map()} | {:error, term()}
  def initialize(handler) do
    GenServer.call(handler, :initialize, @initialize_timeout + 5000)
  end

  @doc """
  Send a message through the transport.
  """
  @spec send_message(pid(), map()) :: :ok | {:error, term()}
  def send_message(handler, message) do
    GenServer.call(handler, {:send_message, message}, :infinity)
  end

  @doc """
  Receive the next message.

  Returns `{:ok, message}`, `:done`, or `{:error, reason}`.
  """
  @spec receive_message(pid()) :: {:ok, map()} | :done | {:error, term()}
  def receive_message(handler) do
    GenServer.call(handler, :receive_message, :infinity)
  end

  @doc """
  Send an interrupt control request.
  """
  @spec interrupt(pid()) :: :ok | {:error, term()}
  def interrupt(handler) do
    GenServer.call(handler, :interrupt, @default_timeout)
  end

  @doc """
  Change permission mode.
  """
  @spec set_permission_mode(pid(), atom()) :: :ok | {:error, term()}
  def set_permission_mode(handler, mode) do
    GenServer.call(handler, {:set_permission_mode, mode}, @default_timeout)
  end

  @doc """
  Change the AI model.
  """
  @spec set_model(pid(), String.t() | nil) :: :ok | {:error, term()}
  def set_model(handler, model) do
    GenServer.call(handler, {:set_model, model}, @default_timeout)
  end

  @doc """
  Rewind files to a specific user message.
  """
  @spec rewind_files(pid(), String.t()) :: :ok | {:error, term()}
  def rewind_files(handler, user_message_id) do
    GenServer.call(handler, {:rewind_files, user_message_id}, @default_timeout)
  end

  @doc """
  Stop the query handler.
  """
  @spec stop(pid()) :: :ok
  def stop(handler) do
    GenServer.stop(handler, :normal)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    transport = Keyword.fetch!(opts, :transport)
    options = Keyword.fetch!(opts, :options)

    # Extract SDK MCP servers
    sdk_mcp_servers =
      case options.mcp_servers do
        servers when is_map(servers) ->
          servers
          |> Enum.filter(fn {_name, config} ->
            is_map(config) && Map.get(config, :type) == :sdk
          end)
          |> Enum.map(fn {name, config} -> {name, Map.get(config, :instance)} end)
          |> Map.new()

        _ ->
          %{}
      end

    state = %__MODULE__{
      transport: transport,
      options: options,
      owner: self(),
      sdk_mcp_servers: sdk_mcp_servers
    }

    # Start reading messages from transport
    # We spawn the reader and then transfer Port ownership to it
    # This ensures Port messages go to the reader process
    handler_pid = self()

    reader_pid =
      spawn_link(fn ->
        # Wait for Port ownership transfer signal
        receive do
          :start_reading -> :ok
        after
          5000 -> exit(:timeout_waiting_for_port)
        end

        read_loop(handler_pid, transport)
      end)

    # Transfer Port ownership to the reader process
    if transport.port do
      Port.connect(transport.port, reader_pid)
    end

    # Signal reader to start
    send(reader_pid, :start_reading)

    {:ok, state}
  end

  @impl true
  def handle_call(:initialize, from, state) do
    # Build hooks configuration
    {hooks_config, callback_map} = build_hooks_config(state.options.hooks, state.next_callback_id)

    # Build initialize request
    request = %{
      "subtype" => "initialize",
      "hooks" => if(hooks_config == %{}, do: nil, else: hooks_config)
    }

    # Store hook callbacks now (will be needed when response arrives)
    new_state = %{
      state
      | hook_callbacks: Map.merge(state.hook_callbacks, callback_map),
        next_callback_id: state.next_callback_id + map_size(callback_map)
    }

    # Send control request and wait asynchronously
    case send_control_request_async(new_state, request, from, @initialize_timeout, :initialize) do
      {:ok, updated_state} ->
        # Don't set initialized yet - will be set when response arrives
        {:noreply, updated_state}

      {:error, reason} ->
        # On error, return original state (don't keep hook callbacks)
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:send_message, message}, _from, state) do
    json = Jason.encode!(message) <> "\n"

    case SubprocessCli.write(state.transport, json) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call(:receive_message, from, state) do
    case :queue.out(state.message_queue) do
      {{:value, :done}, queue} ->
        {:reply, :done, %{state | message_queue: queue}}

      {{:value, {:error, reason}}, queue} ->
        {:reply, {:error, reason}, %{state | message_queue: queue}}

      {{:value, message}, queue} ->
        {:reply, {:ok, message}, %{state | message_queue: queue}}

      {:empty, _} ->
        # Queue the receiver to be notified when a message arrives
        new_queue = :queue.in(from, state.waiting_receivers)
        {:noreply, %{state | waiting_receivers: new_queue}}
    end
  end

  def handle_call(:interrupt, from, state) do
    request = %{"subtype" => "interrupt"}

    case send_control_request_async(state, request, from, @default_timeout) do
      {:ok, updated_state} -> {:noreply, updated_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:set_permission_mode, mode}, from, state) do
    mode_str =
      case mode do
        :default -> "default"
        :accept_edits -> "acceptEdits"
        :plan -> "plan"
        :bypass_permissions -> "bypassPermissions"
      end

    request = %{"subtype" => "set_permission_mode", "mode" => mode_str}

    case send_control_request_async(state, request, from, @default_timeout) do
      {:ok, updated_state} -> {:noreply, updated_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:set_model, model}, from, state) do
    request = %{"subtype" => "set_model", "model" => model}

    case send_control_request_async(state, request, from, @default_timeout) do
      {:ok, updated_state} -> {:noreply, updated_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:rewind_files, user_message_id}, from, state) do
    request = %{"subtype" => "rewind_files", "user_message_id" => user_message_id}

    case send_control_request_async(state, request, from, @default_timeout) do
      {:ok, updated_state} -> {:noreply, updated_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:transport_message, message}, state) do
    new_state = handle_transport_message(message, state)
    {:noreply, new_state}
  end

  def handle_info({:transport_closed, reason}, state) do
    Logger.debug("Transport closed: #{inspect(reason)}")
    new_state = deliver_message(:done, state)
    {:noreply, %{new_state | closed: true}}
  end

  def handle_info({:transport_error, error}, state) do
    Logger.error("Transport error: #{inspect(error)}")
    new_state = deliver_message({:error, error}, state)
    {:noreply, %{new_state | closed: true}}
  end

  def handle_info({:control_timeout, request_id}, state) do
    case Map.pop(state.pending_requests, request_id) do
      {nil, _} ->
        # Request already handled, ignore timeout
        {:noreply, state}

      {{from, _timeout_ref, _request_type}, new_pending} ->
        # Reply with timeout error
        GenServer.reply(from, {:error, "Control request timeout"})
        {:noreply, %{state | pending_requests: new_pending}}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("QueryHandler received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.transport do
      SubprocessCli.close(state.transport)
    end

    :ok
  end

  # Private helpers

  defp read_loop(handler, transport) do
    transport
    |> SubprocessCli.read_messages()
    |> Enum.each(fn message ->
      send(handler, {:transport_message, message})
    end)

    send(handler, {:transport_closed, :normal})
  rescue
    e ->
      send(handler, {:transport_error, e})
  end

  defp handle_transport_message(message, state) do
    case Map.get(message, "type") do
      "control_response" ->
        handle_control_response(message, state)

      "control_request" ->
        # Incoming request from CLI (permissions, hooks, MCP)
        spawn(fn -> handle_incoming_control_request(message, state) end)
        state

      "control_cancel_request" ->
        # TODO: Implement cancellation
        state

      "result" ->
        # Track first result for stream closure
        state = %{state | first_result_received: true}
        deliver_message(message, state)

      _ ->
        # Regular message - deliver to receivers
        deliver_message(message, state)
    end
  end

  defp handle_control_response(message, state) do
    response = Map.get(message, "response", %{})
    request_id = Map.get(response, "request_id")

    case Map.pop(state.pending_requests, request_id) do
      {nil, _} ->
        Logger.warning("Received response for unknown request: #{request_id}")
        state

      {{from, timeout_ref, request_type}, pending} ->
        # Cancel the timeout timer
        Process.cancel_timer(timeout_ref)

        result =
          case Map.get(response, "subtype") do
            "error" ->
              {:error, Map.get(response, "error", "Unknown error")}

            "success" ->
              {:ok, Map.get(response, "response", %{})}

            _ ->
              {:ok, response}
          end

        GenServer.reply(from, result)

        # Update state based on request type and result
        new_state = %{state | pending_requests: pending}

        case {request_type, result} do
          {:initialize, {:ok, _}} ->
            # Mark as initialized only on successful initialize response
            %{new_state | initialized: true}

          _ ->
            new_state
        end
    end
  end

  defp handle_incoming_control_request(message, state) do
    request_id = Map.get(message, "request_id")
    request_data = Map.get(message, "request", %{})
    subtype = Map.get(request_data, "subtype")

    response_data =
      try do
        case subtype do
          "can_use_tool" ->
            handle_permission_request(request_data, state)

          "hook_callback" ->
            handle_hook_callback(request_data, state)

          "mcp_message" ->
            handle_mcp_message(request_data, state)

          _ ->
            {:error, "Unsupported control request subtype: #{subtype}"}
        end
      rescue
        e ->
          {:error, Exception.message(e)}
      end

    # Send response
    response =
      case response_data do
        {:ok, data} ->
          %{
            "type" => "control_response",
            "response" => %{
              "subtype" => "success",
              "request_id" => request_id,
              "response" => data
            }
          }

        {:error, error} ->
          %{
            "type" => "control_response",
            "response" => %{
              "subtype" => "error",
              "request_id" => request_id,
              "error" => error
            }
          }
      end

    json = Jason.encode!(response) <> "\n"
    SubprocessCli.write(state.transport, json)
  end

  defp handle_permission_request(request_data, state) do
    case state.options.can_use_tool do
      nil ->
        {:error, "can_use_tool callback is not provided"}

      callback ->
        tool_name = Map.get(request_data, "tool_name")
        input = Map.get(request_data, "input", %{})
        suggestions = Map.get(request_data, "permission_suggestions", [])

        context = ToolPermissionContext.new(suggestions: suggestions)
        result = callback.(tool_name, input, context)

        case result do
          %PermissionResultAllow{} = allow ->
            {:ok, PermissionResultAllow.to_response_map(allow, input)}

          %PermissionResultDeny{} = deny ->
            {:ok, PermissionResultDeny.to_response_map(deny)}

          other ->
            {:error, "Invalid permission result: #{inspect(other)}"}
        end
    end
  end

  defp handle_hook_callback(request_data, state) do
    callback_id = Map.get(request_data, "callback_id")

    case Map.get(state.hook_callbacks, callback_id) do
      nil ->
        {:error, "No hook callback found for ID: #{callback_id}"}

      callback ->
        input = Map.get(request_data, "input")
        tool_use_id = Map.get(request_data, "tool_use_id")
        context = %{signal: nil}

        result = callback.(input, tool_use_id, context)
        # Convert Elixir field names to CLI-expected names
        converted = convert_hook_output(result)
        {:ok, converted}
    end
  end

  defp handle_mcp_message(request_data, state) do
    server_name = Map.get(request_data, "server_name")
    mcp_message = Map.get(request_data, "message")

    case Map.get(state.sdk_mcp_servers, server_name) do
      nil ->
        {:ok,
         %{
           "mcp_response" => %{
             "jsonrpc" => "2.0",
             "id" => Map.get(mcp_message, "id"),
             "error" => %{
               "code" => -32601,
               "message" => "Server '#{server_name}' not found"
             }
           }
         }}

      server ->
        response = ClaudeAgentSdk.Mcp.Server.handle_request(server, mcp_message)
        {:ok, %{"mcp_response" => response}}
    end
  end

  defp convert_hook_output(output) when is_map(output) do
    output
    |> Enum.map(fn
      {:async_, value} -> {"async", value}
      {:continue_, value} -> {"continue", value}
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
    |> Map.new()
  end

  defp deliver_message(message, state) do
    case :queue.out(state.waiting_receivers) do
      {{:value, from}, remaining} ->
        reply =
          case message do
            :done -> :done
            {:error, _} = err -> err
            msg -> {:ok, msg}
          end

        GenServer.reply(from, reply)
        %{state | waiting_receivers: remaining}

      {:empty, _} ->
        # No waiting receivers, queue the message
        new_queue = :queue.in(message, state.message_queue)
        %{state | message_queue: new_queue}
    end
  end

  # Send a control request and register the caller to receive the response asynchronously.
  # Returns {:ok, new_state} on success (response will be sent via GenServer.reply later),
  # or {:error, reason} if the write fails.
  # The optional `request_type` parameter can be used to track special requests like :initialize.
  defp send_control_request_async(state, request, from, timeout, request_type \\ nil) do
    # Generate unique request ID
    request_id = "req_#{state.request_counter}_#{:crypto.strong_rand_bytes(4) |> Base.encode16()}"

    control_request = %{
      "type" => "control_request",
      "request_id" => request_id,
      "request" => request
    }

    json = Jason.encode!(control_request) <> "\n"

    case SubprocessCli.write(state.transport, json) do
      :ok ->
        # Schedule a timeout
        timeout_ref = Process.send_after(self(), {:control_timeout, request_id}, timeout)

        # Store the pending request with the caller, timeout ref, and optional type
        new_pending = Map.put(state.pending_requests, request_id, {from, timeout_ref, request_type})

        {:ok, %{state | pending_requests: new_pending, request_counter: state.request_counter + 1}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_hooks_config(nil, _next_id), do: {%{}, %{}}

  defp build_hooks_config(hooks, next_id) when is_map(hooks) do
    {config, callbacks, _} =
      Enum.reduce(hooks, {%{}, %{}, next_id}, fn {event, matchers}, {cfg, cbs, id} ->
        event_str = HookMatcher.event_to_string(event)

        {matcher_configs, new_callbacks, new_id} =
          Enum.reduce(matchers, {[], cbs, id}, fn matcher, {mcfgs, mcbs, mid} ->
            callback_ids =
              Enum.map(Enum.with_index(matcher.hooks), fn {_hook, idx} ->
                "hook_#{mid + idx}"
              end)

            new_cbs =
              matcher.hooks
              |> Enum.with_index()
              |> Enum.reduce(mcbs, fn {hook, idx}, acc ->
                Map.put(acc, "hook_#{mid + idx}", hook)
              end)

            matcher_config = %{
              "matcher" => matcher.matcher,
              "hookCallbackIds" => callback_ids
            }

            matcher_config =
              if matcher.timeout do
                Map.put(matcher_config, "timeout", matcher.timeout)
              else
                matcher_config
              end

            {mcfgs ++ [matcher_config], new_cbs, mid + length(matcher.hooks)}
          end)

        {Map.put(cfg, event_str, matcher_configs), new_callbacks, new_id}
      end)

    {config, callbacks}
  end
end
