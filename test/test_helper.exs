ExUnit.start()

# Define mock transport for testing
Mox.defmock(ClaudeAgent.MockTransport, for: ClaudeAgent.Transport)
