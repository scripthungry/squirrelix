# Phoenix + CI Cookbook

Day-to-day Mix workflow for Phoenix apps: migrate before generate/check, recommended
aliases, CI with `mix squirrelix.check`, and intentional coexistence with Ecto.

SquirrElix is **not** an Ecto ORM. Use Ecto for schemas, changesets, and migrations;
put typed queries in `sql/` and call the generated modules. By default those modules
take a `Postgrex.conn()`; optionally generate a **Repo runner** so call sites pass
`MyApp.Repo` and share checkout / Sandbox / transactions via `Ecto.Adapters.SQL`.

## What the optional Repo integration is for

Phoenix apps already own a database through `Ecto.Repo`. Without help, SquirrElix
forces a second seam: dual connection config for `--infer`, and call sites that
pass a raw Postgrex connection even when the rest of the app thinks in Repo terms.

The optional integration closes **only** that seam:

| Capability | Purpose |
| --- | --- |
| Mix `--repo MyApp.Repo` (with `--infer`) | Read host/user/database/SSL (and `:url`) from `Repo.config/0` so generate/check use the same DB settings as Ecto — no second copy of credentials |
| Mix `--runner ecto` | Generate `SQL.find_user(Repo, id)` style functions that call `Ecto.Adapters.SQL.query!/3` / `query/3`, so queries join **Repo checkout**, **`Repo.transaction/2`**, and **`Ecto.Adapters.SQL.Sandbox`** in tests |

