# Configuration

SquirrElix is intentionally minimal: convention over configuration. This guide
covers the two query sources (Postgres inference and metadata files), connection
settings, Mix task options, and the programmatic API.

## Query sources

Every generation or check pass needs type information for each query. SquirrElix
accepts one of two sources:

| Mode | When to use | How to enable |
| --- | --- | --- |
| **Postgres inferrer** | Schema is available locally or in CI | `--infer` |
| **Metadata file** | No database at generation time | Default (requires `squirrelixir.exs`) |

Both `mix squirrelixir.gen` and `mix squirrelixir.check` use the same source for a
given invocation.

## Postgres inference

Pass `--infer` to connect to a live database and read types from Postgrex prepare
metadata:

```sh
mix squirrelixir.gen --infer --database my_app_dev
```

The database must exist, be reachable, and have the schema your queries reference
(migrations applied).

### Connection URL

```sh
mix squirrelixir.gen --infer \
  --url postgres://user:password@host:5432/database?connect_timeout=5
```

Supported URL schemes: `postgres://` and `postgresql://`.

The `connect_timeout` query parameter sets the connection timeout in seconds.

### Environment variables

When no URL is provided, SquirrElix reads standard
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
```

```sh
direnv allow
mix squirrelixir.gen --infer
```

SquirrElix does not read `.env` files directly. Use your shell, `direnv`, or
similar tools to load environment variables.

### CLI flags

Individual flags override environment variables:

```sh
mix squirrelixir.gen --infer \
  --hostname db.example.com \
  --port 5433 \
  --username app \
  --password secret \
  --database my_app_dev
```

Flag precedence (highest first): CLI flags → URL parameters → environment variables
→ defaults.

## Metadata files

When `--infer` is not passed, SquirrElix loads a metadata file that maps query file
paths to parameter and return type descriptors.

Default path: `squirrelixir.exs` in the project root.

Custom path:

```sh
mix squirrelixir.gen --metadata config/squirrelixir.exs
mix squirrelixir.check --metadata config/squirrelixir.exs
```

### Format

The file is evaluated as Elixir and must return a map:

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

Both `mix squirrelixir.gen` and `mix squirrelixir.check` accept:

| Option | Description |
| --- | --- |
| `--metadata PATH` | Metadata file path (default: `squirrelixir.exs`) |
| `--infer` | Infer types from Postgres instead of metadata |
| `--url URL` | Postgres connection URL |
| `--database NAME` | Database name |
| `--hostname HOST` | Database host |
| `--username USER` | Database user |
| `--password PASS` | Database password |
| `--port PORT` | Database port |

## Programmatic API

Use `Squirrelixir.generate/3` and `Squirrelixir.check/3` from Elixir code:

```elixir
# Metadata map
metadata = %{
  "/path/to/lib/my_app/sql/find_user.sql" => [
    params: [:integer],
    returns: [%{name: "name", type: :string, nullable?: false}]
  ]
}

Squirrelixir.generate("/path/to/project", metadata, version: "v0.1.0")

# Postgres inferrer (function or module implementing Squirrelixir.Inference.Inferrer)
{:ok, conn} = Postgrex.start_link(database: "my_app_dev")

try do
  Squirrelixir.generate("/path/to/project", Squirrelixir.Postgres.inferrer(conn),
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

- `Squirrelixir.generate/3` → `%Squirrelixir.CodegenSummary{}`
- `Squirrelixir.check/3` → `%Squirrelixir.CodegenCheckSummary{}`

## CI setup

A typical CI step runs the check task after migrations:

```yaml
- name: Apply migrations
  run: mix ecto.migrate

- name: Check SquirrElix output
  env:
    PGDATABASE: my_app_test
    PGHOST: localhost
    PGUSER: postgres
  run: mix squirrelixir.check --infer
```

Commit generated `sql.ex` files alongside your `.sql` sources so CI verifies they
stay in sync.

## Safe overwrite rules

SquirrElix only overwrites files it recognises as previously generated (containing
the SquirrElix generation marker). If a `sql.ex` file exists and was written by
hand, generation fails with `CannotOverwriteFile`.

During check, an outdated generated file produces `OutdatedFile`.

## Next steps

- [Getting Started](getting_started.md) — first query walkthrough
- [Types](types.md) — type mapping reference
