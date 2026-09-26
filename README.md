# pixi-env

```sh
pixi run build                       # Build all packages
pixi run build TARGET                # Build one package
pixi run extract                     # Install all packages and dependencies
pixi run extract TARGET [DEST]       # Install one package, optionally into DEST
```

```sh
# no GOPROXY
GOPROXY=direct pixi run build nexttrace
```

Package archives: `build/conda/<platform>/`. Default install location: `extract/`,
with executables in `extract/bin/`. Dependencies are installed automatically.

For native macOS virtio-fs sharing, see [virtiofsd build and usage](recipes/virtiofsd/README.md).
Its QEMU integration requires the QEMU recipe's vhost-user support and pipe notification patch.
