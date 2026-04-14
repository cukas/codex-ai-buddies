#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

TASK=""
CWD="$(pwd)"
ENGINES=""
TIMEOUT="$(codex_buddies_timeout)"
PRINT_REPORT="false"
LOCAL_ONLY="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --engines) ENGINES="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --print-report) PRINT_REPORT="true"; shift 1 ;;
    --local-only) LOCAL_ONLY="true"; shift 1 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$TASK" ]] && { echo "ERROR: --task is required" >&2; exit 1; }

brainstorm_collect_signals() {
  local text lower
  text="$1"
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    *cross-file*|*multi-file*|*symbol\ resolution*|*import*|*dependency\ graph*|*circular\ dep*|*graph-aware*)
      CROSS_FILE_COUNT=$((CROSS_FILE_COUNT + 1))
      ;;
  esac
  case "$lower" in
    *react*|*tsx*|*hooks*|*context*|*fragment\ key*|*render\ side\ effect*)
      REACT_COUNT=$((REACT_COUNT + 1))
      ;;
  esac
  case "$lower" in
    *next*|*rsc*|*server\ action*|*userouter*|*usesearchparams*|*client\ boundary*|*server/client*)
      NEXT_COUNT=$((NEXT_COUNT + 1))
      ;;
  esac
  case "$lower" in
    *taint*|*dataflow*|*handler-level*|*spec\ coverage*|*sink*|*source\ tracking*)
      DATAFLOW_COUNT=$((DATAFLOW_COUNT + 1))
      ;;
  esac
  case "$lower" in
    *.kern*|*kern\ semantic*|*ir*|*node\ type*|*target-aware*|*runtime\ behavior*|*provider\ scope*|*machine\ transition*)
      KERN_COUNT=$((KERN_COUNT + 1))
      ;;
  esac
  case "$lower" in
    *review\ pipeline*|*rule\ registry*|*wiring*|*dynamic\ rule*|*rule\ coverage*|*review\ ux*)
      PIPELINE_COUNT=$((PIPELINE_COUNT + 1))
      ;;
  esac
}

brainstorm_failure_issue() {
  local text cleaned issue
  text="$1"
  cleaned="$(printf '%s' "$text" \
    | perl -pe 's/\e\[[0-9;]*[a-zA-Z]//g; s/\e\][^\x07]*\x07//g' \
    | sed '/^ERROR: .* exited with code/d;/^--- stderr ---/d;/^Reading additional input from stdin/d;/^OpenAI Codex/d;/^--------/d;/^user$/d;/^codex$/d' \
    | awk 'NF {print; if (++count == 6) exit}')"
  issue="$(printf '%s\n' "$cleaned" | sed -n '1p')"
  [[ -n "$issue" ]] || issue="Buddy did not return valid JSON."
  printf '%s\n' "$issue"
}

AVAILABLE="$(codex_buddies_default_buddy_roster)"
[[ -z "$AVAILABLE" ]] && { echo "ERROR: no buddies are available" >&2; exit 1; }

if [[ -n "$ENGINES" ]]; then
  SELECTED="$ENGINES"
else
  SELECTED="$AVAILABLE"
fi
if [[ "$LOCAL_ONLY" == "true" ]]; then
  SELECTED="$(codex_buddies_csv_local_only "$SELECTED")"
fi
[[ -n "$SELECTED" ]] || { echo "ERROR: no local-only buddies are available for brainstorm" >&2; exit 1; }

IFS=',' read -r -a ENGINE_LIST <<< "$SELECTED"
CONTEXT="$(codex_buddies_project_context "$CWD")"
PROMPT="$(codex_buddies_build_brainstorm_prompt "$TASK" "$CONTEXT")"

SESSION_DIR="$(codex_buddies_session_dir)"
RUN_DIR="${SESSION_DIR}/brainstorm-$(date '+%Y%m%d-%H%M%S')"
mkdir -p "$RUN_DIR"

PIDS=()
for engine in "${ENGINE_LIST[@]}"; do
  [[ -n "$engine" ]] || continue
  (
    output_path="$(codex_buddies_dispatch_buddy "$engine" "$CWD" "$PROMPT" "$TIMEOUT" exec)"
    printf '%s\n' "$output_path" > "${RUN_DIR}/${engine}.path"
  ) &
  PIDS+=("$!")
done

for pid in "${PIDS[@]}"; do
  wait "$pid"
done

REPORT_FILE="${RUN_DIR}/brainstorm.md"
JSON_FILE="${RUN_DIR}/brainstorm.json"

{
  printf '# Brainstorm Report\n\n'
  printf 'Task: %s\n\n' "$TASK"
  printf '## Buddy Outputs\n\n'
} > "$REPORT_FILE"

JSON_ROWS=()
BEST_ENGINE=""
BEST_CONFIDENCE=-1
VALID_COUNT=0
FAIL_COUNT=0
CROSS_FILE_COUNT=0
REACT_COUNT=0
NEXT_COUNT=0
DATAFLOW_COUNT=0
KERN_COUNT=0
PIPELINE_COUNT=0

