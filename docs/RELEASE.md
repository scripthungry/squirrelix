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

1. Create / log into https://hex.pm (same identity you want as package owner).
2. Auth locally once: `mix hex.user auth` (OAuth device flow).
3. Create a **user API key** in the Hex dashboard (CLI no longer has `hex.user key`):
   - Open https://hex.pm/dashboard/keys
   - **Generate new key**
   - Name: e.g. `squirrelix-github-actions`
   - Permissions: enable **API** write (needed for `mix hex.publish`)
   - Copy the key immediately — Hex only shows it once
4. Add it as a GitHub Actions secret:

```sh
gh secret set HEX_API_KEY --repo scripthungry/squirrelix
# paste the key when prompted
```

First publish claims the public package name `squirr_elix` for that Hex user.

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
