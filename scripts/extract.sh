#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
conda_root="$project_root/build/conda"
package_name="${1:-}"
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

package_names=()
package_files=()
for package_dir in "$conda_root/$target_platform" "$conda_root/noarch"; do
  [[ -d "$package_dir" ]] || continue
  for candidate in "$package_dir"/*.conda; do
    [[ -f "$candidate" ]] || continue
    # Conda filenames end in -VERSION-BUILD. Names may contain hyphens.
    candidate_name="${candidate##*/}"
    candidate_name="${candidate_name%-*}"
    candidate_name="${candidate_name%-*}"
    [[ -z "$package_name" || "$candidate_name" == "$package_name" ]] || continue

    # A prefix can contain only one version of each package.
    package_index=0
    while [[ $package_index -lt ${#package_names[@]} ]]; do
      [[ "${package_names[$package_index]}" == "$candidate_name" ]] && break
      package_index=$((package_index + 1))
    done
    if [[ $package_index -eq ${#package_names[@]} ]]; then
      package_names+=("$candidate_name")
      package_files+=("$candidate")
    elif [[ "$candidate" -nt "${package_files[$package_index]}" ]]; then
      package_files[$package_index]="$candidate"
    fi
  done
done

if [[ ${#package_files[@]} -eq 0 ]]; then
  echo "Package not found: ${package_name:-$conda_root/$target_platform or $conda_root/noarch}" >&2
  exit 1
fi

package_specs=()
for package_file in "${package_files[@]}"; do
  package_stem="${package_file##*/}"
  package_stem="${package_stem%.conda}"
  package_build="${package_stem##*-}"
  package_stem="${package_stem%-*}"
  package_version="${package_stem##*-}"
  package_specs+=("$conda_root::${package_stem%-*}=$package_version=$package_build")
done

# Initialize metadata without recreating build/, which also holds packages and
# incremental build caches. Existing extracted files are replaced on install.
mkdir -p "$destination/conda-meta"
touch "$destination/conda-meta/history"

# Installing by channel MatchSpec resolves runtime dependencies and relocates
# prefixes. Passing archive paths directly would skip dependency resolution.
exec micromamba install --yes --no-rc \
  --prefix "$destination" \
  --override-channels --channel "$conda_root" --channel conda-forge \
  --repodata-ttl 0 --force-reinstall \
  "${package_specs[@]}"
