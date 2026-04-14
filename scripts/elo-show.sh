#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

TASK_CLASS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-class) TASK_CLASS="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

ELO_FILE="$(codex_buddies_elo_file)"
if [[ ! -f "$ELO_FILE" ]]; then
  echo "No ELO data yet. Run forge to start tracking ratings."
  exit 0
fi

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required to display leaderboard" >&2; exit 1; }

if [[ -n "$TASK_CLASS" ]]; then
  echo "## ELO Leaderboard — ${TASK_CLASS}"
  echo
  printf "| %-15s | %-8s | %-6s | %-11s |\n" "Buddy" "Rating" "Games" "Status"
  printf "|%-17s|%-10s|%-8s|%-13s|\n" "-----------------" "----------" "--------" "-------------"
  jq -r --arg c "$TASK_CLASS" '
    to_entries[]
    | select(.value[$c] != null)
    | [.key, (.value[$c].rating | tostring), (.value[$c].games | tostring),
       (if .value[$c].provisional then "provisional" else "established" end)]
    | @tsv
  ' "$ELO_FILE" | sort -t$'\t' -k2 -rn | while IFS=$'\t' read -r name rating games status; do
    printf "| %-15s | %-8s | %-6s | %-11s |\n" "$name" "$rating" "$games" "$status"
  done
  exit 0
fi

CLASSES="$(jq -r '[.[] | keys[]] | unique[]' "$ELO_FILE" 2>/dev/null || true)"
if [[ -z "$CLASSES" ]]; then
  echo "No ELO data yet. Run forge to start tracking ratings."
  exit 0
fi

echo "## ELO Leaderboard — All Classes"
echo
for class in $CLASSES; do
  echo "### ${class}"
  echo
  printf "| %-15s | %-8s | %-6s | %-11s |\n" "Buddy" "Rating" "Games" "Status"
  printf "|%-17s|%-10s|%-8s|%-13s|\n" "-----------------" "----------" "--------" "-------------"
  jq -r --arg c "$class" '
    to_entries[]
    | select(.value[$c] != null)
    | [.key, (.value[$c].rating | tostring), (.value[$c].games | tostring),
       (if .value[$c].provisional then "provisional" else "established" end)]
    | @tsv
  ' "$ELO_FILE" | sort -t$'\t' -k2 -rn | while IFS=$'\t' read -r name rating games status; do
    printf "| %-15s | %-8s | %-6s | %-11s |\n" "$name" "$rating" "$games" "$status"
  done
  echo
done
