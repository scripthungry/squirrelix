defmodule Mix.Tasks.Squirrelixir.Gen do
  @moduledoc """
  Generates Elixir query modules from SQL files in the current Mix project.

  SquirrElix scans `lib/`, `test/`, and `dev/` for `sql/` directories, then
  writes a sibling `sql.ex` module for each one.

  ## Usage

      mix squirrelixir.gen
      mix squirrelixir.gen --metadata config/squirrelixir.exs
      mix squirrelixir.gen --infer --database my_app_dev

  ## Options

    * `--metadata PATH` — metadata file mapping SQL files to parameter and return
      types (default: `squirrelixir.exs` in the project root)
    * `--infer` — infer types from a live Postgres database instead of a metadata file
    * `--url URL` — Postgres connection URL (also reads `PG*` environment variables)
    * `--database NAME` — database name when inferring
    * `--hostname HOST` — database host when inferring
    * `--username USER` — database user when inferring
    * `--password PASS` — database password when inferring
    * `--port PORT` — database port when inferring

  Metadata files are evaluated Elixir that must return a map. Each entry maps a
  query file path to a keyword list with `:params` and `:returns` keys.
  """

  use Mix.Task

  @shortdoc "Generates SquirrElix query modules from SQL files"

  @impl Mix.Task
  def run(args) do
    Squirrelixir.MixTask.generate(args)
  end
end
