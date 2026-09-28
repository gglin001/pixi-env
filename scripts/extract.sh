#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
conda_root="$project_root/build/conda"
package_name="${1:-}"
destination_override="${2:-}"

SECONDS=0
log() {
  printf '[extract +%ss] %s\n' "$SECONDS" "$*" >&2
}

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    target_platform="linux-64"
    checksum_command=(sha256sum)
    ;;
  Darwin-arm64)
    target_platform="osx-arm64"
    checksum_command=(shasum -a 256)
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
      package_files[package_index]="$candidate"
    fi
  done
done

if [[ ${#package_files[@]} -eq 0 ]]; then
  echo "Package not found: ${package_name:-$conda_root/$target_platform or $conda_root/noarch}" >&2
  exit 1
fi

log "Selected ${#package_files[@]} package(s) for $target_platform"

# The indexer reuses records by filename. Hash the archives to detect same-name
# rebuilds, but avoid decompressing their metadata again on unchanged runs.
log "Checking local channel archives"
index_state="$conda_root/.extract-index.sha256"
current_index_state="$(mktemp "$conda_root/.extract-index.XXXXXX")"
trap 'rm -f "$current_index_state"' EXIT
for archive in "$conda_root"/*/*.conda "$conda_root"/*/*.tar.bz2; do
  [[ -f "$archive" ]] || continue
  "${checksum_command[@]}" "$archive"
done > "$current_index_state"

if [[ -f "$conda_root/$target_platform/repodata.json" &&
      -f "$conda_root/noarch/repodata.json" ]] &&
    cmp -s "$current_index_state" "$index_state"; then
  log "Local channel unchanged; reusing index"
else
  log "Refreshing local channel index"
  rattler-index fs "$conda_root" --force
  mv "$current_index_state" "$index_state"
fi

for package_file in "${package_files[@]}"; do
  package_stem="${package_file##*/}"
  package_stem="${package_stem%.conda}"
  selected_name="${package_stem%-*}"
  selected_name="${selected_name%-*}"
  destination="${destination_override:-$project_root/extract}/$selected_name"
  if [[ -n "$package_name" && -n "$destination_override" ]]; then
    destination="$destination_override"
  fi

  install_args=(--repodata-ttl 3600 --force-reinstall)
  # --force-reinstall can keep an older installed build despite an exact spec.
  if [[ ! -f "$destination/conda-meta/$package_stem.json" ]]; then
    install_args=(--repodata-ttl 3600)
  fi
  package_build="${package_stem##*-}"
  package_stem="${package_stem%-*}"
  package_version="${package_stem##*-}"
  package_spec="$conda_root::$selected_name=$package_version=$package_build"

  # Each target gets its own prefix so its dependencies are solved independently.
  mkdir -p "$destination/conda-meta"
  touch "$destination/conda-meta/history"

  # Channel MatchSpecs resolve dependencies and relocate prefixes.
  log "Installing $selected_name and dependencies into $destination using $project_root/.condarc"
  micromamba install --yes --rc-file "$project_root/.condarc" \
    --prefix "$destination" \
    --override-channels --channel "$conda_root" --channel conda-forge \
    "${install_args[@]}" \
    "$package_spec"

  # micromamba re-signs relocated Mach-O files without preserving entitlements.
  if [[ "$target_platform" == osx-arm64 && "$selected_name" == qemu ]]; then
    /usr/bin/codesign --force --sign - \
      --entitlements "$destination/share/qemu/hvf-entitlements.plist" \
      "$destination/bin/qemu-system-aarch64"
  fi

  if [[ "$target_platform" == osx-arm64 && "$selected_name" == vfkit ]]; then
    /usr/bin/codesign --force --sign - \
      --entitlements "$destination/share/vfkit/vf.entitlements" \
      "$destination/bin/vfkit"
  fi

  if [[ -z "$package_name" || -z "$destination_override" ]]; then
    bash "$project_root/scripts/update-shims.sh" "${destination_override:-$project_root/extract}"
  fi
done

log "Completed"
