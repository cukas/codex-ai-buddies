#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

TASK=""
CWD=""
FITNESS=""
FORGE_DIR=""
ENGINE="$(codex_buddies_synthesis_engine)"
TIMEOUT="$(codex_buddies_synthesis_timeout)"
TOP_N="$(codex_buddies_synthesis_top_n)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --fitness) FITNESS="$2"; shift 2 ;;
    --forge-dir) FORGE_DIR="$2"; shift 2 ;;
    --engine) ENGINE="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --top-n) TOP_N="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$TASK" ]] && { echo "ERROR: --task is required" >&2; exit 1; }
[[ -z "$CWD" ]] && { echo "ERROR: --cwd is required" >&2; exit 1; }
[[ -z "$FITNESS" ]] && { echo "ERROR: --fitness is required" >&2; exit 1; }
[[ -z "$FORGE_DIR" ]] && { echo "ERROR: --forge-dir is required" >&2; exit 1; }

MANIFEST_FILE="${FORGE_DIR}/manifest.json"
[[ -f "$MANIFEST_FILE" ]] || { echo "ERROR: missing manifest.json in forge dir" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required for synthesis" >&2; exit 1; }

REPO_ROOT="$(cd "$CWD" && git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -z "$REPO_ROOT" ]] && { echo "ERROR: --cwd must be inside a git repository" >&2; exit 1; }

codex_buddies_find_buddy "$ENGINE" >/dev/null 2>&1 || {
  hint="$(codex_buddies_buddy_config "$ENGINE" "install_hint" "")"
  echo "ERROR: synthesis engine ${ENGINE} CLI not found.${hint:+ Install: $hint}" >&2
  exit 1
}

CANDIDATES_JSON="${FORGE_DIR}/synthesis-candidates.json"
jq --argjson n "$TOP_N" '
  .results
  | map(select((.score.composite_score // 0) > 0))
  | sort_by(.score.composite_score // 0)
  | reverse
  | .[:$n]
' "$MANIFEST_FILE" > "$CANDIDATES_JSON"

candidate_count="$(jq 'length' "$CANDIDATES_JSON" 2>/dev/null || echo 0)"
if [[ ! "$candidate_count" =~ ^[0-9]+$ ]] || (( candidate_count == 0 )); then
  RESULT_FILE="${FORGE_DIR}/synthesis.json"
  jq -n --arg engine "$ENGINE" '{enabled: false, engine: $engine, reason: "no-positive-candidates"}' > "$RESULT_FILE"
  printf '%s\n' "$RESULT_FILE"
  exit 0
fi

HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
WT="${FORGE_DIR}/wt-synthesis"
git -C "$REPO_ROOT" worktree add --detach "$WT" "$HEAD_SHA" >/dev/null 2>&1
codex_buddies_link_shared_node_modules "$REPO_ROOT" "$WT"

CANDIDATES_FILE="${FORGE_DIR}/synthesis-candidates.md"
{
  printf '# Synthesis Candidates\n\n'
} > "$CANDIDATES_FILE"

while IFS= read -r candidate_engine; do
  [[ -n "$candidate_engine" ]] || continue
  score="$(jq -r --arg e "$candidate_engine" '.[] | select(.engine == $e) | .score.composite_score // 0' "$CANDIDATES_JSON")"
  pass="$(jq -r --arg e "$candidate_engine" '.[] | select(.engine == $e) | .score.pass // false' "$CANDIDATES_JSON")"
  diff_lines="$(jq -r --arg e "$candidate_engine" '.[] | select(.engine == $e) | .score.diff_lines // 0' "$CANDIDATES_JSON")"
  files_changed="$(jq -r --arg e "$candidate_engine" '.[] | select(.engine == $e) | .score.files_changed // 0' "$CANDIDATES_JSON")"
  response_file="$(jq -r --arg e "$candidate_engine" '.[] | select(.engine == $e) | .response_file // ""' "$CANDIDATES_JSON")"
  patch_file="$(jq -r --arg e "$candidate_engine" '.[] | select(.engine == $e) | .score.patch_file // ""' "$CANDIDATES_JSON")"

  {
    printf '## %s\n\n' "$candidate_engine"
    printf 'Score: %s\n\n' "$score"
    printf 'Pass: %s\n\n' "$pass"
    printf 'Diff lines: %s\n\n' "$diff_lines"
    printf 'Files changed: %s\n\n' "$files_changed"
    printf '### Response\n\n'
    printf '```text\n%s\n```\n\n' "$(codex_buddies_read_file_snippet "$response_file" 4000)"
    printf '### Patch\n\n'
    printf '```diff\n%s\n```\n\n' "$(codex_buddies_read_file_snippet "$patch_file" 12000)"
  } >> "$CANDIDATES_FILE"
done < <(jq -r '.[].engine' "$CANDIDATES_JSON")

CONTEXT="$(codex_buddies_project_context "$CWD")"
PROMPT="$(codex_buddies_build_synthesis_prompt "$TASK" "$FITNESS" "$CONTEXT" "$(cat "$CANDIDATES_FILE")")"
RESPONSE_FILE="$(codex_buddies_dispatch_buddy "$ENGINE" "$WT" "$PROMPT" "$TIMEOUT" exec)"
SCORE_FILE="$(bash "${SCRIPT_DIR}/forge-score.sh" --dir "$WT" --fitness "$FITNESS" --label "synthesis" --timeout "$TIMEOUT")"
RESULT_FILE="${FORGE_DIR}/synthesis.json"
SUMMARY_FILE="${FORGE_DIR}/synthesis.md"

jq -n \
  --arg engine "$ENGINE" \
  --arg worktree "$WT" \
  --arg response_file "$RESPONSE_FILE" \
  --arg candidates_file "$CANDIDATES_FILE" \
  --slurpfile score "$SCORE_FILE" \
  --slurpfile candidates "$CANDIDATES_JSON" \
  '{
    enabled: true,
    engine: $engine,
    worktree: $worktree,
    response_file: $response_file,
    candidates_file: $candidates_file,
    source_candidates: $candidates[0],
    score: $score[0]
  }' > "$RESULT_FILE"

{
  printf '# Synthesis\n\n'
  printf 'Engine: %s\n\n' "$ENGINE"
  printf 'Source candidates: %s\n\n' "$(jq -r 'map(.engine) | join(", ")' "$CANDIDATES_JSON")"
  printf 'Score: %s\n\n' "$(jq -r '.score.composite_score // 0' "$RESULT_FILE")"
  printf 'Pass: %s\n\n' "$(jq -r '.score.pass // false' "$RESULT_FILE")"
  printf 'Response file: `%s`\n\n' "$RESPONSE_FILE"
  printf 'Candidates file: `%s`\n' "$CANDIDATES_FILE"
} > "$SUMMARY_FILE"

printf '%s\n' "$RESULT_FILE"
