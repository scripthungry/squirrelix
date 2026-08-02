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
the compiler’s gradual typing and typechecking (patterns and guards inference without needing
annotations). Generated Dialyzer `@spec`s remain part of the codegen story on all supported
versions and are still useful for Dialyzer.

The [Gleam Squirrel](https://github.com/giacomocavalieri/squirrel) project is the inspiration
and basis for this work. SquirrElix brings Squirrel's idea and general architecture to native
Elixir code and Elixir-native typing, following Elixir idioms.

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

This is probably fine if you have a few small queries but it can become quite the
burden when you have a lot of queries:

* The SQL query you write is just a plain string. You do not get syntax highlighting,
  auto formatting, suggestions... all the little niceties you would otherwise get if
  you were writing a plain `*.sql` file.
* This also means you lose the ability to run these queries on their own with other
  external tools, inspect them and so on.
* You have to manually keep row decoding in sync with the query's output.

One might be tempted to hide all of this by reaching for something like an ORM.
SquirrElix adopts a different approach: instead of trying to hide the SQL, it
*embraces it and leaves you in control.* You write the SQL queries in plain old
`*.sql` files and SquirrElix takes care of generating the corresponding functions.

Instead of the hand-written example shown earlier you can instead just write the
following query:

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

And run `mix squirrelix.gen --infer`. Just like magic you'll now have a type-safe
function `find_user/2` you can use just as you'd expect:

```elixir
alias MyApp.Accounts.SQL

{:ok, conn} = Postgrex.start_link(database: "my_app_dev")

# And it just works as you'd expect:
rows = SQL.find_user(conn, 42)
# => [%{name: "Ada", age: 36}]
```

Behind the scenes SquirrElix generates the decode helpers and functions you need;
and it's pretty-printed, standard Elixir code. So now you get the best of both worlds:

* You don't have to take care of keeping encoders and decoders in sync — SquirrElix
  does that for you.
* And you're not compromising on type safety either: SquirrElix is able to
  understand the types of your query and produce correct `@spec`s and runtime decoders.
* You can stick to writing plain SQL in `*.sql` files. You'll have better editor
  support, syntax highlighting and completions.
* You can run each query on its own: need to `explain` a query? No big deal, it's
  just a plain old `*.sql` file.

## When SquirrElix may not be the right fit

SquirrElix is opinionated: Postgres only, one query per file, convention over
configuration, and generated modules that talk to Postgrex — not to an Ecto `Repo`.
That is a strength when those constraints match your needs, and a mismatch when they
do not.

**Consider something else when:**

* You need a database other than Postgres (MySQL, SQLite, …). SquirrElix will not help.
* Most of your data access is CRUD through schemas, changesets, and associations, and
  you rarely write hand-tuned SQL. An ORM / query builder (in Elixir, usually Ecto) is
  the better default.
* You need dynamic query construction at runtime (composable filters, optional joins,
  ad-hoc `order by` / pagination assembled in Elixir). File-based SQL is a poor fit;
  prefer `Ecto.Query` or similar.
* You want first-class participation in `Repo.transaction/2`, Multi, or other Ecto
  Repo APIs without wrapping Postgrex yourself. SquirrElix does not integrate with
  `Repo`.
* Your team is new to SQL and wants the database access layer to hide it. SquirrElix
  does the opposite — it keeps SQL front and centre.
* You only have a handful of queries and are happy maintaining small `Postgrex.query/3`
  helpers by hand. Codegen may be more process than payoff.

**Alternatives to consider:**

| Need | Typical choice |
| --- | --- |
| Schemas, changesets, migrations, associations | [Ecto](https://hexdocs.pm/ecto) |
| Composable / dynamic queries in Elixir | `Ecto.Query` (or raw SQL via `Repo.query/2`) |
| One-off or few static queries, no codegen | Direct [Postgrex](https://hexdocs.pm/postgrex) |
| File-based SQL with a different stack | [yesql](https://github.com/krisajenkins/yesql)-style approaches, or [sqlx](https://github.com/launchbadge/sqlx) outside Elixir |
| Gleam instead of Elixir | Upstream [Squirrel](https://github.com/giacomocavalieri/squirrel) |

### Using SquirrElix alongside an ORM

Yes — that is a common and intentional setup, especially in Phoenix apps that already
use Ecto.

A practical split:

* **Ecto** for migrations, schema modules, changesets, and write paths that benefit
  from validation and associations.
* **SquirrElix** for read-heavy or carefully reviewed SQL you want as plain `.sql`
  files with generated types and decoders.
* **Postgrex** at runtime for executing those generated functions (`Postgrex.conn()`).

SquirrElix never reads your Ecto schemas or `config/*.exs`. Point `--infer` at the
same database Ecto migrates (via `DATABASE_URL` / `PG*` / Mix flags). Generated
functions do not accept `MyApp.Repo` and do not automatically join Ecto transactions —
if you need that bridge, wrap a Postgrex connection (or pool) in your app.

See the [Phoenix + CI Cookbook](guides/phoenix.md#coexistence-with-ecto-intentional)
for layout, Mix aliases, and coexistence details. The short FAQ answer below points
at the same policy.

## Requirements

* Elixir ~> 1.18 (recommend **1.20+** for gradual typing / compiler typechecking)
* Postgrex ~> 0.22 (for generated query modules and optional `--infer` mode)
* PostgreSQL >= 16 (when using `--infer` mode)

## Installation

Add SquirrElix as a **dev/test** dependency (codegen Mix tool) and keep Postgrex as a
**runtime** dependency for generated query modules:

```elixir
def deps do
  [
    {:squirr_elix, "~> 0.5.0", only: [:dev, :test], runtime: false},
    {:postgrex, "~> 0.22"},
    # Optional — only needed for `mix squirrelix.gen --watch`
    {:file_system, "~> 1.0", only: [:dev, :test], runtime: false}
  ]
end
```

`only: [:dev, :test]` keeps the generator out of production while still available for
`mix squirrelix.check` in CI. `runtime: false` prevents starting it with your app.
`file_system` is an optional SquirrElix dependency: omit it unless you use `--watch`.

Then fetch dependencies:

```sh
mix deps.get
```

Documentation is published at <https://hexdocs.pm/squirr_elix>. Browse module docs
locally with `mix docs`.

## Quick start

SquirrElix discovers queries under conventional Elixir source roots. Put one SQL
query per file inside a `sql/` directory:

```txt
├── lib
│   ├── my_app
│   │   └── accounts
│   │       ├── sql
│   │       │   ├── find_user.sql
│   │       │   └── list_users.sql
│   │       └── sql.ex          # generated: MyApp.Accounts.SQL
│   └── my_app.ex
└── mix.exs
```

Generate typed query modules by connecting to Postgres and inferring types:

```sh
mix squirrelix.gen --infer --database my_app_dev
```

Each `sql/` directory becomes one Elixir module named from your app and path — for
example, `lib/my_app/accounts/sql/` generates `MyApp.Accounts.SQL`. Each `.sql` file
becomes a function named after the file (without the extension).

Verify generated code is current in CI:

```sh
mix squirrelix.check --infer --database my_app_dev
```

Copy-pasteable GitHub Actions workflows (Postgres + `--infer`, or offline
metadata) are in
[`examples/github-actions/`](examples/github-actions/). See the
[Phoenix + CI Cookbook](guides/phoenix.md#ci-with-mix-squirrelix-check) for Mix
aliases and when to prefer metadata export over live infer.

See the [Getting Started guide](guides/getting_started.md) for a full walkthrough.

## Writing SQL queries

SquirrElix follows a small set of conventions:

* SquirrElix looks for all `sql/` directories under your project's `lib/`, `test/`,
  and `dev/` roots and reads all the `*.sql` files in there (in glob terms
  `{lib,test,dev}/**/sql/*.sql`).
* Each `sql/` directory is turned into a single Elixir module containing a function
  for each `*.sql` file inside it. The generated module is located next to the
  corresponding `sql/` directory and is named `sql.ex`.
* Each `*.sql` file **must contain a single SQL query.** The name of the file is
  the name of the corresponding Elixir function to run that query.
* Leading SQL comments (`-- ...`) become `@doc` strings on the generated functions.

> **Example.** Given the project layout above, running `mix squirrelix.gen --infer`
> creates `lib/my_app/accounts/sql.ex` defining two functions — `find_user/2` and
> `list_users/1` — that you can import and use in your code.

See the [Writing Queries guide](guides/writing_queries.md) for naming rules, comment
conventions, and tips for nullable parameters.

## Generated code overview

For each query SquirrElix generates:

* A per-query row `@type` (PascalCase of the function name + `_row`) describing the
  returned map shape.
* An `@spec` on the function with a `Postgrex.conn()` connection argument followed
  by inferred parameter types.
* A function body that prepares the query, encodes parameters, executes through
  Postgrex, and decodes rows into maps.

Example generated output:

```elixir
@type find_user_row :: %{
  required(:name) => String.t(),
  required(:age) => integer()
}

@doc """
Find a user and their age given their id.
"""
@spec find_user(Postgrex.conn(), integer()) :: [find_user_row()]
def find_user(conn, id) do
  # ...
end
```

Row-returning queries produce `[map()]`. Command queries (for example `insert`,
`update`, or `delete` with no `returning` clause) return `:ok`.

Each generated query also has an **additive** soft companion named `<name>_ok/arity`
that calls `Postgrex.query/3` and returns `{:ok, result} | {:error, Exception.t()}`
instead of raising. Soft command companions return `{:ok, num_rows}` (affected-row
count). The raising API is unchanged — this is not a breaking change.

Generated modules include a runtime helpers section with shared encode/decode
functions. You should treat `sql.ex` as generated code — edit the `.sql` files and
re-run `mix squirrelix.gen` instead of editing the Elixir module directly.

## CLI commands

SquirrElix offers the following Mix tasks to streamline your workflow:

* `mix squirrelix.gen` — Generates typed Elixir code for all SQL queries found
  under `{lib,test,dev}/**/sql/*.sql`. Pass `--watch` to regenerate when those
  `.sql` files change (Ctrl-C to stop; requires the optional `file_system` dep).
* `mix squirrelix.check` — Validates that the generated Elixir code is up-to-date
  with the SQL queries. This is particularly useful to run in a CI pipeline to make
  sure you don't forget to run `mix squirrelix.gen`.

Both tasks accept the same query-source / connection options (`--infer`, `--metadata`,
`DATABASE_URL`, …). `--watch` is gen-only. See [Configuration](guides/configuration.md)
for metadata files, watch mode, connection settings, and programmatic use.

```sh
mix squirrelix.gen --infer --database my_app_dev
mix squirrelix.gen --infer --watch
mix squirrelix.check --infer --database my_app_dev
```

## Query sources

Generation and checking accept a *query source* — either static metadata or a live
Postgres inferrer:

**Metadata file** — keys are absolute or project-relative paths to `.sql` files;
values are keyword lists with `:params` and `:returns`. Load one from
`squirr_elix.exs` in the project root (or pass `--metadata PATH`):

```elixir
# squirr_elix.exs
%{
  "lib/my_app/accounts/sql/find_user.sql" => [
    params: [:integer],
    returns: [
      %{name: "name", type: :string, nullable?: false},
      %{name: "age", type: :integer, nullable?: false}
    ]
  ]
}
```

```sh
mix squirrelix.gen
mix squirrelix.gen --metadata config/squirr_elix.exs
```

**Postgres inferrer** — connects to a database, prepares each query, and reads
parameter and column types from Postgrex. Pass connection options on the CLI,
via `DATABASE_URL`, or via `PG*` environment variables:

```sh
mix squirrelix.gen --infer --database my_app_dev
mix squirrelix.gen --infer --url postgres://localhost/my_app_dev
export DATABASE_URL=postgres://localhost/my_app_dev?sslmode=require
mix squirrelix.gen --infer
```

Use `--write-metadata PATH` with `--infer` to export a reloadable metadata file for
offline `mix squirrelix.check` / `gen` (see the Configuration guide).

The programmatic API mirrors this split — see `Squirrelix.generate/3` and
`Squirrelix.check/3`. The supported public surface (Mix tasks, summaries, error
structs, `Postgres.inferrer/1`, Inferrer behaviour) is inventoried under
[Configuration → Supported public API](guides/configuration.md#supported-public-api).
Other `Squirrelix.*` modules are internal and may change before 1.0.

## Configuration and connection

In order to understand the type of your queries, SquirrElix needs to connect to
the Postgres server where the database schema is defined when you use `--infer`.

Pass a connection URL on the CLI, or set `DATABASE_URL` (prefer env secrets over
embedding passwords in a URL or `--password`):

```sh
export DATABASE_URL=postgres://user@host:5432/database?sslmode=require
mix squirrelix.gen --infer

# or:
mix squirrelix.gen --infer --url postgres://user@host:5432/database?connect_timeout=5
```

URL `sslmode` / `ssl` query parameters map into Postgrex `:ssl` options (see the
[Configuration](guides/configuration.md) guide). `sslmode=require` encrypts without
CA verification (libpq-aligned); use `verify-ca` / `verify-full` when you need peer
checks. Unix sockets are not supported.

Or set [Postgres environment variables](https://www.postgresql.org/docs/current/libpq-envars.html).
When a value is not set, SquirrElix uses these defaults:

| Variable | Default |
| --- | --- |
| `DATABASE_URL` | *(unset — fall back to `PG*`)* |
| `PGHOST` | `"localhost"` |
| `PGPORT` | `5432` |
| `PGUSER` | `"postgres"` |
| `PGDATABASE` | `"postgres"` |
| `PGPASSWORD` | `""` |
| `PGCONNECT_TIMEOUT` | `5` seconds |
| `PGSSLMODE` | *(no SSL)* |

You can also pass individual flags: `--hostname`, `--port`, `--username`, `--password`,
and `--database`. Precedence (highest first): flags → `--url` → `DATABASE_URL` →
`PG*` → defaults.

Generated functions call `Postgrex.query!/3` and raise on database errors. Soft
companions (`<name>_ok/arity`) call `Postgrex.query/3` and return
`{:ok, result} | {:error, Exception.t()}` instead. Metadata files are evaluated
Elixir — only load trusted paths.

See the [Configuration guide](guides/configuration.md) for metadata mode, the
programmatic API, and CI setup.

## Supported types

SquirrElix takes care of the mapping between Postgres types and Elixir types.
This is needed in two places:

* Elixir values need to be *encoded* into Postgres values when you're filling in the
  holes of a prepared statement (`$1`, `$2`, ...).
* Postgres values need to be *decoded* into Elixir ones when you're reading the rows
  returned by a query.

The types that are currently supported are:

| Postgres type | encoded as | decoded as |
| --- | --- | --- |
| `bool` | `boolean()` | `boolean()` |
| `text`, `char`, `bpchar`, `varchar`, `citext`, `name` | `String.t()` | `String.t()` |
| `float4`, `float8` | `float()` | `float()` |
| `numeric` | `Decimal.t()` | `Decimal.t()` |
| `int2`, `int4`, `int8` | `integer()` | `integer()` |
| `json`, `jsonb` | `term()` | `term()` |
| `uuid` | `String.t()` | `String.t()` |
| `bytea` | `binary()` | `binary()` |
| `date` | `Date.t()` | `Date.t()` |
| `time` | `Time.t()` | `Time.t()` |
| `timestamp` | `NaiveDateTime.t()` | `NaiveDateTime.t()` |
| `timestamptz` | `DateTime.t()` | `DateTime.t()` |
| `<type>[]` (where `<type>` is any supported type) | `[type]` | `[type]` |
| user-defined enum | `String.t()` | `String.t()` |
| user-defined domain | base type | base type |

See the [Types guide](guides/types.md) for nullable columns, JSON columns,
unsupported ranges/built-ins, and intentional differences from Gleam Squirrel.

**Unsupported (rejected with hints):** Postgres ranges/multiranges, geometric
types (`point`, …), network types (`inet`, …), `interval`, `bit`/`varbit`,
`tsvector`/`tsquery`, `money`, `xml`, OID-family types, `hstore`, and `timetz`.
Prefer casting to a supported type in SQL or selecting scalar bounds/fields.

### Enums

If your queries deal with user-defined Postgres enums, SquirrElix maps them to
`String.t()` in generated `@spec`s. Enum labels are passed through at runtime as
plain strings — SquirrElix does **not** generate Elixir enum modules or
Gleam-style custom types.

For example, given this enum:

```sql
create type squirrel_colour as enum (
  'light_brown',
  'grey',
  'red'
);
```

A column of type `squirrel_colour` is typed as `String.t()` and decoded as
`"light_brown"`, `"grey"`, or `"red"`.

## FAQ

### What flavour of SQL does SquirrElix support?

SquirrElix only supports Postgres. It supports all versions `>= 16`.

### Why isn't SquirrElix configurable in any way?

By going the "convention over configuration" route, SquirrElix enforces that all
projects adopting it will always have the same structure. If you need to contribute
to a project using SquirrElix you'll immediately know which directories and modules
to look for.

This makes it easier to get started with a new project and cuts down on bike shedding:
*"Where should I put my queries?"*, *"How many queries should go in one file?"*, ...

### Can SquirrElix read my `.env` file?

The approach we recommend is either use your shell's built-in functionality for loading
environment variables or use a convenience tool which builds upon that capability, such
as [`direnv`](https://direnv.net). This way the environment is managed by the
environment rather than the application itself.

### How do I deal with nullable query parameters?

SquirrElix works by inspecting the data that Postgres itself exposes about a query.
Postgres doesn't expose any data about the nullability of query parameters, so
SquirrElix can't generate the correct nullable type when, for example, inserting
into a nullable column.

See the [Writing Queries guide](guides/writing_queries.md#nullable-query-parameters)
for recommended workarounds.

### Why aren't Postgres composite types supported?

SquirrElix intentionally rejects composite types (`create type ... as (...)`)
with an actionable hint. Generating nested row modules (or mapping composites to
`map()`/`term()`) would expand the Elixir-native surface beyond Gleam Squirrel's
model and blur the flat `required/1` row maps used today.

Select individual fields (for example `(location).x`), or cast to
`json`/`jsonb`/`text` in the query. See the
[Types guide](guides/types.md#composite-types-policy) for the full policy.

### Does SquirrElix integrate with Ecto `Repo`?

No — and that is intentional. SquirrElix is not a `Repo` wrapper and does not provide
query macros. You can still use it *alongside* Ecto (migrations / schemas / changesets
via Ecto; typed `.sql` queries via SquirrElix + Postgrex). See
[When SquirrElix may not be the right fit](#when-squirrelix-may-not-be-the-right-fit)
and the
[Phoenix + CI Cookbook](guides/phoenix.md#coexistence-with-ecto-intentional).

## Errors and troubleshooting

SquirrElix reports structured errors during generation and checking. Common cases:

| Error | Typical cause | What to do |
| --- | --- | --- |
| `OutdatedFile` | SQL changed but `sql.ex` was not regenerated | Run `mix squirrelix.gen` |
| `CannotOverwriteFile` | A non-generated file would be overwritten | Remove or rename the existing `sql.ex` |
| `PostgresSyntaxError` | Invalid SQL | Fix the query and re-run generation |
| `MissingPostgresTable` / `MissingPostgresColumn` | Schema mismatch | Apply migrations before `--infer` |
| `DuplicateReturnColumns` | Two columns share the same name in the result | Add aliases in the `select` list |
| `QueryFileHasInvalidName` | Filename is not a valid Elixir function name | Rename the `.sql` file (a suggested name may be shown) |
| `UnsupportedPostgresType` | Postgres type not mapped (ranges, geometric, …) | Check the Types guide; errors include actionable hints |
| `MissingQueryMetadata` | No metadata entry for a query file | Add an entry to `squirr_elix.exs` or use `--infer` |
| `MissingQueryMetadataField` | Metadata entry lacks `params` or `returns` | Complete both fields in `squirr_elix.exs` |
| `InvalidQueryMetadataFile` | Metadata file is not a map / fails to evaluate | Fix `squirr_elix.exs`, or regenerate with `--write-metadata` |
| `CannotReadFile` / `CannotWriteFile` | Filesystem read/write failure | Check paths and permissions |
| `CannotConnectToPostgres` | `--infer` cannot reach Postgres or auth/catalog fails | Check `PG*` / `--hostname` / credentials; or use metadata mode |
| `PostgresConnectionTimeout` | Connection attempt exceeded `PGCONNECT_TIMEOUT` / `connect_timeout` | Increase the timeout, verify host reachability, or use metadata mode |

Generation, check, metadata, and connection failures raise Mix errors with the same
structured formatting (actionable titles and hints), not raw `inspect/1` dumps as the
primary message. CLI option-parse failures (`Unexpected arguments`, `Invalid options`)
and watch-backend startup messages stay as plain Mix raises by design. Verify `PG*`
variables or `--url`, ensure Postgres is running, and confirm the database exists and
has the expected schema.

Generation is project-wide atomic: query errors refuse all writes, and the write
pass prepares every `sql.ex` before committing (temp + rename with rollback).
`mix squirrelix.check` fails globally when any directory has errors or drift. See
[Configuration](guides/configuration.md#atomic-generate-and-check).

## Relationship to Gleam Squirrel

SquirrElix is an Elixir port of [Gleam Squirrel](https://github.com/giacomocavalieri/squirrel)
by Giacomo Cavalieri. It follows upstream query conventions — one query per file,
`sql/` directory layout, comment-to-doc mapping, parameter name inference, and
Postgres type inference — while producing idiomatic Elixir output:

* Row results are plain maps, not Gleam records.
* Types use stdlib typespecs (`String.t()`, `integer()`, `map()` with `required/1`).
* Postgres enums map to `String.t()`, not generated enum ADTs.
* Generated modules use Postgrex, not `pog`.

Both projects are licensed under Apache 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE)
for attribution.

This package also draws inspiration from [yesql](https://github.com/krisajenkins/yesql)
and [sqlx](https://github.com/launchbadge/sqlx).

## Development

Clone the repository and run the local validation suite before committing:

```sh
mix precommit
```

(`mix precommit` compiles with `--warnings-as-errors`, then runs `mix format`,
`mix credo --strict --all`, and `mix test`.)

For the full quality gate used in CI on Elixir 1.20 (also Dialyzer,
[ExDNA](https://github.com/elixir-vibe/ex_dna), and [Reach](https://github.com/elixir-vibe/reach),
with [ExSlop](https://github.com/elixir-vibe/ex_slop) Credo checks):

```sh
mix ci
```

GitHub Actions also compiles and runs `mix test` on Elixir **1.18**, **1.19**, and
**1.20**; every matrix cell is a hard gate (the workflow fails if any version fails).

See [ROADMAP.md](ROADMAP.md) for completed work and remaining compatibility slices.

## Guides

* [Getting Started](guides/getting_started.md)
* [Writing Queries](guides/writing_queries.md)
* [Types](guides/types.md)
* [Configuration](guides/configuration.md)
* [Phoenix + CI Cookbook](guides/phoenix.md)
* [Adopter CI workflows](examples/github-actions/) — copy-pasteable GitHub Actions for `squirrelix.check`

## License

SquirrElix is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
