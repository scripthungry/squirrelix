# 🐿️ Squirrelix — type-safe SQL in Elixir

> Squirrelix (package `squirr_elix`)

[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/squirr_elix/)

Squirrelix turns plain `.sql` files into typed Elixir modules. You write one query
per file; the generator discovers those files, resolves parameter and return types,
and writes a sibling `sql.ex` module with `@spec`-annotated functions that run the
queries through Postgrex.

It targets **Elixir 1.20** and uses native typespecs rather than custom ADTs or
Gleam-style records. See the [Gleam Squirrel](https://github.com/giacomocavalieri/squirrel)
project for the upstream SQL discovery, inference, and query conventions that
Squirrelix follows.

## What's Squirrelix?

If you need to talk with a database in Elixir you'll often write something like this:

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

- The SQL query you write is just a plain string. You do not get syntax highlighting,
  auto formatting, suggestions... all the little niceties you would otherwise get if
  you were writing a plain `*.sql` file.
- This also means you lose the ability to run these queries on their own with other
  external tools, inspect them and so on.
- You have to manually keep row decoding in sync with the query's output.

One might be tempted to hide all of this by reaching for something like an ORM.
Squirrelix proposes a different approach: instead of trying to hide the SQL it
_embraces it and leaves you in control._ You write the SQL queries in plain old
`*.sql` files and Squirrelix will take care of generating all the corresponding
functions.

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

Behind the scenes Squirrelix generates the decode helpers and functions you need;
and it's pretty-printed, standard Elixir code. So now you get the best of both worlds:

- You don't have to take care of keeping encoders and decoders in sync — Squirrelix
  does that for you.
- And you're not compromising on type safety either: Squirrelix is able to
  understand the types of your query and produce correct `@spec`s and runtime decoders.
- You can stick to writing plain SQL in `*.sql` files. You'll have better editor
  support, syntax highlighting and completions.
- You can run each query on its own: need to `explain` a query? No big deal, it's
  just a plain old `*.sql` file.

## Requirements

- Elixir ~> 1.20
- Postgrex ~> 0.22 (for generated query modules and optional `--infer` mode)
- PostgreSQL >= 16 (when using `--infer` mode)

## Installation

Add Squirrelix to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:squirr_elix, "~> 0.1.0"},
    {:postgrex, "~> 0.22"}
  ]
