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

PROMPT_PREFIX="$(codex_buddies_buddy_json_query "$BUDDY_ID" '.prompt_prefix' "")"
if [[ -n "$PROMPT_PREFIX" ]]; then
  PROMPT="${PROMPT_PREFIX}"$'\n\n'"${PROMPT}"
fi

SESSION_DIR="$(codex_buddies_session_dir)"
STAMP="$(date '+%Y%m%d-%H%M%S')"
OUTPUT_FILE="${SESSION_DIR}/${BUDDY_ID}-output-${STAMP}.md"
ERROR_FILE="${SESSION_DIR}/${BUDDY_ID}-error-${STAMP}.log"
PROMPT_FILE="$(mktemp "${SESSION_DIR}/${BUDDY_ID}-prompt-XXXXXX")"
printf '%s' "$PROMPT" > "$PROMPT_FILE"

MODE_QUERY=".${MODE}.args[]?"
MODEL_FLAG="$(codex_buddies_buddy_json_query "$BUDDY_ID" '.model.flag' "")"
MODEL_VALUE="$(codex_buddies_buddy_model "$BUDDY_ID")"
PROMPT_VIA_STDIN="$(codex_buddies_buddy_json_query "$BUDDY_ID" ".${MODE}.stdin_prompt" "false")"
STRIP_ANSI="$(codex_buddies_buddy_json_query "$BUDDY_ID" ".${MODE}.strip_ansi" "$(codex_buddies_buddy_json_query "$BUDDY_ID" '.strip_ansi' 'false')")"

ARGS=()
if command -v jq >/dev/null 2>&1; then
  while IFS= read -r raw_arg; do
    [[ -n "$raw_arg" ]] || continue
    ARGS+=("$(codex_buddies_resolve_template_arg "$raw_arg" "$PROMPT" "$CWD" "$TIMEOUT" "$MODEL_VALUE")")
  done < <(jq -r "$MODE_QUERY" "$(codex_buddies_find_buddy_json "$BUDDY_ID")" 2>/dev/null || true)
fi

if [[ ${#ARGS[@]} -eq 0 ]]; then
  echo "ERROR: ${BUDDY_ID} has no ${MODE} args configured" >&2
  rm -f "$PROMPT_FILE"
  exit 1
fi

if [[ -n "$MODEL_VALUE" && -n "$MODEL_FLAG" ]]; then
  if [[ " ${ARGS[*]} " != *" ${MODEL_FLAG} "* ]]; then
    ARGS=("$MODEL_FLAG" "$MODEL_VALUE" "${ARGS[@]}")
  fi
fi

EXIT_CODE=0
if [[ "$PROMPT_VIA_STDIN" == "true" ]]; then
  (
    cd "$CWD"
    codex_buddies_run_with_timeout "$TIMEOUT" "$BUDDY_BIN" "${ARGS[@]}" < "$PROMPT_FILE"
  ) >"$OUTPUT_FILE" 2>"$ERROR_FILE" || EXIT_CODE=$?
else
  (
    cd "$CWD"
    codex_buddies_run_with_timeout "$TIMEOUT" "$BUDDY_BIN" "${ARGS[@]}" </dev/null
  ) >"$OUTPUT_FILE" 2>"$ERROR_FILE" || EXIT_CODE=$?
fi

rm -f "$PROMPT_FILE"

if [[ "$STRIP_ANSI" == "true" && -f "$OUTPUT_FILE" && -s "$OUTPUT_FILE" ]]; then
  STRIP_TMP="${OUTPUT_FILE}.strip"
  perl -pe 's/\e\[[0-9;]*[a-zA-Z]//g; s/\e\][^\x07]*\x07//g' "$OUTPUT_FILE" > "$STRIP_TMP" && mv "$STRIP_TMP" "$OUTPUT_FILE"
fi

if [[ $EXIT_CODE -eq 124 ]]; then
  printf 'TIMEOUT: %s did not complete within %ss\n' "$BUDDY_ID" "$TIMEOUT" > "$OUTPUT_FILE"
elif [[ $EXIT_CODE -ne 0 ]]; then
  {
    printf 'ERROR: %s exited with code %s\n\n' "$BUDDY_ID" "$EXIT_CODE"
    printf -- '--- stderr ---\n'
    cat "$ERROR_FILE" 2>/dev/null || true
    if [[ "$BUDDY_ID" == "gemini" ]] && grep -q 'Invalid regular expression flags' "$ERROR_FILE" 2>/dev/null; then
      printf '\n--- note ---\n'
      printf 'Gemini CLI failed before prompt execution. This points to a local Gemini CLI or Node runtime mismatch; reinstall Gemini CLI or upgrade the runtime used to launch it.\n'
    fi
  } > "$OUTPUT_FILE"
fi

printf '%s\n' "$OUTPUT_FILE"
