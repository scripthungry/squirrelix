defmodule Squirrelixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :squirrelixir,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      "credo.strict": "credo --strict --all"
    ]
  end
end
