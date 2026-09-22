# recipes

## cloud-utils 0.34

```sh
pixi run build cloud-utils
pixi run extract cloud-utils
export PATH="$PWD/build/bin:$PATH"
cloud-localds seed.iso user-data meta-data
```

The recipe fetches tag `0.34` from `git@github.com:canonical/cloud-utils.git`
using rattler-build's equivalent `ssh://git@github.com/canonical/cloud-utils.git`
URL. GitHub SSH access must be configured for the build.

On macOS, `cloud-localds` uses the system `hdiutil` to create ISO seed images
when `genisoimage` is unavailable. GNU command-line tools and Python are
installed as dependencies. Tar seed formats and `write-mime-multipart` are
also tested. On Linux, ISO creation requires `genisoimage` on `PATH`.

Optional formats need additional tools: `qemu-img` for converted disk images,
and `mkfs.vfat` plus `mcopy` for VFAT. `mount-image-callback` requires Linux
mounting facilities; `growpart` and `resize-part-image` require suitable
partition and filesystem tools. Installing these commands does not make
Linux disk operations available on macOS.
