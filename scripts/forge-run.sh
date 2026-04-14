#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

TASK=""
CWD=""
ENGINES=""
FITNESS=""
TIMEOUT="$(codex_buddies_forge_timeout)"
FITNESS_TIMEOUT="300"
FORGE_DIR=""
SYNTHESIS_ENABLED="$(codex_buddies_synthesis_enabled)"
SYNTHESIS_ENGINE="$(codex_buddies_synthesis_engine)"
SYNTHESIS_TIMEOUT="$(codex_buddies_synthesis_timeout)"
SYNTHESIS_TOP_N="$(codex_buddies_synthesis_top_n)"
PRINT_REPORT="false"
LOCAL_ONLY="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --engines) ENGINES="$2"; shift 2 ;;
    --fitness) FITNESS="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --fitness-timeout) FITNESS_TIMEOUT="$2"; shift 2 ;;
    --forge-dir) FORGE_DIR="$2"; shift 2 ;;
    --no-synthesis) SYNTHESIS_ENABLED="false"; shift 1 ;;
    --synthesis-engine) SYNTHESIS_ENGINE="$2"; shift 2 ;;
    --synthesis-timeout) SYNTHESIS_TIMEOUT="$2"; shift 2 ;;
    --synthesis-top-n) SYNTHESIS_TOP_N="$2"; shift 2 ;;
    --print-report) PRINT_REPORT="true"; shift 1 ;;
    --local-only) LOCAL_ONLY="true"; shift 1 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$TASK" ]] && { echo "ERROR: --task is required" >&2; exit 1; }
[[ -z "$CWD" ]] && { echo "ERROR: --cwd is required" >&2; exit 1; }

REPO_ROOT="$(cd "$CWD" && git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -z "$REPO_ROOT" ]] && { echo "ERROR: --cwd must be inside a git repository" >&2; exit 1; }

if [[ -z "$FITNESS" ]]; then
  FITNESS="$(bash "${SCRIPT_DIR}/detect-project.sh" "$CWD" | jq -r '.fitness_cmd // "true"' 2>/dev/null || echo true)"
fi

AVAILABLE="$(codex_buddies_default_buddy_roster)"
if [[ -z "$AVAILABLE" ]]; then
  codex_buddies_no_buddies_error "forge" >&2
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
  codex_buddies_no_buddies_error "forge" >&2
  exit 1
fi

if [[ -z "$FORGE_DIR" ]]; then
  FORGE_DIR="$(codex_buddies_session_dir)/forge-$(date '+%Y%m%d-%H%M%S')"
fi
mkdir -p "$FORGE_DIR"

HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
CONTEXT="$(codex_buddies_project_context "$CWD")"
PROMPT="$(codex_buddies_build_forge_prompt "$TASK" "$FITNESS" "$CONTEXT")"

IFS=',' read -r -a ENGINE_LIST <<< "$SELECTED"

PIDS=()
for engine in "${ENGINE_LIST[@]}"; do
  [[ -n "$engine" ]] || continue
  WT="${FORGE_DIR}/wt-${engine}"
  git -C "$REPO_ROOT" worktree add --detach "$WT" "$HEAD_SHA" >/dev/null 2>&1
  codex_buddies_link_shared_node_modules "$REPO_ROOT" "$WT"
  (
    output_path="$(codex_buddies_dispatch_buddy "$engine" "$WT" "$PROMPT" "$TIMEOUT" exec)"
    printf '%s\n' "$output_path" > "${FORGE_DIR}/${engine}.response"
  ) &
  PIDS+=("$!")
done

for pid in "${PIDS[@]}"; do
  wait "$pid"
done

WINNER=""
WINNER_SCORE=-1
SUMMARY_FILE="${FORGE_DIR}/summary.md"
MANIFEST_FILE="${FORGE_DIR}/manifest.json"
TASK_CLASS="$(codex_buddies_detect_task_class "$TASK")"
ELO_ROWS=()
RECOMMENDED_KIND="winner"
RECOMMENDED_LABEL="none"

{
  printf '# Forge\n\n'
  printf 'Task: %s\n\n' "$TASK"
  printf 'Fitness: `%s`\n\n' "$FITNESS"
  printf '| Engine | Pass | Score | Diff Lines | Files | Duration |\n'
  printf '|---|---|---|---|---|---|\n'
} > "$SUMMARY_FILE"

