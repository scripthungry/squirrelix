# Release checklist (Squirrelix / squirr_elix)

## Naming

| Layer | Name |
| --- | --- |
| Brand / Elixir modules | `Squirrelix` |
| Mix tasks | `mix squirrelix.gen`, `mix squirrelix.check` |
| Hex package / OTP app | `squirr_elix` |
| GitHub repo | `scripthungry/squirrelix` |
| Metadata file (default) | `squirr_elix.exs` |

## One-time setup

### 1. GitHub

Repo is at https://github.com/scripthungry/squirrelix (public). Local remote:

```sh
git remote set-url origin https://github.com/scripthungry/squirrelix.git
```

### 2. Hex account + API key

1. Create / log into https://hex.pm (use the same identity you want as package owner).
2. Confirm you can claim package name `squirr_elix` (first publish wins the name).
3. Create an **organization or user API key** with permission to publish:
   - Hex → Accounts → API keys → New API key
   - Or: `mix hex.user key generate`
4. Add the key as a **GitHub Actions secret** on `scripthungry/squirrelix`:
   - Name: `HEX_API_KEY`
   - Value: the Hex API key (not your password)

```sh
gh secret set HEX_API_KEY --repo scripthungry/squirrelix
# paste the key when prompted
```

### 3. Postgres for local / CI

CI starts Postgres 16 with:

- `PGUSER=postgres`
- `PGPASSWORD=postgres`
- `PGDATABASE=postgres`

Locally, `mix test` expects a reachable Postgres (often peer auth as your OS user for
`--database postgres` tests). Match CI with:

```sh
export PGHOST=localhost PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres
```

## Publishing a release

1. Ensure `mix.exs` `@version` and `CHANGELOG.md` are updated.
2. Push to `main` and wait for CI green.
3. Tag and push:

```sh
git tag v0.1.0
git push origin v0.1.0
```

4. The **Hex Publish** workflow runs on `v*` tags and publishes with `HEX_API_KEY`.
5. Confirm https://hex.pm/packages/squirr_elix and https://hexdocs.pm/squirr_elix

Manual publish (emergency): Actions → Hex Publish → Run workflow → type `publish`.

## Do not commit

- Hex API keys
- Database passwords
- `erl_crash.dump` (already gitignored)
