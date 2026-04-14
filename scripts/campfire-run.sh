#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

TASK=""
CWD="$(pwd)"
ENGINES=""
FITNESS=""
TIMEOUT="1800"
PRINT_REPORT="false"
MODE=""
LOCAL_ONLY="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --engines) ENGINES="$2"; shift 2 ;;
    --fitness) FITNESS="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --print-report) PRINT_REPORT="true"; shift 1 ;;
    --local-only) LOCAL_ONLY="true"; shift 1 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$TASK" ]] && { echo "ERROR: --task is required" >&2; exit 1; }

if [[ -z "$FITNESS" ]]; then
  FITNESS="$(bash "${SCRIPT_DIR}/detect-project.sh" "$CWD" | jq -r '.fitness_cmd // "true"' 2>/dev/null || echo true)"
fi

if [[ -z "$MODE" ]]; then
  lower="$(printf '%s' "$TASK" | tr '[:upper:]' '[:lower:]')"
  risk="$(codex_buddies_detect_risk_level "$TASK")"

  if [[ "$lower" == *"brainstorm"* || "$lower" == *"what's missing"* || "$lower" == *"what is missing"* || "$lower" == *"compare approaches"* || "$lower" == *"review gaps"* ]]; then
    MODE="brainstorm"
  elif [[ "$lower" == *"evil pipeline"* || "$lower" == *"stress test"* || "$lower" == *"double-check"* || "$lower" == *"be adversarial"* || "$risk" == "high" ]]; then
    MODE="evil-pipeline"
  else
    MODE="forge"
  fi
fi

case "$MODE" in
  brainstorm)
    CMD=(bash "${SCRIPT_DIR}/brainstorm-run.sh" --task "$TASK" --cwd "$CWD" --timeout "$TIMEOUT")
    [[ -n "$ENGINES" ]] && CMD+=(--engines "$ENGINES")
    [[ "$LOCAL_ONLY" == "true" ]] && CMD+=(--local-only)
    [[ "$PRINT_REPORT" == "true" ]] && CMD+=(--print-report)
    ;;
  forge)
    CMD=(bash "${SCRIPT_DIR}/forge-run.sh" --task "$TASK" --cwd "$CWD" --fitness "$FITNESS" --timeout "$TIMEOUT")
    [[ -n "$ENGINES" ]] && CMD+=(--engines "$ENGINES")
    [[ "$LOCAL_ONLY" == "true" ]] && CMD+=(--local-only)
    [[ "$PRINT_REPORT" == "true" ]] && CMD+=(--print-report)
    ;;
  evil-pipeline)
    CMD=(bash "${SCRIPT_DIR}/evil-pipeline.sh" --task "$TASK" --cwd "$CWD" --fitness "$FITNESS" --timeout "$TIMEOUT")
    [[ -n "$ENGINES" ]] && CMD+=(--engines "$ENGINES")
    [[ "$LOCAL_ONLY" == "true" ]] && CMD+=(--local-only)
    [[ "$PRINT_REPORT" == "true" ]] && CMD+=(--print-report)
    ;;
  *)
    echo "ERROR: unsupported mode: $MODE" >&2
    exit 1
    ;;
esac

if [[ "$PRINT_REPORT" == "true" ]]; then
  {
    printf '# Campfire\n\n'
    printf 'Selected mode: `%s`\n\n' "$MODE"
    "${CMD[@]}"
  }
else
  "${CMD[@]}"
fi
