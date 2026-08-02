# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.11] — 2026-08-02

### Changed

- Format generated modules once on the write path: `Codegen.prepare_directory/4`
  passes `format: false` to `Output.prepare_write/3` after
  `generate_module/3` has already formatted (avoids a second
  `Code.format_string!/1`) (#88).
- Memoises Postgres OID→type and column-nullability catalog lookups inside
  `Postgres.inferrer/1` for the lifetime of a generate/check pass; plan column
  sources use tuple indexing instead of `Enum.at/2` (#88).

### Docs

- Clarify independence from Gleam Squirrel (not affiliated / endorsed) (#88).
- Add `docs/PERFORMANCE.md`, `mix bench` (`bench/micro.exs`), and soft CI
  microbench reporting on the quality matrix cell (summary only; no absolute
  timing gates) (#88).
- Add `docs/README.md` clarifying `docs/` (hand-written) vs `guides/` (ExDoc
  guides) vs `doc/` (generated, gitignored); split README Guides / Project
  documentation sections (#88).

## [0.5.10] — 2026-08-02

### Changed

- Lower the Elixir requirement to `~> 1.18` (stdlib `JSON` floor). Recommend
  Elixir **1.20+** for gradual typing / compiler typechecking; generated Dialyzer
  `@spec`s remain for Dialyzer on all supported versions (#85).
- CI matrix compiles and tests on Elixir **1.18**, **1.19**, and **1.20** (every
  cell is a hard gate); Dialyzer / Reach / ExDNA / format / Credo stay on 1.20.
  Hex publish remains on Elixir 1.20 (#85).

### Fixed

- Supervise Postgrex connections in ExUnit setup so Elixir 1.18 does not fail
  `on_exit` cleanup with `GenServer.stop` `{:EXIT, :normal}` (#85).

## [0.5.9] — 2026-08-02

### Changed

- Move SQL directory discovery from `Squirrelix.CLI` into `Squirrelix.Discover`
  (connection parsing stays on `CLI`); codegen shares `TypeMapper.row_typespec/1`
  for generated row field typespecs (#52).

## [0.5.8] — 2026-08-02

### Changed

- Make `file_system` an optional dependency used only by `mix squirrelix.gen --watch`;
  missing dep raises a clear install hint (#50).

### Fixed

- Serialize async test compiles of the same generated module name to avoid flaky
  `MyApp.SQL` “currently being defined” failures under CI parallelism.

### Docs

- Document the intentional libpq-aligned `sslmode=require` → `[verify: :verify_none]`
  mapping and point adopters at `verify-ca` / `verify-full` for peer verification (#70).

## [0.5.7] — 2026-08-02

### Fixed

- Strip trailing `!` / `?` nullability override aliases from result column names
  after applying force-nullability, so guide examples generate valid Elixir map
  keys (#64).
- Fail `--infer` connect on Postgres `server_version_num < 160000` with
  structured `UnsupportedPostgresVersion` instead of silently treating unknown
  columns as nullable (#65).
- Generate nested-array encode/decode (and nested UUID list) runtime helpers by
  expanding collected list types (#67).

### Added

- Hard-reject multi-statement `.sql` files at parse and infer with
  `QueryHasMultipleStatements`; dollar-quote-aware `single_statement?/1` so
  `DO` blocks remain valid (#66).

### Docs

- Soften overstated Gleam parity claims in test moduledocs; document
  `numeric` → `Decimal.t()` in the types divergence table; remove unused
  `timestamptz` reject hint; document EXPLAIN nullability fallback (#68, #69).

## [0.5.6] — 2026-07-29

### Fixed

- Treat Reach Cross-Function Smell findings as hard failures in CI, Hex Publish,
  and `mix ci` (`--strict`), and set `smells: [strict: true]` in `.reach.exs`
  (#60).
- Clear Reach smells in `Squirrelix.Codegen.Runtime` (iolist section join;
  prepend+reverse for list encode/decode accumulators) (#60).

## [0.5.5] — 2026-07-29

### Changed

- Generate encode/decode/UUID runtime helpers from quoted AST in
  `Squirrelix.Codegen.Runtime` so helper bodies are compile-checked in the
  library while generated modules stay self-contained (no SquirrElix runtime
  dependency) (#58).
- Reject unsupported parameter types at generate time and emit a catch-all
  `encode_value/2` that raises with a clear error (#58).

### Docs

- Clarify the release-skill `gh release create` notes example as pseudocode and
  remove a machine-local path from the skill metadata (#58).

## [0.5.4] — 2026-07-28

### Docs

- Standardise on **SquirrElix** as the brand name in documentation (Hex package
  remains `squirr_elix`; Elixir modules remain `Squirrelix`) (#55).
- Expand the README with when SquirrElix may not be the right fit, alternatives,
  and using it alongside an ORM such as Ecto (#55).
- Prefer British English in documentation prose where appropriate (#55).

## [0.5.3] — 2026-07-27

### Added

- VibeKit quality stack for the package: Dialyxir, ExDNA, Reach, and ExSlop
  (Credo plugin), with a `mix ci` alias and matching gates in CI / Hex publish
  (#51).

### Changed

- Internal cleanups for Credo/ExSlop, ExDNA, Reach, and Dialyzer (shared helpers,
  narrower rescues, stricter pattern matches).

### Docs

- Document `mix ci` (full quality gate) vs `mix precommit` (fast local gate).

## [0.5.2] — 2026-07-27

### Added

- Write-pass atomicity for codegen: prepare every `sql.ex` write before committing;
  refuse all writes when any prepare fails; commit via temp + rename with rollback
  if a later rename fails (#49).

### Changed

- Directory discovery returns structured `CannotReadFile` instead of raising on
  unreadable paths.
- Removed unused internal `Codegen.write_directories` / `check_directories` helpers
  (partial progress on #52).

### Docs

- Clarify query-error vs write-pass atomicity in README, Configuration, Phoenix
  guide, and Mix task docs. ROADMAP points at Post-0.5 backlog and 1.0 issues.

## [0.5.1] — 2026-07-27

### Fixed

- Phoenix-style `lib/my_app/.../sql` paths generate `MyApp....SQL` (no duplicated
  app segment).
- Bang/`?` query names sanitize `@type`/`@spec` row identifiers; soft companions
  deconflict against query names and other soft companions with a warning.
- Connection URLs percent-decode userinfo, reject schemeless input, and no longer
  let URL defaults clobber present `PG*` values for omitted fields.
- `mix precommit` compiles with `--warnings-as-errors`; Hex publish runs credo +
  tests before publishing.
- EXPLAIN DO-block warning is captured in tests; inference errors with `code: nil`
  no longer format as `[NIL]`.

## [0.5.0] — 2026-07-27

### Added

- Multi-schema / `search_path` inference docs (Configuration + Writing Queries) and
  ExUnit coverage for unqualified tables resolved via session `search_path` and
  schema-qualified tables outside `search_path`.
- CI test coverage via ExCoveralls: HTML artifact + GitHub Actions job summary,
  soft floor warning (not a hard fail). Local `mix test` / `mix precommit`
  unchanged; opt in with `mix cover` / `mix coveralls.html`.
- Adopter CI workflow examples under `examples/github-actions/` for live
  `mix squirrelix.check --infer` and offline metadata check.

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
- `--infer` honours `DATABASE_URL` with documented precedence: flags → `--url` →
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

- First public release of SquirrElix (Hex package `squirr_elix`): typed Elixir query
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
