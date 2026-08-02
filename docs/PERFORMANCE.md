# SquirrElix performance

This document is the source of truth for how we measure codegen and runtime
cost, how we avoid silent regressions, and what to record after an
implementation round. It lives under hand-written [`docs/`](README.md)
(alongside the release checklist); user guides stay in `guides/`, and
generated ExDoc output goes to gitignored `doc/`.

SquirrElix has **two** performance surfaces:

| Surface | When it runs | Who feels it |
| --- | --- | --- |
| **Codegen / check** | `mix squirrelix.gen`, `mix squirrelix.check`, CI check jobs | Developers and CI wall-clock |
| **Runtime** | Generated `sql.ex` encode → Postgrex → decode | Production request paths |

Optimise the surface you are changing. Do not trade runtime cost for a slightly
faster generator unless the change is clearly justified.

## Suites

Run locally (after `mix compile`):

```sh
mix bench
```

That alias runs `bench/micro.exs`: microbenchmarks for SQL stripping / parameter
name inference, drift-token comparison, module generation on fixture SQL, and
`Output.prepare_write/3` with and without formatting. It prints wall-clock
medians via `:timer.tc/1` (no extra Hex dependency).

Optional deeper suites (add when needed):

| Suite | Measures | Needs Postgres? |
| --- | --- | --- |
| `bench/micro.exs` | Hot pure functions + fixture codegen + write path | No |
| `bench/inference.exs` (future) | Prepare + EXPLAIN + OID/catalog lookups per query | Yes |
| `bench/runtime.exs` (future) | Encode/decode of fixture `Postgrex.Result` rows | No |

Prefer **Benchee** (`only: :dev`) if you need statistical iterations, memory
measurements, or HTML reports. Keep `mix bench` runnable without Benchee so the
default gate stays lightweight.

## Baselines

- Store **relative** baselines, not absolute CI wall-clocks. Absolute times vary
  by machine, BEAM version, and GitHub runner load.
- Commit machine-agnostic artefacts under `bench/baselines/` only when a suite
  produces stable ratios (e.g. “decode 1000×10 rows / decode 100×10 rows”).
- For local work, paste before/after `:timer.tc` or Benchee medians into the PR
  description or CHANGELOG when a change is performance-motivated.

## What to record

Record **meaningful** before→after results only:

- Clear improvements (e.g. order-of-magnitude or sustained multi-iteration wins)
- Intentional trade-offs or regressions that reviewers need to know about

Do **not** document noise: unchanged medians, sub-noise jitter, or “control”
rows that do not aid decision-making. Once a change has solid after numbers,
drop transitional noise commentary from this file.

## CI policy

| Job | When | Gate? |
| --- | --- | --- |
| Unit / integration tests | Every PR | Hard fail |
| `mix bench` micro suite | Quality matrix cell (Elixir 1.20): run and post summary | Soft only — never fails the job |
| Inference e2e benches | Nightly with Postgres service (future) | Soft warning only |

**Default for hot-path PRs:** run `mix bench` locally before and after changes to
codegen, inference, or generated runtime helpers; note meaningful wins or
trade-offs in `CHANGELOG.md` and under **Recorded improvements** below.

Do **not** fail PR CI on absolute millisecond thresholds. Timing noise on shared
runners makes hard gates flaky. Mirror the coverage soft-floor pattern: emit a
job summary (and, once relative baselines exist, a `::warning::` when a median
worsens beyond ~15–20% across several iterations), and investigate before
hardening.

Cache Mix deps/`_build` as today; do not cache bench result files as a
correctness signal.

## Process for each implementation round

1. Identify whether the change touches **codegen**, **inference**, or
   **generated runtime** helpers (`Squirrelix.Codegen.Runtime`).
2. Run `mix bench` **before** changing hot paths (capture medians).
3. Implement; run `mix precommit` (correctness first).
4. Run `mix bench` again under comparable conditions.
5. If there is a meaningful win, intentional trade-off, or regression, note it in
   `CHANGELOG.md` and under **Recorded improvements** below. Skip noise.
6. Avoid performance regressions; call out improvements. Do not expand scope to
   “make it faster” without a measured baseline.

## Hot paths to watch

Codegen / check:

- `Squirrelix.SQL.infer_parameter_names/1` and `single_statement?/1` (charlist
  strip + regex scans). On `--infer`, `Query.from_file/1` and
  `Postgres.infer/2` both call `single_statement?/1` today — strip twice.
- `Squirrelix.Postgres.infer/2` (sequential prepare, EXPLAIN, OID/type lookup,
  catalog nullability). `Postgres.inferrer/1` memoises OID→type and column
  nullability catalog results for the lifetime of the returned function.
- `Squirrelix.Codegen.generate_module/3` (`Code.format_string!/1` once) and
  `Output.prepare_write/3` with `format: false` on the codegen write path
- `Squirrelix.compare_code_snippets/2` (full-module tokenize for drift check)

Runtime (generated modules):

- `encode_value/2` per parameter
- `decode_rows/2` → `decode_row/2` (`Enum.zip` + `Map.new` per row)
- UUID / JSON encode–decode helpers when those types appear

## Recorded improvements

### 2026-08-02 — format-once + catalog memoisation

Local measurements (50 iterations, median µs) on the same machine immediately
before and after the hot-path changes:

| Metric | Before | After | Delta |
| --- | --- | --- | --- |
| `Output.prepare_write` on formatted `.ex` | 453 (`format: true`, previous codegen path) | 5 (`format: false`, new codegen path) | **~90×** write-path format cost removed |

What landed:

- **Format-once:** `Codegen.prepare_directory/4` passes `format: false` into
  `Output.prepare_write/3` because `generate_module/3` already ran
  `Code.format_string!/1`. Default `format: true` remains for other writers.
- **OID / catalog memoisation:** `Postgres.inferrer/1` keeps a process-local
  cache of OID→Elixir type and `{schema, table, column}` → `attnotnull` for the
  lifetime of the inferrer closure. `Postgres.infer/2` (tests / one-shot) still
  uses a fresh cache per call.
- **Column sources:** plan column sources use `List.to_tuple/1` so nullability
  lookup is O(1) per column instead of `Enum.at/2`.

OID/catalog round-trip wins need a live-Postgres inference suite
(`bench/inference.exs`); they are not visible in `bench/micro.exs`.
