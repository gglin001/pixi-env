#!/usr/bin/env bash
set -euo pipefail

if [[ "$build_platform" != "$target_platform" ]]; then
  echo "pi requires a native build for $target_platform" >&2
  exit 2
fi

export npm_config_audit=false
export npm_config_fund=false
export npm_config_update_notifier=false
export npm_config_cache="$BUILD_DIR/npm-cache"

npm ci --ignore-scripts
# Git excludes provider JSON data and native helpers. Hydration validates the
# generated data against the model types committed in this release tag.
npm run hydrate:model-data
npm run build:offline
case "$target_platform" in
  osx-arm64)
    npm run build:native:darwin
    ;;
  linux-64)
    export CPATH="$PREFIX/include${CPATH:+:$CPATH}"
    export LIBRARY_PATH="$PREFIX/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
    npm run build:native:linux
    ;;
esac

# Use upstream's consumer installer so all pi runtime workspaces come from
# this build, with external dependencies pinned by the release shrinkwrap.
cp "$RECIPE_DIR/install.mjs" ./conda-install.mjs
node ./conda-install.mjs

mkdir -p "$PREFIX/bin"
cat > "$PREFIX/bin/pi" <<'EOF'
#!/bin/sh
set -eu
prefix=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export PATH="$prefix/bin:$PATH"
exec "$prefix/bin/node" \
  "$prefix/lib/pi/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js" \
  "$@"
EOF
chmod +x "$PREFIX/bin/pi"
