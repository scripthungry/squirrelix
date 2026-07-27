# Adopter GitHub Actions examples

Copy-pasteable workflows for `mix squirrelix.check` in **your** app. This
repository’s own CI is separate; these files are documentation artifacts.

| File | When to use |
| --- | --- |
| [`squirrelix-check.yml`](squirrelix-check.yml) | CI has Postgres: migrate, then `mix squirrelix.check --infer` |
| [`squirrelix-check-offline.yml`](squirrelix-check-offline.yml) | No database in the job: check against committed `squirr_elix.exs` |

## Live infer (recommended when possible)

1. Copy `squirrelix-check.yml` to `.github/workflows/` in your app (or merge the
   job into an existing workflow).
2. Set `DATABASE_URL` (or `PG*`) to the service database.
3. Ensure `squirr_elix` is in Mix deps for `:test`, and commit generated `sql.ex`
   files.
4. Apply schema before check (`mix ecto.create` / `mix ecto.migrate`, or your
   equivalent).

Failure semantics: any query error or `sql.ex` drift fails the whole check with a
non-zero exit (project-wide atomic check).

## Offline metadata

When some jobs cannot reach Postgres, export once where the database is available:

```sh
mix squirrelix.gen --infer --write-metadata squirr_elix.exs
```

Commit that file, then use `squirrelix-check-offline.yml` (or
`mix squirrelix.check --metadata PATH`). Refresh the export when SQL or the
schema changes — offline check does not see live catalog drift.

## Further reading

- [Phoenix + CI Cookbook](../../guides/phoenix.md#ci-with-mix-squirrelix-check)
- [Configuration — exporting metadata](../../guides/configuration.md#exporting-inferred-metadata)
