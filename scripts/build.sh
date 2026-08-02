#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="$project_root/build"
conda_root="$build_root/conda"

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

mkdir -p "$build_root" "$conda_root"
build_marker="$(mktemp "$build_root/.build-start.XXXXXX")"
trap 'rm -f "$build_marker"' EXIT

rattler-build build \
  --recipe "$project_root/recipe/recipe.yaml" \
  --target-platform "$target_platform" \
  --output-dir "$conda_root" \
  "$@"

package_file=""
while IFS= read -r candidate; do
  if [[ -n "$package_file" ]]; then
    echo "Multiple Herdr packages were produced" >&2
    exit 1
  fi
  package_file="$candidate"
done < <(find "$conda_root/$target_platform" -maxdepth 1 -type f -name 'herdr-*.conda' -newer "$build_marker" -print)

if [[ -z "$package_file" ]]; then
  echo "Herdr package was not produced" >&2
  exit 1
fi

rattler-build package extract "$package_file" --dest "$build_root"
mkdir -p "$build_root/bin" "$build_root/lib" "$build_root/include" "$build_root/share"

rm -rf \
  "$build_root/info" \
  "$conda_root/.tmp" \
  "$conda_root/bld" \
  "$conda_root/src_cache" \
  "$conda_root/test"
rm -f "$conda_root/.condapackageignore" "$conda_root/rattler-build-log.txt"
