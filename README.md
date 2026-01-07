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
text = ClaudeAgentSdk.query_text("What is the capital of France?")
IO.puts(text)
# => "The capital of France is Paris."
```

### Get Full Result with Metadata

```elixir
result = ClaudeAgentSdk.query_result("What is 2 + 2?")
IO.puts("Answer: #{result.result}")
IO.puts("Cost: $#{result.total_cost_usd}")
IO.puts("Duration: #{result.duration_ms}ms")
```

### Stream All Messages

For more control, stream all messages as they arrive:

```elixir
alias ClaudeAgentSdk.Types.Messages.AssistantMessage
alias ClaudeAgentSdk.Types.ContentBlocks.TextBlock

ClaudeAgentSdk.query("What is 2 + 2?")
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
alias ClaudeAgentSdk.Options

opts = %Options{
  system_prompt: "You are a helpful coding assistant",
  allowed_tools: ["Read", "Write", "Bash"],
  permission_mode: :bypass_permissions,
  max_turns: 5
}

ClaudeAgentSdk.query_text("List the files in the current directory", opts)
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

See `ClaudeAgentSdk.Options` for full documentation.

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

## Advanced Features (Work in Progress)

The following features are implemented but still being refined:

- **Interactive Client** - Multi-turn conversations via `ClaudeAgentSdk.Client`
- **Hooks** - Intercept and modify tool usage
- **MCP Servers** - In-process MCP servers with custom tools
- **Tool Permissions** - Programmatic permission callbacks

## License

MIT
