# 🐿️ SquirrElix — type-safe SQL in Elixir

> SquirrElix (package `squirr_elix`)

[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/squirr_elix/)

SquirrElix is a simple database interface that aims to reduce cognitive load when working
with SQL through Postgres and Postgrex.

You stay close to the database by writing plain `.sql` files, which are converted into typed
Elixir modules. You write one query per file; the generator discovers those files, resolves
parameter and return types, and writes a sibling `sql.ex` module with `@spec`-annotated
functions that run the queries through Postgrex.

For many applications that is enough: generated convenience functions and typing, full control
over your SQL, no extra abstraction to learn, and easier visibility when you need to optimise
queries.

SquirrElix requires **Elixir ~> 1.18** (stdlib `JSON`). **Elixir 1.20+** is recommended for
the compiler’s gradual typing and typechecking. Generated Dialyzer `@spec`s remain part of
the codegen story on all supported versions.

SquirrElix is an independent Elixir library inspired by
[Gleam Squirrel](https://github.com/giacomocavalieri/squirrel). It reimplements similar
SQL-file discovery, inference, and codegen ideas in native Elixir with Elixir-native typing
and idioms. It is not affiliated with, endorsed by, or maintained by the Gleam Squirrel
project.

## What's SquirrElix?

Database access in Elixir is often handled using an ORM such as Ecto, or by writing something
like this:

```elixir
def find_user(conn, id) do
  Postgrex.query!(
    conn,
    "select name, age from users where id = $1",
    [id]
  )
  |> Map.fetch!(:rows)
  |> Enum.map(fn [name, age] -> %{name: name, age: age} end)
end
```

That works for a few queries, but it grows painful: SQL is a plain string (no editor SQL
niceties), you cannot easily run the query with external tools, and row decoding drifts out
of sync with the select list.

SquirrElix takes a different approach: instead of hiding SQL, it *embraces it*. Write queries
in plain `*.sql` files; SquirrElix generates the corresponding typed functions.

```sql
-- lib/my_app/accounts/sql/find_user.sql
-- Find a user and their age given their id.
select
  name,
  age
from
  users
where
  id = $1
```

```sh
mix squirrelix.gen --infer
```

```elixir
alias MyApp.Accounts.SQL

rows = SQL.find_user(conn, 42)
# => [%{name: "Ada", age: 36}]
```

You keep plain SQL files (editor support, `explain`, external tools) while SquirrElix keeps
encoders, decoders, and `@spec`s in sync.

## When SquirrElix may not be the right fit

SquirrElix is opinionated: Postgres only, one query per file, convention over configuration,
and generated modules that talk to Postgrex — not to an Ecto `Repo`.

**Consider something else when:**

* You need a database other than Postgres.
* Most of your data access is CRUD through schemas, changesets, and associations (prefer Ecto).
* You need dynamic query construction at runtime (prefer `Ecto.Query`).
* You want first-class `Repo.transaction/2` / Multi integration without wrapping Postgrex.
* Your team wants the data layer to hide SQL — SquirrElix keeps SQL front and centre.
* You only have a handful of queries and are happy with small `Postgrex.query/3` helpers.

**Alternatives:** [Ecto](https://hexdocs.pm/ecto) / `Ecto.Query`, direct
[Postgrex](https://hexdocs.pm/postgrex), or [Gleam Squirrel](https://github.com/giacomocavalieri/squirrel)
on Gleam. Using SquirrElix *alongside* Ecto (migrations/schemas via Ecto; typed `.sql` via
SquirrElix + Postgrex) is a common Phoenix setup — see the
[Phoenix + CI Cookbook](guides/phoenix.md).

## Requirements

* Elixir ~> 1.18 (recommend **1.20+** for gradual typing / compiler typechecking)
* Postgrex ~> 0.22 (generated query modules and optional `--infer`)
* PostgreSQL >= 16 (when using `--infer`)

## Installation

Add SquirrElix as a **dev/test** dependency and keep Postgrex as a **runtime** dependency:

```elixir
def deps do
  [
    {:squirr_elix, "~> 0.5.0", only: [:dev, :test], runtime: false},
    {:postgrex, "~> 0.22"},
    # Optional — only for `mix squirrelix.gen --watch`
    {:file_system, "~> 1.0", only: [:dev, :test], runtime: false}
  ]
end
```

Then `mix deps.get`. Full docs: <https://hexdocs.pm/squirr_elix> (or `mix docs` locally).

## Quick start

Put one SQL query per file under a `sql/` directory:

```txt
lib/my_app/accounts/sql/find_user.sql   →  MyApp.Accounts.SQL.find_user/2
lib/my_app/accounts/sql.ex              # generated
```

```sh
mix squirrelix.gen --infer --database my_app_dev
mix squirrelix.check --infer --database my_app_dev   # CI drift check
```

Copy-pasteable GitHub Actions workflows live in
[`examples/github-actions/`](https://github.com/scripthungry/squirrelix/tree/main/examples/github-actions).
Walkthrough: [Getting Started](guides/getting_started.md).

## Mix tasks

* `mix squirrelix.gen` — generate typed `sql.ex` modules (`--watch` optional; needs `file_system`)
* `mix squirrelix.check` — fail CI when generated code is stale

Both accept the same query-source / connection options (`--infer`, `--metadata`,
`DATABASE_URL`, `PG*`, …). Details: [Configuration](guides/configuration.md).

## Guides

| Guide | Topics |
| --- | --- |
| [Getting Started](guides/getting_started.md) | Install, layout, first generate, soft companions |
| [Writing Queries](guides/writing_queries.md) | Naming, comments, nullability, commands |
| [Types](guides/types.md) | Postgres → Elixir mapping, unsupported types |
| [Configuration](guides/configuration.md) | Infer vs metadata, SSL, watch, public API, CI |
| [Phoenix + CI Cookbook](guides/phoenix.md) | Migrate-then-gen, Mix aliases, Ecto coexistence |
| [Adopter CI workflows](https://github.com/scripthungry/squirrelix/tree/main/examples/github-actions) | Copy-pasteable GitHub Actions |

## FAQ

### What flavour of SQL does SquirrElix support?

Postgres only, versions `>= 16` (for `--infer`).

### Why isn't SquirrElix highly configurable?

Convention over configuration: the same `sql/` layout and `sql.ex` modules everywhere, less
bike-shedding about where queries live.

### Can SquirrElix read my `.env` file?

No. Use your shell, [`direnv`](https://direnv.net), or similar so the environment owns env
vars — not the application.

### How do I deal with nullable query parameters?

Postgres does not expose parameter nullability. See
[Writing Queries](guides/writing_queries.md#nullable-query-parameters) for workarounds.

### Why aren't Postgres composite types supported?

Intentional reject-with-hints policy (flat `required/1` row maps). Select fields or cast in
SQL — see [Types](guides/types.md#composite-types-policy).

### Does SquirrElix integrate with Ecto `Repo`?

No — intentional. Use it *alongside* Ecto; see the
[Phoenix + CI Cookbook](guides/phoenix.md#coexistence-with-ecto-intentional).

## Errors and troubleshooting

| Error | Typical cause | What to do |
| --- | --- | --- |
| `OutdatedFile` | SQL changed, `sql.ex` not regenerated | Run `mix squirrelix.gen` |
| `CannotOverwriteFile` | Non-generated file would be overwritten | Remove or rename the existing `sql.ex` |
| `PostgresSyntaxError` | Invalid SQL | Fix the query and re-run |
| `MissingPostgresTable` / `MissingPostgresColumn` | Schema mismatch | Apply migrations before `--infer` |
| `DuplicateReturnColumns` | Duplicate result column names | Add `as` aliases |
| `QueryFileHasInvalidName` | Invalid Elixir function filename | Rename the `.sql` file |
| `UnsupportedPostgresType` | Type not mapped | See [Types](guides/types.md); hints in the error |
| `MissingQueryMetadata` / `MissingQueryMetadataField` | Incomplete metadata | Fix `squirr_elix.exs` or use `--infer` |
| `InvalidQueryMetadataFile` | Metadata not a map / eval failed | Fix or regenerate with `--write-metadata` |
| `CannotConnectToPostgres` / `PostgresConnectionTimeout` | Infer cannot reach DB | Check `PG*` / URL; or use metadata mode |

Generation is project-wide atomic (query errors refuse all writes; write pass uses
temp + rename with rollback). See
[Configuration](guides/configuration.md#atomic-generate-and-check).

## Relationship to Gleam Squirrel

SquirrElix is an independent project inspired by
[Gleam Squirrel](https://github.com/giacomocavalieri/squirrel) by Giacomo Cavalieri.
It is not an official port of that project and is not affiliated with its authors or
maintainers. SquirrElix follows similar query conventions — one query per file,
`sql/` directory layout, comment-to-doc mapping, parameter name inference, and
Postgres type inference — while producing idiomatic Elixir output:

* Row results are plain maps, not Gleam records.
* Types use stdlib typespecs (`String.t()`, `integer()`, `map()` with `required/1`).
* Postgres enums map to `String.t()`, not generated enum ADTs.
* Generated modules use Postgrex, not `pog`.

Both projects are licensed under Apache 2.0. See
[LICENSE](https://github.com/scripthungry/squirrelix/blob/main/LICENSE) and
[NOTICE](https://github.com/scripthungry/squirrelix/blob/main/NOTICE) for
attribution. This package also draws inspiration from
[yesql](https://github.com/krisajenkins/yesql) and
[sqlx](https://github.com/launchbadge/sqlx).

## Contributing

Maintainer notes live under
[`docs/`](https://github.com/scripthungry/squirrelix/tree/main/docs) on GitHub
(not published on HexDocs):

* [Contributing](https://github.com/scripthungry/squirrelix/blob/main/docs/CONTRIBUTING.md) — `mix precommit`, CI gate, tool pins
* [Roadmap](https://github.com/scripthungry/squirrelix/blob/main/docs/ROADMAP.md) — path to 1.0
* [Performance](https://github.com/scripthungry/squirrelix/blob/main/docs/PERFORMANCE.md) — `mix bench` process
* [Release checklist](https://github.com/scripthungry/squirrelix/blob/main/docs/RELEASE.md) — Hex publish

## License

SquirrElix is licensed under the Apache License 2.0. See
[LICENSE](https://github.com/scripthungry/squirrelix/blob/main/LICENSE).
