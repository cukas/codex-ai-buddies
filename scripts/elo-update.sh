#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

WINNER=""
LOSER=""
TASK_CLASS="other"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --winner) WINNER="$2"; shift 2 ;;
    --loser) LOSER="$2"; shift 2 ;;
    --task-class) TASK_CLASS="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$WINNER" ]] && { echo "ERROR: --winner is required" >&2; exit 1; }
[[ -z "$LOSER" ]] && { echo "ERROR: --loser is required" >&2; exit 1; }

if [[ "$(codex_buddies_elo_enabled)" != "true" ]]; then
  exit 0
fi

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required for ELO updates" >&2; exit 1; }

ELO_FILE="$(codex_buddies_elo_file)"
K_FACTOR="$(codex_buddies_elo_k_factor)"
mkdir -p "$(dirname "$ELO_FILE")"
[[ -f "$ELO_FILE" ]] || echo '{}' > "$ELO_FILE"

get_rating() {
  local id="$1"
  local class="$2"
  local rating
  rating="$(jq -r --arg id "$id" --arg c "$class" '.[$id][$c].rating // empty' "$ELO_FILE" 2>/dev/null || true)"
  if [[ -z "$rating" || "$rating" == "null" ]]; then
    printf '1200\n'
  else
    printf '%s\n' "$rating"
  fi
}

get_games() {
  local id="$1"
  local class="$2"
  local games
  games="$(jq -r --arg id "$id" --arg c "$class" '.[$id][$c].games // 0' "$ELO_FILE" 2>/dev/null || true)"
  if [[ -z "$games" || "$games" == "null" ]]; then
    printf '0\n'
  else
    printf '%s\n' "$games"
  fi
}

WINNER_RATING="$(get_rating "$WINNER" "$TASK_CLASS")"
LOSER_RATING="$(get_rating "$LOSER" "$TASK_CLASS")"
WINNER_GAMES="$(get_games "$WINNER" "$TASK_CLASS")"
LOSER_GAMES="$(get_games "$LOSER" "$TASK_CLASS")"

NEW_RATINGS="$(awk -v wr="$WINNER_RATING" -v lr="$LOSER_RATING" -v k="$K_FACTOR" '
BEGIN {
  ew = 1 / (1 + 10^((lr - wr) / 400))
  el = 1 / (1 + 10^((wr - lr) / 400))
  new_wr = wr + k * (1 - ew)
  new_lr = lr + k * (0 - el)
  if (new_lr < 100) new_lr = 100
  printf "%d %d\n", new_wr, new_lr
}')"

NEW_WINNER_RATING="$(printf '%s\n' "$NEW_RATINGS" | awk '{print $1}')"
NEW_LOSER_RATING="$(printf '%s\n' "$NEW_RATINGS" | awk '{print $2}')"
NEW_WINNER_GAMES=$((WINNER_GAMES + 1))
NEW_LOSER_GAMES=$((LOSER_GAMES + 1))

WINNER_PROVISIONAL=false
LOSER_PROVISIONAL=false
(( NEW_WINNER_GAMES < 10 )) && WINNER_PROVISIONAL=true
(( NEW_LOSER_GAMES < 10 )) && LOSER_PROVISIONAL=true

TMP_FILE="${ELO_FILE}.tmp.$$"
jq \
  --arg w "$WINNER" \
  --arg l "$LOSER" \
  --arg c "$TASK_CLASS" \
  --argjson wr "$NEW_WINNER_RATING" \
  --argjson lr "$NEW_LOSER_RATING" \
  --argjson wg "$NEW_WINNER_GAMES" \
  --argjson lg "$NEW_LOSER_GAMES" \
  --argjson wp "$WINNER_PROVISIONAL" \
  --argjson lp "$LOSER_PROVISIONAL" \
  '
    .[$w][$c] = {rating: $wr, games: $wg, provisional: $wp} |
    .[$l][$c] = {rating: $lr, games: $lg, provisional: $lp}
  ' "$ELO_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$ELO_FILE"

printf 'ELO updated: %s %s->%s, %s %s->%s (%s)\n' \
  "$WINNER" "$WINNER_RATING" "$NEW_WINNER_RATING" "$LOSER" "$LOSER_RATING" "$NEW_LOSER_RATING" "$TASK_CLASS"
