defmodule ClaudeAgent.Subagent do
  @moduledoc """
  Defines a subagent configuration for delegating specialized tasks.

  Subagents allow you to create specialized agents with custom prompts, tool
  restrictions, and model configurations. This enables multi-agent workflows where
  different agents handle different aspects of a task.

  ## Fields

  - `description` (required) - Brief description of what the agent does. This helps
    Claude understand when to delegate to this agent.

  - `prompt` (required) - System prompt that defines the agent's behavior, personality,
    and instructions. This is sent to the model when the agent is invoked.

  - `tools` (optional) - List of tool names this agent is allowed to use. When `nil`,
    the agent has access to all available tools. Use this to restrict agents to specific
    capabilities for safety or cost control.

  - `model` (optional) - Model override for this agent. Can be `:sonnet`, `:opus`,
    `:haiku`, or `:inherit`/`nil` to inherit from parent.

  ## Examples

  ### Using struct syntax

      %Subagent{
        description: "Code review specialist",
        prompt: "You are an expert code reviewer. Focus on security and performance.",
        tools: ["Read", "Grep", "Glob"],
        model: :sonnet
      }

  ### Using the constructor

      Subagent.new(
        "Code review specialist",
        "You are an expert code reviewer. Focus on security and performance.",
        tools: ["Read", "Grep", "Glob"],
        model: :sonnet
      )

  ### Minimal agent (inherits model, has all tools)

      Subagent.new(
        "General assistant",
        "You are a helpful assistant."
      )

  ## Usage in Queries

      agents = %{
        "code-reviewer" => Subagent.new(
          "Security-focused code reviewer",
          "Review code for security vulnerabilities",
          tools: ["Read", "Grep"],
          model: :sonnet
        )
      }

      ClaudeAgent.query_text(
        "Use the code-reviewer to review auth.ex",
        agents: agents
      )

  ## See Also

  - `ClaudeAgent.Options` for full options documentation including subagents
  - `ClaudeAgent.Hooks.HookMatcher` for `:subagent_stop` hook documentation
  """

  @enforce_keys [:description, :prompt]
  defstruct [:description, :prompt, :tools, :model]

  @type model :: :sonnet | :opus | :haiku | :inherit

  @typedoc """
  Subagent configuration struct.

  See module documentation for detailed field descriptions and examples.
  """
  @type t :: %__MODULE__{
          description: String.t(),
          prompt: String.t(),
          tools: [String.t()] | nil,
          model: model() | nil
        }

  @doc """
  Creates a new subagent configuration.

  ## Parameters

  - `description` - Brief description of the agent's purpose
  - `prompt` - System prompt defining the agent's behavior
  - `opts` - Optional keyword list with:
    - `:tools` - List of allowed tool names (default: `nil` for all tools)
    - `:model` - Model to use (`:sonnet`, `:opus`, `:haiku`, `:inherit`, or `nil`)

  ## Examples

      # Basic agent
      Subagent.new(
        "Code reviewer",
        "Review code for issues"
      )

      # With tool restrictions
      Subagent.new(
        "Documentation writer",
        "Write clear documentation",
        tools: ["Read"]
      )

      # With specific model
      Subagent.new(
        "Security auditor",
        "Audit code for vulnerabilities",
        tools: ["Read", "Grep"],
        model: :sonnet
      )
  """
  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(description, prompt, opts \\ []) when is_binary(description) and is_binary(prompt) do
    %__MODULE__{
      description: description,
      prompt: prompt,
      tools: Keyword.get(opts, :tools),
      model: Keyword.get(opts, :model)
    }
  end

  @doc """
  Converts a subagent struct to a map for JSON serialization.

  Filters out `nil` values to keep the JSON payload clean.

  ## Examples

      iex> agent = Subagent.new("Test", "Test prompt", model: :sonnet)
      iex> Subagent.to_map(agent)
      %{description: "Test", prompt: "Test prompt", model: :sonnet}

      iex> agent = Subagent.new("Test", "Test prompt")
      iex> Subagent.to_map(agent)
      %{description: "Test", prompt: "Test prompt"}
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = subagent) do
    subagent
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

  @doc """
  Validates a subagent configuration.

  Returns `:ok` if valid, or `{:error, reason}` if invalid.

  ## Examples

      iex> agent = Subagent.new("Test", "Test prompt")
      iex> Subagent.validate(agent)
      :ok

      iex> agent = Subagent.new("Test", "Test prompt", model: :invalid)
      iex> Subagent.validate(agent)
      {:error, "Invalid model: :invalid. Must be :sonnet, :opus, :haiku, :inherit, or nil"}
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{description: desc, prompt: prompt, tools: tools, model: model}) do
    with :ok <- validate_description(desc),
         :ok <- validate_prompt(prompt),
         :ok <- validate_tools(tools),
         :ok <- validate_model(model) do
      :ok
    end
  end

  defp validate_description(desc) when is_binary(desc) and byte_size(desc) > 0, do: :ok

  defp validate_description(_),
    do: {:error, "description must be a non-empty string"}

  defp validate_prompt(prompt) when is_binary(prompt) and byte_size(prompt) > 0, do: :ok
  defp validate_prompt(_), do: {:error, "prompt must be a non-empty string"}

  defp validate_tools(nil), do: :ok
  defp validate_tools(tools) when is_list(tools) do
    if Enum.all?(tools, &is_binary/1) do
      :ok
    else
      {:error, "tools must be a list of strings"}
    end
  end

  defp validate_tools(_), do: {:error, "tools must be a list of strings or nil"}

  defp validate_model(nil), do: :ok
  defp validate_model(model) when model in [:sonnet, :opus, :haiku, :inherit], do: :ok

  defp validate_model(model),
    do: {:error, "Invalid model: #{inspect(model)}. Must be :sonnet, :opus, :haiku, :inherit, or nil"}
end
