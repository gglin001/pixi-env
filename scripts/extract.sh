#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
conda_root="$project_root/build/conda"
package_name="${1:-herdr}"
destination="${2:-$project_root/build}"

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

package_file=""
for package_dir in "$conda_root/$target_platform" "$conda_root/noarch"; do
  [[ -d "$package_dir" ]] || continue
  for candidate in "$package_dir"/"$package_name"-*.conda; do
    [[ -f "$candidate" ]] || continue
    if [[ -z "$package_file" || "$candidate" -nt "$package_file" ]]; then
      package_file="$candidate"
    fi
  done
done

if [[ -z "$package_file" ]]; then
  echo "Package not found: $package_name" >&2
  exit 1
fi

mkdir -p "$destination"
rattler-build package extract "$package_file" --dest "$destination"
