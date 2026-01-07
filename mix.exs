defmodule ClaudeAgentSdk.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :claude_agent_sdk,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      description: "Elixir SDK for Claude Agent",
      dialyzer: [
        plt_add_apps: [:mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ],
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.0"},

      # Dev/Test
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp docs do
    [
      main: "ClaudeAgentSdk",
      source_ref: "v#{@version}",
      extras: ["README.md"],
      groups_for_modules: [
        "Main API": [
          ClaudeAgentSdk,
          ClaudeAgentSdk.Client,
          ClaudeAgentSdk.Options
        ],
        Types: [
          ClaudeAgentSdk.Types.Messages,
          ClaudeAgentSdk.Types.ContentBlocks,
          ClaudeAgentSdk.Types.Permissions
        ],
        Transport: [
          ClaudeAgentSdk.Transport,
          ClaudeAgentSdk.Transport.SubprocessCli
        ],
        Protocol: [
          ClaudeAgentSdk.Protocol.QueryHandler,
          ClaudeAgentSdk.Protocol.MessageParser,
          ClaudeAgentSdk.Protocol.ControlProtocol
        ],
        MCP: [
          ClaudeAgentSdk.Mcp.Server,
          ClaudeAgentSdk.Mcp.Tool
        ],
        Hooks: [
          ClaudeAgentSdk.Hooks.HookMatcher,
          ClaudeAgentSdk.Hooks.HookHandler
        ],
        Errors: [
          ClaudeAgentSdk.Errors
        ]
      ]
    ]
  end

  defp package do
    [
      name: "claude_agent_sdk",
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE)
    ]
  end
end
