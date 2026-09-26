#!/usr/bin/env bash
set -euo pipefail

if [[ "$target_platform" != osx-arm64 ]]; then
  echo "Unsupported target platform: $target_platform" >&2
  exit 2
fi

export GOPROXY="${GOPROXY:-https://goproxy.cn,https://proxy.golang.org,direct}"
export GOPATH="$BUILD_DIR/go"
export GOCACHE="$BUILD_DIR/go-build/${target_platform}"
export GOTOOLCHAIN=local
export GOOS=darwin GOARCH=arm64 CGO_ENABLED=1
export CGO_CFLAGS="${CFLAGS:-} -mmacosx-version-min=13.0"
export CGO_LDFLAGS="${LDFLAGS:-} -mmacosx-version-min=13.0"

cd "$SRC_DIR"
mkdir -p "$PREFIX/bin" "$PREFIX/share/vfkit"
go build -mod=readonly -trimpath \
  -ldflags "-s -w -X github.com/crc-org/vfkit/pkg/cmdline.gitVersion=v${PKG_VERSION}" \
  -o "$PREFIX/bin/vfkit" ./cmd/vfkit
install -m 644 vf.entitlements "$PREFIX/share/vfkit/vf.entitlements"
/usr/bin/codesign --force --sign - \
  --entitlements "$PREFIX/share/vfkit/vf.entitlements" "$PREFIX/bin/vfkit"
