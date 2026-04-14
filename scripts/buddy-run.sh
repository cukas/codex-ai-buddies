#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

BUDDY_ID=""
PROMPT=""
CWD="$(pwd)"
MODE="exec"
REVIEW_TARGET="uncommitted"
TIMEOUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) BUDDY_ID="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --review-target) REVIEW_TARGET="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$BUDDY_ID" ]] && { echo "ERROR: --id is required" >&2; exit 1; }
if [[ -z "$PROMPT" && ! -t 0 ]]; then
  PROMPT="$(cat)"
fi
[[ -z "$PROMPT" ]] && { echo "ERROR: --prompt is required" >&2; exit 1; }

BUDDY_BIN="$(codex_buddies_find_buddy "$BUDDY_ID" 2>/dev/null)" || {
  hint="$(codex_buddies_buddy_config "$BUDDY_ID" "install_hint" "")"
  echo "ERROR: ${BUDDY_ID} CLI not found.${hint:+ Install: $hint}" >&2
  exit 1
}

if [[ -z "$TIMEOUT" ]]; then
  TIMEOUT="$(codex_buddies_buddy_config "$BUDDY_ID" "timeout" "$(codex_buddies_timeout)")"
fi

if [[ "$MODE" == "review" ]]; then
  PROMPT="$(codex_buddies_build_review_prompt "$PROMPT" "$CWD" "$REVIEW_TARGET")"
fi

SESSION_DIR="$(codex_buddies_session_dir)"
STAMP="$(date '+%Y%m%d-%H%M%S')"
OUTPUT_FILE="${SESSION_DIR}/${BUDDY_ID}-output-${STAMP}.md"
ERROR_FILE="${SESSION_DIR}/${BUDDY_ID}-error-${STAMP}.log"
PROMPT_FILE="$(mktemp "${SESSION_DIR}/${BUDDY_ID}-prompt-XXXXXX.txt")"

printf '%s' "$PROMPT" > "$PROMPT_FILE"

EXIT_CODE=0
(
  cd "$CWD"
  codex_buddies_run_with_timeout "$TIMEOUT" "$BUDDY_BIN" < "$PROMPT_FILE" > "$OUTPUT_FILE" 2>"$ERROR_FILE"
) || EXIT_CODE=$?

rm -f "$PROMPT_FILE"

if [[ $EXIT_CODE -eq 124 ]]; then
  printf 'TIMEOUT: %s did not complete within %ss\n' "$BUDDY_ID" "$TIMEOUT" > "$OUTPUT_FILE"
elif [[ $EXIT_CODE -ne 0 ]]; then
  {
    printf 'ERROR: %s exited with code %s\n\n' "$BUDDY_ID" "$EXIT_CODE"
    printf -- '--- stderr ---\n'
    cat "$ERROR_FILE" 2>/dev/null || true
  } > "$OUTPUT_FILE"
fi

printf '%s\n' "$OUTPUT_FILE"
