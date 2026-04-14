#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

PROMPT=""
CWD="$(pwd)"
MODE="exec"
REVIEW_TARGET="uncommitted"
TIMEOUT="$(codex_buddies_timeout)"
MODEL="$(codex_buddies_buddy_model "gemini")"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt) PROMPT="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --review-target) REVIEW_TARGET="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PROMPT" && ! -t 0 ]]; then
  PROMPT="$(cat)"
fi
[[ -z "$PROMPT" ]] && { echo "ERROR: --prompt is required" >&2; exit 1; }

GEMINI_BIN="$(codex_buddies_find_buddy "gemini" 2>/dev/null)" || {
  echo "ERROR: gemini CLI not found. Install: npm install -g @google/gemini-cli" >&2
  exit 1
}

SESSION_DIR="$(codex_buddies_session_dir)"
STAMP="$(date '+%Y%m%d-%H%M%S')"
OUTPUT_FILE="${SESSION_DIR}/gemini-output-${STAMP}.md"
ERROR_FILE="${SESSION_DIR}/gemini-error-${STAMP}.log"

FINAL_PROMPT="$PROMPT"
if [[ "$MODE" == "review" ]]; then
  FINAL_PROMPT="$(codex_buddies_build_review_prompt "$PROMPT" "$CWD" "$REVIEW_TARGET")"
fi

GEMINI_ARGS=(-p "$FINAL_PROMPT" --approval-mode yolo)
[[ "$MODE" == "review" ]] && GEMINI_ARGS=( -p "$FINAL_PROMPT" --approval-mode plan )
[[ -n "$MODEL" ]] && GEMINI_ARGS+=(--model "$MODEL")

EXIT_CODE=0
(
  cd "$CWD"
  codex_buddies_run_with_timeout "$TIMEOUT" "$GEMINI_BIN" "${GEMINI_ARGS[@]}"
) >"$OUTPUT_FILE" 2>"$ERROR_FILE" || EXIT_CODE=$?

if [[ $EXIT_CODE -eq 124 ]]; then
  printf 'TIMEOUT: Gemini did not complete within %ss\n' "$TIMEOUT" > "$OUTPUT_FILE"
elif [[ $EXIT_CODE -ne 0 ]]; then
  {
    printf 'ERROR: Gemini exited with code %s\n\n' "$EXIT_CODE"
    printf -- '--- stderr ---\n'
    cat "$ERROR_FILE" 2>/dev/null || true
  } > "$OUTPUT_FILE"
fi

printf '%s\n' "$OUTPUT_FILE"
