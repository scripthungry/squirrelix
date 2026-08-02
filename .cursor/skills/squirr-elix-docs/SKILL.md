---
name: squirr-elix-docs
description: >-
  Applies SquirrElix documentation branding and British English conventions for
  README, guides, CHANGELOG, docs/ROADMAP, NOTICE, and moduledocs. Use when editing
  docs or guides, renaming the library in prose, fixing capitalisation, or when
  the user mentions SquirrElix branding, British English, or documentation style.
---

# SquirrElix documentation conventions

## Naming

| Layer | Form | Examples |
| --- | --- | --- |
| Brand (prose, Hex display name) | **SquirrElix** | README, guides, `@moduledoc`, CHANGELOG |
| Hex package / OTP app | `squirr_elix` | `{:squirr_elix, "~> …"}`, hex.pm URL |
| Elixir modules | `Squirrelix` | `Squirrelix.gen/1`, `Squirrelix.Error` |
| Mix tasks | `squirrelix.*` | `mix squirrelix.gen`, `mix squirrelix.check` |
| GitHub repo | `squirrelix` | `scripthungry/squirrelix` |
| Metadata file | `squirr_elix.exs` | default metadata path |

**Rule:** In documentation prose use **SquirrElix**. Do **not** rewrite package names, module names, Mix task names, file names, or code identifiers.

Wrong: "Squirrelix is a type-safe SQL library" (prose)  
Right: "SquirrElix is a type-safe SQL library" / still `mix squirrelix.gen` in code fences

## British English

Prefer British spelling in docs/guides/README/moduledocs where natural:

- organise, optimise, behaviour, favour, colour, centred, modelled
- "licence" only when meaning the legal sense in prose; keep **Apache License** and SPDX/`Apache-2.0` as proper nouns/identifiers

**Do not change:**

- Postgres / PostgreSQL technical terms (e.g. **catalog**, schema names)
- Code, SQL, identifiers, URLs, badge labels that are fixed upstream
- Quoted upstream project names and APIs

## Scope

Apply when editing: `README.md`, `guides/**`, `docs/**` (including `ROADMAP.md`),
`CHANGELOG.md`, `NOTICE`, `@moduledoc` / `@doc` strings.

Do not rename Elixir source modules or Mix task atoms for branding alone.

## Quick checks

- [ ] Prose brand is SquirrElix (capital E)
- [ ] Hex/`mix`/module references unchanged where they are code
- [ ] British spelling in new or touched prose
- [ ] Postgres "catalog" and Apache License left intact
