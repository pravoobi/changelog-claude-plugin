#!/usr/bin/env bash
# Stop hook: launch the isolated changelog writer when enough changes are staged.
# Guards: stop_hook_active, empty staging, threshold, mode.
set -euo pipefail

INPUT=$(cat) || exit 0

# ---------------------------------------------------------------------------
# JSON parsing: jq preferred, node fallback
# ---------------------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null) || exit 0
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null) || exit 0
elif command -v node >/dev/null 2>&1; then
  _PARSED=$(printf '%s' "$INPUT" | node -e "
    let d='';
    process.stdin.on('data',c=>d+=c);
    process.stdin.on('end',()=>{
      try {
        const o=JSON.parse(d);
        process.stdout.write([
          o.stop_hook_active===true ? 'true' : 'false',
          o.cwd||''
        ].join('\n'));
      } catch(e) { process.stdout.write('false\n'); }
    });
  " 2>/dev/null) || exit 0
  STOP_HOOK_ACTIVE=$(printf '%s' "$_PARSED" | sed -n '1p')
  CWD=$(printf '%s' "$_PARSED" | sed -n '2p')
else
  exit 0
fi

# Guard: infinite-loop prevention
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

REPO_ROOT="${CWD:-$(pwd)}"
STAGED_FILE="${REPO_ROOT}/.changelog/.staged.jsonl"
CONFIG_FILE="${REPO_ROOT}/.changelog/config.json"

# Guard: nothing staged
if [ ! -f "$STAGED_FILE" ] || [ ! -s "$STAGED_FILE" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Read config
# ---------------------------------------------------------------------------
MODE="stop"
THRESHOLD=1

if [ -f "$CONFIG_FILE" ]; then
  if command -v jq >/dev/null 2>&1; then
    MODE=$(jq -r '.mode // "stop"' "$CONFIG_FILE" 2>/dev/null) || MODE="stop"
    THRESHOLD=$(jq -r '.threshold // 1' "$CONFIG_FILE" 2>/dev/null) || THRESHOLD=1
  elif command -v node >/dev/null 2>&1; then
    _CFG=$(node -e "
      const fs=require('fs');
      try {
        const c=JSON.parse(fs.readFileSync('$(printf '%s' "$CONFIG_FILE" | sed "s/'/'\\\\''/g")','utf8'));
        process.stdout.write([(c.mode||'stop'),(c.threshold||1)].join('\n'));
      } catch(e) { process.stdout.write('stop\n1'); }
    " 2>/dev/null) || true
    MODE=$(printf '%s' "${_CFG:-stop}" | sed -n '1p')
    THRESHOLD=$(printf '%s' "${_CFG:-1}" | sed -n '2p')
  fi
fi

# Guard: auto-write only in "stop" mode
if [ "$MODE" != "stop" ]; then
  exit 0
fi

# Guard: staged count must reach threshold
STAGED_COUNT=$(wc -l < "$STAGED_FILE" | tr -d '[:space:]')
if [ "${STAGED_COUNT:-0}" -lt "${THRESHOLD:-1}" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# All guards passed — launch isolated writer in background
# Output goes to .changelog/writer.log so failures are diagnosable
# ---------------------------------------------------------------------------
LOG_FILE="${REPO_ROOT}/.changelog/writer.log"
mkdir -p "${REPO_ROOT}/.changelog"

{
  echo "=== $(date -u +"%Y-%m-%dT%H:%M:%SZ") staged:${STAGED_COUNT} ==="
  CHANGELOG_PLUGIN_DISABLE=1 claude -p "$(cat "${CLAUDE_PLUGIN_ROOT}/scripts/writer-prompt.md")" \
    --allowedTools "Read,Edit,Write,Bash(git diff:*),Bash(git log:*),Bash(git status:*)"
} >> "$LOG_FILE" 2>&1 &

exit 0
