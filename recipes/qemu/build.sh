#!/usr/bin/env bash
set -euo pipefail

# target_platform is supplied by rattler-build.
# shellcheck disable=SC2154
platform="$target_platform"

# Preserve source timestamps and the out-of-tree build across rattler rebuilds.
persistent_src="$BUILD_DIR/source-cache/$platform"
build_path="$BUILD_DIR/qemu-build/$platform"
mkdir -p "$persistent_src" "$build_path"
rsync --archive --checksum --delete --no-times --omit-dir-times \
  --exclude '/.source_info.json' \
  --exclude '/build_env.sh' \
  --exclude '/conda_build.log' \
  --exclude '/conda_build.sh' \
  "$SRC_DIR/" "$persistent_src/"

platform_args=()
case "$platform" in
linux-64) platform_args+=(--enable-linux-user --enable-kvm) ;;
osx-arm64)
  # QEMU does not read OBJC from the environment and otherwise selects PATH's clang.
  platform_args+=(--disable-user --enable-hvf --objcc="${OBJC:-$CC}")
  ;;
esac

cd "$build_path"
"$persistent_src/configure" \
  --prefix="$PREFIX" \
  --libdir="$PREFIX/lib" \
  --cc="$CC" \
  --cxx="$CXX" \
  --python="$BUILD_PREFIX/bin/python" \
  --without-default-features \
  --disable-docs \
  --enable-system \
  --enable-tcg \
  --enable-tools \
  --enable-fdt=system \
  --enable-pixman \
  --enable-slirp \
  --enable-vnc \
  "${platform_args[@]}"

make -j"$CPU_COUNT"
make install

if [[ "$platform" == osx-* ]]; then
  # QEMU's Finder icons prevent rattler-build from re-signing relocated binaries.
  /usr/bin/xattr -d com.apple.ResourceFork "$PREFIX"/bin/qemu-system-*
  /usr/bin/xattr -d com.apple.FinderInfo "$PREFIX"/bin/qemu-system-*
fi
