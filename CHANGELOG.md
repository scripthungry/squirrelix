# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Multi-schema / `search_path` inference docs (Configuration + Writing Queries) and
  ExUnit coverage for unqualified tables resolved via session `search_path` and
  schema-qualified tables outside `search_path`.
- CI test coverage via ExCoveralls: HTML artifact + GitHub Actions job summary,
  soft floor warning (not a hard fail). Local `mix test` / `mix precommit`
  unchanged; opt in with `mix cover` / `mix coveralls.html`.

### Changed

- Generated query modules are Dialyzer-friendlier under typical adopter flags:
  encode helpers gain matching `@spec`s and guards, command `num_rows` helpers
  document `non_neg_integer()`, UUID helpers use precise binary specs, and
  underspec'd private `decode_rows`/`decode_row` contracts are omitted. Types and
  Phoenix guides document Dialyzer expectations and known `:overspecs`
  limitations (no Dialyxir dependency).
- User-facing errors for file I/O, missing/incomplete/invalid metadata, invalid
  connection URLs, and invalid CLI options use the same structured titles/hints as
  connection and query diagnostics (no raw `inspect/1` primary messages). Existing
  structured connection error types from 0.2/0.3 are unchanged.
- Documented and narrowed the supported pre-1.0 public API: `Squirrelix.generate/3` /
  `check/3`, Mix tasks, codegen summaries, documented `Squirrelix.Error.*` structs /
  `Error.format`, `Postgres.inferrer/1`, `Inference.Inferrer`, and `Query` (Inferrer
  argument). Other library modules are marked `@moduledoc false` / internal.

## [0.4.0] — 2026-07-27

### Added

- `mix squirrelix.gen --watch` watches `{lib,test,dev}/**/sql/*.sql` and regenerates
  on change (same query source / connection options as a one-shot gen; Ctrl-C to stop).
  Linux needs `inotify-tools`.
- `--write-metadata PATH` on `mix squirrelix.gen` / `mix squirrelix.check` (requires
  `--infer`) exports a reloadable metadata file for offline check/codegen without
  Postgres.
- Broader structural parameter naming beyond `INSERT`: comparison operators
  (`<>`, `!=`, `<`, `>`, `<=`, `>=`), `LIKE`/`ILIKE` (including `NOT`), and
  `SET (columns) = (...)` / `ROW(...)` lists (including `ON CONFLICT ... DO UPDATE SET`).
  Comparison/equality names still win over column-list inference; existing
  `UPDATE ... SET col = $n` and `INSERT (cols) VALUES` naming are unchanged.
- Phoenix + CI cookbook guide (`guides/phoenix.md`) for Mix adoption: migrate-then-gen/check,
  `DATABASE_URL`, Mix aliases, CI check jobs, and intentional Ecto coexistence.

## [0.3.0] — 2026-07-27

### Added

- Generated soft companions (`<name>_ok/arity`) via `Postgrex.query/3` that return
  `{:ok, result} | {:error, Exception.t()}` without raising. Soft command companions
  return `{:ok, num_rows}` (affected-row count). The raising `query!` API is unchanged
  (**additive**, not breaking). See Writing Queries and Getting Started guides.
- Parameter name inference from `INSERT ... (columns) VALUES (...)` placeholders
  (equality / `UPDATE ... SET` naming unchanged; equality wins on conflicts).
- `--infer` honors `DATABASE_URL` with documented precedence: flags → `--url` →
  `DATABASE_URL` → `PG*` → defaults. URL/`PGSSLMODE` `sslmode` (and `ssl=true` /
  `ssl=false`) map into Postgrex `:ssl` options.

### Changed

- Project-wide atomic codegen (Gleam squirrel 4.5+ parity): if any `sql/` directory
  has query errors, `mix squirrelix.gen` / `Squirrelix.generate/3` write nothing.
  `mix squirrelix.check` fails globally when any directory has errors or drift.

## [0.2.0] — 2026-07-27

### Added

- Nullability inference for schema-qualified tables, scalar subqueries in select
  lists, and expression-derived columns (see Writing Queries guide).
- Structured errors for `--infer` connection failures and timeouts
  (`CannotConnectToPostgres`, `PostgresConnectionTimeout`) with actionable hints
  for `PG*` env vars, CLI flags, and metadata-file fallback.

### Changed

- Documented composite-type policy as **reject-with-hints** (aligned with Gleam
  Squirrel and flat Elixir row maps). Inference now attaches actionable hints for
  composites (`kind: "c"`) and geometric `point` values.
- Finalized unsupported-type policy for Postgres ranges/multiranges and remaining
  built-ins (`interval`, geometric, network, `money`, and related types): inference
  rejects them with actionable hints, and the Types guide documents workarounds.

## [0.1.0] — 2026-07-24

### Added

- First public release of Squirrelix (Hex package `squirr_elix`): typed Elixir query
  modules from plain `.sql` files via Postgres inference or metadata.
- Mix tasks `mix squirrelix.gen` and `mix squirrelix.check`.
- Guides for getting started, writing queries, types, and configuration.
- GitHub Actions CI (format, compile, Credo, tests with Postgres 16) and Hex publish
  on `v*` tags.

### Changed

- Public Elixir modules and Mix tasks use the **Squirrelix** name (package/app remain
  `squirr_elix`). Repository: `scripthungry/squirrelix`.

### Security

- Generated SQL and `@doc` strings are embedded with `inspect/2` so `#{}` in `.sql`
  files cannot become Elixir interpolation in generated modules.
