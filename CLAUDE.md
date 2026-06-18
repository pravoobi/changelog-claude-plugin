# CLAUDE.md

Project context for building **`changelog`**, a Claude Code plugin that auto-maintains
a human-facing `CHANGELOG.md` as code changes. Read `PLAN.md` for the full design;
this file is the operational guide you (Claude Code) follow while building.

---

## What we are building

A plugin named `changelog` (so all skills are namespaced `/changelog:*`). It stages
file edits cheaply via a `PostToolUse` hook, then on `Stop` runs an **isolated** writer
(headless `claude -p`) that turns staged changes into Keep-a-Changelog entries under
`## [Unreleased]`. The main session's context is never spent on diff summarizing.

This is for a *human-readable* changelog — NOT a `CLAUDE.md` updater.

---

## Ground rules (verified against current Claude Code docs — do not deviate)

These are the spots people get wrong. Follow them exactly.

1. **Only `plugin.json` lives inside `.claude-plugin/`.** Every other directory
   (`skills/`, `agents/`, `hooks/`, `scripts/`) sits at the **plugin root**, NOT inside
   `.claude-plugin/`. Putting them inside `.claude-plugin/` is the #1 cause of a plugin
   silently not loading.

2. **Hooks receive their event payload as JSON on `stdin`** — there is no
   `$CLAUDE_TOOL_INPUT_FILE_PATH` env var (blog posts that use it are outdated). Read
   stdin and parse with `jq`:
   ```bash
   INPUT=$(cat)
   FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
   TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
   ```

3. **`Stop` hooks must guard against infinite loops.** If a Stop hook keeps Claude
   running, it fires again. Always check `stop_hook_active` first and exit 0 if set:
   ```bash
   [ "$(echo "$INPUT" | jq -r '.stop_hook_active')" = "true" ] && exit 0
   ```

4. **Exit codes:** `0` = success; `2` = block (only respected on blocking-capable events
   like PreToolUse/Stop); other non-zero = non-blocking error. `PostToolUse` is
   observability-only — it cannot undo the edit, only react. The staging hook should
   essentially always `exit 0`.

5. **Hook handler types** are `command`, `http`, `prompt`, `agent`, `mcp_tool`.
   We use `command` hooks. Add `"async": true` so staging/flush never blocks Claude.

6. **Hooks config** goes in `hooks/hooks.json` with the shape
   `{ "hooks": { "<Event>": [ { "matcher": "...", "hooks": [ { "type": "command", "command": "..." } ] } ] } }`.
   Matcher is a regex over tool names; use `"Write|Edit|MultiEdit"`.

