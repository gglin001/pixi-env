# pi

Builds `pi` from the `v0.87.1` release tag over SSH. Supports native builds on
`osx-arm64` and `linux-64`.

```sh
pixi run build pi
pixi run extract pi
extract/shims/pi --version
```

The build uses the release's npm lockfile, compiles the CLI and its workspace
dependencies, and builds the platform's native TUI helper. Git excludes model
JSON data, so `hydrate:model-data` fetches provider catalogs before compilation.
Building requires network access to npm and those catalogs, plus GitHub SSH
access. The resulting package includes Node.js as a runtime dependency.
