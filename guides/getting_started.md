# Getting Started

This guide walks through adding Squirrelix to a Mix project, writing your first
query, and generating typed Elixir modules.

## Add the dependency

Squirrelix is a **codegen Mix tool** — keep it out of production. Postgrex stays a
**runtime** dependency because generated modules call it:

```elixir
def deps do
  [
    {:squirr_elix, "~> 0.3.0", only: [:dev, :test], runtime: false},
    {:postgrex, "~> 0.22"}
  ]
end
```

Include `:test` so `mix squirrelix.check` works in CI (`MIX_ENV=test`). Use
`runtime: false` so Squirrelix is not started with your application.

Then run:

```sh
mix deps.get
```

## Project layout

Squirrelix discovers queries under `lib/`, `test/`, and `dev/` in directories
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
└── squirr_elix.exs                # optional metadata file
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

The filename (`find_user.sql`) becomes the function name (`find_user/2` — conn
plus one parameter).

## Generate code

### With Postgres inference (recommended)

Point Squirrelix at a database that has your schema applied (migrations run):

```sh
mix squirrelix.gen --infer --database my_app_dev
```

Squirrelix connects to Postgres, prepares each query, and reads parameter and
column types from Postgrex metadata.

Set connection details via `DATABASE_URL`, `PG*` environment variables, or flags:

```sh
export DATABASE_URL=postgres://postgres@localhost/my_app_dev
mix squirrelix.gen --infer

# or:
export PGHOST=localhost
export PGDATABASE=my_app_dev
export PGUSER=postgres

mix squirrelix.gen --infer
```

Or pass a URL:

```sh
mix squirrelix.gen --infer --url postgres://postgres@localhost/my_app_dev
```

### With a metadata file

If you cannot connect to Postgres during generation, provide types manually in
`squirr_elix.exs`:

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
mix squirrelix.gen
```

See [Configuration](configuration.md) for the full metadata format.

## Watch while editing

To regenerate whenever a discovered `.sql` file changes:

```sh
mix squirrelix.gen --watch
mix squirrelix.gen --infer --watch
```

Watch uses the same metadata / `--infer` connection options as a one-shot generate.
Press Ctrl-C to stop. See [Configuration](configuration.md#watch-mode) for details.

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

Soft companions return ok/error tuples instead of raising. Soft commands include the
affected-row count:

```elixir
{:ok, [%{id: 1, name: "Ada"}]} = SQL.find_user_ok(conn, 1)
{:ok, 1} = SQL.delete_user_ok(conn, 1)
{:error, %Postgrex.Error{}} = SQL.find_user_ok(conn, -1)
```

## Keep generated code in sync

Run the check task in CI to catch stale generated files:

```sh
mix squirrelix.check --infer --database my_app_dev
```

If SQL changed but `sql.ex` was not regenerated, the check fails with an
`OutdatedFile` error. Fix it by running `mix squirrelix.gen` again and committing
the updated `sql.ex`.

## Next steps

- [Writing Queries](writing_queries.md) — naming, comments, nullable parameters
- [Types](types.md) — Postgres to Elixir type mapping
- [Configuration](configuration.md) — metadata, env vars, programmatic API
- [Phoenix + CI Cookbook](phoenix.md) — migrate-then-gen, Mix aliases, Ecto coexistence
