---
name: add-tool
description: Use when adding, removing, moving or renaming a tool, plugin, skill or group in this Heitorgkk scoop-bucket repository. Covers verifying the package source, editing groups.json, regenerating bucket/*.json and the README table, validating, and committing.
---

# Adding a tool to the Heitorgkk bucket

`groups.json` is the single source of truth. Never hand-edit `bucket/*.json` or the
generated README table (between the `BEGIN/END GENERATED TOOLS TABLE` markers).

## 1. Verify the source (do not guess names)

| Source | How to verify | `package` value |
|---|---|---|
| `scoop` | `https://raw.githubusercontent.com/ScoopInstaller/<Main\|Extras\|Java>/HEAD/bucket/<app>.json` returns 200 | `bucket/app`, e.g. `main/jq` |
| `npm` | `https://registry.npmjs.org/<pkg>/latest` | npm name, e.g. `@google/gemini-cli` |
| `winget` | `manifests/<l>/<Publisher>/<Name>/` exists in microsoft/winget-pkgs | WinGet id, e.g. `Anthropic.Claude` |
| `claude-plugin` | plugin listed in the marketplace's `.claude-plugin/marketplace.json` | `plugin@marketplace` |
| `claude-skill` | `claude/skills/<name>/SKILL.md` exists with `name: <name>` frontmatter | `claude/skills/<name>` |

Prefer an official Scoop manifest. Use npm/WinGet only when no working Scoop manifest
exists, and record why in the README's "Why some tools are not Scoop packages" table.
For a WinGet desktop app, add a `direct` block (`type: msix`, `url.x64`/`url.arm64`,
`appxName`, and the exact MSIX `publisher` and/or a `signer` name) pointing at the vendor's own stable "latest" MSIX URL so it can be
installed without WinGet.

## 2. Edit `groups.json`

Add the entry to the right group's `tools` (fields: `name`, `source`, `package`, `summary`,
`homepage`, optional `command`, `requirements`, `requires`). A new official bucket goes in
`buckets`, a new plugin marketplace in `claudeMarketplaces`. A new group must be lowercase,
must not clash with an existing Scoop app name, and must be added to `all.includes`.

If the dependencies of any metapackage change, bump `METAPACKAGE_VERSION` in
`tools/catalog.py` so `scoop update <group>` notices.

## 3. Regenerate and validate

```bash
python tools/catalog.py generate
python tools/catalog.py validate   # needs: pip install jsonschema
```

Update the expected tool counts in `tests/Test-Scripts.ps1` (the `all` dry run) if they change.

## 4. Commit

Small commits, catalog/manifests separate from script changes. CI
(`.github/workflows/validate.yml`) re-validates and performs real installs on Windows.
