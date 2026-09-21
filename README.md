# pixi-env

```sh
pixi run build
pixi run build TARGET
```

Packages are written to `build/conda/<platform>/`, with incremental build caches
under `build/conda/bld/`.

```sh
pixi run extract
pixi run extract TARGET
```

Without a target, extraction processes all `.conda` packages for the current
platform and `noarch`. With a target, it extracts the newest matching package.
Files are extracted into `build/` by default; an optional second argument sets
the destination directory.
