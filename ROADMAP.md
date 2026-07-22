# Squirrelixir Roadmap

Squirrelixir reimplements [Gleam Squirrel](https://github.com/giacomocavalieri/squirrel)'s core
SQL discovery, inference, and codegen behavior with an idiomatic **Elixir-native** public API.
Upstream Squirrel remains the compatibility reference for query conventions and edge-case tests;
Elixir conventions take precedence for API shape, `@spec` output, and runtime return values.

**Elixir-native direction:** generated modules use stdlib typespecs (`String.t()`, `integer()`,
`map()` with `required/1`, `term()` for JSON, and so on). Squirrelixir does **not** generate
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
  - [x] Structured errors for syntax errors, missing tables, missing columns, invalid enums,
    and unsupported types.

- **Type mapping (Elixir-native)**
  - [x] Scalar Postgres types mapped to Elixir stdlib typespecs.
  - [x] Custom Postgres enums mapped to `String.t()` (not generated enum modules).
  - [x] Custom domains mapped to their base type.
  - [x] Recursive array support with live Postgrex tests.
  - [x] JSON/JSONB mapped to `term()` in `@spec`s; composite/point types rejected with hints.

- **Code generation**
  - [x] Per-query row `@type` definitions and `@spec`-annotated functions.
  - [x] Row queries return decoded maps; command queries return `:ok`.
  - [x] Safe overwrite and `mix squirrelixir.check` drift detection.
  - [x] Runtime decode coverage for nullable values, arrays, JSON, UUIDs, dates/times, and
    command results.

- **Mix tasks and configuration**
  - [x] Metadata-file mode (`squirrelixir.exs` or `--metadata`).
  - [x] `--infer` mode with Postgrex connection options and `PG*` environment defaults.
  - [x] `mix squirrelixir.gen` and `mix squirrelixir.check` task documentation.
  - [x] Programmatic `Squirrelixir.generate/3` and `Squirrelixir.check/3` API.

- **Package and docs**
  - [x] Hex package metadata, Apache-2.0 license, and ExDoc module grouping.
  - [x] README mirroring Gleam Squirrel structure (motivation, installation, types, FAQ).
  - [x] Guides: getting started, writing queries, types, and configuration.
  - [x] ExDoc extras and module docs linking to guides.

## Remaining

- **Parameter inference**
  - [x] Port remaining upstream cases for repeated parameter names, invalid inferred identifiers,
    keyword-like names, and ambiguous comparisons.
  - [x] Rename inferred `connection` arguments to avoid shadowing the Postgrex connection param.

- **Postgres inference**
  - [ ] Expand nullability for schema-qualified tables, subqueries in select lists, and
    expression-derived columns where practical.
  - [ ] Improve structured errors for connection failures and timeouts.

- **Type mapping**
  - [ ] Document and finalize behavior for Postgres ranges and remaining unsupported built-ins.
  - [ ] Revisit composite-type support policy (currently rejected with actionable hints).

- **Upstream fixture porting**
  - [x] Port remaining Birdie snapshots into focused ExUnit cases by behavior rather than
    copying generated Gleam APIs (join nullability, select-list aliases, multi-helper codegen,
    long enum names, enum arrays, connection shadowing).
  - [x] Document intentional Gleam-only snapshot gaps in `squirrelixir_gleam_parity_test.exs`.

- **Gleam implementation alignment**
  - [x] Sort generated query functions by source file path (matches Gleam reproducibility).
  - [x] Align validation error titles and hints with upstream Squirrel wording (duplicate
    columns, invalid file/column names, outdated/cannot-overwrite files).
  - [x] Keep intentional divergences: Elixir row maps and `@spec`s, `String.t()` enums,
    `timestamptz` mapped to `DateTime.t()`, function-name sorting only when file/name differ.

- **Release**
  - [ ] Publish `0.1.0` to Hex and enable HexDocs at <https://hexdocs.pm/squirrelixir>.

## Validation discipline

Each completed slice should run:

```sh
mix precommit
```

(`mix precommit` runs `mix format`, `mix credo.strict`, and `mix test`.)

Commit only after validation passes.
