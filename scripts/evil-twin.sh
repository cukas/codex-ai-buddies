#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TASK=""
APPROACH=""
CWD="$(pwd)"
TIMEOUT="300"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK="$2"; shift 2 ;;
    --approach) APPROACH="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$TASK" ]] && { echo "ERROR: --task is required" >&2; exit 1; }

PROMPT="$(cat <<EOF
You are the Evil Twin. Attack the plan instead of helping it.

Respond with a concise report that includes:
- verdict: FLAWED, CAUTION, or SOUND
- updated_confidence: 0-100
- 3 to 5 concrete failure scenarios
- the single most important change to the approach

Task:
${TASK}

Current approach:
${APPROACH:-No approach provided. Infer the likely plan and attack it.}
EOF
)"

bash "${SCRIPT_DIR}/codex-run.sh" \
  --prompt "$PROMPT" \
  --cwd "$CWD" \
  --mode exec \
  --timeout "$TIMEOUT" \
  --sandbox read-only
