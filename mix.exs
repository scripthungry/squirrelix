defmodule Squirrelix.MixProject do
  use Mix.Project

  @version "0.5.10"
  @source_url "https://github.com/scripthungry/squirrelix"

  def project do
    [
      app: :squirr_elix,
      version: @version,
      elixir: "~> 1.18",
      name: "SquirrElix",
      description:
        "Generates typed Elixir query modules from plain SQL files using Postgres inference or static metadata.",
      start_permanent: Mix.env() == :prod,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
      aliases: aliases(),
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [plt_add_apps: [:ex_unit, :mix]]
    ]
  end

  def cli do
    [
      preferred_envs: [
        precommit: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        ci: :test
      ]
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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.37", only: :dev, runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:file_system, "~> 1.0", optional: true},
      {:postgrex, "~> 0.22"},
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      name: "squirr_elix",
      maintainers: ["Michael Ward"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Upstream Squirrel" => "https://github.com/giacomocavalieri/squirrel"
      },
      files:
        ~w(lib mix.exs README.md LICENSE NOTICE ROADMAP.md CHANGELOG.md guides examples .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "Squirrelix",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "ROADMAP.md",
        "guides/getting_started.md",
        "guides/writing_queries.md",
        "guides/types.md",
        "guides/configuration.md",
        "guides/phoenix.md"
      ],
      groups_for_extras: [
        Guides: Path.wildcard("guides/*.md")
      ],
      source_url: @source_url,
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [Squirrelix.Error],
      groups_for_modules: [
        "Core API": [
          Squirrelix,
          Squirrelix.CodegenSummary,
          Squirrelix.CodegenCheckSummary
        ],
        Inference: [
          Squirrelix.Inference.Inferrer,
          Squirrelix.Postgres,
          Squirrelix.Query
        ],
        Errors: [
          Squirrelix.Error
        ],
        "Mix tasks": [
          Mix.Tasks.Squirrelix.Gen,
          Mix.Tasks.Squirrelix.Check
        ]
      ]
    ]
  end

  defp aliases do
    [
      # Fast local gate before committing.
      precommit: ["compile --warnings-as-errors", "format", "credo.strict", "test"],
      "credo.strict": "credo --strict --all",
      # Opt-in coverage; plain `mix test` / `mix precommit` stay fast locally.
      cover: ["coveralls.html"],
      # Full quality gate (VibeKit): Dialyzer, ExDNA, Reach, plus compile/format/credo/test.
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "test",
        "credo.strict",
        "dialyzer",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells --strict"
      ]
    ]
  end
end
