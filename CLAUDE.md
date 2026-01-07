# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Elixir port of the official Claude Agent SDK, providing a client library for interacting with Claude through the Claude Code CLI. It communicates with the CLI via JSON over stdin/stdout using Elixir Ports.

## Development Commands

```bash
# Install dependencies
mix deps.get

# Run all tests
mix test

# Run a single test file
mix test test/claude_agent_test.exs

# Run a specific test by line number
mix test test/claude_agent_test.exs:10

# Run tests with verbose output
mix test --trace

# Type checking with Dialyzer (first run builds PLT)
mix dialyzer

# Code formatting
mix format

# Check formatting without modifying
mix format --check-formatted

# Generate documentation
mix docs
```

## Architecture

### Core Flow

1. **ClaudeAgent** (`lib/claude_agent.ex`) - Main entry point with `query/2`, `query_text/2`, `query_result/2` for one-shot queries
2. **ClaudeAgent.Client** (`lib/claude_agent/client.ex`) - GenServer for multi-turn conversations with support for interrupts, hooks, and permission callbacks
3. **ClaudeAgent.Query** (`lib/claude_agent/query.ex`) - Simple query execution, returns lazy Stream of messages

### Transport Layer

- **Transport behaviour** (`lib/claude_agent/transport/transport.ex`) - Defines the interface for CLI communication
- **SubprocessCli** (`lib/claude_agent/transport/subprocess_cli.ex`) - Spawns Claude Code CLI as subprocess, handles PTY wrapping on Unix (via `script` command), JSON message buffering and parsing

### Protocol Layer

- **QueryHandler** (`lib/claude_agent/protocol/query_handler.ex`) - GenServer managing bidirectional control protocol, hook callbacks, tool permissions, and SDK MCP server routing. Spawns a reader process that owns the Port for receiving messages.
- **MessageParser** (`lib/claude_agent/protocol/message_parser.ex`) - Converts raw JSON maps from CLI into typed message structs

### Type System

- **Messages** (`lib/claude_agent/types/messages.ex`) - UserMessage, AssistantMessage, SystemMessage, ResultMessage, StreamEvent
- **ContentBlocks** (`lib/claude_agent/types/content_blocks.ex`) - TextBlock, ThinkingBlock, ToolUseBlock, ToolResultBlock
- **Permissions** (`lib/claude_agent/types/permissions.ex`) - PermissionResultAllow, PermissionResultDeny, ToolPermissionContext

### Options and Configuration

- **Options** (`lib/claude_agent/options.ex`) - All configurable options: tools, permission modes, MCP servers, hooks, agents, sandbox settings

### Advanced Features

- **MCP Server** (`lib/claude_agent/mcp/server.ex`, `tool.ex`) - In-process MCP server implementation for custom tools
- **Hooks** (`lib/claude_agent/hooks/hook_matcher.ex`) - Pre/post tool use event interception

## Key Patterns

- Uses Mox for mocking in tests (`test/support/` contains mock modules)
- Lazy evaluation with Streams for message handling
- GenServer pattern for stateful Client
- Behaviour pattern for Transport abstraction
- Control protocol uses JSON messages with request IDs for correlation

## Dependencies

- `jason` - JSON encoding/decoding
- `nimble_options` - Option validation
- `mox` - Test mocks (test only)
- `dialyxir` - Static analysis (dev/test only)
