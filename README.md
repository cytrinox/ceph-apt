# ceph-apt: Ceph packages for Debian

Apt repositories with [Ceph](https://ceph.io) packages for Debian, built from
the upstream Ceph release tarballs:

**https://ceph-apt.cytrinox.net/**

This is not an official Ceph project, and it is not affiliated with the Ceph
Foundation or the upstream Ceph packaging.

## What's available

There is one repository per Ceph release. Each repository keeps every point
release, so you can stay on a point release or go back to one.

| Ceph release | Repository URL | Debian 12 (bookworm) | Debian 13 (trixie) |
|---|---|---|---|
| Squid (19.2.x) | `https://ceph-apt.cytrinox.net/squid` | ✓ | ✓ |
| Tentacle (20.2.x) | `https://ceph-apt.cytrinox.net/tentacle` | ✓ | ✓ |

Architectures: `amd64` and `arm64`. Debug (`-dbg`) packages are not provided.

## Setup

The examples use Squid. For Tentacle, replace `squid` with `tentacle`.

### 1. Install the signing key

```sh
sudo apt install curl ca-certificates
sudo curl -fsSL https://ceph-apt.cytrinox.net/ceph-apt.asc -o /usr/share/keyrings/ceph-apt.asc
gpg --show-keys /usr/share/keyrings/ceph-apt.asc
```

Check that the fingerprint matches:

```
TODO: fingerprint of the repository signing key
```

### 2. Add the repository

This picks up your Debian release automatically:

```sh
sudo tee /etc/apt/sources.list.d/ceph-apt.sources <<EOF
Types: deb
URIs: https://ceph-apt.cytrinox.net/squid
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: main
Signed-By: /usr/share/keyrings/ceph-apt.asc
EOF
```

Or, in the classic one-line `sources.list` format:

```sh
echo "deb [signed-by=/usr/share/keyrings/ceph-apt.asc] https://ceph-apt.cytrinox.net/squid $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
    | sudo tee /etc/apt/sources.list.d/ceph-apt.list
```

Use only one of the two files.

Remove any other Ceph repositories (e.g. `download.ceph.com`) so packages from
different sources don't get mixed.

### 3. Prefer this repository over Debian's own Ceph packages

Debian ships its own, older `ceph` packages, and backports may carry others.
Mixing them with these packages breaks dependencies, so give this repository
priority:

```sh
sudo tee /etc/apt/preferences.d/ceph-apt.pref <<EOF
Package: *
Pin: release o=ceph-apt
Pin-Priority: 1001
EOF
```

### 4. Install

```sh
sudo apt update
apt policy ceph-common           # candidate should be …~deb12u1 / …~deb13u1
sudo apt install ceph-common     # client tools
sudo apt install ceph            # mon, mgr, osd
```

## Versions

Package versions look like this:

```
19.2.3-1~deb12u1
│      │ │    └─ rebuild number (bumped when a version is rebuilt)
│      │ └────── Debian release: deb12 = bookworm, deb13 = trixie
│      └──────── upstream packaging revision
└─────────────── Ceph version
```

List all point releases that are available:

```sh
apt list -a ceph-common
```

### Staying on a point release

To stay on a specific point release instead of the newest one, add a version
pin. It has a higher priority than the repository pin from step 3:

```sh
sudo tee /etc/apt/preferences.d/ceph-apt-version.pref <<'EOF'
Package: /^(ceph|libcephfs|librados|librbd|librgw|libsqlite3-mod-ceph|python3-(ceph|rados|rbd|rgw)|rados|rbd-)/
Pin: version 19.2.2-1~*
Pin-Priority: 1002
EOF
sudo apt update
apt policy ceph-common           # candidate is now 19.2.2-1~…
```

The `Package:` pattern covers all Ceph packages. apt doesn't allow
`Package: *` together with a version pin. Packages from other sources are not
affected, because they don't have a `19.2.2-1~…` version.

If the pinned version is older than what's installed, `apt upgrade` offers a
downgrade (and refuses under `-y` without `--allow-downgrades`). Ceph doesn't
support downgrading a running cluster, so only pin a version that is the same
as or newer than the installed one. Delete the file to follow the newest point
release again.

## Upgrading

### To the next Ceph release (e.g. Squid → Tentacle)

1. Read the [Ceph release notes](https://docs.ceph.com/en/latest/releases/)
   for the supported upgrade paths and the required order (usually mons, then
   mgrs, OSDs, MDS, RGW).
2. Change the URL in `/etc/apt/sources.list.d/ceph-apt.sources` (or
   `ceph-apt.list`) from `…/squid` to `…/tentacle`.
3. `sudo apt update && sudo apt full-upgrade` on each node, in the order the
   release notes describe, and restart the daemons.

### To the next Debian release (bookworm → trixie)

Change the suite in `/etc/apt/sources.list.d/ceph-apt.sources` (`Suites:`) or
`ceph-apt.list` (the word after the URL) from `bookworm` to `trixie`, together
with the rest of your Debian sources. The trixie packages (`…~deb13u1`) have
higher version numbers than the bookworm ones (`…~deb12u1`), so they are
upgraded as part of the distribution upgrade.

## How the packages are built

The packages are built from the unmodified upstream Ceph release tarballs,
using the `debian/` packaging that ships with them. Changes are limited to
build fixes, which are kept in [patches/](patches/). Building and publishing
are described in [BUILD.md](BUILD.md).
