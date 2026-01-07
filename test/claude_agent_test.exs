defmodule ClaudeAgentTest do
  use ExUnit.Case
  doctest ClaudeAgent

  alias ClaudeAgent.Options

  describe "version/0" do
    test "returns version string" do
      version = ClaudeAgent.version()
      assert is_binary(version)
      assert String.match?(version, ~r/^\d+\.\d+\.\d+/)
    end
  end

  describe "Options" do
    test "creates default options" do
      opts = %Options{}
      assert opts.allowed_tools == []
      assert opts.system_prompt == nil
      assert opts.permission_mode == nil
      assert opts.continue_conversation == false
    end

    test "creates options with values" do
      opts = %Options{
        allowed_tools: ["Read", "Write"],
        system_prompt: "Be helpful",
        max_turns: 5
      }

      assert opts.allowed_tools == ["Read", "Write"]
      assert opts.system_prompt == "Be helpful"
      assert opts.max_turns == 5
    end

    test "validates options" do
      assert :ok = Options.validate(%Options{})
      assert :ok = Options.validate(%Options{max_turns: 5})
      assert {:error, _} = Options.validate(%Options{max_turns: -1})
    end

    test "detects streaming requirements" do
      assert Options.requires_streaming?(%Options{can_use_tool: fn _, _, _ -> nil end})
      assert Options.requires_streaming?(%Options{hooks: %{}})
      refute Options.requires_streaming?(%Options{})
    end
  end
end
