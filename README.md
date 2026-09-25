# pixi-env

```sh
pixi run build                       # Build all packages
pixi run build TARGET                # Build one package
pixi run extract                     # Install all packages and dependencies
pixi run extract TARGET [DEST]       # Install one package, optionally into DEST
```

```sh
GOPROXY=direct pixi run build nexttrace
```

Package archives: `build/conda/<platform>/`. Default install location: `extract/`,
with executables in `extract/bin/`. Dependencies are installed automatically.
