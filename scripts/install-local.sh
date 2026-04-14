#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_NAME="codexs-ai-buddies"

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
ln -sfn "$PLUGIN_ROOT" "$PLUGIN_LINK"
ln -sfn "$PLUGIN_ROOT" "$HOME_PLUGIN_LINK"

for skill_dir in "${PLUGIN_ROOT}"/skills/*; do
  [[ -d "$skill_dir" ]] || continue
  skill_name="$(basename "$skill_dir")"
  ln -sfn "$skill_dir" "${SKILLS_TARGET_DIR}/codexs-ai-buddies-${skill_name}"
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
  copy_plugin_tree "$PLUGIN_ROOT" "$CURATED_PLUGIN_LINK"

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

printf 'Linked plugin to %s\n' "$PLUGIN_LINK"
printf 'Linked home-local plugin to %s\n' "$HOME_PLUGIN_LINK"
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
printf 'If Codex caches plugins, restart it before testing.\n'
