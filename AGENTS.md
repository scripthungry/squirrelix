# AGENTS.md

## Cursor Cloud specific instructions

SquirrElix (`squirr_elix`) is an Elixir **library + Mix codegen tool** (no long-running app
server). Development means compiling, testing, linting, and exercising the `mix squirrelix.*`
tasks. Standard workflow commands live in [`README.md`](README.md) and
[`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) (`mix precommit`, `mix ci`, `mix test`,
`mix bench`) — use those rather than duplicating them here.

### Toolchain
- Erlang/OTP and Elixir are managed by [mise](https://mise.jdx.dev) using the pins in
  [`mise.toml`](mise.toml) (Elixir `1.20.2-otp-28`, Erlang `28.5`). They are also set as the
  mise global default, and `mise activate` is wired into `~/.bashrc`, so `mix`/`elixir` are on
  `PATH` in fresh shells and from any directory. The startup update script runs
  `mise install` + `mix deps.get`.

### Postgres (must be started each session — not auto-started on boot)
- The full test suite and any `--infer` codegen require a reachable Postgres. Postgres 16 is
  installed but is **not** running automatically after a VM boot/snapshot restore. Start it with:
  `sudo pg_ctlcluster 16 main start`
- Credentials/connection match CI: user `postgres`, password `postgres`, DB `postgres` on
  `localhost:5432`. Export these before running the DB-backed tests or tasks:
  `export PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres`
- Note: local Postgres is **16**; CI uses **17**. The library requires `>= 16` for `--infer`,
  so 16 is fine for local development.
- Most unit tests use mocks and need no DB; a few integration tests (`test/squirrelix_postgres_test.exs`,
  `test/squirrelix_error_isolation_test.exs`) fail the suite if Postgres is unreachable.

### Known environment-dependent test
- `test/mix_tasks_squirrelix_test.exs` "reports structured connection timeouts" can fail in
  this VM. It connects to the blackhole IP `172.31.255.1` expecting a silent packet drop
  (timeout), but that address is inside the VM's own `172.31.x` subnet and returns a
  connection-close instead, so the message says "closed the connection" rather than
  "Connection timed out". This is a networking quirk of the environment, not a code or setup
  bug. Expect `451/452` passing with `mix test`.