**It is not for:** mapping rows to `%Ecto.Schema{}` structs, changesets,
`Ecto.Multi`, associations, `Ecto.Query`, or replacing Ecto as your persistence
layer. Those remain explicit non-goals (see
[ROADMAP](https://github.com/scripthungry/squirrelix/blob/main/docs/ROADMAP.md#explicit-non-goals-not-on-the-10-path)).
Plain `.sql` files stay the source of truth; SquirrElix still generates typed maps.

Default codegen (`--runner postgrex`) is unchanged for non-Ecto apps.

## Dependencies

Keep SquirrElix as a **dev/test** Mix tool (include `:test` for CI under
`MIX_ENV=test`). Phoenix apps already depend on Postgrex via Ecto SQL:

```elixir
{:squirr_elix, "~> 0.5.0", only: [:dev, :test], runtime: false}
```

`--runner ecto` needs `ecto_sql` at **runtime in the host app** (Phoenix already
has it). SquirrElix itself does not add an Ecto dependency.

## Layout in a Phoenix app

Place `sql/` directories next to the contexts that own the queries — same convention
as [Getting Started](getting_started.md):

```txt
lib/my_app/accounts/sql/*.sql  →  lib/my_app/accounts/sql.ex  (MyApp.Accounts.SQL)
```

Ecto schemas and migrations stay where Phoenix puts them. SquirrElix never reads
those modules; it only needs the **database schema** when you run `--infer`.

## Connection config (`DATABASE_URL`, `PG*`, or `--repo`)

Point SquirrElix at the same database Ecto uses. Any of:

```sh
# Environment (common in CI / runtime.exs)
export DATABASE_URL=postgres://postgres:postgres@localhost:5432/my_app_dev
mix squirrelix.gen --infer

# Or reuse Repo config from config/*.exs (loads via mix app.config)
mix squirrelix.gen --infer --repo MyApp.Repo
```

Precedence (highest first): flags → `--url` → `DATABASE_URL` → `--repo` → `PG*` →
defaults. Prefer secrets in the environment over `--password`. Full SSL /
flag details: [Configuration](configuration.md).

## Migrate, then generate or check

`--infer` prepares each `.sql` file against a live database. Tables and columns
must already exist, or you get `MissingPostgresTable` / `MissingPostgresColumn`.

Recommended local loop:

```sh
mix ecto.migrate
mix squirrelix.gen --infer --repo MyApp.Repo
# optional Repo call sites:
# mix squirrelix.gen --infer --repo MyApp.Repo --runner ecto
```

Then commit both the `.sql` sources and the generated `sql.ex` files.

Check without writing:

```sh
mix ecto.migrate
mix squirrelix.check --infer --repo MyApp.Repo
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
    "sql.gen": ["ecto.migrate", "squirrelix.gen --infer --repo MyApp.Repo"],
    "sql.check": ["ecto.migrate", "squirrelix.check --infer --repo MyApp.Repo"]
  ]
end
```

Add `--runner ecto` to those aliases when you want Repo-first generated modules.

Usage:

```sh
mix sql.gen      # migrate + regenerate sql.ex
mix sql.check    # migrate + verify sql.ex is current
```

## Calling generated modules

### Default: Postgrex connection (`--runner postgrex`)

Generated functions take a `Postgrex.conn()` as the first argument — a pool pid,
named process, or other value accepted by `Postgrex.query!/3` /
`Postgrex.query/3`.

```elixir
alias MyApp.Accounts.SQL

rows = SQL.find_user(conn, 42)
{:ok, rows} = SQL.find_user_ok(conn, 42)
```

### Optional: Ecto Repo (`--runner ecto`)

Regenerate with `--runner ecto` so the first argument is a Repo module. Execution
goes through `Ecto.Adapters.SQL`, which uses the Repo’s checked-out connection
when one is active (transactions and Sandbox).

```sh
mix squirrelix.gen --infer --repo MyApp.Repo --runner ecto
```

```elixir
alias MyApp.Accounts.SQL
alias MyApp.Repo

rows = SQL.find_user(Repo, 42)
{:ok, rows} = SQL.find_user_ok(Repo, 42)

Repo.transaction(fn ->
  # Shares the transaction connection with Ecto.Adapters.SQL
  SQL.insert_event(Repo, user_id, "signed_in")
end)
```

Soft companions (`<name>_ok/arity`) remain additive for both runners.

Pick **one** runner per project (or regenerate when switching): mixing call-site
shapes means regenerating `sql.ex` and updating callers.

## Coexistence with Ecto (intentional)

| Concern | Tool |
| --- | --- |
| Migrations, schema modules, changesets, Multi | Ecto |
| Typed, file-based SQL queries | SquirrElix (`sql/` → `sql.ex`) |
| Runtime execution (default) | Postgrex (`Postgrex.conn()`) |
| Runtime execution (optional Repo runner) | `Ecto.Adapters.SQL` via your Repo |

This split is intentional:

- SquirrElix embraces plain `.sql` files — inspired by
  [Gleam Squirrel](https://github.com/giacomocavalieri/squirrel), with an
  Elixir-native Mix/Hex API.
- Optional Repo support is **connection ownership only** (infer config + SQL
  adapter execution). First-class ORM features remain an **explicit non-goal**
  (see [ROADMAP](https://github.com/scripthungry/squirrelix/blob/main/docs/ROADMAP.md#explicit-non-goals-not-on-the-10-path)).
- Use both in one app: Ecto for schema evolution and CRUD; SquirrElix for
  reviewed SQL that benefits from typed codegen.

## Dialyzer and generated modules

Generated `sql.ex` modules are meant to be Dialyzer-friendly under typical app
flags (`:underspecs`, `:error_handling`, `:unknown`, `:unmatched_returns`). Public
`@spec`s are precise for call sites; shared decode helpers omit underspec'd
contracts. Enabling `:overspecs` / `:specdiffs` may warn about intentional
precision (row types vs `Map.new` success typing) — see
[Types → Dialyzer](types.md#dialyzer).

SquirrElix does not depend on Dialyxir. Add Dialyxir in your Phoenix app if you
want Dialyzer in CI:

```elixir
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
```

## CI with `mix squirrelix.check`

Commit generated `sql.ex` files. In CI, apply migrations, then fail the job when
SQL and generated Elixir drift apart.

**Copy-pasteable workflows** live in
[`examples/github-actions/`](https://github.com/scripthungry/squirrelix/tree/main/examples/github-actions)
(Postgres + `--infer`, and an offline metadata variant). Drop
[`squirrelix-check.yml`](https://github.com/scripthungry/squirrelix/blob/main/examples/github-actions/squirrelix-check.yml)
into your app’s `.github/workflows/` or merge the job into an existing pipeline.

Example GitHub Actions job fragment (Postgres service + Mix):

```yaml
services:
  postgres:
    image: postgres:17
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
  - uses: actions/checkout@v7
  # setup-beam, mix deps.get, compile, … as usual

  - name: Create and migrate database
    run: |
      mix ecto.create --quiet
      mix ecto.migrate

  - name: Check SquirrElix generated modules
    run: mix squirrelix.check --infer
```

Notes:

- `MIX_ENV=test` requires `squirr_elix` in the `:test` dependency list.
- Prefer `DATABASE_URL` (or the `sql.check` alias) so connection settings stay
  consistent with hosted Phoenix configs.
- Generation is project-wide atomic: any query error or write-prepare failure
  refuses the whole generate; check fails globally on errors or drift. See
  [Configuration](configuration.md#atomic-generate-and-check).
- Prefer live `--infer` when CI can run Postgres. Prefer a committed metadata
  file from `--write-metadata` when jobs cannot reach the database — see
  [Configuration](configuration.md#exporting-inferred-metadata) and
  [`squirrelix-check-offline.yml`](https://github.com/scripthungry/squirrelix/blob/main/examples/github-actions/squirrelix-check-offline.yml).

A shorter variant when aliases are defined:

```yaml
- run: mix ecto.create --quiet
- run: mix sql.check
```

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `MissingPostgresTable` / column | Migrations not applied | `mix ecto.migrate` before `--infer` |
| `CannotConnectToPostgres` | Wrong host/ creds / SSL | Align `DATABASE_URL` / `PG*` / `--repo` with Repo; see [Configuration](configuration.md) |
| `Invalid --repo` / config unavailable | Repo not compiled or no `config/0` | Pass `MyApp.Repo`; ensure `mix app.config` can load the app |
| `OutdatedFile` in CI | Forgot to regenerate | Run `mix sql.gen` (or `mix squirrelix.gen --infer`) and commit `sql.ex` |
| Check passes locally, fails in CI | Different database / env | Use the same URL shape; create + migrate in CI before check |

## Next steps

- [Getting Started](getting_started.md) — first query walkthrough
- [Writing Queries](writing_queries.md) — naming, comments, nullable parameters
- [Configuration](configuration.md) — SSL, metadata mode, programmatic API
- [Types](types.md) — Postgres → Elixir mapping
- [Adopter CI workflows](https://github.com/scripthungry/squirrelix/tree/main/examples/github-actions) — full GitHub Actions YAML
