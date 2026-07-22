defmodule Squirrelixir.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mward-sudo/squirrelixir"

  def project do
    [
      app: :squirrelixir,
      version: @version,
      elixir: "~> 1.20",
      name: "SquirrElix",
      description:
        "Generates typed Elixir query modules from plain SQL files using Postgres inference or static metadata.",
      start_permanent: Mix.env() == :prod,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
      aliases: aliases(),
      deps: deps()
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

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.37", only: :dev, runtime: false},
      {:postgrex, "~> 0.22"}
    ]
  end

  defp package do
    [
      name: "squirrelixir",
      maintainers: ["Michael Ward"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Upstream Squirrel" => "https://github.com/giacomocavalieri/squirrel"
      },
      files: ~w(lib mix.exs README.md LICENSE NOTICE ROADMAP.md guides .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "SquirrElix",
      extras: [
        "README.md",
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
          Squirrelixir,
          Squirrelixir.CLI,
          Squirrelixir.Project
        ],
        "Query discovery": [
          Squirrelixir.Query,
          Squirrelixir.QueryDirectory,
          Squirrelixir.TypedQuery,
          Squirrelixir.TypedQueryDirectory,
          Squirrelixir.SQL
        ],
        Inference: [
          Squirrelixir.Inference,
          Squirrelixir.Postgres,
          Squirrelixir.TypeMapper,
          Squirrelixir.Metadata,
          Squirrelixir.ConnectionOptions
        ],
        Codegen: [
          Squirrelixir.Codegen,
          Squirrelixir.Output
        ],
        "Mix tasks": [
          Mix.Tasks.Squirrelixir.Gen,
          Mix.Tasks.Squirrelixir.Check
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
