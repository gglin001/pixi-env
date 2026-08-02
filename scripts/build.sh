#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
conda_root="$project_root/build/conda"
recipes_root="$project_root/recipes"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    target_platform="linux-64"
    ;;
  Darwin-arm64)
    target_platform="osx-arm64"
    ;;
  *)
    echo "Unsupported build host: $(uname -s) $(uname -m)" >&2
    exit 2
    ;;
esac

mkdir -p "$conda_root"

rattler-build build \
  --no-build-id \
  --keep-build \
  --recipe-dir "$recipes_root" \
  --target-platform "$target_platform" \
  --output-dir "$conda_root" \
  "$@"
