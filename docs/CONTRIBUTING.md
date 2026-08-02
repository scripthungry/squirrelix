# Contributing to SquirrElix

Thin maintainer / contributor notes. End-user docs live in [`guides/`](../guides/)
and the root [README](../README.md).

## Tool versions

Pins for local development are in [`mise.toml`](../mise.toml) (Elixir **1.20.2** on
OTP **28.5**, matching the CI quality cell). With [mise](https://mise.jdx.dev):
`mise install`.

## Local validation

```sh
mix precommit
```

(`mix precommit` compiles with `--warnings-as-errors`, then runs `mix format`,
`mix credo --strict --all`, and `mix test`.)

Full quality gate used on the Elixir 1.20 CI cell (also Dialyzer, ExDNA, Reach,
ExSlop Credo checks):

```sh
mix ci
```

GitHub Actions compiles and tests on Elixir **1.18**, **1.19**, and **1.20**; every
matrix cell is a hard gate.

## Performance

When a change touches codegen, inference, or generated runtime helpers, run
`mix bench` before and after and note only meaningful wins or trade-offs in
[`PERFORMANCE.md`](PERFORMANCE.md) (and `CHANGELOG.md` when shipping). Soft CI only —
never hard-fail on absolute timings.

## Releases and roadmap

* [RELEASE.md](RELEASE.md) — Hex publish checklist
* [ROADMAP.md](ROADMAP.md) — path to 1.0 and non-goals
