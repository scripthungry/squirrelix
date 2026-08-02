# Project documentation

Hand-written docs for maintainers and contributors. These are tracked in git.

| Path | Audience | On HexDocs? |
| --- | --- | --- |
| [PERFORMANCE.md](PERFORMANCE.md) | Contributors / CI policy | Yes (`mix docs` extra) |
| [RELEASE.md](RELEASE.md) | Maintainers (ship / Hex publish) | No |

## Related trees (do not merge)

| Directory | Role |
| --- | --- |
| **`docs/`** | This folder — hand-written project docs |
| **`guides/`** | User-facing guides shipped as ExDoc extras |
| **`doc/`** | Generated ExDoc HTML/Markdown (Elixir default; **gitignored**) |
| **`bench/`** | Benchmark scripts (`mix bench` → `bench/micro.exs`) |

`doc/` is the Mix/ExDoc output directory. Do not rename it or fold it into
`docs/` unless `mix.exs` `docs:` is updated accordingly. Run `mix docs` to
regenerate; browse HexDocs at <https://hexdocs.pm/squirr_elix>.

Root files such as `README.md`, `CHANGELOG.md`, and `ROADMAP.md` stay at the
repository root (Hex / ExDoc convention).
