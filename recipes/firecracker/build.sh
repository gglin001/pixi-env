#!/usr/bin/env bash
set -euo pipefail

if [[ "$target_platform" != linux-64 ]]; then
  echo "Unsupported target platform: $target_platform" >&2
  exit 2
fi

# The conda Rust toolchain supplies the native GNU target. Firecracker's
# upstream devtool uses the same GNU path when musl is not selected; the
# resulting binary is suitable for Linux hosts and avoids requiring Docker or
# rustup inside rattler-build.
export CARGO_HOME="$BUILD_DIR/cargo-home/$target_platform"
export CARGO_TARGET_DIR="$BUILD_DIR/cargo-target/$target_platform"
export CARGO_NET_GIT_FETCH_WITH_CLI=true
export AWS_LC_SYS_NO_JITTER_ENTROPY=1
export AWS_LC_SYS_CFLAGS="-DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX"
export LIBRARY_PATH="$BUILD_PREFIX/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"

mkdir -p "$CARGO_HOME" "$CARGO_TARGET_DIR"
cd "$SRC_DIR"

cargo build \
  --locked \
  --release \
  --target x86_64-unknown-linux-gnu \
  --package firecracker

install -Dm755 \
  "$CARGO_TARGET_DIR/x86_64-unknown-linux-gnu/release/firecracker" \
  "$PREFIX/bin/firecracker"
