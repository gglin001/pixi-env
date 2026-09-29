#!/usr/bin/env bash
set -euo pipefail

case "$target_platform" in
  linux-64) rust_target=x86_64-unknown-linux-gnu ;;
  osx-arm64) rust_target=aarch64-apple-darwin ;;
  *) echo "Unsupported target platform: $target_platform" >&2; exit 2 ;;
esac

# Preserve dependencies and compilation outputs across --keep-build rebuilds.
export CARGO_HOME="$BUILD_DIR/cargo-home/$target_platform"
export CARGO_TARGET_DIR="$BUILD_DIR/cargo-target/$target_platform"
export CARGO_NET_GIT_FETCH_WITH_CLI=true
# Keep macOS proc-macro dylibs loadable; strip only the installed executables.
export CARGO_PROFILE_RELEASE_STRIP=none
export CARGO_PROFILE_RELEASE_DEBUG=0
export STABLE_GIT_COMMIT
STABLE_GIT_COMMIT="$(git -C "$SRC_DIR" rev-parse HEAD)"

# Use the same V8 artifacts and trusted checksum manifests as upstream releases.
v8_version="$(python "$SRC_DIR/.github/scripts/rusty_v8_bazel.py" resolved-v8-crate-version)"
v8_dir="$BUILD_DIR/rusty-v8/$v8_version/$rust_target"
v8_base="https://github.com/openai/codex/releases/download/rusty-v8-v$v8_version"
# Public download proxies accept the original URL after their own prefix.
if [[ -n "${GITHUB_DOWNLOAD_PROXY:-}" ]]; then
  v8_base="${GITHUB_DOWNLOAD_PROXY%/}/$v8_base"
fi
v8_profile=ptrcomp_sandbox_release
v8_archive="librusty_v8_${v8_profile}_${rust_target}.a.gz"
v8_binding="src_binding_${v8_profile}_${rust_target}.rs"
v8_checksums="rusty_v8_${v8_profile}_${rust_target}.sha256"
mkdir -p "$v8_dir"
cd "$v8_dir"
for artifact in "$v8_checksums" "$v8_archive" "$v8_binding"; do
  if [[ ! -f "$artifact" ]]; then
    curl --fail --silent --show-error --location --retry 3 "$v8_base/$artifact" -o "$artifact.tmp"
    mv "$artifact.tmp" "$artifact"
  fi
done
if [[ "$target_platform" == linux-64 ]]; then
  checksum=(sha256sum)
else
  checksum=(shasum -a 256)
fi
grep -F "  $v8_checksums" \
  "$SRC_DIR/third_party/v8/rusty_v8_${v8_version//./_}_release_manifests.sha256" \
  | "${checksum[@]}" --check -
tr -d '\r' < "$v8_checksums" | "${checksum[@]}" --check -
export RUSTY_V8_ARCHIVE="$v8_dir/$v8_archive"
export RUSTY_V8_SRC_BINDING_PATH="$v8_dir/$v8_binding"

cd "$SRC_DIR/codex-rs"
# Release tags bump workspace manifests but leave local lock entries at 0.0.0.
# Synchronize workspace versions while retaining locked third-party dependencies.
cargo update --workspace
mkdir -p "$PREFIX/bin"
if [[ "$target_platform" == linux-64 ]]; then
  cargo build --locked --release --target "$rust_target" --package codex-bwrap --bin bwrap --jobs "$CPU_COUNT"
  mkdir -p "$PREFIX/bin/codex-resources" "$PREFIX/share/codex"
  install -m 755 "$CARGO_TARGET_DIR/$rust_target/release/bwrap" "$PREFIX/bin/codex-resources/bwrap"
  "${STRIP:-strip}" --strip-unneeded "$PREFIX/bin/codex-resources/bwrap"
  patchelf --set-rpath '$ORIGIN/../../lib' "$PREFIX/bin/codex-resources/bwrap"
  (cd "$PREFIX" && sha256sum bin/codex-resources/bwrap > share/codex/bwrap.sha256)
  export CODEX_BWRAP_SHA256
  CODEX_BWRAP_SHA256="$(cut -d ' ' -f 1 "$PREFIX/share/codex/bwrap.sha256")"
fi

binaries=(codex codex-code-mode-host codex-responses-api-proxy)
build_args=()
for binary in "${binaries[@]}"; do
  build_args+=(--bin "$binary")
done
cargo build --locked --release --target "$rust_target" \
  --package codex-cli --package codex-code-mode-host --package codex-responses-api-proxy \
  "${build_args[@]}" --jobs "$CPU_COUNT"
for binary in "${binaries[@]}"; do
  install -m 755 "$CARGO_TARGET_DIR/$rust_target/release/$binary" "$PREFIX/bin/$binary"
  "${STRIP:-strip}" "$PREFIX/bin/$binary"
done
