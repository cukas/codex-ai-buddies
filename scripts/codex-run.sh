#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

PROMPT=""
CWD="$(pwd)"
MODE="exec"
REVIEW_TARGET="uncommitted"
TIMEOUT="$(codex_buddies_timeout)"
MODEL="$(codex_buddies_config "codex_model" "")"
SANDBOX="$(codex_buddies_sandbox)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt) PROMPT="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --review-target) REVIEW_TARGET="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --sandbox) SANDBOX="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PROMPT" && ! -t 0 ]]; then
  PROMPT="$(cat)"
fi

[[ -z "$PROMPT" ]] && { echo "ERROR: --prompt is required" >&2; exit 1; }

CODEX_BIN="$(codex_buddies_find_buddy "codex" 2>/dev/null)" || {
  echo "ERROR: codex CLI not found. Install: npm install -g @openai/codex" >&2
  exit 1
}

SESSION_DIR="$(codex_buddies_session_dir)"
STAMP="$(date '+%Y%m%d-%H%M%S')"
OUTPUT_FILE="${SESSION_DIR}/codex-output-${STAMP}.md"
ERROR_FILE="${SESSION_DIR}/codex-error-${STAMP}.log"
NESTED_CODEX_HOME="${SESSION_DIR}/codex-home-${STAMP}"

mkdir -p "${NESTED_CODEX_HOME}/sessions" "${NESTED_CODEX_HOME}/memories" "${NESTED_CODEX_HOME}/tmp"

for file_name in auth.json config.toml version.json; do
  if [[ -f "${HOME}/.codex/${file_name}" && ! -e "${NESTED_CODEX_HOME}/${file_name}" ]]; then
    cp "${HOME}/.codex/${file_name}" "${NESTED_CODEX_HOME}/${file_name}" 2>/dev/null || true
  fi
done

for dir_name in skills plugins rules; do
  if [[ -d "${HOME}/.codex/${dir_name}" && ! -e "${NESTED_CODEX_HOME}/${dir_name}" ]]; then
    ln -s "${HOME}/.codex/${dir_name}" "${NESTED_CODEX_HOME}/${dir_name}" 2>/dev/null || true
  fi
done

EXIT_CODE=0
if [[ "$MODE" == "review" ]]; then
  CMD=("$CODEX_BIN" -C "$CWD")
  [[ -n "$MODEL" ]] && CMD+=(-m "$MODEL")
  CMD+=(review)
  case "$REVIEW_TARGET" in
    uncommitted) CMD+=(--uncommitted) ;;
    branch:*) CMD+=(--base "${REVIEW_TARGET#branch:}") ;;
    commit:*) CMD+=(--commit "${REVIEW_TARGET#commit:}") ;;
  esac
  CMD+=("$PROMPT")
  CODEX_HOME="$NESTED_CODEX_HOME" codex_buddies_run_with_timeout "$TIMEOUT" "${CMD[@]}" >"$OUTPUT_FILE" 2>"$ERROR_FILE" || EXIT_CODE=$?
else
  CMD=("$CODEX_BIN" exec --ephemeral -C "$CWD" -s "$SANDBOX")
  if ! git -C "$CWD" rev-parse --show-toplevel >/dev/null 2>&1; then
    CMD+=(--skip-git-repo-check)
  fi
  [[ -n "$MODEL" ]] && CMD+=(-m "$MODEL")
  CMD+=(-o "$OUTPUT_FILE" "$PROMPT")
  CODEX_HOME="$NESTED_CODEX_HOME" codex_buddies_run_with_timeout "$TIMEOUT" "${CMD[@]}" >/dev/null 2>"$ERROR_FILE" || EXIT_CODE=$?
fi

if [[ $EXIT_CODE -eq 124 ]]; then
  printf 'TIMEOUT: Codex did not complete within %ss\n' "$TIMEOUT" > "$OUTPUT_FILE"
elif [[ $EXIT_CODE -ne 0 ]]; then
  {
    printf 'ERROR: Codex exited with code %s\n\n' "$EXIT_CODE"
    printf -- '--- stderr ---\n'
    cat "$ERROR_FILE" 2>/dev/null || true
  } > "$OUTPUT_FILE"
fi

printf '%s\n' "$OUTPUT_FILE"
