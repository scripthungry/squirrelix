defmodule Mix.Tasks.Squirrelix.Gen do
  @moduledoc """
  Generates Elixir query modules from SQL files in the current Mix project.

  Squirrelix scans `lib/`, `test/`, and `dev/` for `sql/` directories, then
  writes a sibling `sql.ex` module for each one.

  ## Usage

      mix squirrelix.gen
      mix squirrelix.gen --metadata config/squirr_elix.exs
      mix squirrelix.gen --infer --database my_app_dev

  ## Options

    * `--metadata PATH` — metadata file mapping SQL files to parameter and return
      types (default: `squirr_elix.exs` in the project root). The file is evaluated
      as Elixir — treat it like `mix.exs` and never load untrusted paths.
    * `--infer` — infer types from a live Postgres database instead of a metadata file
    * `--url URL` — Postgres connection URL (also reads `PG*` environment variables)
    * `--database NAME` — database name when inferring
    * `--hostname HOST` — database host when inferring
    * `--username USER` — database user when inferring
    * `--password PASS` — database password when inferring (prefer `PGPASSWORD`;
      values on the command line appear in process listings and shell history)
    * `--port PORT` — database port when inferring

  Connection precedence (highest first): CLI flags → `--url` → `PG*` environment
  variables → defaults.

  Generated query functions call `Postgrex.query!/3` and raise on database errors.

  Metadata files are evaluated Elixir that must return a map. Each entry maps a
  query file path to a keyword list with `:params` and `:returns` keys.
  """

  use Mix.Task

  @shortdoc "Generates Squirrelix query modules from SQL files"

  @impl Mix.Task
  def run(args) do
    Squirrelix.MixTask.generate(args)
  end
end
