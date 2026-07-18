# Squirrelixir Roadmap

Squirrelixir aims to reimplement Gleam Squirrel's core behavior with an idiomatic Elixir API. Upstream Squirrel remains the compatibility reference for SQL discovery, inference behavior, generated-query ergonomics, and edge-case tests; Elixir conventions take precedence for public API shape and runtime return values.

## Compatibility Work

- Query discovery and parsing
  - Keep one-query-per-file behavior compatible with upstream.
  - Preserve leading SQL comments as generated function docs.
  - Continue porting invalid filename and suggested-name cases from upstream.

- Parameter inference
  - Match upstream inference around equality comparisons, comments, strings, nested block comments, quoted identifiers, and table-qualified identifiers.
  - Port remaining upstream cases for repeated names, invalid inferred identifiers, keyword-like names, and ambiguous comparisons.
  - Keep generated Elixir arguments valid and deconflicted against `connection` and other arguments.

- Postgres inference
  - Use Postgrex prepare metadata for parameters and result types.
  - Expand nullability inference beyond simple table columns and outer joins to cover `using(...)`, CTEs, aliases, schemas, subqueries, expressions, and foreign-key-derived cases where practical.
  - Improve structured errors for syntax errors, missing tables, missing columns, unsupported types, and connection failures.

- Type mapping
  - Maintain Elixir-native types for scalar Postgres types.
  - Add enum support with idiomatic Elixir representations.
  - Decide and document behavior for domains, ranges, composite types, and unsupported built-ins.
  - Keep arrays recursive and covered through live Postgrex tests.

- Code generation
  - Generate small modules that return decoded maps for row queries and `:ok` for command queries.
  - Preserve safe overwrite/check behavior.
  - Expand generated runtime coverage for multiple rows, no rows, nullable values, arrays, JSON, UUIDs, dates/times, and command results.

- Mix tasks and configuration
  - Keep metadata-file mode as a deterministic escape hatch.
  - Continue improving `--infer` connection configuration around Postgrex environment defaults.
  - Add task-level documentation once the DB inference surface settles.

- Upstream fixture porting
  - Port Birdie snapshots into focused ExUnit cases by behavior rather than copying generated Gleam APIs.
  - Prioritize cases that expose semantic compatibility gaps: joins, nullability, parameter names, unsupported types, duplicate columns, invalid names, and generation safety.

## Validation Discipline

Each completed slice should run:

```sh
mix format
mix test
mix credo.strict
```

Commit only after validation passes.
