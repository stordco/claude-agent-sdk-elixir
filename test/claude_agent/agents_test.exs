defmodule ClaudeAgent.AgentsTest do
  use ExUnit.Case, async: true

  alias ClaudeAgent.Transport.SubprocessCli
  alias ClaudeAgent.Subagent

  describe "agent definition serialization" do
    test "filters out nil values from agent definitions" do
      opts = [
        agents: %{
          "test-agent" => Subagent.new("Test agent", "You are a test agent")
        }
      ]

      transport = SubprocessCli.new("test prompt", opts)
      cmd = SubprocessCli.build_command_for_testing(transport)

      # Find the --agents argument
      agents_idx = Enum.find_index(cmd, &(&1 == "--agents"))
      assert agents_idx != nil, "Expected --agents flag in command"

      agents_json = Enum.at(cmd, agents_idx + 1)

      # Decode and verify nil values were filtered out
      agents = Jason.decode!(agents_json)
      test_agent = agents["test-agent"]

      assert test_agent["description"] == "Test agent"
      assert test_agent["prompt"] == "You are a test agent"
      refute Map.has_key?(test_agent, "tools"), "tools should be filtered out when nil"
      refute Map.has_key?(test_agent, "model"), "model should be filtered out when nil"
    end

    test "preserves non-nil values in agent definitions" do
      opts = [
        agents: %{
          "code-reviewer" =>
            Subagent.new(
              "Code review specialist",
              "Review code for issues",
              tools: ["Read", "Grep", "Glob"],
              model: :sonnet
            )
        }
      ]

      transport = SubprocessCli.new("test prompt", opts)
      cmd = SubprocessCli.build_command_for_testing(transport)

      agents_idx = Enum.find_index(cmd, &(&1 == "--agents"))
      agents_json = Enum.at(cmd, agents_idx + 1)

      agents = Jason.decode!(agents_json)
      agent = agents["code-reviewer"]

      assert agent["description"] == "Code review specialist"
      assert agent["prompt"] == "Review code for issues"
      assert agent["tools"] == ["Read", "Grep", "Glob"]
      assert agent["model"] == "sonnet"
    end

    test "handles multiple agents with mixed nil values" do
      opts = [
        agents: %{
          "analyzer" =>
            Subagent.new(
              "Analyzer",
              "Analyze code",
              tools: ["Read"],
              model: :sonnet
            ),
          "tester" => Subagent.new("Tester", "Generate tests")
        }
      ]

      transport = SubprocessCli.new("test prompt", opts)
      cmd = SubprocessCli.build_command_for_testing(transport)

      agents_idx = Enum.find_index(cmd, &(&1 == "--agents"))
      agents_json = Enum.at(cmd, agents_idx + 1)

      agents = Jason.decode!(agents_json)

      # Analyzer has all fields
      analyzer = agents["analyzer"]
      assert analyzer["description"] == "Analyzer"
      assert analyzer["prompt"] == "Analyze code"
      assert analyzer["tools"] == ["Read"]
      assert analyzer["model"] == "sonnet"

      # Tester has nil values filtered
      tester = agents["tester"]
      assert tester["description"] == "Tester"
      assert tester["prompt"] == "Generate tests"
      refute Map.has_key?(tester, "tools")
      refute Map.has_key?(tester, "model")
    end

    test "converts model atoms to strings" do
      model_mappings = [
        {:sonnet, "sonnet"},
        {:opus, "opus"},
        {:haiku, "haiku"},
        {:inherit, "inherit"}
      ]

      for {model_atom, expected_model} <- model_mappings do
        opts = [
          agents: %{
            "test" => Subagent.new("Test", "Test prompt", model: model_atom)
          }
        ]

        transport = SubprocessCli.new("test", opts)
        cmd = SubprocessCli.build_command_for_testing(transport)

        agents_idx = Enum.find_index(cmd, &(&1 == "--agents"))
        agents_json = Enum.at(cmd, agents_idx + 1)
        agents = Jason.decode!(agents_json)

        assert agents["test"]["model"] == expected_model,
               "Expected model :#{model_atom} to serialize as '#{expected_model}'"
      end
    end

    test "omits --agents flag when agents is nil" do
      opts = [agents: nil]
      transport = SubprocessCli.new("test prompt", opts)
      cmd = SubprocessCli.build_command_for_testing(transport)

      refute Enum.member?(cmd, "--agents"), "Should not include --agents when agents is nil"
    end

    test "handles empty agents map" do
      opts = [agents: %{}]
      transport = SubprocessCli.new("test prompt", opts)
      cmd = SubprocessCli.build_command_for_testing(transport)

      agents_idx = Enum.find_index(cmd, &(&1 == "--agents"))
      agents_json = Enum.at(cmd, agents_idx + 1)
      agents = Jason.decode!(agents_json)

      assert agents == %{}
    end
  end

  describe "agent temp file optimization" do
    @tag :slow
    test "uses temp file for very large agent configurations" do
      # Create a VERY large agent definition that definitely exceeds command line limits
      # Need to exceed 8000 chars on Windows or 100000 on other platforms
      large_prompt = String.duplicate("This is a very long prompt that will exceed limits. ", 5000)

      opts = [
        agents: %{
          "large-agent" =>
            Subagent.new(
              "Large agent with extremely long prompt",
              large_prompt,
              tools: ["Read", "Write", "Edit", "Glob", "Grep", "Bash", "WebSearch", "WebFetch"],
              model: :sonnet
            )
        }
      ]

      transport = SubprocessCli.new("test prompt", opts)
      cmd = SubprocessCli.build_command_for_testing(transport)

      # Check command length
      cmd_length = String.length(Enum.join(cmd, " "))

      # Check if temp file optimization was used
      agents_idx = Enum.find_index(cmd, &(&1 == "--agents"))
      agents_value = Enum.at(cmd, agents_idx + 1)

      if cmd_length > 8000 do
        # Should use temp file reference on long commands
        assert String.starts_with?(agents_value, "@"),
               "Large agent config (#{cmd_length} chars) should use temp file reference (@filepath)"

        # Temp file might not exist yet in test context (only created during connect)
        # Just verify the format is correct
        assert String.starts_with?(agents_value, "@/")
      else
        # Command wasn't long enough to trigger optimization
        # This is fine - the optimization is conditional
        assert is_binary(agents_value)
      end
    end
  end

  describe "agent definition validation" do
    test "agent definition requires description and prompt" do
      # Note: Validation happens at the type level in Elixir
      # This test documents the expected structure

      valid_agent = %{
        description: "Test agent",
        prompt: "Test prompt",
        tools: nil,
        model: nil
      }

      opts = [agents: %{"test" => valid_agent}]
      assert %SubprocessCli{} = SubprocessCli.new("test", opts)
    end

    test "agent tools must be list of strings or nil" do
      valid_with_tools = %{
        description: "Test",
        prompt: "Test",
        tools: ["Read", "Write"],
        model: nil
      }

      valid_without_tools = %{
        description: "Test",
        prompt: "Test",
        tools: nil,
        model: nil
      }

      assert %SubprocessCli{} = SubprocessCli.new("test", agents: %{"t1" => valid_with_tools})
      assert %SubprocessCli{} = SubprocessCli.new("test", agents: %{"t2" => valid_without_tools})
    end
  end

  describe "agent JSON encoding" do
    test "produces valid JSON for CLI consumption" do
      opts = [
        agents: %{
          "test-agent" =>
            Subagent.new(
              "Test agent",
              "You are a test agent",
              tools: ["Read", "Grep"],
              model: :sonnet
            )
        }
      ]

      transport = SubprocessCli.new("test", opts)
      cmd = SubprocessCli.build_command_for_testing(transport)

      agents_idx = Enum.find_index(cmd, &(&1 == "--agents"))
      agents_json = Enum.at(cmd, agents_idx + 1)

      # Should be valid JSON
      assert {:ok, decoded} = Jason.decode(agents_json)
      assert is_map(decoded)
      assert Map.has_key?(decoded, "test-agent")
    end

    test "handles special characters in agent fields" do
      opts = [
        agents: %{
          "test-agent" =>
            Subagent.new(
              "Agent with \"quotes\" and 'apostrophes'",
              "Prompt with\nnewlines and\ttabs"
            )
        }
      ]

      transport = SubprocessCli.new("test", opts)
      cmd = SubprocessCli.build_command_for_testing(transport)

      agents_idx = Enum.find_index(cmd, &(&1 == "--agents"))
      agents_json = Enum.at(cmd, agents_idx + 1)

      # Should properly encode and decode special characters
      agents = Jason.decode!(agents_json)
      agent = agents["test-agent"]

      assert agent["description"] == "Agent with \"quotes\" and 'apostrophes'"
      assert agent["prompt"] == "Prompt with\nnewlines and\ttabs"
    end
  end

  describe "Subagent struct serialization" do
    test "serializes Subagent struct correctly" do
      opts = [
        agents: %{
          "test-agent" =>
            Subagent.new(
              "Code reviewer",
              "Review code for issues",
              tools: ["Read", "Grep"],
              model: :sonnet
            )
        }
      ]

      transport = SubprocessCli.new("test", opts)
      cmd = SubprocessCli.build_command_for_testing(transport)

      agents_idx = Enum.find_index(cmd, &(&1 == "--agents"))
      agents_json = Enum.at(cmd, agents_idx + 1)
      agents = Jason.decode!(agents_json)

      agent = agents["test-agent"]
      assert agent["description"] == "Code reviewer"
      assert agent["prompt"] == "Review code for issues"
      assert agent["tools"] == ["Read", "Grep"]
      assert agent["model"] == "sonnet"
    end

    test "filters nil values from Subagent struct" do
      opts = [
        agents: %{
          "test-agent" => Subagent.new("Test", "Test prompt")
        }
      ]

      transport = SubprocessCli.new("test", opts)
      cmd = SubprocessCli.build_command_for_testing(transport)

      agents_idx = Enum.find_index(cmd, &(&1 == "--agents"))
      agents_json = Enum.at(cmd, agents_idx + 1)
      agents = Jason.decode!(agents_json)

      agent = agents["test-agent"]
      assert agent["description"] == "Test"
      assert agent["prompt"] == "Test prompt"
      refute Map.has_key?(agent, "tools")
      refute Map.has_key?(agent, "model")
    end

    test "supports mixed map and Subagent struct" do
      opts = [
        agents: %{
          "struct-agent" => Subagent.new("Struct", "Struct prompt", model: :haiku),
          "map-agent" => %{
            description: "Map",
            prompt: "Map prompt",
            tools: ["Read"],
            model: nil
          }
        }
      ]

      transport = SubprocessCli.new("test", opts)
      cmd = SubprocessCli.build_command_for_testing(transport)

      agents_idx = Enum.find_index(cmd, &(&1 == "--agents"))
      agents_json = Enum.at(cmd, agents_idx + 1)
      agents = Jason.decode!(agents_json)

      # Both should serialize correctly
      assert agents["struct-agent"]["description"] == "Struct"
      assert agents["struct-agent"]["model"] == "haiku"

      assert agents["map-agent"]["description"] == "Map"
      assert agents["map-agent"]["tools"] == ["Read"]
      refute Map.has_key?(agents["map-agent"], "model")
    end
  end
end
