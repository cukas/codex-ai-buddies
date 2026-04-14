#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

DIR=""
FITNESS=""
LABEL="engine"
TIMEOUT="300"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --fitness) FITNESS="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$DIR" ]] && { echo "ERROR: --dir is required" >&2; exit 1; }
[[ -z "$FITNESS" ]] && { echo "ERROR: --fitness is required" >&2; exit 1; }

SESSION_DIR="$(codex_buddies_session_dir)"
PATCH_FILE="${SESSION_DIR}/${LABEL}-patch.diff"
LOG_FILE="${SESSION_DIR}/${LABEL}-fitness.log"
RESULT_FILE="${SESSION_DIR}/${LABEL}-fitness.json"

(
  cd "$DIR"
  git add -A -- ':!node_modules' ':!**/node_modules' ':!*.tsbuildinfo' >/dev/null 2>&1 || true
  git diff --cached > "$PATCH_FILE" || true
)

DIFF_LINES="$(wc -l < "$PATCH_FILE" 2>/dev/null | tr -d ' ' || echo 0)"
FILES_CHANGED="$(grep -c '^diff --git ' "$PATCH_FILE" 2>/dev/null || true)"
FILES_CHANGED="${FILES_CHANGED:-0}"

STARTED_AT="$(date +%s)"
EXIT_CODE=0
(
  cd "$DIR"
  codex_buddies_run_with_timeout "$TIMEOUT" bash -lc "$FITNESS"
) >"$LOG_FILE" 2>&1 || EXIT_CODE=$?
ENDED_AT="$(date +%s)"
DURATION="$((ENDED_AT - STARTED_AT))"

PASS="false"
[[ $EXIT_CODE -eq 0 ]] && PASS="true"
COMPOSITE="$(codex_buddies_compute_score "$PASS" "$DIFF_LINES" "$FILES_CHANGED" "$DURATION")"

if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg label "$LABEL" \
    --arg dir "$DIR" \
    --arg pass "$PASS" \
    --argjson diff_lines "${DIFF_LINES:-0}" \
    --argjson files_changed "${FILES_CHANGED:-0}" \
    --argjson duration "${DURATION:-0}" \
    --argjson exit_code "${EXIT_CODE:-1}" \
    --argjson composite_score "${COMPOSITE:-0}" \
    --arg patch_file "$PATCH_FILE" \
    --arg log_file "$LOG_FILE" \
    '{
      label: $label,
      dir: $dir,
      pass: ($pass == "true"),
      diff_lines: $diff_lines,
      files_changed: $files_changed,
      duration: $duration,
      exit_code: $exit_code,
      composite_score: $composite_score,
      patch_file: $patch_file,
      log_file: $log_file
    }' > "$RESULT_FILE"
else
  printf '{"label":"%s","pass":%s,"diff_lines":%s,"files_changed":%s,"duration":%s,"exit_code":%s,"composite_score":%s,"patch_file":"%s","log_file":"%s"}\n' \
    "$LABEL" "$PASS" "${DIFF_LINES:-0}" "${FILES_CHANGED:-0}" "${DURATION:-0}" "${EXIT_CODE:-1}" "${COMPOSITE:-0}" "$PATCH_FILE" "$LOG_FILE" > "$RESULT_FILE"
fi

printf '%s\n' "$RESULT_FILE"
