---
description: Show the current state of the changelog plugin — staged file count, config settings, CHANGELOG.md health, and whether the auto-writer will fire this turn.
---

# /changelog:status

Report the current state of the changelog plugin in this repository.

## What to check and report

### 1. Staged changes

Read `.changelog/.staged.jsonl`.
- If missing or empty: "0 files staged"
- If present: count lines, show the last 3 entries (file, tool, timestamp)

### 2. Config

Read `.changelog/config.json`. Show:
- `mode` (default: stop)
- `source` (default: diff)
- `threshold` (default: 1)
- `sessionEndIdleMinutes` (default: 10, only relevant when mode is session-end)
- Number of ignore patterns

If config file is missing, show defaults and note it hasn't been initialized.

**Validate each field and flag issues:**

| Key | Valid values | If invalid |
|---|---|---|
| `mode` | `stop`, `session-end`, `manual` | ⚠ warn, hooks will default to "stop" |
| `source` | `diff`, `commits`, `both` | ⚠ warn, writer will default to "diff" |
| `threshold` | positive integer | ⚠ warn, will default to 1 |
| `sessionEndIdleMinutes` | positive integer | ⚠ warn, will default to 10 |
| `ignore` | array of strings | ⚠ warn if not an array |

### 3. Auto-write readiness

Based on staged count vs threshold:
- **Will fire:** mode == "stop" AND staged count >= threshold
- **Won't fire:** mode != "stop" OR staged count < threshold

Show clearly: `X file(s) staged, threshold Y → auto-writer WILL fire` or `WILL NOT fire`

### 4. CHANGELOG.md health

Check:
- Does `CHANGELOG.md` exist?
- Does it have `## [Unreleased]`?
- Does it have `<!-- changelog:auto:start -->` and `<!-- changelog:auto:end -->` markers?
- How many bullet entries are currently between the markers?

If markers are missing: warn the user to run `/changelog:init`.

### 5. Recent writer log

Check `.changelog/writer.log`.
- If missing: "No writer runs logged yet"
- If present: show the last 15 lines (most recent run)

### 6. Available backups

List files in `.changelog/backups/` if the directory exists.
Show filenames and timestamps so the user knows what `/changelog:undo` can restore.

### 7. Summary

End with a clear one-liner:
- `✓ Ready — auto-writer will fire at end of next turn`
- `⚠ Not initialized — run /changelog:init first`
- `⚠ Manual mode — run /changelog:sync to write entries`
- `⚠ X file(s) staged but below threshold of Y`
