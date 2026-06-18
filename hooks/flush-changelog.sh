#!/usr/bin/env bash
# Stop hook: launch the isolated changelog writer when enough changes are staged.
# Guards: stop_hook_active, empty staging, threshold, mode, session-end idle.
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
IDLE_MINUTES=10

if [ -f "$CONFIG_FILE" ]; then
  if command -v jq >/dev/null 2>&1; then
    MODE=$(jq -r '.mode // "stop"' "$CONFIG_FILE" 2>/dev/null) || MODE="stop"
    THRESHOLD=$(jq -r '.threshold // 1' "$CONFIG_FILE" 2>/dev/null) || THRESHOLD=1
    IDLE_MINUTES=$(jq -r '.sessionEndIdleMinutes // 10' "$CONFIG_FILE" 2>/dev/null) || IDLE_MINUTES=10
  elif command -v node >/dev/null 2>&1; then
    _CFG=$(node -e "
      const fs=require('fs');
      try {
        const c=JSON.parse(fs.readFileSync('$(printf '%s' "$CONFIG_FILE" | sed "s/'/'\\\\''/g")','utf8'));
        process.stdout.write([(c.mode||'stop'),(c.threshold||1),(c.sessionEndIdleMinutes||10)].join('\n'));
      } catch(e) { process.stdout.write('stop\n1\n10'); }
    " 2>/dev/null) || true
    MODE=$(printf '%s' "${_CFG:-stop}" | sed -n '1p')
    THRESHOLD=$(printf '%s' "${_CFG:-1}" | sed -n '2p')
    IDLE_MINUTES=$(printf '%s' "${_CFG:-10}" | sed -n '3p')
  fi
fi

# Guard: manual mode never auto-fires
if [ "$MODE" = "manual" ]; then
  exit 0
fi

# Guard: staged count must reach threshold
STAGED_COUNT=$(wc -l < "$STAGED_FILE" | tr -d '[:space:]')
if [ "${STAGED_COUNT:-0}" -lt "${THRESHOLD:-1}" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# session-end mode: only fire after N minutes of no new changes (idle debounce)
# Reads the timestamp of the most recent staged entry and waits until idle.
# ---------------------------------------------------------------------------
if [ "$MODE" = "session-end" ] && command -v node >/dev/null 2>&1; then
  LATEST_TS=$(tail -1 "$STAGED_FILE" | node -e "
    let d='';
    process.stdin.on('data',c=>d+=c);
    process.stdin.on('end',()=>{
      try { process.stdout.write(JSON.parse(d).ts||''); } catch(e){}
    });
  " 2>/dev/null) || LATEST_TS=""

  if [ -n "$LATEST_TS" ]; then
    AGE_SECS=$(node -e "
      const latest = new Date('$LATEST_TS').getTime();
      const now = Date.now();
      process.stdout.write(String(Math.floor((now - latest) / 1000)));
    " 2>/dev/null) || AGE_SECS=0
    IDLE_SECS=$(( ${IDLE_MINUTES:-10} * 60 ))
    if [ "${AGE_SECS:-0}" -lt "$IDLE_SECS" ]; then
      exit 0  # Still within idle window — not a session end yet
    fi
  fi
fi

# stop mode: fire after every turn (no extra guard needed beyond threshold)

# ---------------------------------------------------------------------------
# All guards passed — launch isolated writer, log output for diagnostics
# ---------------------------------------------------------------------------
LOG_FILE="${REPO_ROOT}/.changelog/writer.log"
mkdir -p "${REPO_ROOT}/.changelog"

{
  echo "=== $(date -u +"%Y-%m-%dT%H:%M:%SZ") mode:${MODE} staged:${STAGED_COUNT} ==="
  CHANGELOG_PLUGIN_DISABLE=1 claude -p "$(cat "${CLAUDE_PLUGIN_ROOT}/scripts/writer-prompt.md")" \
    --allowedTools "Read,Edit,Write,Bash(git diff:*),Bash(git log:*),Bash(git status:*)"
} >> "$LOG_FILE" 2>&1 &

exit 0