for engine in "${ENGINE_LIST[@]}"; do
  [[ -f "${RUN_DIR}/${engine}.path" ]] || continue
  response_file="$(cat "${RUN_DIR}/${engine}.path")"
  response="$(cat "$response_file" 2>/dev/null || true)"

  if command -v jq >/dev/null 2>&1 && printf '%s' "$response" | jq -e . >/dev/null 2>&1; then
    confidence="$(printf '%s' "$response" | jq -r '.confidence // 0' 2>/dev/null || echo 0)"
    approach="$(printf '%s' "$response" | jq -r '.approach // ""' 2>/dev/null || true)"
    why_you="$(printf '%s' "$response" | jq -r '.why_you // ""' 2>/dev/null || true)"
    risks="$(printf '%s' "$response" | jq -r '.risks[]? // empty' 2>/dev/null || true)"

    {
      printf '### %s\n\n' "$engine"
      printf 'Confidence: `%s`\n\n' "$confidence"
      printf 'Approach: %s\n\n' "$approach"
      printf 'Why fit: %s\n\n' "$why_you"
      if [[ -n "$risks" ]]; then
        printf 'Risks:\n'
        while IFS= read -r risk; do
          [[ -n "$risk" ]] || continue
          printf '- %s\n' "$risk"
        done <<< "$risks"
        printf '\n'
      fi
    } >> "$REPORT_FILE"

    JSON_ROWS+=("$(jq -n --arg engine "$engine" --slurpfile data "$response_file" '{engine: $engine, response: $data[0]}')")
    brainstorm_collect_signals "${approach} ${why_you} ${risks}"
    VALID_COUNT=$((VALID_COUNT + 1))
    if [[ "$confidence" =~ ^[0-9]+$ ]] && (( confidence > BEST_CONFIDENCE )); then
      BEST_CONFIDENCE="$confidence"
      BEST_ENGINE="$engine"
    fi
  else
    issue="$(brainstorm_failure_issue "$response")"
    {
      printf '### %s\n\n' "$engine"
      printf 'Status: failed locally\n\n'
      printf 'Issue: %s\n\n' "$issue"
    } >> "$REPORT_FILE"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

if command -v jq >/dev/null 2>&1; then
  if [[ ${#JSON_ROWS[@]} -gt 0 ]]; then
    printf '%s\n' "${JSON_ROWS[@]}" | jq -s --arg task "$TASK" --arg best "$BEST_ENGINE" '{
      task: $task,
      winner: $best,
      responses: .
    }' > "$JSON_FILE"
  else
    jq -n --arg task "$TASK" '{task: $task, winner: "", responses: []}' > "$JSON_FILE"
  fi
fi

{
  printf '## Convergence\n\n'
} >> "$REPORT_FILE"

CONVERGENCE_FOUND="false"
if (( CROSS_FILE_COUNT >= 2 )); then
  printf '- Multiple buddies independently pointed to cross-file or graph-aware validation gaps.\n' >> "$REPORT_FILE"
  CONVERGENCE_FOUND="true"
fi
if (( KERN_COUNT >= 2 )); then
  printf '- There is strong overlap around missing `.kern` semantic or target-aware review coverage.\n' >> "$REPORT_FILE"
  CONVERGENCE_FOUND="true"
fi
if (( REACT_COUNT >= 2 )); then
  printf '- React/TSX review breadth looks under-covered beyond the current fundamentals.\n' >> "$REPORT_FILE"
  CONVERGENCE_FOUND="true"
fi
if (( NEXT_COUNT >= 2 )); then
  printf '- Several buddies called out Next.js or RSC-style client/server boundary checks as a likely blind spot.\n' >> "$REPORT_FILE"
  CONVERGENCE_FOUND="true"
fi
if (( DATAFLOW_COUNT >= 2 )); then
  printf '- Handler-level taint or dataflow analysis came up repeatedly as a missing capability.\n' >> "$REPORT_FILE"
  CONVERGENCE_FOUND="true"
fi
if (( PIPELINE_COUNT >= 2 )); then
  printf '- More than one buddy suggested the main gap may be review-pipeline wiring, not just missing standalone rules.\n' >> "$REPORT_FILE"
  CONVERGENCE_FOUND="true"
fi
if [[ "$CONVERGENCE_FOUND" != "true" ]]; then
  if (( VALID_COUNT >= 2 )); then
    printf '- Buddies overlapped only loosely; they agreed there are review gaps but diverged on the exact highest-priority area.\n' >> "$REPORT_FILE"
  else
    printf '- Not enough structured buddy responses to assess convergence.\n' >> "$REPORT_FILE"
  fi
fi
printf '\n' >> "$REPORT_FILE"

if [[ -n "$BEST_ENGINE" ]]; then
  {
    printf '## Winner\n\n'
    printf 'Recommended buddy: `%s` (%s%% confidence)\n' "$BEST_ENGINE" "$BEST_CONFIDENCE"
  } >> "$REPORT_FILE"
fi

if [[ "$PRINT_REPORT" == "true" ]]; then
  cat "$REPORT_FILE"
else
  printf '%s\n' "$REPORT_FILE"
fi
