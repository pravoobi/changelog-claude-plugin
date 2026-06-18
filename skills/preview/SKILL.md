---
description: Preview pending changelog entries — shows what would be written to CHANGELOG.md based on staged changes and the current git diff, without modifying any files.
---

# /changelog:preview

Show a dry-run of the changelog entries that would be generated, without writing anything.

## Steps

### 1. Gather changes

Read `.changelog/.staged.jsonl` if it exists to get files staged during this session.

Run `git status` and `git diff HEAD` to see current working-tree changes.

Combine both sources.

### 2. Classify changes

Apply the same classification logic used by `/changelog:sync`:

| Category | When to use |
|---|---|
| **Added** | New features, endpoints, config, files |
| **Changed** | Modified behavior, updated deps, refactored |
| **Deprecated** | Marked for removal |
| **Removed** | Deleted features or files |
| **Fixed** | Bug fixes, error handling |
| **Security** | Auth, validation, dependency security |

Skip: lock files, build artifacts, node_modules, dist, `.changelog/`, `CHANGELOG.md`.

### 3. Show preview

Display what the auto-managed block would look like after an update:

```
Preview — entries that would be added to CHANGELOG.md [Unreleased]:

### Added
- ...

### Fixed
- ...

(X entries across Y categories)
No files will be modified — run /changelog:sync to apply.
```

If there are no meaningful changes, say so clearly.

### 4. Show staged file count

Also report: "X file(s) currently staged in .changelog/.staged.jsonl"

This helps the user understand whether the auto-writer will fire (based on threshold).
