#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

TASK=""
CWD="$(pwd)"
ENGINES=""
FITNESS=""
TIMEOUT="1800"
SKIP_TWIN="false"
SKIP_BRAINSTORM="false"
QUICK="false"
PRINT_REPORT="false"
LOCAL_ONLY="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --engines) ENGINES="$2"; shift 2 ;;
    --fitness) FITNESS="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --skip-twin) SKIP_TWIN="true"; shift 1 ;;
    --skip-brainstorm) SKIP_BRAINSTORM="true"; shift 1 ;;
    --quick) QUICK="true"; SKIP_BRAINSTORM="true"; shift 1 ;;
    --print-report) PRINT_REPORT="true"; shift 1 ;;
    --local-only) LOCAL_ONLY="true"; shift 1 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$TASK" ]] && { echo "ERROR: --task is required" >&2; exit 1; }

codex_buddies_ensure_doppelganger

if [[ -z "$FITNESS" ]]; then
  FITNESS="$(bash "${SCRIPT_DIR}/detect-project.sh" "$CWD" | jq -r '.fitness_cmd // "true"' 2>/dev/null || echo true)"
fi

AVAILABLE="$(codex_buddies_default_buddy_roster)"
if [[ -z "$AVAILABLE" ]]; then
  codex_buddies_no_buddies_error "evil-pipeline" >&2
  exit 1
fi
if [[ -n "$ENGINES" ]]; then
  FORGE_ENGINES="$ENGINES"
else
  FORGE_ENGINES="$AVAILABLE"
fi
if [[ "$LOCAL_ONLY" == "true" ]]; then
  FORGE_ENGINES="$(codex_buddies_csv_local_only "$FORGE_ENGINES")"
fi
if [[ -z "$FORGE_ENGINES" ]]; then
  codex_buddies_no_buddies_error "evil-pipeline" >&2
  exit 1
fi
if [[ "$FORGE_ENGINES" != *"doppelganger"* ]]; then
  FORGE_ENGINES="${FORGE_ENGINES},doppelganger"
fi

RUN_DIR="$(codex_buddies_session_dir)/evil-pipeline-$(date '+%Y%m%d-%H%M%S')"
mkdir -p "$RUN_DIR"

TWIN_RESULT=""
BRAINSTORM_RESULT=""
FORGE_RESULT=""

if [[ "$SKIP_TWIN" != "true" ]]; then
  twin_timeout="300"
  [[ "$QUICK" == "true" ]] && twin_timeout="120"
  TWIN_RESULT="$(bash "${SCRIPT_DIR}/evil-twin.sh" --task "$TASK" --cwd "$CWD" --timeout "$twin_timeout")"
fi

if [[ "$SKIP_BRAINSTORM" != "true" ]]; then
  brainstorm_timeout="600"
  [[ "$QUICK" == "true" ]] && brainstorm_timeout="240"
  BRAINSTORM_CMD=(bash "${SCRIPT_DIR}/brainstorm-run.sh" --task "$TASK" --cwd "$CWD" --engines "$AVAILABLE" --timeout "$brainstorm_timeout")
  [[ "$LOCAL_ONLY" == "true" ]] && BRAINSTORM_CMD+=(--local-only)
  BRAINSTORM_RESULT="$("${BRAINSTORM_CMD[@]}")"
fi

FORGE_RESULT="$(bash "${SCRIPT_DIR}/forge-run.sh" \
  --task "$TASK" \
  --cwd "$CWD" \
  --engines "$FORGE_ENGINES" \
  --fitness "$FITNESS" \
  --timeout "$TIMEOUT")"

REPORT_FILE="${RUN_DIR}/report.md"
{
  printf '# Evil Pipeline\n\n'
  printf 'Task: %s\n\n' "$TASK"
  printf 'Fitness: `%s`\n\n' "$FITNESS"
  if [[ -n "$TWIN_RESULT" ]]; then
    printf '## Evil Twin\n\n'
    printf '%s\n\n' "$TWIN_RESULT"
  fi
  if [[ -n "$BRAINSTORM_RESULT" ]]; then
    printf '## Brainstorm\n\n'
    printf '%s\n\n' "$BRAINSTORM_RESULT"
  fi
  printf '## Forge\n\n'
  printf '%s\n' "$FORGE_RESULT"
} > "$REPORT_FILE"

if [[ "$PRINT_REPORT" == "true" ]]; then
  cat "$REPORT_FILE"
else
  printf '%s\n' "$REPORT_FILE"
fi
