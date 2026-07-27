# Configuration

Squirrelix is intentionally minimal: convention over configuration. This guide
covers the two query sources (Postgres inference and metadata files), connection
settings, Mix task options, and the programmatic API.

## Query sources

Every generation or check pass needs type information for each query. Squirrelix
accepts one of two sources:

| Mode | When to use | How to enable |
| --- | --- | --- |
| **Postgres inferrer** | Schema is available locally or in CI | `--infer` |
| **Metadata file** | No database at generation time | Default (requires `squirr_elix.exs`) |

Both `mix squirrelix.gen` and `mix squirrelix.check` use the same source for a
given invocation.

## Postgres inference

Pass `--infer` to connect to a live database and read types from Postgrex prepare
metadata:

```sh
mix squirrelix.gen --infer --database my_app_dev
```

The database must exist, be reachable, and have the schema your queries reference
(migrations applied).

### Multi-schema and `search_path`

`--infer` uses the **session** Postgres connection: it does not set `search_path`
itself, and there is no CLI flag for it. Unqualified table names resolve the same
way they would in `psql` for that role — via
[`search_path`](https://www.postgresql.org/docs/current/ddl-schemas.html#DDL-SCHEMAS-PATH)
/`current_schemas(true)`. Schema-qualified names (`app.users`) resolve that
schema regardless of `search_path`.

Practical guidance:

- Prefer **schema-qualified** table names in `.sql` files when objects live outside
  `public`, so codegen and runtime see the same relation even if role defaults differ.
- If you rely on unqualified names, ensure the role used for
  `mix squirrelix.gen --infer` / `mix squirrelix.check --infer` has the same
  `search_path` as production (database/role `ALTER ... SET search_path`, or a
  connection that already applies it).
- Temporary tables (`pg_temp`) are resolved like ordinary Postgres sessions.

Intentional gaps (out of scope):

- Squirrelix does not migrate objects across schemas or rewrite SQL to add qualifiers.
- Cross-database federation is unsupported.
- Connection options do not expose a `search_path` override; configure it in Postgres
  (or qualify names in SQL) instead.

Nullability for schema-qualified and `search_path`-resolved columns is covered in
[Writing Queries](writing_queries.md#nullable-result-columns).

If connection fails, Squirrelix reports a structured error (refused host/port,
timeout, invalid credentials, or missing database) with hints for `PG*` variables
and Mix flags. Timeouts are reported separately from other connection failures.
When you cannot reach Postgres at generation time, use a metadata file instead of
`--infer` (see below).

### Connection URL

Prefer putting secrets in the environment (`PGPASSWORD` / `DATABASE_URL`) rather
than in a URL or `--password` flag — both appear in process listings and shell
history.

Phoenix-style apps can rely on `DATABASE_URL` with no extra flags:

```sh
export DATABASE_URL=postgres://user:pass@host:5432/database?sslmode=require
mix squirrelix.gen --infer
```

Or pass an explicit URL:

```sh
mix squirrelix.gen --infer \
  --url postgres://user@host:5432/database?connect_timeout=5&sslmode=require
```

Supported URL schemes: `postgres://` and `postgresql://`.

The `connect_timeout` query parameter sets the connection timeout in seconds.

SSL query parameters:

| Parameter | Postgrex `:ssl` |
| --- | --- |
| `sslmode=disable` | `false` |
| `sslmode=allow` / `prefer` | `false` (Postgrex cannot negotiate SSL fallback) |
| `sslmode=require` / `ssl=true` | `[verify: :verify_none]` (encrypt; no CA check) |
| `sslmode=verify-ca` / `verify-full` | `true` (Postgrex secure defaults) |
| `ssl=false` | `false` |

Unix sockets are not supported.

`--infer` runs your `.sql` files against a real database (prepare + EXPLAIN). Only
point it at trusted SQL and a database you intend to use for codegen.

### Environment variables

Squirrelix reads `DATABASE_URL` (when set) and standard
[libpq environment variables](https://www.postgresql.org/docs/current/libpq-envars.html):

| Variable | Default |
| --- | --- |
| `DATABASE_URL` | _(unset — fall back to `PG*`)_ |
| `PGHOST` | `localhost` |
| `PGPORT` | `5432` |
| `PGUSER` | `postgres` |
| `PGDATABASE` | `postgres` |
| `PGPASSWORD` | `""` |
| `PGCONNECT_TIMEOUT` | `5` (seconds) |
| `PGSSLMODE` | _(no SSL)_ |

`PGSSLMODE` uses the same mapping as URL `sslmode` above. A URL `sslmode` /
`ssl` parameter overrides `PGSSLMODE`.

Example with `direnv`:

```sh
# .envrc
export DATABASE_URL=postgres://postgres@localhost:5432/my_app_dev
# or:
export PGDATABASE=my_app_dev
export PGUSER=postgres
export PGPASSWORD=secret
```

```sh
direnv allow
mix squirrelix.gen --infer
```

Squirrelix does not read `.env` files directly. Use your shell, `direnv`, or
similar tools to load environment variables.

### CLI flags

```sh
mix squirrelix.gen --infer \
  --hostname db.example.com \
  --port 5433 \
  --username app \
  --database my_app_dev
```

Connection precedence (highest first): flags → `--url` → `DATABASE_URL` → `PG*`
environment variables → defaults. Prefer `PGPASSWORD` / `DATABASE_URL` over
`--password`.

## Metadata files

When `--infer` is not passed, Squirrelix loads a metadata file that maps query file
paths to parameter and return type descriptors.

Default path: `squirr_elix.exs` in the project root.

Custom path:

```sh
mix squirrelix.gen --metadata config/squirr_elix.exs
mix squirrelix.check --metadata config/squirr_elix.exs
```

### Exporting inferred metadata

Some CI jobs cannot reach Postgres. Capture types once with `--infer`, then run
offline check from the written metadata file:

```sh
# Locally or in a migrate job with Postgres available:
mix squirrelix.gen --infer --database my_app_dev --write-metadata squirr_elix.exs

# Later, offline (no database):
mix squirrelix.check
# or:
mix squirrelix.check --metadata squirr_elix.exs
```

`--write-metadata PATH` requires `--infer`. It writes after a successful inference
pass (all queries typed with no errors) and overwrites `PATH`. Commit the file if
offline CI should use it.

The export is ordinary evaluated Elixir in the same shape as a hand-written
metadata file — treat it like `mix.exs` and never load untrusted paths.

### Format

The file is **evaluated as Elixir** (like `mix.exs`) and must return a map. Only
load trusted, project-local metadata — never evaluate untrusted paths.

```elixir
%{
  "lib/my_app/accounts/sql/find_user.sql" => [
    params: [:integer],
    returns: [
      %{name: "id", type: :integer, nullable?: false},
      %{name: "name", type: :string, nullable?: false},
      %{name: "email", type: :string, nullable?: true}
    ]
  ],

  "lib/my_app/accounts/sql/delete_user.sql" => [
    params: [:integer],
    returns: []
  ]
}
```

Keys are project-relative or absolute paths to `.sql` files. Values are keyword lists
with:

- `:params` — list of type atoms for `$1`, `$2`, ... in order.
- `:returns` — list of column maps with `:name`, `:type`, and `:nullable?` keys.
  Use `returns: []` for command queries with no returned rows.

See [Types](types.md) for the supported type atoms.

Every discovered `.sql` file must have a metadata entry, or generation fails with
`MissingQueryMetadata`.

## Mix task options

Both `mix squirrelix.gen` and `mix squirrelix.check` accept:

| Option | Description |
| --- | --- |
| `--metadata PATH` | Metadata file path (default: `squirr_elix.exs`) |
| `--infer` | Infer types from Postgres instead of metadata |
| `--write-metadata PATH` | Write inferred types to a metadata file (requires `--infer`) |
| `--url URL` | Postgres connection URL |
| `--database NAME` | Database name |
| `--hostname HOST` | Database host |
| `--username USER` | Database user |
| `--password PASS` | Database password (prefer `PGPASSWORD`) |
| `--port PORT` | Database port |

`mix squirrelix.gen` also accepts:

| Option | Description |
| --- | --- |
| `--watch` | After the initial generate, watch `{lib,test,dev}/**/sql/*.sql` and regenerate on change |

## Watch mode

While editing queries, keep generation in sync without re-running the Mix task by hand:

```sh
mix squirrelix.gen --watch
mix squirrelix.gen --infer --watch
mix squirrelix.gen --metadata config/squirr_elix.exs --watch
```

Watch mode:

1. Runs a normal generate once (same query source and connection options as without `--watch`).
2. Watches existing `lib/`, `test/`, and `dev/` trees for changes to `.sql` files that live
   directly in a `sql/` directory.
3. Debounces rapid editor events, then regenerates.
4. Logs success or failure for each regenerate; failures do **not** stop the watcher.
5. Stops cleanly on Ctrl-C.

`--watch` is not supported by `mix squirrelix.check` (use check in CI for drift detection).

On Linux, watch mode needs [inotify-tools](https://github.com/rvoicilas/inotify-tools/wiki)
(e.g. `apt install inotify-tools`). macOS and Windows use built-in file-system backends.

## Programmatic API

### Supported public API

Pre-1.0, only the following are part of the **supported** programmatic surface.
Anything else under `Squirrelix.*` is internal (`@moduledoc false`) and may
change without a SemVer bump before 1.0.

| Surface | Role |
| --- | --- |
| `Squirrelix.generate/3` | Generate `sql.ex` modules for a project root |
| `Squirrelix.check/3` | Drift-check without writing files |
| `Squirrelix.CodegenSummary` / `CodegenCheckSummary` | Return values from generate / check |
| `mix squirrelix.gen` / `mix squirrelix.check` | Supported Mix task entry points |
| `Squirrelix.Error.*` structs | Pattern-matchable diagnostics in summaries |
| `Squirrelix.Error.format/1` / `format_all/1` | Render the same text Mix prints |
| `Squirrelix.Postgres.inferrer/1` | Live-Postgres query source for generate / check |
| `Squirrelix.Inference.Inferrer` | Behaviour for custom query sources |
| `Squirrelix.Query` | Struct passed to Inferrer callbacks (fields only) |

Do **not** expand the public surface silently: new modules or functions intended
for adopters need docs (module/`@doc`, README / this guide) in the same change.

### Usage

Use `Squirrelix.generate/3` and `Squirrelix.check/3` from Elixir code:

```elixir
# Metadata map
metadata = %{
  "/path/to/lib/my_app/sql/find_user.sql" => [
    params: [:integer],
    returns: [%{name: "name", type: :string, nullable?: false}]
  ]
}

Squirrelix.generate("/path/to/project", metadata, version: "v0.5.1")

# Postgres inferrer (function or module implementing Squirrelix.Inference.Inferrer)
{:ok, conn} = Postgrex.start_link(database: "my_app_dev")

try do
  Squirrelix.generate("/path/to/project", Squirrelix.Postgres.inferrer(conn),
    version: "v0.5.1"
  )
after
  GenServer.stop(conn)
end
```

Options:

- `:version` (required) — version string written into generated file headers.
- `:postgrex` — module passed to generated code (defaults to `Postgrex`).

Returns:

- `Squirrelix.generate/3` → `%Squirrelix.CodegenSummary{}`
- `Squirrelix.check/3` → `%Squirrelix.CodegenCheckSummary{}`

## CI setup

A typical CI step runs the check task after migrations:

```yaml
- name: Apply migrations
  run: mix ecto.migrate

- name: Check Squirrelix output
  env:
    PGDATABASE: my_app_test
    PGHOST: localhost
    PGUSER: postgres
  run: mix squirrelix.check --infer
```

When some jobs cannot reach Postgres, export metadata where the database is
available and check offline elsewhere:

```yaml
- name: Export Squirrelix metadata
  env:
    PGDATABASE: my_app_test
    PGHOST: localhost
    PGUSER: postgres
  run: mix squirrelix.gen --infer --write-metadata squirr_elix.exs

# In a later job without Postgres:
- name: Check Squirrelix output (offline)
  run: mix squirrelix.check
```

Commit generated `sql.ex` files (and the exported metadata file, when using offline
check) alongside your `.sql` sources so CI verifies they stay in sync.

Prefer live `--infer` whenever CI can run Postgres (it catches catalog drift). Use
exported metadata only when the job has no database — and refresh
`squirr_elix.exs` when queries or the schema change.

**Copy-pasteable GitHub Actions workflows** for adopters:

- [`examples/github-actions/squirrelix-check.yml`](https://github.com/scripthungry/squirrelix/blob/main/examples/github-actions/squirrelix-check.yml)
  — Postgres service + `DATABASE_URL` + `mix squirrelix.check --infer`
- [`examples/github-actions/squirrelix-check-offline.yml`](https://github.com/scripthungry/squirrelix/blob/main/examples/github-actions/squirrelix-check-offline.yml)
  — offline check from committed metadata

For Phoenix apps — Mix aliases, `DATABASE_URL`, and cookbook context — see the
[Phoenix + CI Cookbook](phoenix.md#ci-with-mix-squirrelix-check).

## Safe overwrite rules

Squirrelix only overwrites files whose header contains the Squirrelix generation
marker (written into `@moduledoc`). If a `sql.ex` file exists without that header
marker, generation fails with `CannotOverwriteFile`.

During check, an outdated generated file produces `OutdatedFile`.

## Atomic generate and check

Code generation is **project-wide atomic** (Gleam squirrel 4.5+ parity):

1. **Query-error atomicity** — If any `sql/` directory has query errors (invalid
   file names, missing metadata, inference failures, unsupported types, and so
   on), `mix squirrelix.gen` writes **nothing**. Directories that would otherwise
   succeed are left untouched until every error is fixed.
2. **Write-pass atomicity** — When every directory is query-valid, Squirrelix
   prepares all `sql.ex` writes first. If any prepare fails (for example
   `CannotOverwriteFile`), nothing is written. Successful commits use temp files
   + rename, and roll back earlier renames if a later one fails mid-pass.

`mix squirrelix.check` fails globally when any directory has query errors or
generated-file drift. Errors from every failing directory are reported together;
a single bad directory is enough for a non-zero exit.

## Next steps

- [Getting Started](getting_started.md) — first query walkthrough
- [Phoenix + CI Cookbook](phoenix.md) — Phoenix Mix aliases and CI
- [Adopter CI workflows](https://github.com/scripthungry/squirrelix/tree/main/examples/github-actions) — copy-pasteable GitHub Actions
- [Types](types.md) — type mapping reference
