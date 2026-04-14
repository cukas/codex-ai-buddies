#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

BUDDY_ID=""
BINARY=""
DISPLAY_NAME=""
MODES="exec"
SEARCH_PATHS=""
INSTALL_HINT=""
TIMEOUT="600"
ADAPTER_SCRIPT=""
MODEL_FLAG=""
DEFAULT_MODEL=""
PROMPT_PREFIX=""
EXEC_ARGS_JSON=""
REVIEW_ARGS_JSON=""
STDIN_PROMPT="false"
STRIP_ANSI="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) BUDDY_ID="$2"; shift 2 ;;
    --binary) BINARY="$2"; shift 2 ;;
    --display) DISPLAY_NAME="$2"; shift 2 ;;
    --modes) MODES="$2"; shift 2 ;;
    --search-paths) SEARCH_PATHS="$2"; shift 2 ;;
    --install-hint) INSTALL_HINT="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --adapter-script) ADAPTER_SCRIPT="$2"; shift 2 ;;
    --model-flag) MODEL_FLAG="$2"; shift 2 ;;
    --default-model) DEFAULT_MODEL="$2"; shift 2 ;;
    --prompt-prefix) PROMPT_PREFIX="$2"; shift 2 ;;
    --exec-args-json) EXEC_ARGS_JSON="$2"; shift 2 ;;
    --review-args-json) REVIEW_ARGS_JSON="$2"; shift 2 ;;
    --stdin-prompt) STDIN_PROMPT="$2"; shift 2 ;;
    --strip-ansi) STRIP_ANSI="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$BUDDY_ID" ]] && { echo "ERROR: --id is required" >&2; exit 1; }
[[ -z "$BINARY" ]] && { echo "ERROR: --binary is required" >&2; exit 1; }
[[ "$BUDDY_ID" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo "ERROR: invalid buddy id" >&2; exit 1; }

case "$BUDDY_ID" in
  codex|doppelganger)
    echo "ERROR: ${BUDDY_ID} is reserved by codexs-ai-buddies" >&2
    exit 1
    ;;
esac

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

mkdir -p "${CODEX_BUDDIES_HOME}/buddies"
[[ -n "$DISPLAY_NAME" ]] || DISPLAY_NAME="$BUDDY_ID"

MODES_JSON="$(printf '%s' "$MODES" | jq -R 'split(",")')"
PATHS_JSON="[]"
if [[ -n "$SEARCH_PATHS" ]]; then
  PATHS_JSON="$(printf '%s' "$SEARCH_PATHS" | jq -R 'split(",")')"
fi

if [[ -n "$EXEC_ARGS_JSON" || -n "$REVIEW_ARGS_JSON" || -n "$MODEL_FLAG" || "$STDIN_PROMPT" == "true" || "$STRIP_ANSI" == "true" ]]; then
  [[ -n "$ADAPTER_SCRIPT" ]] || ADAPTER_SCRIPT="templated-run.sh"
fi
[[ -n "$ADAPTER_SCRIPT" ]] || ADAPTER_SCRIPT="buddy-run.sh"
if [[ "$ADAPTER_SCRIPT" == "templated-run.sh" && -z "$EXEC_ARGS_JSON" && -z "$REVIEW_ARGS_JSON" ]]; then
  echo "ERROR: templated-run.sh requires --exec-args-json and/or --review-args-json" >&2
  exit 1
fi

if [[ -n "$EXEC_ARGS_JSON" ]]; then
  printf '%s' "$EXEC_ARGS_JSON" | jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null 2>&1 || {
    echo "ERROR: --exec-args-json must be a JSON array of strings" >&2
    exit 1
  }
fi
if [[ -n "$REVIEW_ARGS_JSON" ]]; then
  printf '%s' "$REVIEW_ARGS_JSON" | jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null 2>&1 || {
    echo "ERROR: --review-args-json must be a JSON array of strings" >&2
    exit 1
  }
fi
[[ "$STDIN_PROMPT" == "true" || "$STDIN_PROMPT" == "false" ]] || {
  echo "ERROR: --stdin-prompt must be true or false" >&2
  exit 1
}
[[ "$STRIP_ANSI" == "true" || "$STRIP_ANSI" == "false" ]] || {
  echo "ERROR: --strip-ansi must be true or false" >&2
  exit 1
}

OUTPUT_FILE="${CODEX_BUDDIES_HOME}/buddies/${BUDDY_ID}.json"
JQ_ARGS=(
  --arg id "$BUDDY_ID" \
  --arg display_name "$DISPLAY_NAME" \
  --arg binary "$BINARY" \
  --argjson search_paths "$PATHS_JSON" \
  --argjson modes "$MODES_JSON" \
  --arg install_hint "$INSTALL_HINT" \
  --argjson timeout "$TIMEOUT" \
  --arg adapter_script "$ADAPTER_SCRIPT" \
  --arg model_flag "$MODEL_FLAG" \
  --arg default_model "$DEFAULT_MODEL" \
  --arg prompt_prefix "$PROMPT_PREFIX" \
  --argjson stdin_prompt "$STDIN_PROMPT" \
  --argjson strip_ansi "$STRIP_ANSI"
)

if [[ -n "$EXEC_ARGS_JSON" ]]; then
  JQ_ARGS+=(--argjson exec_args "$EXEC_ARGS_JSON")
else
  JQ_ARGS+=(--argjson exec_args '[]')
fi
if [[ -n "$REVIEW_ARGS_JSON" ]]; then
  JQ_ARGS+=(--argjson review_args "$REVIEW_ARGS_JSON")
else
  JQ_ARGS+=(--argjson review_args '[]')
fi

jq -n "${JQ_ARGS[@]}" '
  {
    schema_version: 1,
    id: $id,
    display_name: $display_name,
    binary: $binary,
    search_paths: $search_paths,
    version_cmd: ["--version"],
    model_config_key: ($id + "_model"),
    modes: $modes,
    builtin: false,
    adapter_script: $adapter_script,
    install_hint: $install_hint,
    timeout: $timeout
  }
  + (if $default_model != "" then {default_model: $default_model} else {} end)
  + (if $prompt_prefix != "" then {prompt_prefix: $prompt_prefix} else {} end)
  + (if $model_flag != "" then {model: {flag: $model_flag}} else {} end)
  + (if ($exec_args | length) > 0 or ($review_args | length) > 0 or $stdin_prompt or $strip_ansi then {
      exec: ({args: $exec_args} + (if $stdin_prompt then {stdin_prompt: true} else {} end) + (if $strip_ansi then {strip_ansi: true} else {} end)),
      review: ({args: (if ($review_args | length) > 0 then $review_args else $exec_args end)} + (if $stdin_prompt then {stdin_prompt: true} else {} end) + (if $strip_ansi then {strip_ansi: true} else {} end)),
      strip_ansi: $strip_ansi
    } else {} end)
' > "$OUTPUT_FILE"

printf 'Registered buddy %s at %s\n' "$BUDDY_ID" "$OUTPUT_FILE"
