---
description: "Cut a release — promotes all [Unreleased] entries to a new dated version section. Usage: /changelog:release <version> [date]"
---

# /changelog:release

Promote the `[Unreleased]` section into a new dated, versioned release entry.

## Input

`$ARGUMENTS` contains: `<version> [date]`

Examples:
- `/changelog:release 1.2.0` → uses today's date
- `/changelog:release 1.2.0 2024-06-15` → uses specified date

## Steps

### 1. Parse arguments

Extract `<version>` from `$ARGUMENTS`. It should look like `1.2.0` or `v1.2.0` (strip
the leading `v` if present for the section heading).

Extract `[date]` if provided. If omitted, use today's date in `YYYY-MM-DD` format.

If no version is provided, tell the user the correct usage and stop.

### 2. Read CHANGELOG.md

Read the file. Confirm the `## [Unreleased]` section and the auto-markers exist.

Extract all content within `## [Unreleased]` (both inside and outside the auto-markers).

If `## [Unreleased]` has no entries (the auto block is empty and there's no manual prose),
warn the user that there is nothing to release, then stop.

### 3. Back up

Copy the current `CHANGELOG.md` content to `.changelog/backups/CHANGELOG.md.bak`
(create the `backups/` directory if needed). This enables `/changelog:undo`.

### 4. Write the new release section

Edit `CHANGELOG.md` to:

1. **Replace** the `## [Unreleased]` section (keep the heading) with a fresh empty auto block:
   ```markdown
   ## [Unreleased]
   <!-- changelog:auto:start -->
   <!-- changelog:auto:end -->
   ```

2. **Insert** a new versioned section immediately after the `## [Unreleased]` block,
   before any prior versioned sections:
   ```markdown
   ## [<version>] - <date>
   <everything that was in [Unreleased]>
   ```

The result should look like:
```markdown
## [Unreleased]
<!-- changelog:auto:start -->
<!-- changelog:auto:end -->

## [1.2.0] - 2024-06-15
### Added
- ...

### Fixed
- ...

## [1.1.0] - 2024-05-01
...
```

### 5. Clear staged queue

Write empty content to `.changelog/.staged.jsonl` if it exists — the released
content is now in a named section and should not be re-processed.

### 6. Report

Tell the user:
- The version and date that were cut
- How many entries moved into the new section
- That `/changelog:undo` can revert this if needed
