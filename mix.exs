defmodule Squirrelix.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/scripthungry/squirrelix"

  def project do
    [
      app: :squirr_elix,
      version: @version,
      elixir: "~> 1.20",
      name: "Squirrelix",
      description:
        "Generates typed Elixir query modules from plain SQL files using Postgres inference or static metadata.",
      start_permanent: Mix.env() == :prod,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
      aliases: aliases(),
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def cli do
    [
      preferred_envs: [
        precommit: :test
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
      {:ex_doc, "~> 0.37", only: :dev, runtime: false},
      {:postgrex, "~> 0.22"}
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
        ~w(lib mix.exs README.md LICENSE NOTICE ROADMAP.md CHANGELOG.md guides .formatter.exs)
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
        "guides/configuration.md"
      ],
      groups_for_extras: [
        Guides: Path.wildcard("guides/*.md")
      ],
      source_url: @source_url,
      source_ref: "v#{@version}",
      groups_for_modules: [
        "Core API": [
          Squirrelix,
          Squirrelix.CLI,
          Squirrelix.Project
        ],
        "Query discovery": [
          Squirrelix.Query,
          Squirrelix.QueryDirectory,
          Squirrelix.TypedQuery,
          Squirrelix.TypedQueryDirectory,
          Squirrelix.SQL
        ],
        Inference: [
          Squirrelix.Inference,
          Squirrelix.Postgres,
          Squirrelix.TypeMapper,
          Squirrelix.Metadata,
          Squirrelix.ConnectionOptions
        ],
        Codegen: [
          Squirrelix.Codegen,
          Squirrelix.Output
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
      precommit: ["format", "credo.strict", "test"],
      "credo.strict": "credo --strict --all"
    ]
  end
end
