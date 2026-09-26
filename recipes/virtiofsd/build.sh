#!/usr/bin/env bash
set -euo pipefail

# Rattler downloads .crate files without extracting them. These are tar.gz
# archives; unpack into Cargo's pinned path dependencies, then patch locally.
tar -xzf vendor/vhost/vhost-0.16.0.tar.gz -C vendor/vhost --strip-components=1
tar -xzf vendor/vmm-sys-util/vmm-sys-util-0.15.0.tar.gz -C vendor/vmm-sys-util --strip-components=1
patch --batch -p1 -d vendor/vhost < "$RECIPE_DIR/patches/0002-vhost-macos.patch"
patch --batch -p1 -d vendor/vmm-sys-util < "$RECIPE_DIR/patches/0003-vmm-sys-util-macos.patch"

# Keep release LTO and portable CPU code generation. Do not strip proc-macro
# dylibs: conda's macOS strip can misalign LINKEDIT during compilation.
export CARGO_PROFILE_RELEASE_STRIP=none
export CARGO_TARGET_DIR="$BUILD_DIR/cargo-target/$target_platform"

cargo install --path . --locked --no-track --force --root "$PREFIX" --bin virtiofsd
if [[ "$build_platform" == "$target_platform" ]]; then
  cargo test --release --locked --lib --tests
fi

install -d "$PREFIX/share/doc/virtiofsd"
install -m 644 "$RECIPE_DIR/README.md" "$PREFIX/share/doc/virtiofsd/README.md"
