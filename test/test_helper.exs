ExUnit.start()

# Define mock transport for testing
Mox.defmock(ClaudeAgentSdk.MockTransport, for: ClaudeAgentSdk.Transport)
