# Phoenix + CI Cookbook

0.3 made `--infer` Phoenix-ready (`DATABASE_URL` / SSL). This cookbook covers the
day-to-day Mix workflow: migrate before generate/check, recommended aliases, CI
with `mix squirrelix.check`, and intentional coexistence with Ecto.

Squirrelix is **not** an Ecto `Repo` wrapper. Use Ecto for schemas and migrations;
put typed queries in `sql/` and call the generated modules with a `Postgrex.conn()`.

## Dependencies

Keep Squirrelix as a **dev/test** Mix tool and Postgrex as a **runtime** dependency
(Phoenix apps already depend on Postgrex via Ecto SQL):

```elixir
def deps do
  [
    {:squirr_elix, "~> 0.4.0", only: [:dev, :test], runtime: false},
    {:postgrex, "~> 0.22"}
  ]
end
```

Include `:test` so `mix squirrelix.check` works under `MIX_ENV=test` in CI.

## Layout in a Phoenix app

Place `sql/` directories next to the contexts that own the queries — the same
convention as [Getting Started](getting_started.md):

```txt
lib/
└── my_app/
    └── accounts/
        ├── sql/
        │   ├── find_user.sql
        │   └── list_users.sql
        └── sql.ex              # generated: MyApp.Accounts.SQL
```

Ecto schemas and migrations stay where Phoenix puts them (`lib/my_app/accounts/user.ex`,
`priv/repo/migrations/`). Squirrelix never reads those modules; it only needs the
**database schema** to exist when you run `--infer`.

## `DATABASE_URL` and connection config

Squirrelix does **not** read `config/*.exs` or your `Ecto.Repo` settings. Point it
at the same database Ecto uses via `DATABASE_URL`, `PG*` variables, or Mix flags.

Precedence (highest first): flags → `--url` → `DATABASE_URL` → `PG*` → defaults.

Phoenix-style local / CI usage:

```sh
export DATABASE_URL=postgres://postgres:postgres@localhost:5432/my_app_dev
mix squirrelix.gen --infer
```

Hosted or SSL databases:

```sh
export DATABASE_URL=postgres://user:pass@host:5432/database?sslmode=require
mix squirrelix.gen --infer
```