7. **Reference `${CLAUDE_PLUGIN_ROOT}`** (the plugin's install dir) in hook commands so
   scripts resolve regardless of where the plugin is installed. Do not hardcode paths.

8. **Test by piping JSON**, e.g.
   `echo '{"tool_name":"Edit","tool_input":{"file_path":"src/x.ts"},"stop_hook_active":false}' | bash hooks/stage-change.sh`.

---

## Target directory layout

```
changelog/
├── .claude-plugin/
│   └── plugin.json                # ONLY this file goes in here
├── README.md
├── settings.json                  # optional plugin defaults
├── skills/
│   ├── init/SKILL.md              # /changelog:init
│   ├── sync/SKILL.md              # /changelog:sync
│   ├── preview/SKILL.md           # /changelog:preview
│   ├── release/SKILL.md           # /changelog:release
│   └── undo/SKILL.md              # /changelog:undo
├── agents/
│   └── changelog-writer.md        # subagent: diff -> categorized entries
├── hooks/
│   ├── hooks.json
│   ├── stage-change.sh            # PostToolUse: append staged path
│   └── flush-changelog.sh         # Stop: guard + invoke isolated writer
└── scripts/
    └── writer-prompt.md           # prompt fed to headless `claude -p`
```

User-side runtime files (created in the user's repo at runtime, gitignored by them):
```
.changelog/
├── config.json                    # mode/source/threshold/ignore
├── .staged.jsonl                  # pending changes (one JSON object per line)
└── backups/                       # pre-write backups for /changelog:undo
```

---

## `plugin.json`

```json
{
  "name": "changelog",
  "description": "Keeps a human-facing CHANGELOG.md in sync with code changes, using an isolated writer so it never spends your main session context.",
  "version": "0.1.0",
  "author": { "name": "<you>" }
}
```

Keep `version` set so users only update on a deliberate bump.

---

## Behavior contracts

### `stage-change.sh` (PostToolUse, async)
- Read stdin JSON; extract `tool_input.file_path`.
- If the path matches an `ignore` glob, or is `CHANGELOG.md`, or is under `.changelog/`,
  or `CHANGELOG_PLUGIN_DISABLE=1` is set → `exit 0` (do nothing).
- Otherwise append a compact JSON line `{file, tool, ts}` to `.changelog/.staged.jsonl`.
- Never print to stdout. Always `exit 0`.

### `flush-changelog.sh` (Stop, async)
- `exit 0` immediately if `stop_hook_active` is true, or `.staged.jsonl` is missing/empty,
  or staged count < `threshold`, or `mode != stop`.
- Otherwise launch the writer in a **separate process** with the hooks disabled for that
  process:
  ```bash
  CHANGELOG_PLUGIN_DISABLE=1 claude -p "$(cat "${CLAUDE_PLUGIN_ROOT}/scripts/writer-prompt.md")" \
    --allowedTools "Read,Edit,Bash(git diff:*),Bash(git log:*)" >/dev/null 2>&1 &
  ```
- The writer is responsible for clearing `.staged.jsonl` on success.

### `changelog-writer` (the writing logic, in `agents/changelog-writer.md` + `scripts/writer-prompt.md`)
- Inputs: the staged file list and `git diff` (and `git log` if `source` includes commits).
- Classify each change into Keep-a-Changelog categories:
  **Added, Changed, Deprecated, Removed, Fixed, Security**.
- Write concise, *user-facing* entries (what changed and why it matters — not "edited file X").
- Edit ONLY the content between `<!-- changelog:auto:start -->` and
  `<!-- changelog:auto:end -->` inside the `## [Unreleased]` section. Never touch anything
  outside the markers. De-duplicate against entries already present.
- On success, truncate `.staged.jsonl`.

### CHANGELOG.md shape that `/changelog:init` scaffolds
```markdown
# Changelog
All notable changes to this project are documented here.
Format based on Keep a Changelog; this project adheres to Semantic Versioning.

## [Unreleased]
<!-- changelog:auto:start -->
<!-- changelog:auto:end -->
```

### `/changelog:release <version> [date]`
- Move everything in `[Unreleased]` into a new `## [<version>] - <YYYY-MM-DD>` section.
- Reset the `[Unreleased]` auto block to empty (keep the markers).
- Default date to today if omitted.

---

## Build order (do these in sequence)

Follow `PLAN.md` phases. Concretely:
1. Scaffold tree + `plugin.json`; load with `claude --plugin-dir ./changelog`; confirm in `/plugin`.
2. Build `/changelog:init`, `/changelog:sync`, and the writer logic. **Validate writing
   quality manually before adding any hooks.**
3. Add the two hooks + `hooks.json`; implement all four guards from the Ground Rules.
4. Add `/changelog:preview`, `/changelog:release`, `/changelog:undo`.
5. Config, ignore globs, `commits` mode, README, then `claude plugin validate`.

After any change to plugin files during a dev session, run `/reload-plugins` (no restart needed).

---

## Coding conventions

- Hook scripts: POSIX-friendly `bash`, `set -euo pipefail`, `jq` for all JSON parsing,
  no unguarded `stdout` from PostToolUse.
- Make scripts idempotent and fast; assume they run on every edit / every turn.
- Resolve plugin paths via `${CLAUDE_PLUGIN_ROOT}`; resolve repo paths via the hook's
  `cwd` field, not `pwd`.
- Fail safe: if anything is uncertain, the hook should `exit 0` and leave the changelog
  untouched rather than write garbage.
- Each `SKILL.md` needs YAML frontmatter with a `description`; use `$ARGUMENTS` for input
  (e.g. the version in `/changelog:release`).

## Things to verify before calling it done
- Editing code → ending a turn updates `[Unreleased]` with correct categories.
- Manual changelog prose is never overwritten (only the marked auto block changes).
- The writer's own edit to CHANGELOG.md does NOT re-trigger staging (recursion guard works).
- Empty staging → Stop hook returns in milliseconds.
- `claude plugin validate` passes with no errors.
