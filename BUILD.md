# Building the ceph-apt repository

This document is for maintaining the repository. To install Ceph from it, see
[README.md](README.md).

The tooling in this project builds upstream [Ceph](https://ceph.io) releases as
Debian packages in a container and publishes them as signed apt repositories. There is one repository
per Ceph series, `<release>/<major.minor>` (e.g. `squid/19.2`, or
`umbrella/21.1` for pre-releases), and it keeps every point release built into
it. Users of a series only get its point releases.

- Distributions: Debian bookworm/trixie/forky, Ubuntu jammy/noble (any
  `debian:`/`ubuntu:` base image should work)
- Architectures: amd64 and arm64, each built natively on a host of that arch
- Output: a static directory tree, published to S3 (e.g. Hetzner Object
  Storage) and served from there

## How it works

```
download.ceph.com/tarballs/ceph-X.Y.Z.tar.gz
        │  ./ceph-apt build X.Y.Z <dist>      (container per dist, native arch)
        ▼
repo/<release>/<series>/pool/<dist>/main/c/ceph/*.deb   (immutable, all versions kept)
        │  ./ceph-apt index                     (container, apt-ftparchive)
        ▼
repo/<release>/<series>/dists/<dist>/{Release,main/binary-*/Packages}
        │  ./ceph-apt sign                      (host, your own gpg)
        ▼
repo/<release>/<series>/dists/<dist>/{InRelease,Release.gpg}
        │  ./ceph-apt publish                   (index + sign + upload with rclone)
        ▼
S3 bucket → https://ceph.apt.cytrinox.net/repo/<release>/<series>
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
| Debian 14 forky (testing) | `19.2.3-1~deb14u1` |
| Ubuntu 24.04 noble | `19.2.3-1~ubuntu24.04u1` |

Debian testing has no release number yet. The number it will be released as
comes from `debian_version()` in [scripts/lib/releases.sh](scripts/lib/releases.sh);
add the next codename there when it becomes testing.

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

Say what changed with `--changelog`. Each use becomes one item of the
package's changelog entry (`/usr/share/doc/<package>/changelog.Debian.gz`):

```sh
./ceph-apt build 19.2.3 bookworm --rev 2 \
    --changelog "Rebuild with the mgr Python 3.13 fix." \
    --changelog "Build rgw_common without speculative devirtualization."
./ceph-apt-cloudbuild build cpx62 19.2.3 trixie -- --rev 2 --changelog "…"
```

Without `--changelog` the entry reads "Rebuild of upstream Ceph <version> for
<dist>."

### Repository layout

```
repo/
  ceph-apt.asc                                  public signing key
  squid/19.2/
    dists/bookworm/{Release,InRelease,Release.gpg}
    dists/bookworm/main/binary-{amd64,arm64}/Packages{,.gz,.xz}
    pool/bookworm/main/c/ceph/*.deb
    buildlogs/bookworm/*.{buildinfo,changes,build.xz}
    dists/trixie/... pool/trixie/...
  tentacle/20.2/...
  umbrella/21.1/...                             pre-releases of the next release
```

The series is `major.minor` of the Ceph version and is derived from it by
`build`. `index`, `sign` and `publish` take `squid` (all its series) or
`squid/19.2` as arguments.

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

By default `./ceph-apt` reads `ceph-apt.conf` next to the script. To use
another file, e.g. one per build host, pass it before the command with
`-c`/`--config`, or set `CEPH_APT_CONF` (`-c` wins if both are given):

```sh
./ceph-apt -c ceph-apt.conf.pollux build 19.2.3 trixie
CEPH_APT_CONF=ceph-apt.conf.pollux ./ceph-apt index
```

A file given this way must exist. A missing default `ceph-apt.conf` is fine,
and the built-in defaults are used.

## Building

```sh
./ceph-apt build 19.2.3 bookworm
./ceph-apt build 19.2.3 trixie
./ceph-apt index                             # all series, or: ./ceph-apt index squid/19.2
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
| `--changelog TEXT` | text of the changelog entry, one item per use (default: "Rebuild of upstream Ceph <version> for <dist>.") |
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

## Building on Hetzner Cloud

`./ceph-apt-cloudbuild` builds on a temporary Hetzner Cloud server, so no build
host of your own is needed. It works from any machine with Python 3 and an
OpenSSH client:

1. Creates a temporary SSH key and a server of the given type (Debian 13).
2. Installs podman, git and rclone, clones the repository and runs
   `./ceph-apt image` and `./ceph-apt build` for each distribution.
3. Uploads the new packages and build logs to S3, with the same layout as
   `REPO_DIR` (`<release>/<series>/pool/…`, `<release>/<series>/buildlogs/…`).
4. Deletes the server and the key, also when the build fails or you press
   Ctrl-C.

Before creating the server it checks the Hetzner token and server type, that
the repository and `--ref` are reachable (with the local `git`, if installed),
and that it can upload to and delete from `CEPH_APT_S3_URL`. A wrong setting
therefore fails immediately, not after hours of building.

It also stops if the package version it would build already exists in
`incoming/` or in the published repository (`CEPH_APT_S3_PUBLISH_URL`, same
default as for `./ceph-apt publish`): the build server starts with an empty
pool, so the pool check of `./ceph-apt build` cannot catch that there. Build a
new revision with `-- --rev N`; `-- --force` skips the check.

The server type decides the architecture: `cax*` (Ampere) builds arm64,
`cpx*`/`ccx*` build amd64. Pick one with at least 32 GB RAM, e.g. `cax41`
or `ccx43`. The server starts without a ccache, so every build is a full
build.

```sh
export CEPH_APT_HCLOUD_TOKEN=…         # Hetzner Cloud API token (read & write)
export CEPH_APT_S3_ACCESS_KEY_ID=… CEPH_APT_S3_SECRET_ACCESS_KEY=…
export CEPH_APT_GIT_URL=https://github.com/cytrinox/ceph-apt.git   # default in the script
export CEPH_APT_S3_URL=https://nbg1.your-objectstorage.com/ceph-apt/incoming   # default in the script
export CEPH_APT_DEBFULLNAME="Your Name" CEPH_APT_DEBEMAIL=you@example.org  # optional, default: DEBFULLNAME/DEBEMAIL from ceph-apt.conf

./ceph-apt-cloudbuild build cax41 19.2.6 bookworm trixie
./ceph-apt-cloudbuild build ccx43 19.2.6 trixie --location nbg1 -- --rev 2
./ceph-apt-cloudbuild cleanup     # delete servers and keys this tool left behind
```

- Options after `--` go to `./ceph-apt build`.
- `--ref` clones a specific branch or tag. The server clones the repository,
  so local changes must be pushed first.
- `--local-patches` uses the `patches/` directory of your checkout instead of
  the cloned one, to test new patches before pushing them.
- `--keep-on-failure` keeps a failed server for inspection and prints the SSH
  command. Delete it afterwards with `cleanup`.
- `--max-hours` (default 12) is the limit after which the server is deleted
  regardless.
- The full build log is kept in `~/.cache/ceph-apt-cloudbuild/<server name>/`.
  The terminal only shows the steps and the compile progress.
- If the script itself dies (e.g. your machine loses power), the server keeps
  running and costs money. Run `cleanup` in that case.

`CEPH_APT_S3_URL` is `https://<endpoint>/<bucket>[/<prefix>]` for any
S3-compatible storage, or `s3://<bucket>[/<prefix>]` for AWS. For Hetzner
Object Storage the region is derived from the endpoint; otherwise set
`CEPH_APT_S3_REGION` if needed. Uploads use rclone's `--immutable`, so a package
that already exists with different content is not overwritten.

The cloud build only produces packages. To publish them, move them into
`REPO_DIR` on the host that holds the signing key and publish from there:

```sh
./ceph-apt fetch-incoming     # S3 incoming/ → REPO_DIR (needs rclone)
./ceph-apt publish            # index, sign, upload (see below)
```

`fetch-incoming` moves the files, so `incoming/` is empty afterwards. It
never overwrites a file in the pool: a file that exists with different content
stays in S3 and rclone reports an error. `--dry-run` shows what would be
moved. It uses the same `CEPH_APT_S3_*` variables as `ceph-apt-cloudbuild`, taken
from the environment or `ceph-apt.conf`.

## Publishing

`REPO_DIR` on the signing host is the master copy of the repository.
`publish` uploads it to `CEPH_APT_S3_PUBLISH_URL` (default
`https://nbg1.your-objectstorage.com/ceph-apt/repo`) with rclone, using the
same `CEPH_APT_S3_*` credentials as `fetch-incoming`:

```sh
./ceph-apt publish                 # all releases
./ceph-apt publish squid/19.2      # only re-index and re-sign squid 19.2
./ceph-apt publish --key=<ID>      # sign with another key
```

`publish` runs `index` and `sign`, then uploads in three passes so that
clients never see metadata that references missing files: first the packages
(and build logs and the public key), then the `Packages` indexes, then the
signed `Release`, `InRelease` and `Release.gpg`. It never deletes anything in
the bucket.

apt clients need anonymous read access to the published prefix, e.g. through
a bucket policy that allows `s3:GetObject` on `ceph-apt/repo/*`. With the
default settings the repository is then reachable at
`https://ceph-apt.nbg1.your-objectstorage.com/repo/<release>/<series>`. Clients use
`https://ceph.apt.cytrinox.net/repo/<release>/<series>`, a proxy for the bucket that
redirects each request to a short-lived signed S3 URL, so the URL in
README.md stays stable even if the storage moves. `incoming/` holds unsigned
packages and does not need to be public.

Storage grows with every point release: about 1.2 GB per distribution and
arch, without debug packages.

## Using the repository

Client setup (key, sources, pinning) is described in [README.md](README.md).
The pinning shown there matches on `o=ceph-apt`, so keep `REPO_ORIGIN` at its
default or update the README together with it.
