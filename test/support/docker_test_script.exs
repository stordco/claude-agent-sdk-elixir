#!/usr/bin/env elixir

# Test script to reproduce the Docker bug
# This should be run inside the Docker container

Mix.install([
  {:jason, "~> 1.4"}
])

defmodule DockerTest do
  def run do
    IO.puts("=== Docker Environment Test ===\n")

    # Check environment
    IO.puts("1. Checking environment...")
    IO.puts("   Claude CLI version:")

    case System.cmd("/home/app/.npm-global/bin/claude", ["--version"], stderr_to_stdout: true) do
      {output, 0} -> IO.puts("   ✓ #{String.trim(output)}")
      {output, _} -> IO.puts("   ✗ Failed: #{output}")
    end

    IO.puts("   script command location:")
    IO.puts("   ✓ #{System.find_executable("script") || "NOT FOUND"}")

    IO.puts("   User: #{System.get_env("USER")}")
    IO.puts("   Home: #{System.get_env("HOME")}")

    # Test shell escaping
    IO.puts("\n2. Testing shell escaping...")
    test_args = [
      "/home/app/.npm-global/bin/claude",
      "--output-format",
      "stream-json",
      "--verbose",
      "--system-prompt",
      "",
      "--print",
      "--",
      "What is 2+2?"
    ]

    escaped = shell_escape_command(test_args)
    IO.puts("   Command: #{String.slice(escaped, 0, 100)}...")

    # Test actual execution (if credentials are available)
    IO.puts("\n3. Testing actual CLI execution...")
    cred_path = Path.join(System.user_home(), ".claude/.credentials.json")

    if File.exists?(cred_path) do
      IO.puts("   ✓ Credentials found")

      # Try running a simple query
      test_query = "What is 2+2? Reply with just the number."

      IO.puts("   Running test query: #{test_query}")

      # Use script command directly to simulate the fix
      script_path = System.find_executable("script")

      if script_path do
        full_cmd = shell_escape_command([
          "/home/app/.npm-global/bin/claude",
          "--output-format",
          "stream-json",
          "--verbose",
          "--system-prompt",
          "",
          "--print",
          "--",
          test_query
        ])

        port_args = ["-q", "-c", full_cmd, "/dev/null"]

        port =
          Port.open({:spawn_executable, script_path}, [
            :binary,
            :exit_status,
            :use_stdio,
            {:args, port_args},
            {:env, [
              {~c"CLAUDE_CODE_ENTRYPOINT", ~c"sdk-elixir-test"},
              {~c"PATH", String.to_charlist(System.get_env("PATH", ""))}
            ]}
          ])

        result = collect_output(port, "")

        if String.length(result) > 0 do
          IO.puts("   ✓ Received output (#{String.length(result)} bytes)")

          # Try to parse JSON messages
          messages = parse_json_messages(result)
          IO.puts("   ✓ Parsed #{length(messages)} JSON messages")

          if length(messages) > 0 do
            IO.puts("\n=== SUCCESS ===")
            IO.puts("The fix is working! Received messages from Claude CLI.")
          else
            IO.puts("\n=== ISSUE ===")
            IO.puts("Received output but no valid JSON messages.")
            IO.puts("Raw output (first 500 chars):")
            IO.puts(String.slice(result, 0, 500))
          end
        else
          IO.puts("   ✗ No output received (BUG REPRODUCED)")
          IO.puts("\n=== BUG REPRODUCED ===")
          IO.puts("This indicates the shell escaping issue is still present.")
        end
      else
        IO.puts("   ✗ script command not found")
      end
    else
      IO.puts("   ✗ No credentials found at #{cred_path}")
      IO.puts("   Skipping actual execution test")
      IO.puts("\n   To test with credentials, mount them:")
      IO.puts("   docker run -v ~/.claude:/home/app/.claude ...")
    end
  end

  defp shell_escape_command(args) do
    args
    |> Enum.map(&shell_escape_arg/1)
    |> Enum.join(" ")
  end

  defp shell_escape_arg(arg) do
    escaped =
      arg
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("$", "\\$")
      |> String.replace("`", "\\`")
      |> String.replace("\n", "\\n")

    "\"#{escaped}\""
  end

  defp collect_output(port, acc) do
    receive do
      {^port, {:data, data}} ->
        collect_output(port, acc <> data)

      {^port, {:exit_status, _}} ->
        acc

      {:EXIT, ^port, _} ->
        acc
    after
      5000 -> acc
    end
  end

  defp parse_json_messages(output) do
    output
    |> String.split("\n")
    |> Enum.filter(&(&1 != ""))
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "{"))
    |> Enum.filter(fn line ->
      case Jason.decode(line) do
        {:ok, _} -> true
        _ -> false
      end
    end)
  end
end

DockerTest.run()