end
```

Then fetch dependencies:

```sh
mix deps.get
```

Documentation is published at <https://hexdocs.pm/squirr_elix>. Browse module docs
locally with `mix docs`.

## Quick start

Squirrelix discovers queries under conventional Elixir source roots. Put one SQL
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

See the [Getting Started guide](guides/getting_started.md) for a full walkthrough.

## Writing SQL queries

Squirrelix follows a small set of conventions:

- Squirrelix looks for all `sql/` directories under your project's `lib/`, `test/`,
  and `dev/` roots and reads all the `*.sql` files in there (in glob terms
  `{lib,test,dev}/**/sql/*.sql`).
- Each `sql/` directory is turned into a single Elixir module containing a function
  for each `*.sql` file inside it. The generated module is located next to the
  corresponding `sql/` directory and is named `sql.ex`.
- Each `*.sql` file **must contain a single SQL query.** The name of the file is
  the name of the corresponding Elixir function to run that query.
- Leading SQL comments (`-- ...`) become `@doc` strings on the generated functions.

> **Example.** Given the project layout above, running `mix squirrelix.gen --infer`
> creates `lib/my_app/accounts/sql.ex` defining two functions — `find_user/2` and
> `list_users/1` — that you can import and use in your code.

See the [Writing Queries guide](guides/writing_queries.md) for naming rules, comment
conventions, and tips for nullable parameters.

## Generated code overview

For each query Squirrelix generates:

- A per-query row `@type` (PascalCase of the function name + `_row`) describing the
  returned map shape.
- An `@spec` on the function with a `Postgrex.conn()` connection argument followed
  by inferred parameter types.
- A function body that prepares the query, encodes parameters, executes through
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

Generated modules include a runtime helpers section with shared encode/decode
functions. You should treat `sql.ex` as generated code — edit the `.sql` files and
re-run `mix squirrelix.gen` instead of editing the Elixir module directly.

## CLI commands

Squirrelix offers the following Mix tasks to streamline your workflow:

- `mix squirrelix.gen` — Generates typed Elixir code for all SQL queries found
  under `{lib,test,dev}/**/sql/*.sql`.
- `mix squirrelix.check` — Validates that the generated Elixir code is up-to-date
  with the SQL queries. This is particularly useful to run in a CI pipeline to make
  sure you don't forget to run `mix squirrelix.gen`.

Both tasks accept the same options. See [Configuration](guides/configuration.md) for
metadata files, connection settings, and programmatic use.

```sh
mix squirrelix.gen --infer --database my_app_dev
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
parameter and column types from Postgrex. Pass connection options on the CLI or
via `PG*` environment variables:

```sh
mix squirrelix.gen --infer --database my_app_dev
mix squirrelix.gen --infer --url postgres://localhost/my_app_dev
```

The programmatic API mirrors this split — see `Squirrelix.generate/3` and
`Squirrelix.check/3`.

## Configuration and connection

In order to understand the type of your queries, Squirrelix needs to connect to
the Postgres server where the database schema is defined when you use `--infer`.

Pass a connection URL on the CLI (prefer `PGPASSWORD` over embedding passwords in
the URL or `--password`):

```sh
mix squirrelix.gen --infer --url postgres://user@host:5432/database?connect_timeout=5
```

Or set [Postgres environment variables](https://www.postgresql.org/docs/current/libpq-envars.html).
When a value is not set, Squirrelix uses these defaults:

| Variable | Default |
| --- | --- |
| `PGHOST` | `"localhost"` |
| `PGPORT` | `5432` |
| `PGUSER` | `"postgres"` |
| `PGDATABASE` | `"postgres"` |
| `PGPASSWORD` | `""` |
| `PGCONNECT_TIMEOUT` | `5` seconds |

You can also pass individual flags: `--hostname`, `--port`, `--username`, `--password`,
and `--database`. Precedence (highest first): CLI flags → `--url` → environment →
defaults.

Generated functions call `Postgrex.query!/3` and raise on database errors. Metadata
files are evaluated Elixir — only load trusted paths.

See the [Configuration guide](guides/configuration.md) for metadata mode, the
programmatic API, and CI setup.

## Supported types

Squirrelix takes care of the mapping between Postgres types and Elixir types.
This is needed in two places:

- Elixir values need to be _encoded_ into Postgres values when you're filling in the
  holes of a prepared statement (`$1`, `$2`, ...).
- Postgres values need to be _decoded_ into Elixir ones when you're reading the rows
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

See the [Types guide](guides/types.md) for nullable columns, JSON columns, and
intentional differences from Gleam Squirrel.

### Enums

If your queries deal with user-defined Postgres enums, Squirrelix maps them to
`String.t()` in generated `@spec`s. Enum labels are passed through at runtime as
plain strings — Squirrelix does **not** generate Elixir enum modules or
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

### What flavour of SQL does Squirrelix support?

Squirrelix only supports Postgres. It supports all versions `>= 16`.

### Why isn't Squirrelix configurable in any way?

By going the "convention over configuration" route, Squirrelix enforces that all
projects adopting it will always have the same structure. If you need to contribute
to a project using Squirrelix you'll immediately know which directories and modules
to look for.

This makes it easier to get started with a new project and cuts down on bike shedding:
_"Where should I put my queries?"_, _"How many queries should go in one file?"_, ...

### Can Squirrelix read my `.env` file?

The approach we recommend is either use your shell's built-in functionality for loading
environment variables or use a convenience tool which builds upon that capability, such
as [`direnv`](https://direnv.net). This way the environment is managed by the
environment rather than the application itself.

### How do I deal with nullable query parameters?

Squirrelix works by inspecting the data that Postgres itself exposes about a query.
Postgres doesn't expose any data about the nullability of query parameters, so
Squirrelix can't generate the correct nullable type when, for example, inserting
into a nullable column.

See the [Writing Queries guide](guides/writing_queries.md#nullable-query-parameters)
for recommended workarounds.

## Errors and troubleshooting

Squirrelix reports structured errors during generation and checking. Common cases:

| Error | Typical cause | What to do |
| --- | --- | --- |
| `OutdatedFile` | SQL changed but `sql.ex` was not regenerated | Run `mix squirrelix.gen` |
| `CannotOverwriteFile` | A non-generated file would be overwritten | Remove or rename the existing `sql.ex` |
| `PostgresSyntaxError` | Invalid SQL | Fix the query and re-run generation |
| `MissingPostgresTable` / `MissingPostgresColumn` | Schema mismatch | Apply migrations before `--infer` |
| `DuplicateReturnColumns` | Two columns share the same name in the result | Add aliases in the `select` list |
| `QueryFileHasInvalidName` | Filename is not a valid Elixir function name | Rename the `.sql` file (a suggested name may be shown) |
| `UnsupportedPostgresType` | Postgres type not yet mapped | Check the supported types table; some types include hints |
| `MissingQueryMetadata` | No metadata entry for a query file | Add an entry to `squirr_elix.exs` or use `--infer` |

Connection failures during `--infer` produce a Mix error with the underlying
Postgrex reason. Verify `PG*` variables or `--url`, ensure Postgres is running, and
confirm the database exists and has the expected schema.

## Relationship to Gleam Squirrel

Squirrelix is an Elixir port of [Gleam Squirrel](https://github.com/giacomocavalieri/squirrel)
by Giacomo Cavalieri. It follows upstream query conventions — one query per file,
`sql/` directory layout, comment-to-doc mapping, parameter name inference, and
Postgres type inference — while producing idiomatic Elixir output:

- Row results are plain maps, not Gleam records.
- Types use stdlib typespecs (`String.t()`, `integer()`, `map()` with `required/1`).
- Postgres enums map to `String.t()`, not generated enum ADTs.
- Generated modules use Postgrex, not `pog`.

Both projects are licensed under Apache 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE)
for attribution.

This package also draws inspiration from [yesql](https://github.com/krisajenkins/yesql)
and [sqlx](https://github.com/launchbadge/sqlx).

## Development

Clone the repository and run the full validation suite before committing:

```sh
mix precommit
```

(`mix precommit` runs `mix format`, `mix credo --strict --all`, and `mix test`.)

See [ROADMAP.md](ROADMAP.md) for completed work and remaining compatibility slices.

## Guides

- [Getting Started](guides/getting_started.md)
- [Writing Queries](guides/writing_queries.md)
- [Types](guides/types.md)
- [Configuration](guides/configuration.md)

## License

Squirrelix is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
