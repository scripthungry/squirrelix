# Project documentation (maintainers)

Hand-written docs for maintainers and contributors. Tracked in git; **not** the
primary HexDocs surface (user guides ship from `guides/`).

| Path | Audience | On HexDocs? |
| --- | --- | --- |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contributors (local gates) | No |
| [ROADMAP.md](ROADMAP.md) | Maintainers (path to 1.0) | No |
| [PERFORMANCE.md](PERFORMANCE.md) | Contributors / CI policy | No |
| [RELEASE.md](RELEASE.md) | Maintainers (ship / Hex publish) | No |

## Related trees (do not merge)

| Directory | Role |
| --- | --- |
| **`docs/`** | This folder — hand-written maintainer docs |
| **`guides/`** | User-facing guides shipped as ExDoc extras |
| **`doc/`** | Generated ExDoc HTML (Elixir default; **gitignored**) |
| **`bench/`** | Benchmark scripts (`mix bench` → `bench/micro.exs`) |

`doc/` is the Mix/ExDoc output directory. Do not rename it or fold it into
`docs/` unless `mix.exs` `docs:` is updated accordingly. Run `mix docs` to
regenerate; browse HexDocs at <https://hexdocs.pm/squirr_elix>.

Root files for adopters and Hex: `README.md`, `CHANGELOG.md`, `LICENSE`, `NOTICE`.
