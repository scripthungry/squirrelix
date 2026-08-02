# SquirrElix Roadmap

SquirrElix is an independent Elixir library that reimplements
[Gleam Squirrel](https://github.com/giacomocavalieri/squirrel)'s core SQL discovery,
inference, and codegen ideas with an idiomatic **Elixir-native** public API (Mix, Hex,
ExDoc, Postgrex, stdlib typespecs). It is not affiliated with, endorsed by, or
maintained by the Gleam Squirrel project.

Gleam Squirrel remains a behavioural reference for query conventions and edge-case tests;
Elixir conventions take precedence for API shape, `@spec` output, and runtime return
values. The product goal is a solid Elixir/OTP typed-SQL helper — not a line-by-line
Gleam clone.

**Elixir-native direction:** generated modules use stdlib typespecs (`String.t()`,
`integer()`, `map()` with `required/1`, `term()` for JSON, and so on). SquirrElix does
**not** generate Gleam records, custom enum ADTs, or opaque tagged error values.

## Shipped (0.x → current 0.5.x)

Core product surface is in place: query discovery and parsing, parameter naming,
Postgres `--infer` (nullability, multi-schema / `search_path`, structured errors),
Elixir-native type mapping (including reject-with-hints for composites / ranges /
unsupported built-ins), codegen (row maps, soft `_ok` companions, Dialyzer-oriented
`@spec`s, atomic generate/check), Mix tasks (metadata, `DATABASE_URL` / SSL, watch,
`--write-metadata`), programmatic `generate/3` / `check/3`, Hex package, user guides,
and adopter CI examples.

Point-release history and detailed notes live in [`CHANGELOG.md`](../CHANGELOG.md).
GitHub issues record individual slices.

## Remaining (path to 1.0)

GitHub is the source of truth for open work: [project board](https://github.com/orgs/scripthungry/projects/1)
and the milestone below. **1.0** means production-ready typed SQL codegen for
Elixir/Phoenix — an Elixir-appropriate reimplementation with Gleam-inspired query
conventions where intentional — plus a SemVer stability promise. It is **not** infinite
feature creep or a checklist of remaining Gleam APIs.

### [v1.0.0](https://github.com/scripthungry/squirrelix/milestone/5) — Stability promise

1.0 is a **stability / SemVer promise**. Prep work below can finish on schedule;
**shipping is blocked on adoption** — do not tag until meaningful real-world usage /
feedback validates the API (maintainer judgement). Completing #23–#26 is necessary but
**not sufficient** without that gate (#28).

- [ ] SemVer / stability / deprecation policy (#23) — includes formal deprecation mechanism
- [ ] Non-goals freeze verified (ROADMAP canonical; #24)
- [ ] Docs freeze and HexDocs polish (#25)
- [x] Prune internal APIs before 1.0 (#52)
- [ ] Adoption / feedback gate: sufficient real-world users (#28)
- [ ] Ship via [`docs/RELEASE.md`](RELEASE.md) (#26) — after maintainer confirms #28

### Explicit non-goals (not on the 1.0 path)

This section is the **canonical** freeze list for 1.0. These are intentional product
boundaries (not “not yet”):

- Composites as nested modules
- First-class ranges / geometric / network / `interval`
- Gleam-style enum ADTs
- Catalog-inferred nullable parameters
- Unix sockets
- PostGIS
- ULID
- First-class Ecto `Repo` integration
- Built-in SQL formatter

Guides may link here for scope (FAQ, Types reject-with-hints, Phoenix + Ecto) without
re-listing every item. Freeze verification is tracked in #24.

## Validation discipline

See [Contributing](CONTRIBUTING.md) for `mix precommit`, `mix ci`, and the
[performance](PERFORMANCE.md) bench loop on hot-path changes.
