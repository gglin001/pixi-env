#!/usr/bin/env bash
set -euo pipefail

# Set GOPROXY=direct to bypass proxies, or supply a custom proxy URL.
export GOPROXY="${GOPROXY:-https://goproxy.cn,https://proxy.golang.org,direct}"

# Keep module downloads and compilation cached across --keep-build rebuilds.
export GOPATH="$BUILD_DIR/go"
export GOCACHE="$BUILD_DIR/go-build/${target_platform}"
export GOTOOLCHAIN=local

case "$target_platform" in
  osx-arm64)
    export GOOS=darwin GOARCH=arm64 CGO_ENABLED=1
    export CGO_CFLAGS="${CFLAGS:-} -I$PREFIX/include"
    export CGO_LDFLAGS="${LDFLAGS:-} -L$PREFIX/lib"
    ;;
  linux-64)
    export GOOS=linux GOARCH=amd64 CGO_ENABLED=0
    ;;
  *)
    echo "Unsupported target platform: $target_platform" >&2
    exit 2
    ;;
esac

cd "$SRC_DIR"
build_date="$(git show -s --format=%cI HEAD)"
commit_id="$(git rev-parse --short HEAD)"
ldflags="-s -w -X github.com/nxtrace/NTrace-core/config.Version=v${PKG_VERSION}"
ldflags+=" -X github.com/nxtrace/NTrace-core/config.BuildDate=${build_date}"
ldflags+=" -X github.com/nxtrace/NTrace-core/config.CommitID=${commit_id}"

mkdir -p "$PREFIX/bin"
go build -mod=readonly -trimpath -ldflags "$ldflags" -o "$PREFIX/bin/nexttrace" .
