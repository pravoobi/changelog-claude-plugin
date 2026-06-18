# Build Plan — `changelog` (a Claude Code plugin)

A Claude Code plugin that keeps a real, human-facing **CHANGELOG.md** in sync as
Claude edits code — without spending your main session's context window.

It is **not** a CLAUDE.md updater (that niche is taken by `claude-code-auto-memory`).
The output here is a Keep-a-Changelog file your users and teammates read.

---

## 1. Problem & differentiator

- `CHANGELOG.md` files rot because updating them is manual and easy to forget.
- Existing community plugins mostly keep *the AI's* context file (`CLAUDE.md`) fresh.
- **Gap:** nothing maintains a proper human-facing changelog (Added / Changed /
  Fixed / etc.) automatically from actual code changes.

**This plugin fills that gap.** Edits are staged cheaply as they happen; a separate,
isolated writer turns them into changelog entries so the main conversation stays clean.

---

## 2. How it works (architecture)

Three moving parts, mirroring the proven "track cheap, write isolated" pattern:

```
Claude edits a file
   │
   ▼
PostToolUse hook  ──►  append {file, tool, ts} to .changelog/.staged.jsonl   (no output, async)
   │
   ▼   (turn ends)
Stop hook  ──►  guard checks: staged entries exist? threshold met? not a recursive run?
   │                 │ yes
   │                 ▼
   │            run writer in an ISOLATED process (headless `claude -p`)
   │                 │  reads staged files + `git diff`, classifies changes,
   │                 │  updates the AUTO-MANAGED block of ## [Unreleased],
   │                 │  preserves manual content, then clears .staged.jsonl
   ▼
main session context untouched
```

**Why isolated.** The writer runs in a separate headless process, so summarizing
diffs and rewriting the changelog never consumes the tokens of the session you're
actually working in.

**Why staging first.** The `PostToolUse` hook must be near-instant and silent. It only
records *which* files changed; all the expensive reasoning happens later, once.

### Key safeguards (each is a known footgun — see CLAUDE.md for the fix)
- **Infinite-loop guard:** the Stop hook checks `stop_hook_active` and exits early if set.
- **Recursion guard:** the staging hook ignores edits to `CHANGELOG.md` and the
  `.changelog/` dir, and the writer process sets `CHANGELOG_PLUGIN_DISABLE=1` so it
  can't re-trigger the hooks on itself.
- **Manual edits preserved:** the writer only touches content between
  `<!-- changelog:auto:start -->` and `<!-- changelog:auto:end -->` markers.
- **Cheap when idle:** if nothing is staged, the Stop hook exits in milliseconds.

---

## 3. Components to build

| Component | Path | Purpose |
| :-- | :-- | :-- |
| Manifest | `.claude-plugin/plugin.json` | Plugin identity (`name: "changelog"` → `/changelog:*`) |
| Staging hook | `hooks/stage-change.sh` | `PostToolUse` (Write\|Edit\|MultiEdit): append changed path |
| Flush hook | `hooks/flush-changelog.sh` | `Stop`: guard + invoke writer when threshold met |
| Hook config | `hooks/hooks.json` | Wires the two hooks to their events |
| Writer agent | `agents/changelog-writer.md` | Subagent prompt: diff → categorized entries |
| Writer prompt | `scripts/writer-prompt.md` | Prompt passed to headless `claude -p` |
| `/changelog:init` | `skills/init/SKILL.md` | Scaffold CHANGELOG.md + markers + config |
| `/changelog:sync` | `skills/sync/SKILL.md` | Run the writer now on staged + working-tree diff |
| `/changelog:preview` | `skills/preview/SKILL.md` | Show pending changes not yet written |
| `/changelog:release` | `skills/release/SKILL.md` | Promote `[Unreleased]` → versioned, dated section |
| `/changelog:undo` | `skills/undo/SKILL.md` | Revert the last auto-write from backup |
| Defaults | `settings.json` (optional) | Mode, source, threshold, ignore globs |
| Docs | `README.md` | Install + usage |

---

## 4. Configuration surface

Stored at `.changelog/config.json` in the user's repo (created by `/changelog:init`):

| Key | Values | Default | Meaning |
| :-- | :-- | :-- | :-- |
| `mode` | `stop` \| `session-end` \| `manual` | `stop` | When the writer runs |
| `source` | `diff` \| `commits` \| `both` | `diff` | Summarize from code diffs, conventional commits, or both |
| `threshold` | integer | `1` | Min staged files before an auto-write fires |
| `ignore` | glob[] | lockfiles, `node_modules`, `dist`, `build`, `.changelog/`, `CHANGELOG.md` | Paths that never produce entries |
| `categories` | map | Keep-a-Changelog set | Added / Changed / Deprecated / Removed / Fixed / Security |

---

## 5. Phased delivery

**Phase 0 — Scaffold (½ day)**
Create the directory tree, `plugin.json`, and a stub `README.md`. Load with
`claude --plugin-dir ./changelog` and confirm it appears in `/plugin`.

**Phase 1 — Manual core (1 day)** *(prove the writing logic before automating)*
Build `/changelog:init` and `/changelog:sync` plus the `changelog-writer` agent.
At this point a human can run `/changelog:sync` and get correct, categorized entries
from `git diff`. No hooks yet — this de-risks the hard part first.

**Phase 2 — Automation (1 day)**
Add `stage-change.sh`, `flush-changelog.sh`, and `hooks.json`. Wire the isolated
writer. Implement all guards. Verify with `echo '<sample json>' | ./hooks/stage-change.sh`.

**Phase 3 — Lifecycle commands (½ day)**
`/changelog:preview`, `/changelog:release <version>`, `/changelog:undo`.

**Phase 4 — Polish & ship (½ day)**
Config handling, ignore globs, `commits` mode, README, `claude plugin validate`,
then publish to a marketplace.

---

## 6. Test strategy

- **Hook units:** pipe sample JSON to each `.sh` and assert staging/guards
  (`echo '{"tool_name":"Edit","tool_input":{"file_path":"src/a.ts"},"stop_hook_active":false}' | ./hooks/stage-change.sh`).
- **Writer quality:** run `/changelog:sync` against a repo with a known diff; check
  entries land in the right categories and manual content survives.
- **Loop safety:** confirm the writer's own edits don't re-trigger staging.
- **Idle cost:** Stop hook with empty staging returns immediately.
- **Integration:** `claude --plugin-dir ./changelog`, make edits, end a turn, inspect
  `CHANGELOG.md` and `.changelog/.staged.jsonl`.

---

## 7. Definition of done

- Editing code then ending a turn updates `## [Unreleased]` with correctly categorized,
  human-readable entries.
- Manual changelog prose is never clobbered.
- Main session context shows no large diff dumps from the writer.
- `/changelog:release 1.2.0` cuts a clean dated section.
- `claude plugin validate` passes.
