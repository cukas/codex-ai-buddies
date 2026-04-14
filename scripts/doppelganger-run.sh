#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

PROMPT=""
CWD="$(pwd)"
TIMEOUT="900"
MODEL="$(codex_buddies_config "doppelganger_model" "")"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt) PROMPT="$2"; shift 2 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PROMPT" && ! -t 0 ]]; then
  PROMPT="$(cat)"
fi
[[ -z "$PROMPT" ]] && { echo "ERROR: prompt required" >&2; exit 1; }

REPO_ROOT="$(cd "$CWD" && git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -z "$REPO_ROOT" ]] && { echo "ERROR: --cwd must be inside a git repository" >&2; exit 1; }

GIT_DIR="$(cd "$CWD" && git rev-parse --git-dir 2>/dev/null || true)"
COMMON_DIR="$(cd "$CWD" && git rev-parse --git-common-dir 2>/dev/null || true)"
WORK_DIR="$CWD"

if [[ -n "$GIT_DIR" && -n "$COMMON_DIR" ]]; then
  GIT_DIR_REAL="$(cd "$CWD" && cd "$GIT_DIR" && pwd)"
  COMMON_DIR_REAL="$(cd "$CWD" && cd "$COMMON_DIR" && pwd)"
  if [[ "$GIT_DIR_REAL" == "$COMMON_DIR_REAL" ]]; then
    WORK_DIR="$(codex_buddies_session_dir)/doppelganger-wt-$(date '+%Y%m%d-%H%M%S')"
    HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
    git -C "$REPO_ROOT" worktree add --detach "$WORK_DIR" "$HEAD_SHA" >/dev/null 2>&1
    if [[ -d "${REPO_ROOT}/node_modules" && ! -e "${WORK_DIR}/node_modules" ]]; then
      ln -s "${REPO_ROOT}/node_modules" "${WORK_DIR}/node_modules" 2>/dev/null || true
    fi
    for pkg_nm in "${REPO_ROOT}"/packages/*/node_modules; do
      [[ -d "$pkg_nm" ]] || continue
      pkg_name="$(basename "$(dirname "$pkg_nm")")"
      target_dir="${WORK_DIR}/packages/${pkg_name}"
      if [[ -d "$target_dir" && ! -e "${target_dir}/node_modules" ]]; then
        ln -s "$pkg_nm" "${target_dir}/node_modules" 2>/dev/null || true
      fi
    done
  fi
fi

PROJECT_JSON="$(bash "${SCRIPT_DIR}/detect-project.sh" "$WORK_DIR" 2>/dev/null || echo '{}')"
BUILD_CMD="$(printf '%s' "$PROJECT_JSON" | jq -r '.build_cmd // "true"' 2>/dev/null || echo true)"
TEST_CMD="$(printf '%s' "$PROJECT_JSON" | jq -r '.test_cmd // "true"' 2>/dev/null || echo true)"

DOPPEL_PROMPT="$(cat <<EOF
You are the Doppelganger: a blind second implementation in a clean worktree.

Rules:
- Treat this as a fresh solve with no prior solution.
- Read the repository and implement the task directly.
- Follow existing conventions.
- Keep the patch focused.
- Run these commands before finishing:
  - build: ${BUILD_CMD}
  - test: ${TEST_CMD}

Task:
${PROMPT}
EOF
)"

CMD=(
  bash "${SCRIPT_DIR}/codex-run.sh"
  --prompt "$DOPPEL_PROMPT"
  --cwd "$WORK_DIR"
  --mode exec
  --timeout "$TIMEOUT"
)
if [[ -n "$MODEL" ]]; then
  CMD+=(--model "$MODEL")
fi

RESULT_FILE="$("${CMD[@]}")"

printf '\nWORKTREE: %s\n' "$WORK_DIR" >> "$RESULT_FILE"
printf '%s\n' "$RESULT_FILE"
