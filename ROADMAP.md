# SquirrElix Roadmap

SquirrElix reimplements [Gleam Squirrel](https://github.com/giacomocavalieri/squirrel)'s core
SQL discovery, inference, and codegen behaviour with an idiomatic **Elixir-native** public API.
Upstream Squirrel remains the compatibility reference for query conventions and edge-case tests;
Elixir conventions take precedence for API shape, `@spec` output, and runtime return values.

**Elixir-native direction:** generated modules use stdlib typespecs (`String.t()`, `integer()`,
`map()` with `required/1`, `term()` for JSON, and so on). SquirrElix does **not** generate
Gleam records, custom enum ADTs, or opaque tagged error values.

## Completed

- **Query discovery and parsing**
  - [x] One-query-per-file discovery under `lib/`, `test/`, and `dev/`.
  - [x] Leading SQL comments become generated function `@doc` strings.
  - [x] Invalid filename handling with suggested renames where possible.

- **Parameter inference**
  - [x] Equality comparisons, line and block comments, string literals, quoted identifiers,
    and table-qualified identifiers.
  - [x] Generated Elixir argument names deconflicted against `connection` and reserved names.

- **Postgres inference**
  - [x] Postgrex prepare metadata for parameters and result types.
  - [x] Nullability for table columns, outer joins, `using(...)`, CTEs, and foreign-key-derived
    cases.
  - [x] Multi-schema / `search_path` inference docs and focused tests.
  - [x] Structured errors for syntax errors, missing tables, missing columns, invalid enums,
    and unsupported types.
  - [x] Consistent structured formatting for user-facing codegen/check/metadata/connection
    errors.

- **Type mapping (Elixir-native)**
  - [x] Scalar Postgres types mapped to Elixir stdlib typespecs.
  - [x] Custom Postgres enums mapped to `String.t()` (not generated enum modules).
  - [x] Custom domains mapped to their base type.
  - [x] Recursive array support with live Postgrex tests.
  - [x] JSON/JSONB mapped to `term()` in `@spec`s; composite/point types rejected with hints.
  - [x] Composite-type policy: **reject-with-hints** (no nested row modules / opaque
    encodings); geometric `point` also rejected with workarounds. Documented in
    `guides/types.md` and the README FAQ.
  - [x] Ranges/multiranges and remaining unsupported built-ins rejected with actionable
    hints; inventory documented in `guides/types.md`.

- **Code generation**
  - [x] Per-query row `@type` definitions and `@spec`-annotated functions.
  - [x] Row queries return decoded maps; command queries return `:ok`.
  - [x] Soft companions (`<name>_ok`) via `Postgrex.query/3`; soft commands return
    `{:ok, num_rows}` (additive; raising API unchanged).
  - [x] Dialyzer-oriented public `@spec`s / helpers for generated modules (documented
    expectations and known `:overspecs` limits).
  - [x] Safe overwrite and `mix squirrelix.check` drift detection.
  - [x] Runtime decode coverage for nullable values, arrays, JSON, UUIDs, dates/times, and
    command results.

- **Mix tasks and configuration**
  - [x] Metadata-file mode (`squirr_elix.exs` or `--metadata`).
  - [x] `--infer` mode with Postgrex connection options and `PG*` environment defaults.
  - [x] `--infer` honours `DATABASE_URL` / SSL (`sslmode`) with documented precedence.
  - [x] Project-wide atomic generate/check (query-error refuse-all + write-pass
    temp/rename with rollback).
  - [x] INSERT/VALUES structural parameter naming.
  - [x] Broader structural parameter naming (comparisons, LIKE/ILIKE, SET/ROW lists).
  - [x] `--write-metadata` export for offline check/codegen.
  - [x] `mix squirrelix.gen --watch` for SQL file watching / regenerate.
  - [x] `mix squirrelix.gen` and `mix squirrelix.check` task documentation.
  - [x] Programmatic `Squirrelix.generate/3` and `Squirrelix.check/3` API.

- **Package and docs**
  - [x] Hex package metadata, Apache-2.0 licence, and ExDoc module grouping.
  - [x] README mirroring Gleam Squirrel structure (motivation, installation, types, FAQ).
  - [x] Guides: getting started, writing queries, types, configuration, and Phoenix + CI.
  - [x] Supported pre-1.0 public API inventory; internals `@moduledoc false`.
  - [x] Adopter CI workflow examples (`examples/github-actions/`).
  - [x] CI test coverage metrics (ExCoveralls; soft floor).
  - [x] ExDoc extras and module docs linking to guides.

## Remaining (path to 1.0)

GitHub is the source of truth for open work: [project board](https://github.com/orgs/scripthungry/projects/1)
and milestones below. **1.0** means production-ready typed SQL codegen for Elixir/Phoenix,
Gleam-aligned where intentional, with a SemVer stability promise — not infinite feature creep.

### Shipped slices (folded into Completed above)

Post-0.1 roadmap items through **v0.5.1** are done: nullability expansion, structured
connection/timeout errors, ranges/unsupported built-ins, composite reject-with-hints,
parameter-name/Gleam parity ports, Phoenix-ready `DATABASE_URL`/SSL `--infer`, atomic
codegen (query-error refuse-all; write-pass temp/rename in **0.5.2**), INSERT/VALUES and
broader structural parameter naming, additive soft query companions with command row
counts, watch mode, `--write-metadata`, Phoenix + CI cookbook, production hardening
(multi-schema docs/tests, Dialyzer-friendly codegen, public API audit, adopter CI
examples, error-message consistency, CI coverage), and Hex `0.1.0`–`0.5.2` releases
(**0.5.3** adds Dialyzer/ExDNA/Reach/ExSlop CI gates).

### [Post-0.5 backlog](https://github.com/scripthungry/squirrelix/milestone/6)

Point-release follow-ups from the multi-model review (not the 1.0 SemVer cut):

- Optional `file_system` (watch-only) (#50) — **0.5.8**
- Document intentional `sslmode=require` → `verify_none` (libpq-aligned; no silent
  hardening) (#70) — **0.5.8**
- Strip bang/`?` nullability overrides (#64) — **0.5.7**
- Postgres ≥ 16 version guard on `--infer` connect (#65) — **0.5.7**
- Hard-reject multi-statement `.sql` files (#66) — **0.5.7**
- Nested array runtime helper recursion (#67) — **0.5.7**
- Docs hygiene: soften parity claims, `numeric` divergence, dead `timestamptz` hint (#68) — **0.5.7**
- Document EXPLAIN nullability fallback (#69) — **0.5.7**
- Library Dialyzer CI job for the package itself (#51) — **0.5.3**
- Write-pass atomicity (#49) — **0.5.2**

### [v1.0.0](https://github.com/scripthungry/squirrelix/milestone/5) — Stability promise

1.0 is a **stability / SemVer promise**. Prep work below can finish on schedule;
**shipping is blocked on adoption** — do not tag until meaningful real-world usage /
feedback validates the API (maintainer judgement). Completing #23–#26 is necessary but
**not sufficient** without that gate (#28).

- [ ] SemVer / stability / deprecation policy (#23) — includes formal deprecation mechanism
- [ ] Documented non-goals freeze (#24)
- [ ] Docs freeze and HexDocs polish (#25)
- [x] Prune internal APIs before 1.0 (#52)
- [ ] Adoption / feedback gate: sufficient real-world users (#28)
- [ ] Ship via `docs/RELEASE.md` (#26) — after maintainer confirms #28

### Explicit non-goals (not on the 1.0 path)

Composites as nested modules, first-class ranges/geometric/network/`interval`, Gleam-style
enum ADTs, catalog-inferred nullable parameters, Unix sockets, PostGIS, ULID, first-class
Ecto `Repo` integration, and a built-in SQL formatter. See FAQ / Types guide; freeze tracked
in #24.

## Validation discipline

Each completed slice should run:

```sh
mix precommit
```

(`mix precommit` runs `mix format`, `mix credo.strict`, and `mix test`.)

For the full CI quality gate (Dialyzer, ExDNA, Reach, ExSlop):

```sh
mix ci
```

Commit only after validation passes.