If your `dev.exs` hardcodes Repo hostname and database without `DATABASE_URL`,
export matching `PG*` variables (or a URL) before generating — see
[Configuration](configuration.md#environment-variables).

Prefer secrets in the environment (`DATABASE_URL` / `PGPASSWORD`) over `--password`
or passwords embedded in shell history.

## Migrate, then generate or check

`--infer` prepares each `.sql` file against a live database. Tables and columns
must already exist, or you get `MissingPostgresTable` / `MissingPostgresColumn`.

Recommended local loop:

```sh
mix ecto.migrate
mix squirrelix.gen --infer
```

Then commit both the `.sql` sources and the generated `sql.ex` files.

Check without writing:

```sh
mix ecto.migrate
mix squirrelix.check --infer
```

## Recommended Mix aliases

Wire migrate-then-gen/check into `mix.exs` so the schema is always applied first:

```elixir
defp aliases do
  [
    setup: ["deps.get", "ecto.setup", "sql.gen"],
    "ecto.setup": ["ecto.create", "ecto.migrate"],
    "ecto.reset": ["ecto.drop", "ecto.setup"],
    test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
    "sql.gen": ["ecto.migrate", "squirrelix.gen --infer"],
    "sql.check": ["ecto.migrate", "squirrelix.check --infer"]
  ]
end
```

Usage:

```sh
mix sql.gen      # migrate + regenerate sql.ex
mix sql.check    # migrate + verify sql.ex is current
```

Ensure `DATABASE_URL` or `PG*` is set in the shell (or CI `env:`) so `--infer`
reaches the same database `ecto.migrate` just updated.

## Calling generated modules

Generated functions take a `Postgrex.conn()` as the first argument — a pool pid,
named process, or other value accepted by `Postgrex.query!/3` /
`Postgrex.query/3`. They do **not** take an `Ecto.Repo` module.

```elixir
alias MyApp.Accounts.SQL

# Raising API
rows = SQL.find_user(conn, 42)
# => [%{id: 42, name: "Ada", email: "ada@example.com"}]

# Soft companion — {:ok, result} | {:error, Exception.t()}
{:ok, rows} = SQL.find_user_ok(conn, 42)
{:ok, 1} = SQL.delete_user_ok(conn, 42)
```

Soft companions (`<name>_ok/arity`) are additive: use them when you want ok/error
tuples (for example in contexts that pattern-match on failure) without changing
the raising API.

A common Phoenix setup is a supervised Postgrex pool configured from the same
URL / credentials as `MyApp.Repo`, then pass that pool into generated functions.
Sharing one Ecto transaction with Squirrelix queries is **out of scope** — there is
no first-class `Repo` integration (see below).

## Coexistence with Ecto (intentional)

| Concern | Tool |
| --- | --- |
| Migrations, schema modules, changesets | Ecto |
| Typed, file-based SQL queries | Squirrelix (`sql/` → `sql.ex`) |
| Runtime execution of generated queries | Postgrex (`Postgrex.conn()`) |

This split is intentional:

- Squirrelix embraces plain `.sql` files and Postgrex — the same model as
  [Gleam Squirrel](https://github.com/giacomocavalieri/squirrel).
- First-class Ecto `Repo` integration / query macros are an **explicit non-goal**
  (see [ROADMAP](../ROADMAP.md#explicit-non-goals-not-on-the-10-path)).
- You can use both in one app: Ecto for writes and schema evolution, Squirrelix for
  read-heavy or carefully reviewed SQL that benefits from typed codegen.

Do not expect generated modules to accept `MyApp.Repo`, participate in
`Repo.transaction/2` automatically, or replace `Ecto.Query`. If you need that
integration layer, build a thin wrapper in your app — it is not part of Squirrelix.

## CI with `mix squirrelix.check`

Commit generated `sql.ex` files. In CI, apply migrations, then fail the job when
SQL and generated Elixir drift apart.

Example GitHub Actions job fragment (Postgres service + Mix):

```yaml
services:
  postgres:
    image: postgres:16
    env:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: my_app_test
    ports:
      - 5432:5432
    options: >-
      --health-cmd "pg_isready -U postgres"
      --health-interval 10s
      --health-timeout 5s
      --health-retries 5

env:
  MIX_ENV: test
  DATABASE_URL: postgres://postgres:postgres@localhost:5432/my_app_test

steps:
  - uses: actions/checkout@v4
  # setup-beam, mix deps.get, compile, … as usual

  - name: Create and migrate database
    run: |
      mix ecto.create --quiet
      mix ecto.migrate

  - name: Check Squirrelix generated modules
    run: mix squirrelix.check --infer
```

Notes:

- `MIX_ENV=test` requires `squirr_elix` in the `:test` dependency list.
- Prefer `DATABASE_URL` (or the `sql.check` alias) so connection settings stay
  consistent with hosted Phoenix configs.
- Generation is project-wide atomic: any query error fails the whole check. See
  [Configuration](configuration.md#atomic-generate-and-check).

A shorter variant when aliases are defined:

```yaml
- run: mix ecto.create --quiet
- run: mix sql.check
```

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `MissingPostgresTable` / column | Migrations not applied | `mix ecto.migrate` before `--infer` |
| `CannotConnectToPostgres` | Wrong host/ creds / SSL | Align `DATABASE_URL` / `PG*` with Repo; see [Configuration](configuration.md) |
| `OutdatedFile` in CI | Forgot to regenerate | Run `mix sql.gen` (or `mix squirrelix.gen --infer`) and commit `sql.ex` |
| Check passes locally, fails in CI | Different database / env | Use the same URL shape; create + migrate in CI before check |

## Next steps

- [Getting Started](getting_started.md) — first query walkthrough
- [Writing Queries](writing_queries.md) — naming, comments, nullable parameters
- [Configuration](configuration.md) — SSL, metadata mode, programmatic API
- [Types](types.md) — Postgres → Elixir mapping
