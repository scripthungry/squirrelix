defmodule Mix.Tasks.SquirrElix.Check do
  @moduledoc """
  Verifies generated query modules are up to date without writing files.

  Uses the same discovery rules and options as `mix squirr_elix.gen`. Exits
  with a non-zero status when generated output would change or when metadata,
  inference, or SQL parsing fails.

  ## Usage

      mix squirr_elix.check
      mix squirr_elix.check --metadata config/squirr_elix.exs
      mix squirr_elix.check --infer --database my_app_dev

  ## Options

    * `--metadata PATH` — metadata file (default: `squirr_elix.exs`)
    * `--infer` — infer types from Postgres instead of reading a metadata file
    * `--url URL` — Postgres connection URL
    * `--database NAME` — database name when inferring
    * `--hostname HOST` — database host when inferring
    * `--username USER` — database user when inferring
    * `--password PASS` — database password when inferring
    * `--port PORT` — database port when inferring
  """

  use Mix.Task

  @shortdoc "Checks SquirrElix query modules are current"

  @impl Mix.Task
  def run(args) do
    SquirrElix.MixTask.check(args)
  end
end
