#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

QUESTION=""
CWD="$(pwd)"
ENGINES=""
TIMEOUT="$(codex_buddies_timeout)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --question) QUESTION="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --engines) ENGINES="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$QUESTION" ]] && { echo "ERROR: --question is required" >&2; exit 1; }

if [[ -n "$ENGINES" ]]; then
  IFS=',' read -r -a ENGINE_LIST <<< "$ENGINES"
else
  AVAILABLE="$(codex_buddies_default_buddy_roster)"
  IFS=',' read -r -a ENGINE_LIST <<< "$AVAILABLE"
fi

[[ ${#ENGINE_LIST[@]} -lt 2 ]] && { echo "ERROR: tribunal needs at least two buddies" >&2; exit 1; }

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
{
  printf '# Tribunal\n\n'
  printf 'Question: %s\n\n' "$QUESTION"
  printf '## %s opening\n\n```text\n%s\n```\n\n' "$FOR_ENGINE" "$FOR_TEXT"
  printf '## %s opening\n\n```text\n%s\n```\n\n' "$AGAINST_ENGINE" "$AGAINST_TEXT"
  printf '## %s rebuttal\n\n```text\n%s\n```\n\n' "$FOR_ENGINE" "$(cat "$REBUT_FOR" 2>/dev/null || true)"
  printf '## %s rebuttal\n\n```text\n%s\n```\n' "$AGAINST_ENGINE" "$(cat "$REBUT_AGAINST" 2>/dev/null || true)"
} > "$REPORT_FILE"

printf '%s\n' "$REPORT_FILE"
