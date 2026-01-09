defmodule ClaudeAgent.SubagentTest do
  use ExUnit.Case, async: true

  alias ClaudeAgent.Subagent

  describe "new/3" do
    test "creates a subagent with required fields" do
      agent = Subagent.new("Test agent", "Test prompt")

      assert %Subagent{
               description: "Test agent",
               prompt: "Test prompt",
               tools: nil,
               model: nil
             } = agent
    end

    test "creates a subagent with tools" do
      agent = Subagent.new("Test agent", "Test prompt", tools: ["Read", "Write"])

      assert agent.tools == ["Read", "Write"]
    end

    test "creates a subagent with model" do
      agent = Subagent.new("Test agent", "Test prompt", model: :sonnet)

      assert agent.model == :sonnet
    end

    test "creates a subagent with all options" do
      agent =
        Subagent.new("Test agent", "Test prompt",
          tools: ["Read"],
          model: :haiku
        )

      assert agent.description == "Test agent"
      assert agent.prompt == "Test prompt"
      assert agent.tools == ["Read"]
      assert agent.model == :haiku
    end
  end

  describe "struct syntax" do
    test "allows creating with all fields" do
      agent = %Subagent{
        description: "Test",
        prompt: "Prompt",
        tools: ["Read"],
        model: :sonnet
      }

      assert agent.description == "Test"
      assert agent.prompt == "Prompt"
      assert agent.tools == ["Read"]
      assert agent.model == :sonnet
    end
  end

  describe "to_map/1" do
    test "converts struct to map" do
      agent = Subagent.new("Test", "Prompt", tools: ["Read"], model: :sonnet)
      map = Subagent.to_map(agent)

      assert map == %{
               description: "Test",
               prompt: "Prompt",
               tools: ["Read"],
               model: :sonnet
             }
    end

    test "filters out nil values" do
      agent = Subagent.new("Test", "Prompt")
      map = Subagent.to_map(agent)

      assert map == %{description: "Test", prompt: "Prompt"}
      refute Map.has_key?(map, :tools)
      refute Map.has_key?(map, :model)
    end

    test "preserves non-nil values" do
      agent = Subagent.new("Test", "Prompt", tools: nil, model: :haiku)
      map = Subagent.to_map(agent)

      assert map == %{description: "Test", prompt: "Prompt", model: :haiku}
      refute Map.has_key?(map, :tools)
    end
  end

  describe "validate/1" do
    test "validates a valid subagent" do
      agent = Subagent.new("Test", "Prompt")
      assert :ok = Subagent.validate(agent)
    end

    test "validates with all fields" do
      agent = Subagent.new("Test", "Prompt", tools: ["Read"], model: :sonnet)
      assert :ok = Subagent.validate(agent)
    end

    test "rejects empty description" do
      agent = %Subagent{description: "", prompt: "Test"}
      assert {:error, msg} = Subagent.validate(agent)
      assert msg =~ "description"
    end

    test "rejects empty prompt" do
      agent = %Subagent{description: "Test", prompt: ""}
      assert {:error, msg} = Subagent.validate(agent)
      assert msg =~ "prompt"
    end

    test "rejects invalid tools" do
      agent = %Subagent{description: "Test", prompt: "Prompt", tools: "invalid"}
      assert {:error, msg} = Subagent.validate(agent)
      assert msg =~ "tools"
    end

    test "rejects non-string tool names" do
      agent = %Subagent{description: "Test", prompt: "Prompt", tools: [:read, :write]}
      assert {:error, msg} = Subagent.validate(agent)
      assert msg =~ "tools"
    end

    test "rejects invalid model" do
      agent = %Subagent{description: "Test", prompt: "Prompt", model: :invalid}
      assert {:error, msg} = Subagent.validate(agent)
      assert msg =~ "Invalid model"
      assert msg =~ ":invalid"
    end

    test "accepts all valid models" do
      for model <- [:sonnet, :opus, :haiku, :inherit, nil] do
        agent = Subagent.new("Test", "Prompt", model: model)
        assert :ok = Subagent.validate(agent)
      end
    end
  end
end
