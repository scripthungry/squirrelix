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

If connection fails, Squirrelix reports a structured error (refused host/port,
timeout, invalid credentials, or missing database) with hints for `PG*` variables
and Mix flags. Timeouts are reported separately from other connection failures.
When you cannot reach Postgres at generation time, use a metadata file instead of
`--infer` (see below).

### Connection URL

Prefer putting secrets in the environment (`PGPASSWORD`) rather than in a URL or
`--password` flag — both appear in process listings and shell history.

```sh
mix squirrelix.gen --infer \
  --url postgres://user@host:5432/database?connect_timeout=5
```

Supported URL schemes: `postgres://` and `postgresql://`.

The `connect_timeout` query parameter sets the connection timeout in seconds.

`--infer` runs your `.sql` files against a real database (prepare + EXPLAIN). Only
point it at trusted SQL and a database you intend to use for codegen.

### Environment variables

Squirrelix reads standard
[libpq environment variables](https://www.postgresql.org/docs/current/libpq-envars.html):

| Variable | Default |
| --- | --- |
| `PGHOST` | `localhost` |
| `PGPORT` | `5432` |
| `PGUSER` | `postgres` |
| `PGDATABASE` | `postgres` |
| `PGPASSWORD` | `""` |
| `PGCONNECT_TIMEOUT` | `5` (seconds) |

Example with `direnv`:

```sh
# .envrc
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

Connection precedence (highest first): CLI flags → `--url` → `PG*` environment
variables → defaults. Prefer `PGPASSWORD` over `--password`.

## Metadata files

When `--infer` is not passed, Squirrelix loads a metadata file that maps query file
paths to parameter and return type descriptors.

Default path: `squirr_elix.exs` in the project root.

Custom path:

```sh
mix squirrelix.gen --metadata config/squirr_elix.exs
mix squirrelix.check --metadata config/squirr_elix.exs
```

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
| `--url URL` | Postgres connection URL |
| `--database NAME` | Database name |
| `--hostname HOST` | Database host |
| `--username USER` | Database user |
| `--password PASS` | Database password (prefer `PGPASSWORD`) |
| `--port PORT` | Database port |

## Programmatic API

Use `Squirrelix.generate/3` and `Squirrelix.check/3` from Elixir code:

```elixir
# Metadata map
metadata = %{
  "/path/to/lib/my_app/sql/find_user.sql" => [
    params: [:integer],
    returns: [%{name: "name", type: :string, nullable?: false}]
  ]
}

Squirrelix.generate("/path/to/project", metadata, version: "v0.1.0")

# Postgres inferrer (function or module implementing Squirrelix.Inference.Inferrer)
{:ok, conn} = Postgrex.start_link(database: "my_app_dev")

try do
  Squirrelix.generate("/path/to/project", Squirrelix.Postgres.inferrer(conn),
    version: "v0.1.0"
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

Commit generated `sql.ex` files alongside your `.sql` sources so CI verifies they
stay in sync.

## Safe overwrite rules

Squirrelix only overwrites files whose header contains the Squirrelix generation
marker (written into `@moduledoc`). If a `sql.ex` file exists without that header
marker, generation fails with `CannotOverwriteFile`.

During check, an outdated generated file produces `OutdatedFile`.

## Next steps

- [Getting Started](getting_started.md) — first query walkthrough
- [Types](types.md) — type mapping reference
