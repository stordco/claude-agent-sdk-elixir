defmodule ClaudeAgent.Transport.SubprocessCliTest do
  use ExUnit.Case, async: true

  alias ClaudeAgent.Transport.SubprocessCli

  describe "shell escaping for script command" do
    test "properly escapes arguments with special characters on Linux" do
      test_args = [
        "/usr/bin/claude",
        "--output-format",
        "stream-json",
        "--verbose",
        "--system-prompt",
        "",
        "--print",
        "--",
        "What is 2+2?"
      ]

      # Expected: each argument should be properly quoted
      expected =
        ~s("/usr/bin/claude" "--output-format" "stream-json" "--verbose" "--system-prompt" "" "--print" "--" "What is 2+2?")

      result = SubprocessCli.shell_escape_command(test_args)
      assert result == expected
    end

    test "handles arguments with quotes and special characters" do
      test_args = [
        "/usr/bin/claude",
        "--json",
        ~s({"key": "value with spaces", "nested": {"foo": "bar"}})
      ]

      result = SubprocessCli.shell_escape_command(test_args)

      # The JSON argument should be properly escaped with backslashes before quotes
      expected =
        ~s("/usr/bin/claude" "--json" "{\\"key\\": \\"value with spaces\\", \\"nested\\": {\\"foo\\": \\"bar\\"}}")

      assert result == expected
    end

    test "handles arguments with single quotes" do
      test_args = [
        "/usr/bin/claude",
        "--prompt",
        "What's the answer?"
      ]

      result = SubprocessCli.shell_escape_command(test_args)

      # Should escape the single quote properly
      assert result == ~s("/usr/bin/claude" "--prompt" "What's the answer?")
    end

    test "handles empty arguments" do
      test_args = [
        "/usr/bin/claude",
        "--system-prompt",
        ""
      ]

      result = SubprocessCli.shell_escape_command(test_args)
      assert result == ~s("/usr/bin/claude" "--system-prompt" "")
    end

    test "handles arguments with backslashes" do
      test_args = [
        "/usr/bin/claude",
        "--path",
        "C:\\Users\\Test\\file.txt"
      ]

      result = SubprocessCli.shell_escape_command(test_args)
      assert String.contains?(result, "C:\\\\Users\\\\Test\\\\file.txt")
    end
  end
end
