# pixi-env

```sh
pixi run build                       # Build all packages
pixi run build TARGET                # Build one package
pixi run extract                     # Install all packages in separate environments
pixi run extract TARGET [DEST]       # Install one package, optionally into DEST
export PATH="$PWD/extract/shims:$PATH"
```

```sh
# Build without GOPROXY
GOPROXY=direct pixi run build nexttrace
GOPROXY=direct pixi run build vfkit
```

Optional GitHub download acceleration for Codex's V8 files:

```sh
GITHUB_DOWNLOAD_PROXY=https://gh-proxy.com pixi run build codex
# Alternative: GITHUB_DOWNLOAD_PROXY=https://ghfast.top
# Alternative: GITHUB_DOWNLOAD_PROXY=https://ghproxy.net
```

Unset it for direct downloads. Cached files and upstream checksum verification
remain in use. This setting does not affect Git clones or Cargo dependencies.

Archives are in `build/conda/<platform>/`. Each package and its dependencies are
installed in `extract/<package>/`, with shared command entry points in `extract/shims/`.
An explicit `DEST` installs directly into that directory; use `DEST/bin/`.

Configure exported commands in `recipes/<package>/shims.txt`, one name per line.
For duplicate names, use `extract/shims/by-package/<package>/<command>`.
After editing a list, refresh without reinstalling:

```sh
bash scripts/update-shims.sh extract
```
