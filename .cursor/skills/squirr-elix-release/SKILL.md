---
name: squirr-elix-release
description: >-
  Ships SquirrElix (squirr_elix) via GitHub issue, PR, project board, merge, tag,
  and Hex publish. Use when the user asks to release, publish to Hex, bump
  version, tag vX.Y.Z, merge and release, add work to the Squirrelix project
  board, or follow docs/RELEASE.md.
---

# SquirrElix release & ship loop

Canonical setup and secrets: [`docs/RELEASE.md`](../../../docs/RELEASE.md).

**Repo:** `scripthungry/squirrelix`  
**Project board:** owner `scripthungry`, project **Squirrelix** `#1`  
**Status options:** Todo · In Progress · Done

## Naming (quick)

| Brand | Package | Modules / Mix |
| --- | --- | --- |
| SquirrElix | `squirr_elix` | `Squirrelix` / `mix squirrelix.*` |

## Full ship checklist

Copy and track:

```
- [ ] GitHub issue created (lean); link with Fixes #N in PR
- [ ] Issue on project #1 → In Progress
- [ ] Branch from latest main
- [ ] Version: mix.exs @version + CHANGELOG (Keep a Changelog)
- [ ] Commit / push / PR
- [ ] PR on project board (optional); issue stays linked
- [ ] CI green
- [ ] Approve (self-approve may fail — ask user if needed)
- [ ] Squash-merge (default unless user says otherwise)
- [ ] Issue → Done
- [ ] Tag vX.Y.Z on main tip; push tag
- [ ] GitHub Release for the tag
- [ ] Hex Publish workflow on v* succeeds
- [ ] Confirm hex.pm/packages/squirr_elix + hexdocs
```

## Version + CHANGELOG

1. Set `@version` in `mix.exs` to `X.Y.Z`.
2. In `CHANGELOG.md` (Keep a Changelog): move Unreleased notes under `## [X.Y.Z] - YYYY-MM-DD`; leave a fresh `## [Unreleased]` stub.
3. Do **not** bump version for every feature PR — only when cutting a release (unless the user asks).

## GitHub project board

```sh
# Add issue or PR to org project #1
gh project item-add 1 --owner scripthungry --url https://github.com/scripthungry/squirrelix/issues/N

# List Status field options / item id as needed, then:
gh project item-edit --project-id <PROJECT_ID> --id <ITEM_ID> --field-id <STATUS_FIELD_ID> --single-select-option-id <OPTION_ID>
```

Discover IDs with `gh project field-list 1 --owner scripthungry` and `gh project item-list 1 --owner scripthungry`. Move work Todo → In Progress → Done as it progresses.

## Tag → Hex

After merge to `main` and CI green:

```sh
git checkout main && git pull
git tag vX.Y.Z
git push origin vX.Y.Z
# Pseudocode — replace the heredoc body with the real CHANGELOG summary for X.Y.Z
# before running (do not leave a placeholder in the published notes).
gh release create vX.Y.Z --title "vX.Y.Z" --notes-file - <<'EOF'
<CHANGELOG summary for X.Y.Z>
EOF
```

The **Hex Publish** workflow runs on `v*` tags (`HEX_API_KEY` secret).  
**Timing:** often ~5 minutes; Dialyzer dominates. Not hung if runtime matches prior successful publishes.

Manual fallback: Actions → Hex Publish → Run workflow → type `publish`.

## Do not commit / leak

- Hex API keys, DB passwords, `erl_crash.dump`

## Partial workflows

| User ask | Do |
| --- | --- |
| "PR only" / "land PR" | Branch/PR/merge + board Done; **no** version bump/tag unless asked |
| "Release" / "publish" | Full checklist from version bump through Hex |
| "Add to project board" | `gh project item-add` + set Status |
