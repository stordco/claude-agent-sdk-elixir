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

  describe "get_config/0" do
    setup do
      # Store original config
      original_config = Application.get_all_env(:claude_agent_sdk)

      # Clear config for test
      for {key, _} <- original_config do
        Application.delete_env(:claude_agent_sdk, key)
      end

      on_exit(fn ->
        # Restore original config
        for {key, _} <- Application.get_all_env(:claude_agent_sdk) do
          Application.delete_env(:claude_agent_sdk, key)
        end

        for {key, value} <- original_config do
          Application.put_env(:claude_agent_sdk, key, value)
        end
      end)

      :ok
    end

    test "returns defaults when no config set" do
      config = ClaudeAgent.get_config()
      # Should return defaults from Options module
      assert is_list(config)
      assert config[:allowed_tools] == []
    end

    test "returns application configuration" do
      Application.put_env(:claude_agent_sdk, :cli_path, "/test/path")
      Application.put_env(:claude_agent_sdk, :max_turns, 10)

      config = ClaudeAgent.get_config()
      assert config[:cli_path] == "/test/path"
      assert config[:max_turns] == 10
    end
  end

  describe "Options" do
    test "returns default options" do
      opts = Options.defaults()
      assert opts[:allowed_tools] == []
      assert opts[:system_prompt] == nil
      assert opts[:permission_mode] == nil
      assert opts[:continue_conversation] == false
    end

    test "normalizes options with values" do
      {:ok, opts} =
        Options.normalize(
          allowed_tools: ["Read", "Write"],
          system_prompt: "Be helpful",
          max_turns: 5
        )

      assert opts[:allowed_tools] == ["Read", "Write"]
      assert opts[:system_prompt] == "Be helpful"
      assert opts[:max_turns] == 5
    end

    test "validates options" do
      assert :ok = Options.validate([])
      assert :ok = Options.validate(max_turns: 5)
      assert {:error, _} = Options.validate(max_turns: -1)
    end

    test "detects streaming requirements" do
      assert Options.requires_streaming?(can_use_tool: fn _, _, _ -> nil end)
      assert Options.requires_streaming?(hooks: %{})
      refute Options.requires_streaming?([])
    end

    test "gets values with defaults" do
      opts = [max_turns: 5, system_prompt: "Test"]
      assert Options.get(opts, :max_turns) == 5
      assert Options.get(opts, :model) == nil
      assert Options.get(opts, :model, "sonnet") == "sonnet"
    end

    test "merges options" do
      base = [max_turns: 5, system_prompt: "Base"]
      overrides = [max_turns: 10]
      merged = Options.merge(base, overrides)

      assert merged[:max_turns] == 10
      assert merged[:system_prompt] == "Base"
    end

    test "loads from app env" do
      # Store original config
      original_config = Application.get_all_env(:claude_agent_sdk)

      try do
        # Clear and set test config
        for {key, _} <- original_config do
          Application.delete_env(:claude_agent_sdk, key)
        end

        Application.put_env(:claude_agent_sdk, :permission_mode, :bypass_permissions)
        Application.put_env(:claude_agent_sdk, :max_turns, 10)

        # Should merge app env with query options
        opts = Options.from_app_env(max_turns: 5, system_prompt: "Test")

        assert opts[:permission_mode] == :bypass_permissions
        # Query option overrides app env
        assert opts[:max_turns] == 5
        assert opts[:system_prompt] == "Test"
      after
        # Restore original config
        for {key, _} <- Application.get_all_env(:claude_agent_sdk) do
          Application.delete_env(:claude_agent_sdk, key)
        end

        for {key, value} <- original_config do
          Application.put_env(:claude_agent_sdk, key, value)
        end
      end
    end

    test "from_app_env uses defaults when no app config" do
      # Store original config
      original_config = Application.get_all_env(:claude_agent_sdk)

      try do
        # Clear config
        for {key, _} <- original_config do
          Application.delete_env(:claude_agent_sdk, key)
        end

        opts = Options.from_app_env(max_turns: 5)

        # Should have defaults
        assert opts[:allowed_tools] == []
        assert opts[:permission_mode] == nil
        # But query options override
        assert opts[:max_turns] == 5
      after
        # Restore original config
        for {key, value} <- original_config do
          Application.put_env(:claude_agent_sdk, key, value)
        end
      end
    end
  end
end
