# Getting Started

This guide walks through adding Squirrelixir to a Mix project, writing your first
query, and generating typed Elixir modules.

## Add the dependency

Add Squirrelixir and Postgrex to your `mix.exs`:

```elixir
def deps do
  [
    {:squirrelixir, "~> 0.1.0"},
    {:postgrex, "~> 0.22"}
  ]
end
```

Before the initial Hex release:

```elixir
{:squirrelixir, github: "mward-sudo/squirrelixir"}
```

Then run:

```sh
mix deps.get
```

Squirrelixir is typically a **dev dependency** — you run code generation at build or
CI time rather than at runtime in production. Add it under `only: :dev` if you prefer.

## Project layout

Squirrelixir discovers queries under `lib/`, `test/`, and `dev/` in directories
named `sql/`:

```txt
my_app/
├── lib/
│   └── my_app/
│       └── accounts/
│           ├── sql/
│           │   └── find_user.sql
│           └── sql.ex              # generated
├── mix.exs
└── squirrelixir.exs                # optional metadata file
```

Each `sql/` directory maps to one generated module. The module name is derived from
your app name and the path under `lib/`:

| SQL directory | Generated module |
| --- | --- |
| `lib/my_app/sql/` | `MyApp.SQL` |
| `lib/my_app/accounts/sql/` | `MyApp.Accounts.SQL` |
| `test/support/sql/` | `Support.SQL` (under test) |

The generated file is always named `sql.ex` and lives in the parent of the `sql/`
directory.

## Write a query

Create one SQL statement per file. Use leading comments for documentation:

```sql
-- lib/my_app/accounts/sql/find_user.sql
-- Find a user by primary key.
select
  id,
  name,
  email
from
  users
where
  id = $1
```

The filename (`find_user.sql`) becomes the function name (`find_user/2` — connection
plus one parameter).

## Generate code

### With Postgres inference (recommended)

Point Squirrelixir at a database that has your schema applied (migrations run):

```sh
mix squirrelixir.gen --infer --database my_app_dev
```

Squirrelixir connects to Postgres, prepares each query, and reads parameter and
column types from Postgrex metadata.

Set connection details via environment variables or flags:

```sh
export PGHOST=localhost
export PGDATABASE=my_app_dev
export PGUSER=postgres

mix squirrelixir.gen --infer
```

Or pass a URL:

```sh
mix squirrelixir.gen --infer --url postgres://postgres@localhost/my_app_dev
```

### With a metadata file

If you cannot connect to Postgres during generation, provide types manually in
`squirrelixir.exs`:

```elixir
%{
  "lib/my_app/accounts/sql/find_user.sql" => [
    params: [:integer],
    returns: [
      %{name: "id", type: :integer, nullable?: false},
      %{name: "name", type: :string, nullable?: false},
      %{name: "email", type: :string, nullable?: true}
    ]
  ]
}
```

```sh
mix squirrelixir.gen
```

See [Configuration](configuration.md) for the full metadata format.

## Use the generated module

After generation, call functions from the generated module with a Postgrex connection:

```elixir
alias MyApp.Accounts.SQL

defmodule MyApp.Accounts do
  def find_user(conn, id) do
    SQL.find_user(conn, id)
  end
end
```

Row queries return a list of maps:

```elixir
[%{id: 1, name: "Ada", email: "ada@example.com"}] = SQL.find_user(conn, 1)
```

Command queries (no returned rows) return `:ok`:

```elixir
:ok = SQL.delete_user(conn, 1)
```

## Keep generated code in sync

Run the check task in CI to catch stale generated files:

```sh
mix squirrelixir.check --infer --database my_app_dev
```

If SQL changed but `sql.ex` was not regenerated, the check fails with an
`OutdatedFile` error. Fix it by running `mix squirrelixir.gen` again and committing
the updated `sql.ex`.

## Next steps

- [Writing Queries](writing_queries.md) — naming, comments, nullable parameters
- [Types](types.md) — Postgres to Elixir type mapping
- [Configuration](configuration.md) — metadata, env vars, programmatic API
