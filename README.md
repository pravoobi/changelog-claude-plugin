# changelog

A Claude Code plugin that keeps a human-facing `CHANGELOG.md` in sync as you edit
code — without spending your main session's context window.

Staged file paths are recorded cheaply on every edit. When your session ends, an
isolated headless writer reads the diffs, categorizes changes, and writes Keep-a-Changelog
entries into the `## [Unreleased]` section. Your conversation context is never used for
summarizing diffs.

---

## Install

```bash
claude --plugin-dir /path/to/changelog
```

Or add to your Claude Code settings to load it automatically.

---

## Quick start

```
/changelog:init       # scaffold CHANGELOG.md + .changelog/config.json
```

Then edit code as normal. When your session ends, the auto-writer fires and updates
`CHANGELOG.md`. Or trigger it manually:

```
/changelog:sync       # write entries now, based on current git diff + staged files
/changelog:preview    # dry-run — see what would be written without changing anything
```

When you're ready to ship:

```
/changelog:release 1.2.0           # cut a release dated today
/changelog:release 1.2.0 2024-06-15  # cut a release with a specific date
```

Oops:

```
/changelog:undo       # restore CHANGELOG.md from the pre-write backup
```

---

## How it works

```
You edit a file
    │
    ▼
PostToolUse hook ──► append {file, tool, ts} to .changelog/.staged.jsonl   (async, ~1ms)
    │
    ▼   (turn ends)
Stop hook ──► guards: staged? threshold met? mode=stop? not recursive?
    │              │ yes
    │              ▼
    │         headless `claude -p` (isolated process)
    │              reads staged files + git diff
    │              classifies → Added / Changed / Fixed / etc.
    │              updates only the <!-- changelog:auto:* --> block
    │              clears .staged.jsonl
    ▼
main session context untouched
```

---

## Configuration

`/changelog:init` creates `.changelog/config.json`. Edit it to customize behavior:

```json
{
  "mode": "stop",
  "source": "diff",
  "threshold": 1,
  "ignore": ["**/node_modules/**", "**/dist/**"]
}
```

| Key | Values | Default | Meaning |
|---|---|---|---|
| `mode` | `stop` \| `manual` | `stop` | `stop` = auto-write at end of every turn; `manual` = only via `/changelog:sync` |
| `source` | `diff` \| `commits` \| `both` | `diff` | What to summarize from |
| `threshold` | integer | `1` | Min staged files before auto-write fires |
| `ignore` | glob[] | lock files, build dirs | Paths that never produce entries |

---

## CHANGELOG.md format

The plugin manages only the content between these markers in `## [Unreleased]`:

```markdown
## [Unreleased]
<!-- changelog:auto:start -->
### Added
- Added dark mode toggle to user settings

### Fixed
- Fixed crash on empty search input
<!-- changelog:auto:end -->

You can write anything you like here and it will never be touched.
```

Anything outside the markers is yours — the plugin never modifies it.

---

## Runtime files

These live in `.changelog/` inside your repo (add to `.gitignore`):

| File | Purpose |
|---|---|
| `config.json` | Plugin settings |
| `.staged.jsonl` | Files changed this session (cleared after each write) |
| `backups/CHANGELOG.md.bak` | Pre-write backup for `/changelog:undo` |

---

## Safety

- **Recursion guard:** the writer runs with `CHANGELOG_PLUGIN_DISABLE=1` so its own
  edits to `CHANGELOG.md` never re-trigger staging.
- **Infinite-loop guard:** the Stop hook checks `stop_hook_active` and exits early.
- **Manual content preserved:** only the auto-marked block is ever modified.
- **Fail safe:** on any error the hooks exit 0 and leave the changelog untouched.
