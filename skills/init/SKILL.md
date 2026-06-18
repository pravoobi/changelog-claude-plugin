---
description: Initialize the changelog plugin in this repository — scaffolds CHANGELOG.md with Keep-a-Changelog format and auto-markers, and creates .changelog/config.json with defaults.
---

# /changelog:init

Set up the changelog plugin in the current repository.

## Steps

### 1. Check for existing CHANGELOG.md

If `CHANGELOG.md` already exists:
- Read it.
- Check whether it already contains `<!-- changelog:auto:start -->`.
- If yes, report that it's already initialized and stop (do not overwrite).
- If no, ask the user whether to add the auto-markers to the existing file or skip.
  - If they say yes, insert the markers at the top of the `## [Unreleased]` section
    (create the section if it doesn't exist).
  - If they say skip, stop.

If `CHANGELOG.md` does not exist, create it with this exact content:

```markdown
# Changelog

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/);
this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]
<!-- changelog:auto:start -->
<!-- changelog:auto:end -->
```

### 2. Create .changelog/config.json

Create the `.changelog/` directory if it doesn't exist.

Create `.changelog/config.json` with these defaults (do not overwrite if it already exists):

```json
{
  "mode": "stop",
  "source": "diff",
  "threshold": 1,
  "ignore": [
    "**/node_modules/**",
    "**/dist/**",
    "**/build/**",
    "**/.git/**",
    "**/package-lock.json",
    "**/yarn.lock",
    "**/pnpm-lock.yaml",
    "**/Cargo.lock",
    "**/poetry.lock",
    "**/*.lock"
  ]
}
```

### 3. Update .gitignore

If a `.gitignore` file exists, check whether `.changelog/` is already listed.
If not, append these lines:

```
# changelog plugin runtime files
.changelog/
```

Note: `CHANGELOG.md` itself should NOT be gitignored — it's the output users track.

### 4. Report

Tell the user:
- What was created or already existed
- That they can now use `/changelog:sync` to manually trigger a write, or just edit
  code and the plugin will update the changelog automatically when a session ends
- That `/changelog:release <version>` cuts a dated release section when ready
