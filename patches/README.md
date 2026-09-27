# Patch queue

Patches are applied with `patch -p1` to the extracted upstream tarball before
building, in lexical order:

1. `patches/<release>/*.patch` for every distribution
2. `patches/<release>/<codename>/*.patch` for that distribution only

Examples:

```
patches/squid/0001-fix-something.patch
patches/squid/trixie/0001-gcc-14-missing-include.patch
patches/tentacle/noble/0001-python-3.12-fix.patch
```

## Limiting a patch to certain Ceph versions

By default a patch applies to every version of its release. To restrict it,
add a `Ceph-Version:` line to the patch header, before the first `---` line:

```
Description: Fix the frobnicator
Ceph-Version: >= 20.2.0, < 20.2.5
---
--- a/src/...
```

- Conditions use `<`, `<=`, `=`, `>=` or `>` followed by a version, and
  several are combined with commas. All of them must hold.
- `Ceph-Version: = 20.2.3` applies the patch to exactly that version.
- Patches that don't match are skipped, which the build log shows as
  `Skipping <patch> (Ceph-Version: …)`.

Use an upper bound when upstream has fixed the problem in a later point
release. Otherwise the patch no longer applies to that release, and the build
fails.

## Notes

Patches may also touch `debian/` (e.g. to tweak dependencies). The directory
is mounted into the build container, so no image rebuild is needed after
adding one. When a patch changes the result of an already published version,
rebuild with `--rev N+1`.

Good sources for build fixes: the Proxmox Ceph packaging
(<https://git.proxmox.com/?p=ceph.git>) and Debian's packaging
(<https://salsa.debian.org/ceph-team/ceph>).
