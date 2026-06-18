#!/usr/bin/env bash
# PostToolUse hook: record a changed file path into .changelog/.staged.jsonl
# Always exits 0 — PostToolUse is observability-only and must not block.
set -euo pipefail

INPUT=$(cat) || exit 0

# Recursion guard: writer sets this to prevent re-triggering on CHANGELOG.md edits
if [ "${CHANGELOG_PLUGIN_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# JSON parsing: jq preferred, node fallback, bail if neither available
# ---------------------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
  FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
  CWD=$(printf '%s'  "$INPUT" | jq -r '.cwd // ""' 2>/dev/null) || exit 0
elif command -v node >/dev/null 2>&1; then
  _PARSED=$(printf '%s' "$INPUT" | node -e "
    let d='';
    process.stdin.on('data',c=>d+=c);
    process.stdin.on('end',()=>{
      try {
        const o=JSON.parse(d);
        process.stdout.write([
          o.tool_name||'',
          (o.tool_input||{}).file_path||'',
          o.cwd||''
        ].join('\n'));
      } catch(e) { process.stdout.write('\n\n'); }
    });
  " 2>/dev/null) || exit 0
  TOOL=$(printf '%s' "$_PARSED" | sed -n '1p')
  FILE=$(printf '%s' "$_PARSED" | sed -n '2p')
  CWD=$(printf '%s'  "$_PARSED" | sed -n '3p')
else
  exit 0
fi

# Nothing to do without a file path
if [ -z "$FILE" ]; then
  exit 0
fi

REPO_ROOT="${CWD:-$(pwd)}"
STAGED_FILE="${REPO_ROOT}/.changelog/.staged.jsonl"
CONFIG_FILE="${REPO_ROOT}/.changelog/config.json"

# ---------------------------------------------------------------------------
# Built-in skip rules (no jq needed)
# ---------------------------------------------------------------------------
# Skip CHANGELOG.md itself
case "$(basename "$FILE")" in
  CHANGELOG.md) exit 0 ;;
esac

# Skip anything inside .changelog/
case "$FILE" in
  */.changelog/*|.changelog/*) exit 0 ;;
esac

# Skip lock files and generated output directories
case "$FILE" in
  *package-lock.json|*yarn.lock|*pnpm-lock.yaml|*Cargo.lock|*poetry.lock|*.lock) exit 0 ;;
  */node_modules/*|*/dist/*|*/build/*|*/.git/*) exit 0 ;;
esac

# ---------------------------------------------------------------------------
# User-configured ignore globs from config.json
# ---------------------------------------------------------------------------
if [ -f "$CONFIG_FILE" ]; then
  if command -v jq >/dev/null 2>&1; then
    IGNORE_PATTERNS=$(jq -r '.ignore // [] | .[]' "$CONFIG_FILE" 2>/dev/null) || true
  elif command -v node >/dev/null 2>&1; then
    IGNORE_PATTERNS=$(node -e "
      const fs=require('fs');
      try {
        const c=JSON.parse(fs.readFileSync('$CONFIG_FILE','utf8'));
        (c.ignore||[]).forEach(p=>console.log(p));
      } catch(e) {}
    " 2>/dev/null) || true
  fi
  if [ -n "${IGNORE_PATTERNS:-}" ]; then
    while IFS= read -r pattern; do
      [ -z "$pattern" ] && continue
      case "$FILE" in
        $pattern) exit 0 ;;
      esac
    done <<< "$IGNORE_PATTERNS"
  fi
fi

# ---------------------------------------------------------------------------
# Stage the change
# ---------------------------------------------------------------------------
mkdir -p "${REPO_ROOT}/.changelog"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if command -v jq >/dev/null 2>&1; then
  jq -cn --arg f "$FILE" --arg t "$TOOL" --arg s "$TS" \
    '{file:$f,tool:$t,ts:$s}' >> "$STAGED_FILE"
elif command -v node >/dev/null 2>&1; then
  FILE="$FILE" TOOL="$TOOL" TS="$TS" node -e "
    process.stdout.write(JSON.stringify({
      file:  process.env.FILE,
      tool:  process.env.TOOL,
      ts:    process.env.TS
    }) + '\n');
  " >> "$STAGED_FILE" 2>/dev/null || true
else
  # Plain fallback — safe for ASCII paths
  printf '{"file":"%s","tool":"%s","ts":"%s"}\n' \
    "$(printf '%s' "$FILE" | sed 's/\\/\\\\/g;s/"/\\"/g')" \
    "$TOOL" "$TS" >> "$STAGED_FILE"
fi

exit 0
