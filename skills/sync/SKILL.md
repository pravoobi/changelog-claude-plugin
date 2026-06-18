---
description: Run the changelog writer immediately — reads staged files and current git diff, then updates CHANGELOG.md with categorized Keep-a-Changelog entries. Use this to manually trigger a write without waiting for a session to end.
---

# /changelog:sync

Trigger an immediate changelog update based on staged changes and the current working-tree diff.

## Steps

### 1. Validate config

Read `.changelog/config.json` if it exists and check for invalid values. Warn the
user (but do not stop) if any of the following are wrong:

| Key | Valid values |
|---|---|
| `mode` | `"stop"`, `"session-end"`, `"manual"` |
| `source` | `"diff"`, `"commits"`, `"both"` |
| `threshold` | positive integer |
| `sessionEndIdleMinutes` | positive integer |
| `ignore` | array of strings |

Example warning: `⚠ config.json: "mode" is "auto" — not a valid value. Expected one of: stop, session-end, manual. Defaulting to "stop".`

Continue with defaults for any invalid field rather than aborting.

### 2. Verify prerequisites

Check that `CHANGELOG.md` exists and contains the auto-markers:
```
<!-- changelog:auto:start -->
<!-- changelog:auto:end -->
```

If not, tell the user to run `/changelog:init` first and stop.

### 2. Gather changes

Run `git status` and `git diff HEAD` to see what has changed.

Also read `.changelog/.staged.jsonl` if it exists — these are files the plugin
tracked during this session.

Combine both sources: staged JSONL entries + any files shown in `git diff HEAD`.

### 3. Write changelog entries

Follow the same classification logic as the writer agent:

Classify each meaningful change into one of:
- **Added** — new features, endpoints, config options, files
- **Changed** — modified behavior, updated deps, refactored logic
- **Deprecated** — features marked for removal
- **Removed** — deleted features or files
- **Fixed** — bug fixes, error handling
- **Security** — auth, validation, dependency security

Skip: lock files, build artifacts, node_modules, dist, formatting-only changes,
changes to `.changelog/` itself, changes to `CHANGELOG.md` itself.

Write concise, user-facing entries — not "edited src/auth.ts" but what the change
means to someone reading the changelog.

### 4. Update CHANGELOG.md

Edit only the content between:
```
<!-- changelog:auto:start -->
<!-- changelog:auto:end -->
```

Format entries by category:
```markdown
<!-- changelog:auto:start -->
### Added
- Added X to enable Y

### Fixed
- Fixed Z crash when input was empty

<!-- changelog:auto:end -->
```

- Only include categories that have at least one entry
- De-duplicate: do not re-add entries already present
- Never touch content outside the markers

### 5. Clear staged queue

After a successful write, clear `.changelog/.staged.jsonl` by writing empty content
to it (prevents double-processing on next auto-run).

### 6. Report

Tell the user what entries were added (or that nothing changed).
