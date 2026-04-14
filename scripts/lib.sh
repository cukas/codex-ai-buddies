#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  _CODEX_BUDDIES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  _CODEX_BUDDIES_LIB_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
  _CODEX_BUDDIES_LIB_DIR=""
fi

CODEX_BUDDIES_PLUGIN_ROOT="$(cd "${_CODEX_BUDDIES_LIB_DIR}/.." 2>/dev/null && pwd)"
CODEX_BUDDIES_HOME="${HOME}/.codexs-ai-buddies"
CODEX_BUDDIES_CONFIG="${CODEX_BUDDIES_HOME}/config.json"
CODEX_BUDDIES_DEBUG_LOG="${CODEX_BUDDIES_HOME}/debug.log"

codex_buddies_debug() {
  local enabled
  enabled="$(codex_buddies_config "debug" "false")"
  [[ "$enabled" != "true" ]] && return 0
  mkdir -p "$CODEX_BUDDIES_HOME"
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$CODEX_BUDDIES_DEBUG_LOG"
}

codex_buddies_config() {
  local key="$1"
  local default="${2:-}"

  if [[ -f "$CODEX_BUDDIES_CONFIG" ]] && command -v jq >/dev/null 2>&1; then
    local value
    value="$(jq -r --arg k "$key" '.[$k] // empty' "$CODEX_BUDDIES_CONFIG" 2>/dev/null || true)"
    if [[ -n "$value" && "$value" != "null" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  fi

  printf '%s\n' "$default"
}

codex_buddies_session_dir() {
  local dir="/tmp/codexs-ai-buddies-${CODEX_SESSION_ID:-default}"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

codex_buddies_timeout() {
  codex_buddies_config "timeout" "600"
}

codex_buddies_sandbox() {
  codex_buddies_config "sandbox" "workspace-write"
}

codex_buddies_forge_timeout() {
  codex_buddies_config "forge_timeout" "1200"
}

codex_buddies_synthesis_enabled() {
  codex_buddies_config "synthesis_enabled" "true"
}

codex_buddies_synthesis_engine() {
  codex_buddies_config "synthesis_engine" "codex"
}

codex_buddies_synthesis_timeout() {
  codex_buddies_config "synthesis_timeout" "900"
}

codex_buddies_synthesis_top_n() {
  codex_buddies_config "synthesis_top_n" "2"
}

codex_buddies_preflight_network_buddies() {
  codex_buddies_config "preflight_network_buddies" "true"
}

codex_buddies_preflight_timeout() {
  codex_buddies_config "preflight_timeout" "4"
}

codex_buddies_include_experimental() {
  codex_buddies_config "include_experimental" "false"
}

codex_buddies_elo_enabled() {
  codex_buddies_config "elo_enabled" "true"
}

codex_buddies_elo_k_factor() {
  codex_buddies_config "elo_k_factor" "32"
}

codex_buddies_elo_file() {
  printf '%s\n' "${CODEX_BUDDIES_HOME}/elo.json"
}

codex_buddies_run_with_timeout() {
  local timeout_secs="$1"
  shift

  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${timeout_secs}s" "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "${timeout_secs}s" "$@"
  else
    perl -e '
      use POSIX qw(setpgid);
      alarm shift @ARGV;
      $pid = fork;
      if ($pid == 0) { setpgid(0,0); exec @ARGV; die "exec failed: $!" }
      $SIG{ALRM} = sub { kill -9, $pid; exit 124 };
      waitpid $pid, 0;
      exit ($? >> 8);
    ' "$timeout_secs" "$@"
  fi
}

codex_buddies_registry_dir() {
  printf '%s:%s\n' \
    "${CODEX_BUDDIES_PLUGIN_ROOT}/buddies/builtin" \
    "${CODEX_BUDDIES_HOME}/buddies"
}

codex_buddies_list_buddies() {
  local registry builtin_dir user_dir id
  registry="$(codex_buddies_registry_dir)"
  builtin_dir="${registry%%:*}"
  user_dir="${registry##*:}"

  mkdir -p "$user_dir"

  local seen=()
  for dir in "$user_dir" "$builtin_dir"; do
    [[ -d "$dir" ]] || continue
    for file in "$dir"/*.json; do
      [[ -f "$file" ]] || continue
      id="$(basename "$file" .json)"
      local duplicate=false
      local existing
      for existing in "${seen[@]+"${seen[@]}"}"; do
        if [[ "$existing" == "$id" ]]; then
          duplicate=true
          break
        fi
      done
      [[ "$duplicate" == "true" ]] && continue
      seen+=("$id")
      printf '%s\n' "$id"
    done
  done
}

codex_buddies_find_buddy_json() {
  local id="$1"
  local registry builtin_dir user_dir
  registry="$(codex_buddies_registry_dir)"
  builtin_dir="${registry%%:*}"
  user_dir="${registry##*:}"

  if [[ -f "${user_dir}/${id}.json" ]]; then
    printf '%s\n' "${user_dir}/${id}.json"
    return 0
  fi
  if [[ -f "${builtin_dir}/${id}.json" ]]; then
    printf '%s\n' "${builtin_dir}/${id}.json"
    return 0
  fi
  return 1
}

codex_buddies_buddy_config() {
  local id="$1"
  local key="$2"
  local default="${3:-}"
  local json_file

  json_file="$(codex_buddies_find_buddy_json "$id" 2>/dev/null || true)"
  if [[ -n "$json_file" && -f "$json_file" && "$(command -v jq || true)" != "" ]]; then
    local value
    value="$(jq -r --arg k "$key" '.[$k] // empty' "$json_file" 2>/dev/null || true)"
    if [[ -n "$value" && "$value" != "null" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  fi

  printf '%s\n' "$default"
}

codex_buddies_buddy_json_query() {
  local id="$1"
  local query="$2"
  local default="${3:-}"
  local json_file

  json_file="$(codex_buddies_find_buddy_json "$id" 2>/dev/null || true)"
  if [[ -n "$json_file" && -f "$json_file" ]] && command -v jq >/dev/null 2>&1; then
    local value
    value="$(jq -r "$query // empty" "$json_file" 2>/dev/null || true)"
    if [[ -n "$value" && "$value" != "null" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  fi

  printf '%s\n' "$default"
}

codex_buddies_find_buddy() {
  local id="$1"
  local binary configured json_file

  binary="$(codex_buddies_buddy_config "$id" "binary" "$id")"
  configured="$(codex_buddies_config "${id}_path" "")"
  if [[ -n "$configured" && -x "$configured" ]]; then
    printf '%s\n' "$configured"
    return 0
  fi

  if command -v "$binary" >/dev/null 2>&1; then
    command -v "$binary"
    return 0
  fi

  json_file="$(codex_buddies_find_buddy_json "$id" 2>/dev/null || true)"
  if [[ -n "$json_file" && -f "$json_file" && "$(command -v jq || true)" != "" ]]; then
    while IFS= read -r pattern; do
      [[ -z "$pattern" ]] && continue
      pattern="${pattern//\$\{HOME\}/${HOME}}"
      for candidate in $pattern; do
        if [[ -x "$candidate" ]]; then
          printf '%s\n' "$candidate"
          return 0
        fi
      done
    done < <(jq -r '.search_paths[]? // empty' "$json_file")
  fi

  return 1
}

codex_buddies_available_buddies() {
  local id available=()
  while IFS= read -r id; do
    if codex_buddies_find_buddy "$id" >/dev/null 2>&1; then
      available+=("$id")
    fi
  done < <(codex_buddies_list_buddies)

  local IFS=','
  printf '%s\n' "${available[*]-}"
}

codex_buddies_gemini_runtime_healthy() {
  local gemini_bin package_root resolved

  gemini_bin="$(codex_buddies_find_buddy "gemini" 2>/dev/null || true)"
  [[ -n "$gemini_bin" ]] || return 1
  command -v node >/dev/null 2>&1 || return 1

  resolved="$(readlink "$gemini_bin" 2>/dev/null || true)"
  if [[ -n "$resolved" ]]; then
    package_root="$(cd "$(dirname "${gemini_bin}")/../lib/node_modules/@google/gemini-cli" 2>/dev/null && pwd)"
  else
    package_root="$(cd "$(dirname "$gemini_bin")/.." 2>/dev/null && pwd)"
  fi

  [[ -n "$package_root" ]] || return 1
  [[ -f "${package_root}/node_modules/string-width/index.js" ]] || return 1

  node -e "import('${package_root}/node_modules/string-width/index.js').then(()=>process.exit(0)).catch(()=>process.exit(1))" >/dev/null 2>&1
}

codex_buddies_url_reachable() {
  local url="$1"
  local timeout_secs
  timeout_secs="$(codex_buddies_preflight_timeout)"

  command -v curl >/dev/null 2>&1 || return 0

  curl \
    --silent \
    --show-error \
    --location \
    --output /dev/null \
    --connect-timeout "$timeout_secs" \
    --max-time "$timeout_secs" \
    "$url" >/dev/null 2>&1
}

codex_buddies_buddy_network_reachable() {
  local id="$1"
  local url json_file

  if [[ "$(codex_buddies_preflight_network_buddies)" != "true" ]]; then
    return 0
  fi

  if [[ "$(codex_buddies_buddy_json_query "$id" '.network_required' 'false')" != "true" ]]; then
    return 0
  fi

  json_file="$(codex_buddies_find_buddy_json "$id" 2>/dev/null || true)"
  [[ -n "$json_file" && -f "$json_file" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    if codex_buddies_url_reachable "$url"; then
      return 0
    fi
  done < <(jq -r '.preflight_urls[]? // empty' "$json_file" 2>/dev/null || true)

  if jq -e '.preflight_urls | length > 0' "$json_file" >/dev/null 2>&1; then
    return 1
  fi

  return 0
}

codex_buddies_buddy_is_healthy() {
  local id="$1"

  codex_buddies_buddy_runtime_healthy "$id" || return 1

  codex_buddies_buddy_network_reachable "$id"
}

codex_buddies_buddy_runtime_healthy() {
  local id="$1"

  case "$id" in
    gemini)
      codex_buddies_gemini_runtime_healthy
      ;;
    *)
      return 0
      ;;
  esac
}

codex_buddies_csv_without_experimental() {
  local csv="$1"
  local engine
  local -a filtered=() _engines=()

  IFS=',' read -r -a _engines <<< "$csv"
  for engine in "${_engines[@]-}"; do
    [[ -n "$engine" ]] || continue
    if [[ "$(codex_buddies_buddy_json_query "$engine" '.experimental' 'false')" == "true" ]]; then
      continue
    fi
    filtered+=("$engine")
  done

  local IFS=','
  printf '%s\n' "${filtered[*]-}"
}

codex_buddies_sort_csv_by_priority() {
  local csv="$1"
  local lines="" engine priority
  local -a _engines=()

  IFS=',' read -r -a _engines <<< "$csv"
  for engine in "${_engines[@]-}"; do
    [[ -n "$engine" ]] || continue
    priority="$(codex_buddies_buddy_json_query "$engine" '.default_priority' '50')"
    lines+="${priority}:${engine}"$'\n'
  done

  if [[ -z "$lines" ]]; then
    printf '\n'
    return 0
  fi

  local sorted=()
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    sorted+=("${line#*:}")
  done < <(printf '%s' "$lines" | sort -t: -k1,1n)

  local IFS=','
  printf '%s\n' "${sorted[*]-}"
}

codex_buddies_host_is_codex() {
  [[ -n "${CODEX_SESSION_ID:-}" ]] && printf 'true\n' || printf 'false\n'
}

codex_buddies_csv_without_engine() {
  local csv="$1"
  local banned="$2"
  local engine
  local -a filtered=() _engines=()

  IFS=',' read -r -a _engines <<< "$csv"
  for engine in "${_engines[@]-}"; do
    [[ -n "$engine" ]] || continue
    [[ "$engine" == "$banned" ]] && continue
    filtered+=("$engine")
  done

  local IFS=','
  printf '%s\n' "${filtered[*]-}"
}

codex_buddies_csv_local_only() {
  local csv="$1"
  local engine
  local -a filtered=() _engines=()

  IFS=',' read -r -a _engines <<< "$csv"
  for engine in "${_engines[@]-}"; do
    [[ -n "$engine" ]] || continue
    if [[ "$(codex_buddies_buddy_json_query "$engine" '.network_required' 'false')" == "true" ]]; then
      continue
    fi
    filtered+=("$engine")
  done

  local IFS=','
  printf '%s\n' "${filtered[*]-}"
}

codex_buddies_no_buddies_error() {
  local mode="$1"
  cat <<EOF
ERROR: no usable buddies are available for ${mode} in this session.

Installed buddies were either not found locally or failed their runtime / network preflight checks from this process.

You can retry from your normal shell, or disable buddy network preflight with:
  ~/.codexs-ai-buddies/config.json -> {"preflight_network_buddies": false}
EOF
}

codex_buddies_default_buddy_roster() {
  local available engine healthy=()
  available="$(codex_buddies_available_buddies)"

  if [[ "$(codex_buddies_include_experimental)" != "true" ]]; then
    available="$(codex_buddies_csv_without_experimental "$available")"
  fi

  IFS=',' read -r -a _engines <<< "$available"
  for engine in "${_engines[@]-}"; do
    [[ -n "$engine" ]] || continue
    if codex_buddies_buddy_is_healthy "$engine"; then
      healthy+=("$engine")
    fi
  done
  local IFS=','
  available="${healthy[*]-}"

  available="$(codex_buddies_sort_csv_by_priority "$available")"

  printf '%s\n' "$available"
}

codex_buddies_buddy_supports_mode() {
  local id="$1"
  local mode="$2"
  local json_file

  json_file="$(codex_buddies_find_buddy_json "$id" 2>/dev/null || true)"
  [[ -z "$json_file" || ! -f "$json_file" ]] && return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -e --arg m "$mode" '.modes // [] | index($m)' "$json_file" >/dev/null 2>&1
}

codex_buddies_buddy_model() {
  local id="$1"
  local config_key default_model
  config_key="$(codex_buddies_buddy_config "$id" "model_config_key" "${id}_model")"
  default_model="$(codex_buddies_buddy_config "$id" "default_model" "")"
  codex_buddies_config "$config_key" "$default_model"
}

codex_buddies_resolve_template_arg() {
  local template="$1"
  local prompt="$2"
  local cwd="$3"
  local timeout="$4"
  local model="$5"

  template="${template//\{prompt\}/$prompt}"
  template="${template//\{cwd\}/$cwd}"
  template="${template//\{timeout\}/$timeout}"
  template="${template//\{model\}/$model}"
  printf '%s\n' "$template"
}

codex_buddies_elo_rating() {
  local id="$1"
  local task_class="$2"
  local elo_file rating

  elo_file="$(codex_buddies_elo_file)"
  if [[ ! -f "$elo_file" ]] || ! command -v jq >/dev/null 2>&1; then
    printf '1200\n'
    return 0
  fi

  rating="$(jq -r --arg id "$id" --arg c "$task_class" '.[$id][$c].rating // empty' "$elo_file" 2>/dev/null || true)"
  if [[ -z "$rating" || "$rating" == "null" ]]; then
    printf '1200\n'
  else
    printf '%s\n' "$rating"
  fi
}

codex_buddies_dispatch_buddy() {
  local id="$1"
  local cwd="$2"
  local prompt="$3"
  local timeout="$4"
  local mode="${5:-exec}"
  local review_target="${6:-uncommitted}"
  local adapter

  adapter="$(codex_buddies_buddy_config "$id" "adapter_script" "buddy-run.sh")"
  if [[ "$adapter" == "buddy-run.sh" || "$adapter" == "templated-run.sh" ]]; then
    bash "${CODEX_BUDDIES_PLUGIN_ROOT}/scripts/${adapter}" \
      --id "$id" \
      --prompt "$prompt" \
      --cwd "$cwd" \
      --mode "$mode" \
      --review-target "$review_target" \
      --timeout "$timeout"
  else
    bash "${CODEX_BUDDIES_PLUGIN_ROOT}/scripts/${adapter}" \
      --prompt "$prompt" \
      --cwd "$cwd" \
      --mode "$mode" \
      --review-target "$review_target" \
      --timeout "$timeout"
  fi
}

codex_buddies_build_review_prompt() {
  local prompt="$1"
  local cwd="$2"
  local target="$3"
  local diff_content=""

  case "$target" in
    uncommitted)
      diff_content="$(cd "$cwd" && git diff HEAD 2>/dev/null || git diff 2>/dev/null || true)"
      ;;
    branch:*)
      diff_content="$(cd "$cwd" && git diff "${target#branch:}...HEAD" 2>/dev/null || true)"
      ;;
    commit:*)
      diff_content="$(cd "$cwd" && git show "${target#commit:}" 2>/dev/null || true)"
      ;;
  esac

  cat <<EOF
Review the following code changes and report the highest-signal bugs, regressions, or missing tests first.

\`\`\`diff
${diff_content}
\`\`\`

${prompt}
EOF
}

codex_buddies_project_context() {
  local cwd="$1"
  local summary=""

  if [[ -f "${cwd}/README.md" ]]; then
    summary+="README"$'\n'
    summary+="$(sed -n '1,80p' "${cwd}/README.md" | head -c 1500)"$'\n'
  fi

  if [[ -f "${cwd}/package.json" ]]; then
    summary+="STACK: JavaScript/TypeScript"$'\n'
  elif [[ -f "${cwd}/pyproject.toml" || -f "${cwd}/requirements.txt" ]]; then
    summary+="STACK: Python"$'\n'
  elif [[ -f "${cwd}/Cargo.toml" ]]; then
    summary+="STACK: Rust"$'\n'
  elif [[ -f "${cwd}/go.mod" ]]; then
    summary+="STACK: Go"$'\n'
  fi

  printf '%s' "$summary"
}

codex_buddies_build_brainstorm_prompt() {
  local task="$1"
  local context="${2:-}"

  cat <<EOF
You are one competitor in a confidence-bid round for a software task.

Respond with ONLY valid JSON:
{"confidence": 0, "approach": "", "why_you": "", "risks": ["", ""]}

Rules:
- confidence must be an integer from 0 to 100
- approach must be concise and implementation-oriented
- why_you must say why this engine is a good fit
- risks should list 1 to 3 concrete risks

TASK:
${task}

CONTEXT:
${context}
EOF
}

codex_buddies_build_tribunal_prompt() {
  local question="$1"
  local position="$2"
  local previous="${3:-}"

  cat <<EOF
You are participating in a technical debate.

Position: ${position}
Question: ${question}

${previous:+Previous argument to address:
${previous}}

Respond with a concise argument grounded in the repository context. Cite files when useful.
EOF
}

codex_buddies_build_forge_prompt() {
  local task="$1"
  local fitness="$2"
  local context="${3:-}"

  cat <<EOF
TASK:
${task}

FITNESS:
${fitness}

CONTEXT:
${context}

CONSTRAINTS:
- Write code, not a plan.
- Change only what is required for the task.
- Run the fitness command before finishing.
- Keep the patch focused.
EOF
}

codex_buddies_build_synthesis_prompt() {
  local task="$1"
  local fitness="$2"
  local context="$3"
  local candidates="$4"

  cat <<EOF
You are running the synthesis round of a competitive coding arena.

Your job is to study the strongest candidate implementations, merge the best ideas, and produce the best final code in this worktree.

TASK:
${task}

FITNESS:
${fitness}

CONTEXT:
${context}

CANDIDATES:
${candidates}

RULES:
- Implement the final synthesized solution in code, not prose.
- Reuse the strongest ideas from the candidates, but do not mechanically combine everything.
- Prefer the smallest correct patch that satisfies the task.
- Run the fitness command before finishing.
- If one candidate is already clearly best, keep that shape and only improve it where needed.
EOF
}

codex_buddies_detect_task_class() {
  local desc="$1"
  local lower
  lower="$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    *algorithm*|*sort*|*search*|*scoring*|*math*|*compute*|*calculate*)
      printf 'algorithm\n'
      ;;
    *refactor*|*rename*|*extract*|*simplify*|*reorganize*|*clean*)
      printf 'refactor\n'
      ;;
    *fix*|*bug*|*error*|*crash*|*broken*|*regression*)
      printf 'bugfix\n'
      ;;
    *test*|*spec*|*coverage*|*assert*)
      printf 'test\n'
      ;;
    *doc*|*readme*|*comment*|*changelog*)
      printf 'docs\n'
      ;;
    *add*|*implement*|*create*|*build*|*feature*|*new*)
      printf 'feature\n'
      ;;
    *)
      printf 'other\n'
      ;;
  esac
}

codex_buddies_detect_risk_level() {
  local desc="$1"
  local lower
  lower="$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    *auth*|*security*|*payment*|*billing*|*crypto*|*migration*|*concurrency*|*race*|*thread*|*deploy*|*production*|*critical*|*dangerous*|*risky*)
      printf 'high\n'
      ;;
    *refactor*|*api*|*schema*|*validation*|*middleware*|*performance*|*queue*|*worker*|*cache*|*retry*)
      printf 'medium\n'
      ;;
    *)
      printf 'low\n'
      ;;
  esac
}

codex_buddies_compute_score() {
  local pass="$1"
  local diff_lines="${2:-0}"
  local files_changed="${3:-0}"
  local duration="${4:-0}"

  diff_lines="${diff_lines%%.*}"
  files_changed="${files_changed%%.*}"
  duration="${duration%%.*}"

  diff_lines="${diff_lines//[!0-9]/}"
  files_changed="${files_changed//[!0-9]/}"
  duration="${duration//[!0-9]/}"

  diff_lines="${diff_lines:-0}"
  files_changed="${files_changed:-0}"
  duration="${duration:-0}"

  [[ "$pass" != "true" ]] && printf '0\n' && return 0
  (( diff_lines == 0 )) && printf '0\n' && return 0

  local diff_score=100
  local files_score=100
  local duration_score=100

  if (( diff_lines > 250 )); then
    diff_score=20
  elif (( diff_lines > 100 )); then
    diff_score=60
  fi

  if (( files_changed > 10 )); then
    files_score=10
  elif (( files_changed > 5 )); then
    files_score=50
  fi

  if (( duration > 600 )); then
    duration_score=10
  elif (( duration > 180 )); then
    duration_score=60
  fi

  printf '%s\n' $(( (diff_score * 35 + files_score * 15 + duration_score * 10 + 40 * 100) / 100 ))
}

codex_buddies_escape_json() {
  local input="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -Rs .
  else
    printf '"%s"' "$(printf '%s' "$input" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  fi
}

codex_buddies_read_file_snippet() {
  local file="$1"
  local max_chars="${2:-12000}"
  local content=""

  [[ -f "$file" ]] || return 0
  content="$(cat "$file" 2>/dev/null || true)"
  printf '%s' "${content:0:max_chars}"
}

codex_buddies_link_shared_node_modules() {
  local repo_root="$1"
  local worktree="$2"

  if [[ -d "${repo_root}/node_modules" && ! -e "${worktree}/node_modules" ]]; then
    ln -s "${repo_root}/node_modules" "${worktree}/node_modules" 2>/dev/null || true
  fi

  local pkg_nm pkg_name target_dir
  for pkg_nm in "${repo_root}"/packages/*/node_modules; do
    [[ -d "$pkg_nm" ]] || continue
    pkg_name="$(basename "$(dirname "$pkg_nm")")"
    target_dir="${worktree}/packages/${pkg_name}"
    if [[ -d "$target_dir" && ! -e "${target_dir}/node_modules" ]]; then
      ln -s "$pkg_nm" "${target_dir}/node_modules" 2>/dev/null || true
    fi
  done
}

codex_buddies_ensure_doppelganger() {
  local doppel_file="${CODEX_BUDDIES_HOME}/buddies/doppelganger.json"
  mkdir -p "${CODEX_BUDDIES_HOME}/buddies"
  [[ -f "$doppel_file" ]] && return 0

  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg path "${CODEX_BUDDIES_PLUGIN_ROOT}/scripts/doppelganger-run.sh" \
      '{
        schema_version: 1,
        id: "doppelganger",
        display_name: "Doppelganger (Blind Codex)",
        binary: $path,
        search_paths: [],
        version_cmd: ["--help"],
        model_config_key: "doppelganger_model",
        modes: ["exec"],
        builtin: false,
        adapter_script: "buddy-run.sh",
        install_hint: "This buddy is created automatically by codexs-ai-buddies.",
        timeout: 900
      }' > "$doppel_file"
  fi
}
