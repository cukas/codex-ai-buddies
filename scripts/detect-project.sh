#!/usr/bin/env bash
set -euo pipefail

CWD="${1:-$(pwd)}"

package_manager="npm"
language="unknown"
build_cmd="true"
test_cmd="true"
lint_cmd=""
fitness_cmd="true"

if [[ -f "${CWD}/pnpm-lock.yaml" ]]; then
  package_manager="pnpm"
elif [[ -f "${CWD}/yarn.lock" ]]; then
  package_manager="yarn"
fi

if [[ -f "${CWD}/package.json" ]]; then
  language="javascript"
  if command -v jq >/dev/null 2>&1; then
    build_script="$(jq -r '.scripts.build // empty' "${CWD}/package.json" 2>/dev/null || true)"
    test_script="$(jq -r '.scripts.test // empty' "${CWD}/package.json" 2>/dev/null || true)"
    lint_script="$(jq -r '.scripts.lint // empty' "${CWD}/package.json" 2>/dev/null || true)"
    [[ -n "$build_script" ]] && build_cmd="${package_manager} run build"
    [[ -n "$test_script" ]] && test_cmd="${package_manager} test"
    [[ -n "$lint_script" ]] && lint_cmd="${package_manager} run lint"
  fi
elif [[ -f "${CWD}/pyproject.toml" || -f "${CWD}/requirements.txt" ]]; then
  language="python"
  build_cmd="python -m compileall ."
  test_cmd="pytest"
  if [[ -f "${CWD}/pyproject.toml" ]] && grep -q "\\[tool.ruff" "${CWD}/pyproject.toml" 2>/dev/null; then
    lint_cmd="ruff check ."
  fi
elif [[ -f "${CWD}/Cargo.toml" ]]; then
  language="rust"
  build_cmd="cargo build"
  test_cmd="cargo test"
  lint_cmd="cargo fmt --check"
elif [[ -f "${CWD}/go.mod" ]]; then
  language="go"
  build_cmd="go build ./..."
  test_cmd="go test ./..."
fi

if [[ -n "$lint_cmd" && "$test_cmd" != "true" ]]; then
  fitness_cmd="${lint_cmd} && ${test_cmd}"
elif [[ "$test_cmd" != "true" ]]; then
  fitness_cmd="$test_cmd"
elif [[ "$build_cmd" != "true" ]]; then
  fitness_cmd="$build_cmd"
fi

if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg language "$language" \
    --arg build_cmd "$build_cmd" \
    --arg test_cmd "$test_cmd" \
    --arg lint_cmd "$lint_cmd" \
    --arg fitness_cmd "$fitness_cmd" \
    '{
      language: $language,
      build_cmd: $build_cmd,
      test_cmd: $test_cmd,
      lint_cmd: $lint_cmd,
      fitness_cmd: $fitness_cmd
    }'
else
  printf '{"language":"%s","build_cmd":"%s","test_cmd":"%s","lint_cmd":"%s","fitness_cmd":"%s"}\n' \
    "$language" "$build_cmd" "$test_cmd" "$lint_cmd" "$fitness_cmd"
fi
