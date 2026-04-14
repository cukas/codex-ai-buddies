#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

BUDDY_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --buddy) BUDDY_ID="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

contains_csv_id() {
  local csv="$1"
  local needle="$2"
  local item
  local -a items=()

  IFS=',' read -r -a items <<< "$csv"
  for item in "${items[@]-}"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

buddy_preflight_urls() {
  local id="$1"
  local json_file

  json_file="$(codex_buddies_find_buddy_json "$id" 2>/dev/null || true)"
  [[ -n "$json_file" && -f "$json_file" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -r '.preflight_urls[]? // empty' "$json_file" 2>/dev/null || true
}

buddy_status_line() {
  local id="$1"
  local binary_path binary_status runtime_status network_status roster_status health_status note
  local install_hint network_required preflight_enabled url urls=()

  install_hint="$(codex_buddies_buddy_config "$id" "install_hint" "")"
  network_required="$(codex_buddies_buddy_json_query "$id" '.network_required' 'false')"
  preflight_enabled="$(codex_buddies_preflight_network_buddies)"

  binary_path="$(codex_buddies_find_buddy "$id" 2>/dev/null || true)"
  if [[ -n "$binary_path" ]]; then
    binary_status="ok"
  else
    binary_status="missing"
  fi

  if [[ "$binary_status" == "ok" ]]; then
    if codex_buddies_buddy_runtime_healthy "$id"; then
      runtime_status="ok"
    else
      runtime_status="failed"
    fi
  else
    runtime_status="n/a"
  fi

  if [[ "$network_required" != "true" ]]; then
    network_status="n/a"
  elif [[ "$preflight_enabled" != "true" ]]; then
    network_status="not checked"
  elif [[ "$binary_status" != "ok" ]]; then
    network_status="n/a"
  else
    while IFS= read -r url; do
      [[ -n "$url" ]] || continue
      urls+=("$url")
    done < <(buddy_preflight_urls "$id")

    if [[ ${#urls[@]} -eq 0 ]]; then
      network_status="no preflight urls"
    else
      network_status="blocked"
      for url in "${urls[@]}"; do
        if codex_buddies_url_reachable "$url"; then
          network_status="ok"
          break
        fi
      done
    fi
  fi

  if contains_csv_id "$DEFAULT_ROSTER" "$id"; then
    roster_status="yes"
  else
    roster_status="no"
  fi

  if [[ "$binary_status" == "ok" ]] && codex_buddies_buddy_is_healthy "$id"; then
    health_status="ok"
  else
    health_status="failed"
  fi

  if [[ "$binary_status" == "missing" ]]; then
    note="${install_hint:-Install the CLI and retry.}"
  elif [[ "$runtime_status" == "failed" ]]; then
    note="Runtime health check failed."
  elif [[ "$roster_status" == "yes" && "$health_status" == "failed" ]]; then
    note="Repeated preflight checks are flaky from this process."
  elif [[ "$network_status" == "blocked" ]]; then
    note="Provider endpoint preflight failed from this process."
  elif [[ "$network_status" == "no preflight urls" ]]; then
    note="No provider preflight configured."
  else
    note="ok"
  fi

  printf '| %s | %s | %s | %s | %s | %s | %s |\n' \
    "$id" \
    "$binary_status" \
    "$runtime_status" \
    "$network_status" \
    "$health_status" \
    "$roster_status" \
    "$note"
}

if [[ -n "$BUDDY_ID" ]]; then
  BUDDIES_CSV="$BUDDY_ID"
else
  BUDDIES_CSV="$(codex_buddies_list_buddies | paste -sd, -)"
fi

DEFAULT_ROSTER="$(codex_buddies_default_buddy_roster)"

printf '# Buddy Doctor\n\n'
printf 'Default roster now: `%s`\n\n' "${DEFAULT_ROSTER:-none}"
printf 'Network preflight enabled: `%s`\n\n' "$(codex_buddies_preflight_network_buddies)"
printf '| Buddy | Binary | Runtime | Provider Reachability | Overall Health | In Default Roster | Notes |\n'
printf '|---|---|---|---|---|---|---|\n'

IFS=',' read -r -a BUDDY_LIST <<< "$BUDDIES_CSV"
for buddy in "${BUDDY_LIST[@]-}"; do
  [[ -n "$buddy" ]] || continue
  buddy_status_line "$buddy"
done
