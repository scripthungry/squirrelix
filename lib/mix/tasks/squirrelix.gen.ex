defmodule Mix.Tasks.Squirrelix.Gen do
  @moduledoc """
  Generates Elixir query modules from SQL files in the current Mix project.

  SquirrElix scans `lib/`, `test/`, and `dev/` for `sql/` directories, then
  writes a sibling `sql.ex` module for each one.

  Generation is project-wide atomic: query errors refuse all writes; the write
  pass prepares every `sql.ex` before committing (temp + rename with rollback).

  ## Usage

      mix squirrelix.gen
      mix squirrelix.gen --metadata config/squirr_elix.exs
      mix squirrelix.gen --infer --database my_app_dev
      mix squirrelix.gen --infer --write-metadata squirr_elix.exs
      mix squirrelix.gen --watch
      mix squirrelix.gen --infer --watch

  ## Options

    * `--metadata PATH` — metadata file mapping SQL files to parameter and return
      types (default: `squirr_elix.exs` in the project root). The file is evaluated
      as Elixir — treat it like `mix.exs` and never load untrusted paths.
    * `--infer` — infer types from a live Postgres database instead of a metadata file
    * `--write-metadata PATH` — after a successful `--infer` pass, write inferred
      types to a metadata file for offline `gen` / `check` (requires `--infer`)
    * `--watch` — after the initial generate, watch `{lib,test,dev}/**/sql/*.sql` and
      regenerate when those files change. Press Ctrl-C to stop. Requires the optional
      `:file_system` dependency. Uses the same query source / connection options as a
      one-shot generate; regenerate failures are logged and watching continues.
    * `--url URL` — Postgres connection URL (also reads `DATABASE_URL` and `PG*`
      environment variables)
    * `--database NAME` — database name when inferring
    * `--hostname HOST` — database host when inferring
    * `--username USER` — database user when inferring
    * `--password PASS` — database password when inferring (prefer `PGPASSWORD`;
      values on the command line appear in process listings and shell history)
    * `--port PORT` — database port when inferring

  Connection precedence (highest first): flags → `--url` → `DATABASE_URL` → `PG*` → defaults.

  URLs may include `sslmode` (`disable`, `allow`, `prefer`, `require`, `verify-ca`,
  `verify-full`) or `ssl=true`/`ssl=false`. See the Configuration guide for how those
  map to Postgrex `:ssl` options. Unix sockets are not supported.

  Generated query functions call `Postgrex.query!/3` and raise on database errors.
  Soft companions named `<name>_ok/arity` call `Postgrex.query/3` and return
  `{:ok, result} | {:error, Exception.t()}` (commands: `{:ok, num_rows}`). This soft
  API is additive — the raising functions are unchanged.

  Metadata files are evaluated Elixir that must return a map. Each entry maps a
  query file path to a keyword list with `:params` and `:returns` keys.
  """

  use Mix.Task

  @shortdoc "Generates SquirrElix query modules from SQL files"

  @impl Mix.Task
  def run(args), do: Squirrelix.MixTask.generate(args)
end
