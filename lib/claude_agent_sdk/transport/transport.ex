defmodule ClaudeAgentSdk.Transport do
  @moduledoc """
  Behaviour for transport implementations.

  This is the low-level I/O interface for communicating with the Claude Code CLI
  or other backends. The default implementation (`SubprocessCli`) spawns the
  Claude Code CLI as a subprocess and communicates via JSON over stdin/stdout.

  ## Custom Transports

  You can implement custom transports for:

  - Testing (mock transport)
  - Remote connections
  - Alternative backends

  ## Implementing a Transport

      defmodule MyTransport do
        @behaviour ClaudeAgentSdk.Transport

        defstruct [:connection]

        @impl true
        def connect(%__MODULE__{} = transport) do
          # Establish connection
          {:ok, %{transport | connection: conn}}
        end

        @impl true
        def write(%__MODULE__{connection: conn}, data) do
          # Send data
          :ok
        end

        @impl true
        def read_messages(%__MODULE__{} = transport) do
          # Return a Stream of messages
          Stream.resource(
            fn -> transport end,
            fn t -> receive_next(t) end,
            fn _ -> :ok end
          )
        end

        @impl true
        def close(%__MODULE__{connection: conn}) do
          # Close connection
          :ok
        end

        @impl true
        def ready?(%__MODULE__{connection: conn}) do
          conn != nil
        end

        @impl true
        def end_input(%__MODULE__{} = transport) do
          # Signal end of input
          :ok
        end
      end

  ## Warning

  This is an internal API that may change between versions. Custom transport
  implementations must be updated to match interface changes.
  """

  @type t :: struct()

  @doc """
  Connect the transport and prepare for communication.

  For subprocess transports, this starts the process.
  For network transports, this establishes the connection.

  Returns `{:ok, transport}` with updated state on success,
  or `{:error, reason}` on failure.
  """
  @callback connect(t()) :: {:ok, t()} | {:error, term()}

  @doc """
  Write raw data to the transport.

  Data is typically a JSON string with a newline terminator.
  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @callback write(t(), String.t()) :: :ok | {:error, term()}

  @doc """
  Read and parse messages from the transport.

  Returns a `Stream` that yields parsed JSON maps from the transport.
  The stream should terminate when the connection is closed.
  """
  @callback read_messages(t()) :: Enumerable.t()

  @doc """
  Close the transport connection and clean up resources.

  Always returns `:ok`. Should be idempotent.
  """
  @callback close(t()) :: :ok

  @doc """
  Check if transport is ready for communication.

  Returns `true` if the transport is connected and ready to
  send/receive messages.
  """
  @callback ready?(t()) :: boolean()

  @doc """
  End the input stream.

  For subprocess transports, this closes stdin.
  For other transports, this signals that no more input will be sent.
  """
  @callback end_input(t()) :: :ok | {:error, term()}
end