RESULT_ROWS=()
for engine in "${ENGINE_LIST[@]}"; do
  [[ -n "$engine" ]] || continue
  WT="${FORGE_DIR}/wt-${engine}"
  RESULT_PATH="$(bash "${SCRIPT_DIR}/forge-score.sh" --dir "$WT" --fitness "$FITNESS" --label "$engine" --timeout "$FITNESS_TIMEOUT")"
  SCORE="$(jq -r '.composite_score // 0' "$RESULT_PATH" 2>/dev/null || echo 0)"
  PASS="$(jq -r '.pass // false' "$RESULT_PATH" 2>/dev/null || echo false)"
  DIFF_LINES="$(jq -r '.diff_lines // 0' "$RESULT_PATH" 2>/dev/null || echo 0)"
  FILES_CHANGED="$(jq -r '.files_changed // 0' "$RESULT_PATH" 2>/dev/null || echo 0)"
  DURATION="$(jq -r '.duration // 0' "$RESULT_PATH" 2>/dev/null || echo 0)"
  RESPONSE_FILE="$(cat "${FORGE_DIR}/${engine}.response" 2>/dev/null || true)"

  printf '| %s | %s | %s | %s | %s | %ss |\n' \
    "$engine" "$PASS" "$SCORE" "$DIFF_LINES" "$FILES_CHANGED" "$DURATION" >> "$SUMMARY_FILE"

  RESULT_ROWS+=("$(jq -n \
    --arg engine "$engine" \
    --arg worktree "$WT" \
    --arg response_file "$RESPONSE_FILE" \
    --slurpfile score "$RESULT_PATH" \
    '{engine: $engine, worktree: $worktree, response_file: $response_file, score: $score[0]}')")

  if [[ "$SCORE" =~ ^[0-9]+$ ]] && (( SCORE > WINNER_SCORE )); then
    WINNER_SCORE="$SCORE"
    WINNER="$engine"
  fi
done

if [[ ! "$WINNER_SCORE" =~ ^[0-9]+$ || "$WINNER_SCORE" -le 0 ]]; then
  WINNER="none"
fi

printf '\nWinner: %s (score %s)\n' "$WINNER" "$WINNER_SCORE" >> "$SUMMARY_FILE"
RECOMMENDED_LABEL="$WINNER"

if command -v jq >/dev/null 2>&1; then
  printf '%s\n' "${RESULT_ROWS[@]}" | jq -s \
    --arg task "$TASK" \
    --arg cwd "$CWD" \
    --arg fitness "$FITNESS" \
    --arg winner "$WINNER" \
    --arg task_class "$TASK_CLASS" \
    '{
      task: $task,
      cwd: $cwd,
      fitness: $fitness,
      task_class: $task_class,
      winner: $winner,
      results: .
    }' > "$MANIFEST_FILE"
else
  printf '{"task":"%s","cwd":"%s","fitness":"%s","winner":"%s"}\n' "$TASK" "$CWD" "$FITNESS" "$WINNER" > "$MANIFEST_FILE"
fi

if [[ "$SYNTHESIS_ENABLED" == "true" ]]; then
  SYNTHESIS_RESULT="$(bash "${SCRIPT_DIR}/synthesis-run.sh" \
    --task "$TASK" \
    --cwd "$CWD" \
    --fitness "$FITNESS" \
    --forge-dir "$FORGE_DIR" \
    --engine "$SYNTHESIS_ENGINE" \
    --timeout "$SYNTHESIS_TIMEOUT" \
    --top-n "$SYNTHESIS_TOP_N")"

  if [[ -f "$SYNTHESIS_RESULT" ]] && command -v jq >/dev/null 2>&1; then
    synth_enabled="$(jq -r '.enabled // false' "$SYNTHESIS_RESULT" 2>/dev/null || echo false)"
    if [[ "$synth_enabled" == "true" ]]; then
      synth_engine="$(jq -r '.engine // ""' "$SYNTHESIS_RESULT" 2>/dev/null || true)"
      synth_score="$(jq -r '.score.composite_score // 0' "$SYNTHESIS_RESULT" 2>/dev/null || echo 0)"
      synth_pass="$(jq -r '.score.pass // false' "$SYNTHESIS_RESULT" 2>/dev/null || echo false)"
      synth_sources="$(jq -r '.source_candidates | map(.engine) | join(", ")' "$SYNTHESIS_RESULT" 2>/dev/null || true)"
      synth_source_count="$(jq -r '.source_candidates | length' "$SYNTHESIS_RESULT" 2>/dev/null || echo 0)"

      {
        printf '\n## Synthesis\n\n'
        printf 'Engine: `%s`\n\n' "$synth_engine"
        printf 'Source candidates: %s\n\n' "$synth_sources"
        printf 'Pass: `%s`\n\n' "$synth_pass"
        printf 'Score: `%s`\n' "$synth_score"
      } >> "$SUMMARY_FILE"

      if [[ "$synth_pass" == "true" && "$synth_score" =~ ^[0-9]+$ && "$WINNER_SCORE" =~ ^-?[0-9]+$ ]] && {
        [[ "$synth_score" -gt "$WINNER_SCORE" ]] || { [[ "$synth_source_count" =~ ^[0-9]+$ ]] && (( synth_source_count > 1 )) && [[ "$synth_score" -ge "$WINNER_SCORE" ]]; }
      }; then
        RECOMMENDED_KIND="synthesis"
        RECOMMENDED_LABEL="synthesis:${synth_engine}"
      fi

      tmp="${MANIFEST_FILE}.tmp.$$"
      jq --slurpfile synthesis "$SYNTHESIS_RESULT" '. + {synthesis: $synthesis[0]}' "$MANIFEST_FILE" > "$tmp" && mv "$tmp" "$MANIFEST_FILE"
    else
      {
        printf '\n## Synthesis\n\n'
        printf 'Skipped: `%s`\n' "$(jq -r '.reason // "unknown"' "$SYNTHESIS_RESULT" 2>/dev/null || echo unknown)"
      } >> "$SUMMARY_FILE"
    fi
  fi
