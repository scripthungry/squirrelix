defmodule Mix.Tasks.Squirrelix.Check do
  @moduledoc """
  Verifies generated query modules are up to date without writing files.

  Uses the same discovery rules and options as `mix squirrelix.gen`. Exits
  with a non-zero status when generated output would change or when metadata,
  inference, or SQL parsing fails. Failure is project-wide: errors from every
  directory are collected, and a single failing directory fails the whole check.

  ## Usage

      mix squirrelix.check
      mix squirrelix.check --metadata config/squirr_elix.exs
      mix squirrelix.check --infer --database my_app_dev

  ## Options

    * `--metadata PATH` — metadata file (default: `squirr_elix.exs`). Evaluated as
      Elixir — only load trusted files.
    * `--infer` — infer types from Postgres instead of reading a metadata file
    * `--url URL` — Postgres connection URL (also reads `DATABASE_URL` and `PG*`)
    * `--database NAME` — database name when inferring
    * `--hostname HOST` — database host when inferring
    * `--username USER` — database user when inferring
    * `--password PASS` — database password when inferring (prefer `PGPASSWORD`)
    * `--port PORT` — database port when inferring

  Connection precedence (highest first): flags → `--url` → `DATABASE_URL` → `PG*` → defaults.

  URLs may include `sslmode` / `ssl` query parameters. See the Configuration guide.
  """

  use Mix.Task

  @shortdoc "Checks Squirrelix query modules are current"

  @impl Mix.Task
  def run(args) do
    Squirrelix.MixTask.check(args)
  end
end
