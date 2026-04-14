#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

PROMPT="Focus on the highest-signal bugs, regressions, and missing tests first."
CWD="$(pwd)"
ENGINES=""
TIMEOUT="$(codex_buddies_timeout)"
REVIEW_TARGET="uncommitted"
PRINT_REPORT="false"
LOCAL_ONLY="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt) PROMPT="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --engines) ENGINES="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --review-target) REVIEW_TARGET="$2"; shift 2 ;;
    --print-report) PRINT_REPORT="true"; shift 1 ;;
    --local-only) LOCAL_ONLY="true"; shift 1 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

review_collect_signals() {
  local text lower
  text="$1"
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    *missing\ test*|*add\ test*|*coverage*|*test\ case*)
      TEST_COUNT=$((TEST_COUNT + 1))
      ;;
  esac
  case "$lower" in
    *regression*|*break*|*broken*|*behavior\ change*|*backward\ compat*)
      REGRESSION_COUNT=$((REGRESSION_COUNT + 1))
      ;;
  esac
  case "$lower" in
    *security*|*injection*|*auth*|*permission*|*leak*|*secret*)
      SECURITY_COUNT=$((SECURITY_COUNT + 1))
      ;;
  esac
  case "$lower" in
    *performance*|*slow*|*n\+1*|*wasteful*|*expensive*)
      PERFORMANCE_COUNT=$((PERFORMANCE_COUNT + 1))
      ;;
  esac
  case "$lower" in
    *api*|*contract*|*edge\ case*|*validation*|*null*|*undefined*)
      CORRECTNESS_COUNT=$((CORRECTNESS_COUNT + 1))
      ;;
  esac
}

review_failure_issue() {
  local text cleaned issue
  text="$1"
  cleaned="$(printf '%s' "$text" \
    | perl -pe 's/\e\[[0-9;]*[a-zA-Z]//g; s/\e\][^\x07]*\x07//g' \
    | sed '/^ERROR: .* exited with code/d;/^--- stderr ---/d' \
    | awk 'NF {print; if (++count == 6) exit}')"
  issue="$(printf '%s\n' "$cleaned" | sed -n '1p')"
  [[ -n "$issue" ]] || issue="Buddy did not return a usable review."
  printf '%s\n' "$issue"
}

AVAILABLE="$(codex_buddies_default_buddy_roster)"
if [[ -z "$AVAILABLE" ]]; then
  codex_buddies_no_buddies_error "review" >&2
  exit 1
fi

if [[ -n "$ENGINES" ]]; then
  SELECTED="$ENGINES"
else
  SELECTED="$AVAILABLE"
fi
if [[ "$LOCAL_ONLY" == "true" ]]; then
  SELECTED="$(codex_buddies_csv_local_only "$SELECTED")"
fi
if [[ -z "$SELECTED" ]]; then
  codex_buddies_no_buddies_error "review" >&2
  exit 1
fi

IFS=',' read -r -a ENGINE_LIST <<< "$SELECTED"
SESSION_DIR="$(codex_buddies_session_dir)"
RUN_DIR="${SESSION_DIR}/review-$(date '+%Y%m%d-%H%M%S')"
mkdir -p "$RUN_DIR"

PIDS=()
for engine in "${ENGINE_LIST[@]}"; do
  [[ -n "$engine" ]] || continue
  (
    output_path="$(codex_buddies_dispatch_buddy "$engine" "$CWD" "$PROMPT" "$TIMEOUT" review "$REVIEW_TARGET")"
    printf '%s\n' "$output_path" > "${RUN_DIR}/${engine}.path"
  ) &
  PIDS+=("$!")
done

for pid in "${PIDS[@]}"; do
  wait "$pid"
done

REPORT_FILE="${RUN_DIR}/review.md"
{
  printf '# Buddy Review\n\n'
  printf 'Review target: `%s`\n\n' "$REVIEW_TARGET"
  printf 'Prompt: %s\n\n' "$PROMPT"
  printf '## Engine Reviews\n\n'
} > "$REPORT_FILE"

VALID_COUNT=0
TEST_COUNT=0
REGRESSION_COUNT=0
SECURITY_COUNT=0
PERFORMANCE_COUNT=0
CORRECTNESS_COUNT=0

for engine in "${ENGINE_LIST[@]}"; do
  [[ -f "${RUN_DIR}/${engine}.path" ]] || continue
  response_file="$(cat "${RUN_DIR}/${engine}.path")"
  response="$(cat "$response_file" 2>/dev/null || true)"

  if [[ "$response" == ERROR:* || "$response" == TIMEOUT:* ]]; then
    issue="$(review_failure_issue "$response")"
    {
      printf '### %s\n\n' "$engine"
      printf 'Status: failed locally\n\n'
      printf 'Issue: %s\n\n' "$issue"
    } >> "$REPORT_FILE"
    continue
  fi

  {
    printf '### %s\n\n' "$engine"
    printf '```text\n%s\n```\n\n' "$response"
  } >> "$REPORT_FILE"
  review_collect_signals "$response"
  VALID_COUNT=$((VALID_COUNT + 1))
done

{
  printf '## Convergence\n\n'
} >> "$REPORT_FILE"

CONVERGENCE_FOUND="false"
if (( TEST_COUNT >= 2 )); then
  printf '- Multiple buddies independently called out missing tests or coverage gaps.\n' >> "$REPORT_FILE"
  CONVERGENCE_FOUND="true"
fi
if (( REGRESSION_COUNT >= 2 )); then
  printf '- There is overlap around potential regressions or behavior changes.\n' >> "$REPORT_FILE"
  CONVERGENCE_FOUND="true"
fi
if (( SECURITY_COUNT >= 2 )); then
  printf '- More than one buddy surfaced a security or permission-related concern.\n' >> "$REPORT_FILE"
  CONVERGENCE_FOUND="true"
fi
if (( PERFORMANCE_COUNT >= 2 )); then
  printf '- Performance risk came up repeatedly across the reviews.\n' >> "$REPORT_FILE"
  CONVERGENCE_FOUND="true"
fi
if (( CORRECTNESS_COUNT >= 2 )); then
  printf '- Correctness or contract-validation issues appeared in multiple reviews.\n' >> "$REPORT_FILE"
  CONVERGENCE_FOUND="true"
fi
if [[ "$CONVERGENCE_FOUND" != "true" ]]; then
  if (( VALID_COUNT >= 2 )); then
    printf '- Buddies produced usable reviews, but they did not strongly converge on a single dominant risk.\n' >> "$REPORT_FILE"
  else
    printf '- Not enough successful buddy reviews to assess convergence.\n' >> "$REPORT_FILE"
  fi
fi
printf '\n' >> "$REPORT_FILE"

if [[ "$PRINT_REPORT" == "true" ]]; then
  cat "$REPORT_FILE"
else
  printf '%s\n' "$REPORT_FILE"
fi
