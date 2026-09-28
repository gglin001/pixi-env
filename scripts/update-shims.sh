#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(cd "$1" && pwd)"
shims="$root/shims"
# This directory is generated; never replace an unrelated directory.
if [[ -e "$shims" && ! -f "$shims/.extract-managed" ]]; then
  echo "Refusing to replace unmanaged directory: $shims" >&2
  exit 1
fi
staging="$(mktemp -d "$root/.shims.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/bin/by-package" "$staging/duplicates"
touch "$staging/bin/.extract-managed"

# Export only the commands explicitly selected by each package's recipe.
for prefix in "$root"/*; do
  [[ -f "$prefix/conda-meta/history" ]] || continue
  package="${prefix##*/}"
  exports="$project_root/recipes/$package/shims.txt"
  if [[ ! -f "$exports" ]]; then
    echo "No shim exports configured for $package; skipping" >&2
    continue
  fi
  mkdir "$staging/bin/by-package/$package"
  while read -r command_name || [[ -n "$command_name" ]]; do
    case "$command_name" in
      ''|\#*) continue ;;
    esac
    if [[ ! "$command_name" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.+-]*$ ]]; then
      echo "Invalid command name in $exports: $command_name" >&2
      exit 1
    fi
    executable="$prefix/bin/$command_name"
    # The same list can cover platform-specific executables.
    [[ -f "$executable" && -x "$executable" ]] || continue
    launcher="$staging/bin/by-package/$package/$command_name"
    {
      printf '#!/usr/bin/env bash\n'
      printf 'export PATH=%q:"$PATH"\n' "$prefix/bin"
      printf 'exec %q "$@"\n' "$executable"
    } > "$launcher"
    chmod +x "$launcher"
  done < "$exports"
done

# Expose short command names only when exactly one environment provides them.
for directory in "$staging/bin/by-package/"*/; do
  [[ -d "$directory" ]] || continue
  package="${directory%/}"
  package="${package##*/}"
  for launcher in "$directory"*; do
    [[ -f "$launcher" ]] || continue
    command_name="${launcher##*/}"
    short="$staging/bin/$command_name"
    if [[ -e "$staging/duplicates/$command_name" ]]; then
      continue
    elif [[ -L "$short" ]]; then
      rm "$short"
      touch "$staging/duplicates/$command_name"
    elif [[ -e "$short" ]]; then
      # The qualified launcher directory or ownership marker uses this name.
      touch "$staging/duplicates/$command_name"
    else
      ln -s "by-package/$package/$command_name" "$short"
    fi
  done
done

if [[ -d "$shims" ]]; then
  mv "$shims" "$staging/previous"
fi
if ! mv "$staging/bin" "$shims"; then
  [[ ! -d "$staging/previous" ]] || mv "$staging/previous" "$shims"
  exit 1
fi
duplicates=("$staging/duplicates/"*)
if [[ -e "${duplicates[0]}" ]]; then
  echo "Some command names are ambiguous or reserved; use $shims/by-package/<package>/<command>:" >&2
  printf '  %s\n' "${duplicates[@]##*/}" >&2
fi
echo "Unified command directory: $shims" >&2
