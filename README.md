# Squirrelixir

Squirrelixir turns plain `.sql` files into typed Elixir modules. You write one
query per file; the generator discovers those files, resolves parameter and
return types, and writes a sibling `sql.ex` module with `@spec`-annotated
functions that run the queries through Postgrex.

It targets **Elixir 1.20** and uses native typespecs rather than custom ADTs or
Gleam-style records. See the [Gleam Squirrel](https://github.com/giacomocavalieri/squirrel)
project for the upstream SQL discovery, inference, and query conventions that
Squirrelixir follows.

## Quick start

Add Squirrelixir as a dependency, put queries under a `sql/` directory, and
generate with Postgres type inference:

```elixir
# mix.exs
def deps do
  [
    {:squirrelixir, "~> 0.1.0"},
    {:postgrex, "~> 0.22"}
  ]
end
```

```
lib/my_app/
├── accounts/
│   ├── sql/
│   │   └── find_user.sql
│   └── sql.ex          # generated: MyApp.Accounts.SQL
```

```sh
mix squirrelixir.gen --infer --database my_app_dev
```

Each `sql/` directory becomes one module named from your app and path — for
example, `lib/my_app/accounts/sql/` generates `MyApp.Accounts.SQL`. Each
`.sql` file becomes a function named after the file (without the extension).

Verify generated code is current in CI:

```sh
mix squirrelixir.check --infer --database my_app_dev
```

## Types

Generated modules define a per-query row type and use stdlib types in `@spec`s:

```elixir
@type find_user_row :: %{
  required(:name) => String.t() | nil,
  required(:age) => integer()
}

@spec find_user(Postgrex.conn(), integer()) :: [find_user_row()]
def find_user(connection, id)
```

Postgres enums map to `String.t()`. Row shapes use `map/0` with `required/1`
(and `| nil` for nullable columns). Scalars use the usual Elixir types:
`integer()`, `boolean()`, `float()`, `Decimal.t()`, `Date.t()`,
`NaiveDateTime.t()`, `DateTime.t()`, and so on.

## Query sources

Generation and checking accept a *query source* — either static metadata or a
live Postgres inferrer:

**Metadata map** — keys are absolute or project-relative paths to `.sql` files;
values are keyword lists with `:params` and `:returns`. Load one from
`squirrelixir.exs` in the project root (or pass `--metadata PATH`):

```elixir
# squirrelixir.exs
%{
  "lib/my_app/accounts/sql/find_user.sql" => [
    params: [:integer],
    returns: [
      %{name: "name", type: :string, nullable?: true},
      %{name: "age", type: :integer, nullable?: false}
    ]
  ]
}
```

```sh
mix squirrelixir.gen
mix squirrelixir.gen --metadata config/squirrelixir.exs
```

**Postgres inferrer** — connects to a database, prepares each query, and reads
parameter and column types from Postgrex. Pass connection options on the CLI or
via `PG*` environment variables:

```sh
mix squirrelixir.gen --infer --database my_app_dev
mix squirrelixir.gen --infer --url postgres://localhost/my_app_dev
```

The programmatic API mirrors this split — see `Squirrelixir.generate/3` and
`Squirrelixir.check/3`.

## API overview

| Mix task | Purpose |
| --- | --- |
| `mix squirrelixir.gen` | Write or refresh `sql.ex` modules |
| `mix squirrelixir.check` | Fail when generated output would change |

Discovery scans `lib/`, `test/`, and `dev/` for `**/sql/*.sql`. Each directory
must contain exactly one SQL statement per file; leading SQL comments become
`@doc` strings on the generated functions.

## Installation

If [available in Hex](https://hex.pm/docs/publish), add `squirrelixir` to your
dependencies:

```elixir
def deps do
  [
    {:squirrelixir, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can be
found at <https://hexdocs.pm/squirrelixir>.
