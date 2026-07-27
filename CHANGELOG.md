# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Documented composite-type policy as **reject-with-hints** (aligned with Gleam
  Squirrel and flat Elixir row maps). Inference now attaches actionable hints for
  composites (`kind: "c"`) and geometric `point` values.

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
- EXPLAIN nullability rejects multi-statement SQL before using the simple query
  protocol (required for `$n` + `generic_plan`).
- Plan JSON decoding uses stdlib `JSON` (no undeclared Jason dependency).
- Overwrite protection trusts the generation marker only in the file header.
