#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
recipe_args=(--recipe-dir "$project_root/recipes")

if [[ -n "${1:-}" && "$1" != -* ]]; then
  recipe_args=(--recipe "$project_root/recipes/$1")
  shift
fi

exec rattler-build build \
  --no-build-id \
  --keep-build \
  "${recipe_args[@]}" \
  --output-dir "$project_root/build/conda" \
  "$@"
