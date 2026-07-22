defmodule Mix.Tasks.Squirrelixir.Check do
  @moduledoc """
  Verifies generated query modules are up to date without writing files.

  Uses the same discovery rules and options as `mix squirrelixir.gen`. Exits
  with a non-zero status when generated output would change or when metadata,
  inference, or SQL parsing fails.

  ## Usage

      mix squirrelixir.check
      mix squirrelixir.check --metadata config/squirrelixir.exs
      mix squirrelixir.check --infer --database my_app_dev

  ## Options

    * `--metadata PATH` — metadata file (default: `squirrelixir.exs`)
    * `--infer` — infer types from Postgres instead of reading a metadata file
    * `--url URL` — Postgres connection URL
    * `--database NAME` — database name when inferring
    * `--hostname HOST` — database host when inferring
    * `--username USER` — database user when inferring
    * `--password PASS` — database password when inferring
    * `--port PORT` — database port when inferring
  """

  use Mix.Task

  @shortdoc "Checks Squirrelixir query modules are current"

  @impl Mix.Task
  def run(args) do
    Squirrelixir.MixTask.check(args)
  end
end
