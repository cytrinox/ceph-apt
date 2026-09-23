# Building the ceph-apt repository

This document is for maintaining the repository. To install Ceph from it, see
[README.md](README.md).

The tooling in this project builds upstream [Ceph](https://ceph.io) releases as
Debian packages in a container and publishes them as signed apt repositories. There is one repository
per Ceph release (squid, tentacle, …), and it keeps every point release built
into it.

- Distributions: Debian bookworm/trixie, Ubuntu jammy/noble (any
  `debian:`/`ubuntu:` base image should work)
- Architectures: amd64 and arm64, each built natively on a host of that arch
- Output: a static directory tree you can `rsync` to any web hosting

## How it works

```
download.ceph.com/tarballs/ceph-X.Y.Z.tar.gz
        │  ./ceph-apt build X.Y.Z <dist>      (container per dist, native arch)
        ▼
repo/<release>/pool/<dist>/main/c/ceph/*.deb      (immutable, all versions kept)
        │  ./ceph-apt index                     (container, apt-ftparchive)
        ▼
repo/<release>/dists/<dist>/{Release,main/binary-*/Packages}
        │  ./ceph-apt sign                      (host, your own gpg)
        ▼
repo/<release>/dists/<dist>/{InRelease,Release.gpg}
        │  rsync
        ▼
https://ceph-apt.cytrinox.net/<release>
```

- `build` uses the `debian/` directory that ships in the upstream release
  tarball. It adds a changelog entry and installs the build dependencies
  inside the container. It skips the `-dbg` packages (like upstream's
  `make-debs.sh`), builds, and copies the `.deb`s into the pool.
- `index` regenerates all metadata from the pool contents. It keeps no state,
  so you can merge pools from several hosts with rsync and index anywhere.
  The result is unsigned.
- `sign` runs on the host with your normal gpg setup (agent, pinentry,
  smartcards). The secret key never enters a container, and build hosts need
  no key at all.
- Packages in the pool are never overwritten (without `--force`). To rebuild a
  published version, bump the rebuild number with `--rev`.

### Versions

Packages are versioned `<upstream>-1~<distro><version>u<rev>`:

| Distribution | Example |
|---|---|
| Debian 12 bookworm | `19.2.3-1~deb12u1` |
| Debian 13 trixie | `19.2.3-1~deb13u1` |
| Ubuntu 24.04 noble | `19.2.3-1~ubuntu24.04u1` |

The numeric distro tag makes packages upgrade correctly on distribution
upgrades. The version string also avoids `+`, which some static hosts (S3 and
friends) mangle in URLs.

### Rebuilding a version (`--rev`)

The trailing `u<rev>` is the rebuild number. It defaults to 1. To rebuild a
version that is already in the pool (for example after adding a patch), bump
it with `--rev`:

```sh
./ceph-apt build 19.2.3 bookworm --rev 2     # → 19.2.3-1~deb12u2
```

- A build refuses to reuse a version that is already in the pool for that
  arch. Don't use `--force` for published versions: clients that downloaded
  the old file would get hash mismatches.
- Build amd64 and arm64 with the same `--rev`. The arch:all packages are built
  on amd64, and the arch-specific packages depend on them at exactly the same
  version.
- The number is per distribution, so rebuilding only trixie (`…~deb13u2`)
  leaves bookworm at `…~deb12u1`.
- Clients upgrade normally: `…u2` is newer than `…u1`, and any later point
  release (`19.2.4-1~deb12u1`) is newer than both.

### Repository layout

```
repo/
  ceph-apt.asc                                  public signing key
  squid/
    dists/bookworm/{Release,InRelease,Release.gpg}
    dists/bookworm/main/binary-{amd64,arm64}/Packages{,.gz,.xz}
    pool/bookworm/main/c/ceph/*.deb
    buildlogs/bookworm/*.{buildinfo,changes,build.xz}
    dists/trixie/... pool/trixie/...
  tentacle/...
```

## Requirements

On each build host:

- podman (rootless works) or docker
- About 60 GB of free disk in `WORK_DIR` per concurrent build, plus room for
  ccache (30 GB default) and the repository (about 1.2 GB per point release
  per distribution and arch, without debug packages)
- RAM: the build runs one compile job per 3 GB of RAM (capped at the CPU
  count). With 8 cores and 32 GB, expect several hours for the first build of
  a release. Point releases are faster thanks to ccache.

## Setup

```sh
cp ceph-apt.conf.example ceph-apt.conf
$EDITOR ceph-apt.conf

# Signing key (once, on the host that signs). Clients trust this key.
# Put its fingerprint into SIGNING_KEY in ceph-apt.conf.
gpg --quick-generate-key "Ceph apt repository <you@example.org>" ed25519 sign never

# Builder images, one per distribution, on every build host
./ceph-apt image bookworm trixie
```

## Building

```sh
./ceph-apt build 19.2.3 bookworm
./ceph-apt build 19.2.3 trixie
./ceph-apt index                             # all releases, or: ./ceph-apt index squid
./ceph-apt sign                              # with SIGNING_KEY from the config
./ceph-apt sign --key=<ID>                   # override the configured key for one run
./ceph-apt build 20.2.4 trixie --index       # build, index, and sign if SIGNING_KEY is set
```

Every `index` removes the previous signatures of the suites it rewrites, so
always run `sign` after `index` and before uploading. A repository uploaded
unsigned makes `apt update` fail on the clients.

Build options (after `<version> <dist>`):

| Option | Meaning |
|---|---|
| `--rev N` | rebuild number (`…u2`) for rebuilding an already published version, see [above](#rebuilding-a-version---rev) |
| `--index` | run `index` afterwards, and `sign` if `SIGNING_KEY` is set |
| `--jobs N` | override the number of parallel compile jobs |
| `--with-dbg` | also build and publish the `-dbg` packages (several GB) |
| `--release NAME` | Ceph release name, if the version→name mapping doesn't know it yet |
| `--keep` | keep the build tree in `WORK_DIR/build` |
| `--prepare-only` | stop after installing the build dependencies (for debugging) |
| `--force` | overwrite packages already in the pool (don't use this for published versions) |

If a build fails, the build tree stays in `WORK_DIR/build/` and the log is at
`build.log` in there. Use `./ceph-apt shell <dist>` for a shell in the build
environment. Fixes go into [patches/](patches/README.md).

`arch: all` packages (python modules, dashboards, cephadm, …) are built on the
amd64 host only, so both architectures reference the same file.

## Multiple build hosts (amd64 + arm64)

Build on each host into its own `REPO_DIR`, then merge the pools on the host
that does the indexing and upload. File names contain the architecture and
nothing is ever overwritten, so the merge is conflict free:

```sh
# on the arm64 host
./ceph-apt build 19.2.3 bookworm
./ceph-apt build 19.2.3 trixie

# on the amd64 host (holds the signing key)
./ceph-apt build 19.2.3 bookworm
./ceph-apt build 19.2.3 trixie
rsync -a --ignore-existing --exclude dists/ arm64-host:/srv/ceph-apt/repo/ /srv/ceph-apt/repo/
./ceph-apt index
./ceph-apt sign
```

## Publishing

Upload in two passes, so the packages are online before the metadata that
references them:

```sh
rsync -av --exclude dists/ /srv/ceph-apt/repo/ user@host:htdocs/ceph/
rsync -av --delete-delay   /srv/ceph-apt/repo/ user@host:htdocs/ceph/
```

Plan storage when choosing a free host. Every point release adds about 1.2 GB
per distribution and arch, and many free static hosts cap total size at around
1 GB or single files at 25–100 MB. Ceph's largest `.deb`s are around 50 MB.

## Using the repository

Client setup (key, sources, pinning) is described in [README.md](README.md).
The pinning shown there matches on `o=ceph-apt`, so keep `REPO_ORIGIN` at its
default or update the README together with it.
