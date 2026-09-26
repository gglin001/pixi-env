# virtiofsd

Build the upstream GitLab release v1.14.0, released 2026-07-06. The release API
and tags were checked on 2026-09-25 UTC. The release commit is
`c2540f8db14caba81c1e37fba23fc7bf2cd7f0dd`.

```sh
pixi run build virtiofsd
pixi run extract virtiofsd
```

## macOS usage

The macOS backend runs as an ordinary host user. Export a directory to a trusted
guest with host-user permissions. Guest UID/GID translation is needed when its
users differ from the host. For a single-user share:

```sh
mkdir -p shared
extract/bin/virtiofsd \
  --socket-path "$PWD/virtiofs.sock" \
  --shared-dir "$PWD/shared" \
  --sandbox none \
  --translate-uid "squash-guest:0:$(id -u):4294967295" \
  --translate-gid "squash-guest:0:$(id -g):4294967295" \
  --cache auto --thread-pool-size 4
```

Root execution is rejected on macOS. Linux namespaces, seccomp, capabilities,
POSIX ACLs, SELinux security labels, killpriv-v2, mandatory inode file handles,
direct I/O and live migration are unavailable in this backend. The macOS default
sandbox is `none`; Linux retains the upstream namespace default. Host permissions
still apply, and this macOS port is intended for trusted local guests, not
isolation of hostile guests. Linux keeps the upstream implementations.

QEMU must enable vhost-user, which this repository's QEMU recipe now does:

```sh
pixi run build qemu
pixi run extract qemu
```

Add the following to an existing QEMU command, with a matching `-m 2G`. Use a
regular writable file for shared memory on macOS; Linux `memory-backend-memfd`
is not available there. Each running VM needs its own memory file and socket.

```sh
-object memory-backend-file,id=mem,size=2G,mem-path="$PWD/guest.ram",share=on \
-numa node,memdev=mem \
-chardev socket,id=fs,path="$PWD/virtiofs.sock" \
-device vhost-user-fs-pci,chardev=fs,tag=hostshare
```

Mount inside the Linux guest:

```sh
sudo mkdir -p /mnt/hostshare
sudo mount -t virtiofs hostshare /mnt/hostshare
```

## Implementation and performance

The recipe applies local patches to the release and two checksum-pinned crates.
It does not build from floating fork branches. The filesystem portability patch
is adapted from Christopher Thomas's BSD/Apache-licensed macOS port, commit
`390cc8887e92e4e2a688538ee6da50bdc24501d8` in
`github.com/christhomas/virtiofsd`, with the unrelated host notification feature
excluded. Additional fixes cover guest/host flag translation, read-only opens,
inode identity checks when reopening files, concurrent credentials, directory
pagination and append writes. The dependency patches retain the upstream release's
vhost 0.16.0, vhost-user-backend 0.22.0 and vmm-sys-util 0.15.0 versions.

- Release LTO remains enabled. CPU flags remain portable across Apple Silicon.
- Guest RAM is shared with QEMU. Normal data I/O uses `preadv`/`pwritev` directly
  on guest buffers, without an intermediate file-data copy in the daemon.
- `kqueue` blocks until work arrives. Pipe notifications are drained in batches;
  a full notification pipe is treated as an already-pending wakeup.
- Each open directory retains a buffered Darwin directory stream and cookies.
  Pagination uses bounded batches instead of rescanning the whole directory.
- Worker threads do not change process-wide credentials or the working directory.
- Keep `--cache auto` for normal use. `--cache always` and `--writeback` require
  exclusive guest ownership of shared data to avoid stale host/guest views.

macOS has no general equivalent to Linux `copy_file_range`; the daemon returns
`EOPNOTSUPP` so the guest can fall back to normal I/O. Sparse extent seeking is
translated to Darwin's different SEEK_DATA/SEEK_HOLE numbering. `fallocate`
returns `EOPNOTSUPP` because Darwin cannot uphold Linux range allocation
guarantees. Reopening an unlinked inode by name is not
supported, although already-open file handles remain usable after unlink.
Darwin also lacks Linux's permission-independent `O_PATH`: looking up an inode
that the host user cannot open, including a mode-000 file, returns `EACCES`.
Use matching guest/host UID mapping when normal ownership semantics are needed;
the squash example intentionally maps all guest writers to one host user.

## Validation

The build runs Rust unit tests and macOS filesystem integration tests. The
installed-package test drives the real vhost-user socket with SCM_RIGHTS,
shared guest RAM, descriptor rings, kick/call notifications and hundreds of
FUSE requests, including ring wraparound. It tests both synchronous handling
and a four-worker thread pool. Logs and VM validation artifacts from local
development are kept under `debug_agent/`.
