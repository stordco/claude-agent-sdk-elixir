ExUnit.start()

# Configure SDK for testing
Application.put_env(:claude_agent_sdk, :skip_version_check, true)

# Create a fake CLI executable for testing (so tests don't require actual Claude CLI)
fake_cli_path =
  System.tmp_dir!() |> Path.join("fake-claude-test-#{System.unique_integer([:positive])}")

File.write!(fake_cli_path, "#!/bin/sh\necho 'fake claude'\n")
File.chmod!(fake_cli_path, 0o755)

# Configure the SDK to use the fake CLI by default in tests
Application.put_env(:claude_agent_sdk, :cli_path, fake_cli_path)

# Clean up the fake CLI on exit
System.at_exit(fn _status -> File.rm(fake_cli_path) end)

# Define mock transport for testing
Mox.defmock(ClaudeAgent.MockTransport, for: ClaudeAgent.Transport)