fi

{
  printf '\nRecommended result: `%s`\n' "$RECOMMENDED_LABEL"
  printf 'Recommended kind: `%s`\n' "$RECOMMENDED_KIND"
} >> "$SUMMARY_FILE"

if command -v jq >/dev/null 2>&1; then
  tmp="${MANIFEST_FILE}.tmp.$$"
  jq \
    --arg recommended_kind "$RECOMMENDED_KIND" \
    --arg recommended_label "$RECOMMENDED_LABEL" \
    '. + {recommended_result: {kind: $recommended_kind, label: $recommended_label}}' \
    "$MANIFEST_FILE" > "$tmp" && mv "$tmp" "$MANIFEST_FILE"
fi

if [[ "$WINNER" != "none" && "$(codex_buddies_elo_enabled)" == "true" ]]; then
  for engine in "${ENGINE_LIST[@]}"; do
    [[ -n "$engine" ]] || continue
    before="$(codex_buddies_elo_rating "$engine" "$TASK_CLASS")"
    printf '%s %s\n' "$engine" "$before" > "${FORGE_DIR}/${engine}.elo-before"
  done

  for engine in "${ENGINE_LIST[@]}"; do
    [[ -n "$engine" ]] || continue
    [[ "$engine" == "$WINNER" ]] && continue
    bash "${SCRIPT_DIR}/elo-update.sh" --winner "$WINNER" --loser "$engine" --task-class "$TASK_CLASS" >/dev/null 2>&1 || true
  done

  {
    printf '\n## ELO\n\n'
    printf 'Task class: `%s`\n\n' "$TASK_CLASS"
    printf '| Engine | Before | After | Delta |\n'
    printf '|---|---|---|---|\n'
  } >> "$SUMMARY_FILE"

  for engine in "${ENGINE_LIST[@]}"; do
    [[ -n "$engine" ]] || continue
    before="$(awk '{print $2}' "${FORGE_DIR}/${engine}.elo-before" 2>/dev/null || echo 1200)"
    after="$(codex_buddies_elo_rating "$engine" "$TASK_CLASS")"
    delta=$((after - before))
    delta_label="$delta"
    if (( delta > 0 )); then
      delta_label="+${delta}"
    fi
    printf '| %s | %s | %s | %s |\n' "$engine" "$before" "$after" "$delta_label" >> "$SUMMARY_FILE"
    ELO_ROWS+=("$(jq -n --arg engine "$engine" --argjson before "$before" --argjson after "$after" --argjson delta "$delta" '{engine:$engine,before:$before,after:$after,delta:$delta}')")
  done

  if command -v jq >/dev/null 2>&1 && [[ ${#ELO_ROWS[@]} -gt 0 ]]; then
    tmp="${MANIFEST_FILE}.tmp.$$"
    printf '%s\n' "${ELO_ROWS[@]}" | jq -s --arg task_class "$TASK_CLASS" '. as $rows | {task_class:$task_class, rows:$rows}' > "${FORGE_DIR}/elo.json"
    jq --slurpfile elo "${FORGE_DIR}/elo.json" '. + {elo: $elo[0]}' "$MANIFEST_FILE" > "$tmp" && mv "$tmp" "$MANIFEST_FILE"
  fi
fi

if [[ "$PRINT_REPORT" == "true" ]]; then
  cat "$SUMMARY_FILE"
else
  printf '%s\n' "$MANIFEST_FILE"
fi
