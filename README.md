# Claude Agent SDK for Elixir

An Elixir SDK for interacting with [Claude](https://www.anthropic.com/claude) through the [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI.

> **Note**: This is an Elixir port of the official [claude-agent-sdk-python](https://github.com/anthropics/claude-agent-sdk).

## Installation

Add `claude_agent_sdk` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:claude_agent_sdk, "~> 0.1.0"}
  ]
end
```

You'll also need the Claude Code CLI installed:

```bash
npm install -g @anthropic-ai/claude-code
```

## Quick Start

### Get Text Response

The simplest way to get a response from Claude:

```elixir
text = ClaudeAgent.query_text("What is the capital of France?")
IO.puts(text)
# => "The capital of France is Paris."
```

### Get Full Result with Metadata

```elixir
result = ClaudeAgent.query_result("What is 2 + 2?")
IO.puts("Answer: #{result.result}")
IO.puts("Cost: $#{result.total_cost_usd}")
IO.puts("Duration: #{result.duration_ms}ms")
```

### Stream All Messages

For more control, stream all messages as they arrive:

```elixir
alias ClaudeAgent.Types.Messages.AssistantMessage
alias ClaudeAgent.Types.ContentBlocks.TextBlock

ClaudeAgent.query("What is 2 + 2?")
|> Enum.each(fn
  %AssistantMessage{content: blocks} ->
    Enum.each(blocks, fn
      %TextBlock{text: text} -> IO.puts(text)
      _ -> :ok
    end)
  _ -> :ok
end)
```

### With Options

```elixir
ClaudeAgent.query_text("List the files in the current directory",
  system_prompt: "You are a helpful coding assistant",
  allowed_tools: ["Read", "Write", "Bash"],
  permission_mode: :bypass_permissions,
  max_turns: 5
)
```

## Configuration

Configure default options in your application's `config/config.exs` file:

```elixir
# In your app's config/config.exs
config :claude_agent_sdk,
  cli_path: "/path/to/claude",           # Path to Claude CLI
  permission_mode: :bypass_permissions,  # Default permission mode
  system_prompt: "You are helpful",      # Default system prompt
  max_turns: 10,                         # Maximum conversation turns
  max_budget_usd: 1.0                    # Budget limit
```

### Environment-Specific Configuration

Use environment-specific config files for different settings:

```elixir
# config/dev.exs
config :claude_agent_sdk,
  permission_mode: :bypass_permissions,
  max_turns: 20

# config/test.exs
config :claude_agent_sdk,
  permission_mode: :bypass_permissions,
  max_turns: 5

# config/runtime.exs - for production environment variables
if cli_path = System.get_env("CLAUDE_CLI_PATH") do
  config :claude_agent_sdk, cli_path: cli_path
