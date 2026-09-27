#!/usr/bin/env bash
set -euo pipefail

if [[ "$target_platform" != linux-64 ]]; then
  echo "Unsupported target platform: $target_platform" >&2
  exit 2
fi

# Preserve downloads and compiled dependencies across --keep-build rebuilds.
export CARGO_HOME="$BUILD_DIR/cargo-home/$target_platform"
export CARGO_TARGET_DIR="$BUILD_DIR/cargo-target/$target_platform"
export CARGO_NET_GIT_FETCH_WITH_CLI=true

cd "$SRC_DIR"
cargo build --locked --release --target x86_64-unknown-linux-gnu \
  --package cloud-hypervisor --bins --jobs "$CPU_COUNT"

mkdir -p "$PREFIX/bin"
for binary in cloud-hypervisor ch-remote; do
  install -m 755 "$CARGO_TARGET_DIR/x86_64-unknown-linux-gnu/release/$binary" \
    "$PREFIX/bin/$binary"
done
