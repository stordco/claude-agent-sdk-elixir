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
alias ClaudeAgent.Options

opts = %Options{
  system_prompt: "You are a helpful coding assistant",
  allowed_tools: ["Read", "Write", "Bash"],
  permission_mode: :bypass_permissions,
  max_turns: 5
}

ClaudeAgent.query_text("List the files in the current directory", opts)
```

## Configuration Options

| Option | Description |
|--------|-------------|
| `system_prompt` | Custom system prompt |
| `allowed_tools` | List of allowed tool names |
| `disallowed_tools` | List of disallowed tool names |
| `permission_mode` | `:default`, `:accept_edits`, `:plan`, `:bypass_permissions` |
| `max_turns` | Maximum conversation turns |
| `max_budget_usd` | Maximum cost limit |
| `model` | Model to use (e.g., "claude-sonnet-4-5") |
| `cwd` | Working directory |

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
alias ClaudeAgent.Options
alias ClaudeAgent.Types.Messages.{AssistantMessage, ResultMessage}
alias ClaudeAgent.Types.ContentBlocks.TextBlock

# Start client
{:ok, client} = Client.start_link(%Options{permission_mode: :bypass_permissions})

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

## Advanced Features (Work in Progress)

The following features are implemented but still being refined:

- **Hooks** - Intercept and modify tool usage
- **MCP Servers** - In-process MCP servers with custom tools
- **Tool Permissions** - Programmatic permission callbacks

## License

MIT