end
```

### Precedence

Configuration follows this precedence (highest to lowest):
1. **Per-query options** - Passed directly to `query/2`, `query_text/2`, etc.
2. **Application config** - Set in your app's `config/*.exs` files
3. **Built-in defaults** - Defined in `ClaudeAgent.Options.defaults/0`

```elixir
# Uses application config defaults
ClaudeAgent.query_text("Hello!")

# Per-query options override application config
ClaudeAgent.query_text("Hello!", system_prompt: "Be concise", max_turns: 3)
```

## Configuration Options

| Option | Description |
|--------|-------------|
| `cli_path` | Path to Claude CLI executable |
| `system_prompt` | Custom system prompt |
| `allowed_tools` | List of allowed tool names |
| `disallowed_tools` | List of disallowed tool names |
| `permission_mode` | `:default`, `:accept_edits`, `:plan`, `:bypass_permissions` |
| `max_turns` | Maximum conversation turns |
| `max_budget_usd` | Maximum cost limit |
| `model` | Model to use (e.g., "claude-sonnet-4-5") |
| `cwd` | Working directory |
| `skip_version_check` | Skip CLI version check (default: `false`) |
| `stream_close_timeout` | Timeout in ms for stream close (default: 300000) |

See `ClaudeAgent.Options` for full documentation.

## Message Types

The SDK returns these message types when streaming:

- `SystemMessage` - System events (initialization)
- `AssistantMessage` - Claude's responses
- `ResultMessage` - Final result with cost info

Content blocks within AssistantMessage:

- `TextBlock` - Plain text
- `ThinkingBlock` - Claude's reasoning
- `ToolUseBlock` - Tool invocation
- `ToolResultBlock` - Tool result

## Interactive Client

For multi-turn conversations with full control:

```elixir
alias ClaudeAgent.Client
alias ClaudeAgent.Types.Messages.{AssistantMessage, ResultMessage}
alias ClaudeAgent.Types.ContentBlocks.TextBlock

# Start client
{:ok, client} = Client.start_link(permission_mode: :bypass_permissions)

# Send first message
:ok = Client.query(client, "My name is Alice. Remember this.")
client |> Client.receive_response() |> Enum.to_list()

# Follow-up message - Claude remembers context
:ok = Client.query(client, "What is my name?")
messages = client |> Client.receive_response() |> Enum.to_list()

# Extract text from response
text = messages
|> Enum.filter(&match?(%AssistantMessage{}, &1))
|> Enum.flat_map(& &1.content)
|> Enum.filter(&match?(%TextBlock{}, &1))
|> Enum.map(& &1.text)
|> Enum.join(" ")

IO.puts(text)  # => "Your name is Alice!"

# Cleanup
Client.disconnect(client)
```

### Client API

- `Client.start_link/2` - Start a new client
- `Client.connect/1` - Explicitly connect (optional, happens automatically)
- `Client.query/2` - Send a message
- `Client.receive_response/1` - Stream messages until result
- `Client.receive_messages/1` - Stream all messages continuously
- `Client.interrupt/1` - Interrupt current operation
- `Client.get_server_info/1` - Get available commands and capabilities
- `Client.disconnect/1` - Close the connection

## Livebook Demo

Try the interactive demo notebook [demo.livemd](demo.livemd):

1. Download and install [LiveBook Desktop](https://livebook.dev/)
2. Open the LiveBook Desktop app
3. Click "Open" and navigate to `demo.livemd` in this repository
4. Run the cells to see examples

The demo runs locally and has access to your environment, including the Claude CLI.

### Livebook via Escript (Alternative)

For local development and easy configuration via CLI options, you can install Livebook as an escript:

```bash
# Install Livebook escript
mix do local.rebar --force, local.hex --force
mix escript.install hex livebook

# Start the Livebook server
livebook server

# See all configuration options
livebook server --help
```

**Important**: After installing the escript, ensure the escript directory is in your `$PATH`:

- If you installed Elixir with `asdf`, run `asdf reshim elixir` after the escript is built
- The escript directory is typically `~/.mix/escripts`

Once Livebook is running, you can:

1. Navigate to the Livebook web interface (usually `http://localhost:8080`)
2. Import the demo notebook by URL: `http://localhost:8080/import?url=file:///path/to/demo.livemd`
3. Or use "Open" and select [demo.livemd](demo.livemd) from this repository

This method provides a convenient way to interact with the SDK directly in your local environment, with full access to your filesystem and installed tools like the Claude CLI.

## SDK MCP Tools (Custom In-Process Tools)

Create custom tools that run directly in your Elixir application with zero IPC overhead.

### Quick Example

```elixir
alias ClaudeAgent.Mcp.Tool

# Define a tool
greet_tool = Tool.from_spec("greet", "Greet a person",
  %{name: :string},
  fn args -> {:ok, "Hello, #{args["name"]}!"} end,
  required: [:name]
)

# Create server
server = ClaudeAgent.create_sdk_mcp_server("greeter", tools: [greet_tool])

# Use in query
ClaudeAgent.query_text("Greet Alice",
  mcp_servers: %{"greeter" => %{type: :sdk, instance: server}},
  allowed_tools: ["mcp__greeter__greet"]
)
```

### Why SDK MCP Tools?

- **Performance** - No IPC overhead, tools run in your application process
- **Simple Deployment** - Single process, no external servers to manage
- **Easy Debugging** - Standard Elixir debugging tools work seamlessly
- **Direct Access** - Tools can access your application's state and modules via closures

### Calculator Example

```elixir
# Define calculator tools
add_tool = Tool.from_spec("add", "Add two numbers",
  %{a: :number, b: :number},
  fn args -> {:ok, "#{args["a"] + args["b"]}"} end,
  required: [:a, :b]
)

divide_tool = Tool.from_spec("divide", "Divide two numbers",
  %{a: :number, b: :number},
  fn args ->
    if args["b"] == 0 do
      {:error, "Cannot divide by zero"}
    else
      {:ok, "#{args["a"] / args["b"]}"}
    end
  end,
  required: [:a, :b]
)

# Create server with multiple tools
calculator = ClaudeAgent.create_sdk_mcp_server("calc",
  version: "1.0.0",
  tools: [add_tool, divide_tool]
)

# Use with Claude
ClaudeAgent.query_text("Calculate 15 + 27",
  mcp_servers: %{"calc" => %{type: :sdk, instance: calculator}},
  allowed_tools: ["mcp__calc__add", "mcp__calc__divide"]
)
```

### Advanced Features

**Multiple Content Types:**
```elixir
# Tool returning text and images
{:ok, [
  %{"type" => "text", "text" => "Here's the chart:"},
  %{"type" => "image", "data" => base64_data, "mimeType" => "image/png"}
]}
```

**Error Handling:**
```elixir
# Return errors that Claude can see and respond to
{:error, "Invalid input: value must be positive"}
```

**Stateful Tools:**
```elixir
# Tools can access application state via closures
Tool.from_spec("get_user", "Get user info", %{id: :integer},
  fn args ->
    # Access your app's modules and state
    user = MyApp.Users.get_user(args["id"])
    {:ok, Jason.encode!(user)}
  end
)
```

See [demo.livemd](demo.livemd) for interactive examples!

## Advanced Features

The following features are production-ready:

- **Hooks** - Intercept and modify tool usage
- **SDK MCP Tools** - In-process MCP servers with custom tools
- **Tool Permissions** - Programmatic permission callbacks
- **Subagents** - Delegate tasks to specialized agents

## Testing

Run the test suite:

```bash
mix test
```

## License

MIT
