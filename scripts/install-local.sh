#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_NAME="codexs-ai-buddies"
INSTALL_MODE="${CODEX_BUDDIES_INSTALL_MODE:-copy}"

usage() {
  cat <<'EOF'
Usage: bash scripts/install-local.sh [--copy|--link|--mode copy|link]

Install modes:
  --copy          Copy the plugin into ~/.codex/plugins/local for normal use.
                  This is the default and does not depend on keeping the repo.
  --link          Symlink the repo into ~/.codex/plugins/local for development.
                  Keep the repo at the same path after installing.
  --mode <value>  Explicitly choose copy or link mode.
  -h, --help      Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --copy)
      INSTALL_MODE="copy"
      shift
      ;;
    --link)
      INSTALL_MODE="link"
      shift
      ;;
    --mode)
      if [[ $# -lt 2 ]]; then
        printf 'install-local.sh: --mode requires copy or link\n' >&2
        exit 1
      fi
      INSTALL_MODE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'install-local.sh: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$INSTALL_MODE" in
  copy|link)
    ;;
  *)
    printf 'install-local.sh: invalid mode: %s\n' "$INSTALL_MODE" >&2
    usage >&2
    exit 1
    ;;
esac

copy_plugin_tree() {
  local src="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if command -v rsync >/dev/null 2>&1; then
    mkdir -p "$dest"
    rsync -a --delete \
      --exclude '.git' \
      --exclude '.DS_Store' \
      "${src}/" "${dest}/"
  else
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -R "${src}/." "$dest/"
    rm -rf "$dest/.git" "$dest/.DS_Store"
  fi
}

replace_with_symlink() {
  local src="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  ln -s "$src" "$dest"
}

CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}"
PLUGIN_TARGET_DIR="${CODEX_HOME}/plugins/local"
PLUGIN_LINK="${PLUGIN_TARGET_DIR}/${PLUGIN_NAME}"
SKILLS_TARGET_DIR="${CODEX_HOME}/skills"
HOME_PLUGINS_DIR="${HOME}/plugins"
HOME_PLUGIN_LINK="${HOME_PLUGINS_DIR}/${PLUGIN_NAME}"
AGENTS_DIR="${HOME}/.agents/plugins"
MARKETPLACE_FILE="${AGENTS_DIR}/marketplace.json"
CURATED_ROOT="${CODEX_HOME}/.tmp/plugins"
CURATED_PLUGINS_DIR="${CURATED_ROOT}/plugins"
CURATED_PLUGIN_LINK="${CURATED_PLUGINS_DIR}/${PLUGIN_NAME}"
CURATED_MARKETPLACE_FILE="${CURATED_ROOT}/.agents/plugins/marketplace.json"
CODEX_CONFIG_FILE="${CODEX_HOME}/config.toml"

mkdir -p "$PLUGIN_TARGET_DIR" "$SKILLS_TARGET_DIR" "$HOME_PLUGINS_DIR" "$AGENTS_DIR"

if [[ "$INSTALL_MODE" == "copy" ]]; then
  rm -rf "$PLUGIN_LINK"
  copy_plugin_tree "$PLUGIN_ROOT" "$PLUGIN_LINK"
else
  replace_with_symlink "$PLUGIN_ROOT" "$PLUGIN_LINK"
fi

replace_with_symlink "$PLUGIN_LINK" "$HOME_PLUGIN_LINK"

for skill_dir in "${PLUGIN_LINK}"/skills/*; do
  [[ -d "$skill_dir" ]] || continue
  skill_name="$(basename "$skill_dir")"
  replace_with_symlink "$skill_dir" "${SKILLS_TARGET_DIR}/codexs-ai-buddies-${skill_name}"
done

if command -v jq >/dev/null 2>&1; then
  if [[ ! -f "$MARKETPLACE_FILE" ]]; then
    jq -n \
      --arg name "home-local" \
      --arg display "Home Local Plugins" \
      '{
        name: $name,
        interface: {displayName: $display},
        plugins: []
      }' > "$MARKETPLACE_FILE"
  fi

  tmp="${MARKETPLACE_FILE}.tmp.$$"
  jq --arg plugin_name "$PLUGIN_NAME" '
    .plugins = (
      (.plugins // [])
      | map(select(.name != $plugin_name))
      + [{
        name: $plugin_name,
        source: {
          source: "local",
          path: ("./plugins/" + $plugin_name)
        },
        policy: {
          installation: "AVAILABLE",
          authentication: "ON_INSTALL"
        },
        category: "Coding"
      }]
    )
  ' "$MARKETPLACE_FILE" > "$tmp" && mv "$tmp" "$MARKETPLACE_FILE"
fi

if [[ -d "$CURATED_ROOT" ]]; then
  mkdir -p "$CURATED_PLUGINS_DIR"
  copy_plugin_tree "$PLUGIN_LINK" "$CURATED_PLUGIN_LINK"

  if command -v jq >/dev/null 2>&1 && [[ -f "$CURATED_MARKETPLACE_FILE" ]]; then
    tmp="${CURATED_MARKETPLACE_FILE}.tmp.$$"
    jq --arg plugin_name "$PLUGIN_NAME" '
      .plugins = (
        (.plugins // [])
        | map(select(.name != $plugin_name))
        + [{
          name: $plugin_name,
          source: {
            source: "local",
            path: ("./plugins/" + $plugin_name)
          },
          policy: {
            installation: "AVAILABLE",
            authentication: "ON_INSTALL"
          },
          category: "Coding"
        }]
      )
    ' "$CURATED_MARKETPLACE_FILE" > "$tmp" && mv "$tmp" "$CURATED_MARKETPLACE_FILE"
  fi
fi

if [[ -f "$CODEX_CONFIG_FILE" ]] && ! grep -q '\[plugins\."codexs-ai-buddies@openai-curated"\]' "$CODEX_CONFIG_FILE"; then
  {
    printf '\n[plugins."codexs-ai-buddies@openai-curated"]\n'
    printf 'enabled = true\n'
  } >> "$CODEX_CONFIG_FILE"
fi

printf 'Installed plugin in %s mode at %s\n' "$INSTALL_MODE" "$PLUGIN_LINK"
printf 'Linked home-local plugin alias to %s\n' "$HOME_PLUGIN_LINK"
printf 'Linked skills into %s\n' "$SKILLS_TARGET_DIR"
if [[ -f "$MARKETPLACE_FILE" ]]; then
  printf 'Updated marketplace %s\n' "$MARKETPLACE_FILE"
fi
if [[ -d "$CURATED_PLUGIN_LINK" ]]; then
  printf 'Copied plugin into cached command index at %s\n' "$CURATED_PLUGIN_LINK"
fi
if [[ -f "$CURATED_MARKETPLACE_FILE" ]]; then
  printf 'Updated cached marketplace %s\n' "$CURATED_MARKETPLACE_FILE"
fi
if [[ "$INSTALL_MODE" == "link" ]]; then
  printf 'Link mode points at %s\n' "$PLUGIN_ROOT"
  printf 'Keep the repo at that path for the install to keep working.\n'
else
  printf 'Copy mode is self-contained under %s\n' "$PLUGIN_LINK"
fi
printf 'If Codex is already running, restart it before testing.\n'
