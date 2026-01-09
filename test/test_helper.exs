ExUnit.start()

# Configure SDK for testing
Application.put_env(:claude_agent_sdk, :skip_version_check, true)

# Define mock transport for testing
Mox.defmock(ClaudeAgent.MockTransport, for: ClaudeAgent.Transport)
