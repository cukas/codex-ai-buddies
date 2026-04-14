#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

QUESTION=""
CWD="$(pwd)"
ENGINES=""
TIMEOUT="$(codex_buddies_timeout)"
PRINT_REPORT="false"
LOCAL_ONLY="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --question) QUESTION="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --engines) ENGINES="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --print-report) PRINT_REPORT="true"; shift 1 ;;
    --local-only) LOCAL_ONLY="true"; shift 1 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$QUESTION" ]] && { echo "ERROR: --question is required" >&2; exit 1; }

tribunal_failure_issue() {
  local text cleaned issue
  text="$1"
  cleaned="$(printf '%s' "$text" \
    | perl -pe 's/\e\[[0-9;]*[a-zA-Z]//g; s/\e\][^\x07]*\x07//g' \
    | sed '/^ERROR: .* exited with code/d;/^--- stderr ---/d;/^Reading additional input from stdin/d;/^OpenAI Codex/d;/^--------/d;/^user$/d;/^codex$/d' \
    | awk 'NF {print; if (++count == 6) exit}')"
  issue="$(printf '%s\n' "$cleaned" | sed -n '1p')"
  [[ -n "$issue" ]] || issue="Buddy did not return a usable debate response."
  printf '%s\n' "$issue"
}

if [[ -n "$ENGINES" ]]; then
  IFS=',' read -r -a ENGINE_LIST <<< "$ENGINES"
else
  AVAILABLE="$(codex_buddies_default_buddy_roster)"
  IFS=',' read -r -a ENGINE_LIST <<< "$AVAILABLE"
fi

if [[ "$LOCAL_ONLY" == "true" ]]; then
  SELECTED="$(codex_buddies_csv_local_only "$(IFS=,; printf '%s' "${ENGINE_LIST[*]-}")")"
  IFS=',' read -r -a ENGINE_LIST <<< "$SELECTED"
fi

if [[ ${#ENGINE_LIST[@]} -lt 2 ]]; then
  codex_buddies_no_buddies_error "tribunal" >&2
  exit 1
fi

FOR_ENGINE="${ENGINE_LIST[0]}"
AGAINST_ENGINE="${ENGINE_LIST[1]}"
SESSION_DIR="$(codex_buddies_session_dir)"
RUN_DIR="${SESSION_DIR}/tribunal-$(date '+%Y%m%d-%H%M%S')"
mkdir -p "$RUN_DIR"

OPEN_FOR="$(codex_buddies_dispatch_buddy "$FOR_ENGINE" "$CWD" "$(codex_buddies_build_tribunal_prompt "$QUESTION" "FOR")" "$TIMEOUT" exec)"
OPEN_AGAINST="$(codex_buddies_dispatch_buddy "$AGAINST_ENGINE" "$CWD" "$(codex_buddies_build_tribunal_prompt "$QUESTION" "AGAINST")" "$TIMEOUT" exec)"

FOR_TEXT="$(cat "$OPEN_FOR" 2>/dev/null || true)"
AGAINST_TEXT="$(cat "$OPEN_AGAINST" 2>/dev/null || true)"

REBUT_FOR="$(codex_buddies_dispatch_buddy "$FOR_ENGINE" "$CWD" "$(codex_buddies_build_tribunal_prompt "$QUESTION" "FOR rebuttal" "$AGAINST_TEXT")" "$TIMEOUT" exec)"
REBUT_AGAINST="$(codex_buddies_dispatch_buddy "$AGAINST_ENGINE" "$CWD" "$(codex_buddies_build_tribunal_prompt "$QUESTION" "AGAINST rebuttal" "$FOR_TEXT")" "$TIMEOUT" exec)"

REPORT_FILE="${RUN_DIR}/tribunal.md"
FOR_REBUT_TEXT="$(cat "$REBUT_FOR" 2>/dev/null || true)"
AGAINST_REBUT_TEXT="$(cat "$REBUT_AGAINST" 2>/dev/null || true)"
VALID_COUNT=0

for text in "$FOR_TEXT" "$AGAINST_TEXT"; do
  if [[ -n "$text" ]] && [[ "$text" != ERROR:* ]] && [[ "$text" != TIMEOUT:* ]]; then
    VALID_COUNT=$((VALID_COUNT + 1))
  fi
done

{
  printf '# Tribunal\n\n'
  printf 'Question: %s\n\n' "$QUESTION"
  printf 'Buddies: `%s` vs `%s`\n\n' "$FOR_ENGINE" "$AGAINST_ENGINE"
  printf '## Debate\n\n'

  if [[ -n "$FOR_TEXT" ]] && [[ "$FOR_TEXT" != ERROR:* ]] && [[ "$FOR_TEXT" != TIMEOUT:* ]]; then
    printf '### %s opening\n\n```text\n%s\n```\n\n' "$FOR_ENGINE" "$FOR_TEXT"
  else
    printf '### %s opening\n\nStatus: failed locally\n\nIssue: %s\n\n' "$FOR_ENGINE" "$(tribunal_failure_issue "$FOR_TEXT")"
  fi

  if [[ -n "$AGAINST_TEXT" ]] && [[ "$AGAINST_TEXT" != ERROR:* ]] && [[ "$AGAINST_TEXT" != TIMEOUT:* ]]; then
    printf '### %s opening\n\n```text\n%s\n```\n\n' "$AGAINST_ENGINE" "$AGAINST_TEXT"
  else
    printf '### %s opening\n\nStatus: failed locally\n\nIssue: %s\n\n' "$AGAINST_ENGINE" "$(tribunal_failure_issue "$AGAINST_TEXT")"
  fi

  if [[ -n "$FOR_REBUT_TEXT" ]] && [[ "$FOR_REBUT_TEXT" != ERROR:* ]] && [[ "$FOR_REBUT_TEXT" != TIMEOUT:* ]]; then
    printf '### %s rebuttal\n\n```text\n%s\n```\n\n' "$FOR_ENGINE" "$FOR_REBUT_TEXT"
  fi

  if [[ -n "$AGAINST_REBUT_TEXT" ]] && [[ "$AGAINST_REBUT_TEXT" != ERROR:* ]] && [[ "$AGAINST_REBUT_TEXT" != TIMEOUT:* ]]; then
    printf '### %s rebuttal\n\n```text\n%s\n```\n\n' "$AGAINST_ENGINE" "$AGAINST_REBUT_TEXT"
  fi

  printf '## Outcome\n\n'
  if (( VALID_COUNT >= 2 )); then
    printf -- '- Both buddies returned usable opening arguments.\n'
    printf -- '- Compare the openings and rebuttals above to identify the strongest claim and the unresolved disagreement.\n'
  elif (( VALID_COUNT == 1 )); then
    printf -- '- Only one buddy returned a usable opening argument, so this was not a full debate.\n'
    printf -- '- Treat the surviving argument as one-sided input, not a tribunal verdict.\n'
  else
    printf -- '- No usable buddy debate was produced in this run.\n'
    printf -- '- The failures above are local execution failures, not evidence that one side won.\n'
  fi
} > "$REPORT_FILE"

if [[ "$PRINT_REPORT" == "true" ]]; then
  cat "$REPORT_FILE"
else
  printf '%s\n' "$REPORT_FILE"
fi
