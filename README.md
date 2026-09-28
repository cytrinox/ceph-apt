# ceph-apt: Ceph packages for Debian

> [!WARNING]
> **This project and its repositories are experimental. Do not use them for
> production systems or any data you care about.**
>
> Packages, URLs, the signing key, version numbering and the repository layout
> may change or disappear at any time, without notice. Packages may be
> removed or rebuilt, and there are no updates or security fixes you can rely
> on.

Apt repositories with [Ceph](https://ceph.io) packages for Debian, built from
the upstream Ceph release tarballs. Base URL of the repositories:

**https://ceph.apt.cytrinox.net/repo/**

This is not an official Ceph project, and it is not affiliated with the Ceph
Foundation or the upstream Ceph packaging.

## What's available

There is one repository per Ceph series (`major.minor`), e.g.
`repo/squid/19.2`. A repository only contains the point releases of its
series: with the Squid 19.2 repository you get 19.2.x updates, but never
20.2. Pre-releases of a future Ceph release (e.g. 21.1.x) get a repository of
their own. Each repository keeps every point release, so you can stay on a
point release or go back to one.

| Ceph series | Repository URL | Debian 12 (bookworm) | Debian 13 (trixie) | Debian 14 (forky) |
|---|---|---|---|---|
| Tentacle 20.2 | `https://ceph.apt.cytrinox.net/repo/tentacle/20.2` | ✓ | ✓ | – |
| Squid 19.2 | `https://ceph.apt.cytrinox.net/repo/squid/19.2` | ✓ | ✓ | ✓ |
| Reef 18.2 | `https://ceph.apt.cytrinox.net/repo/reef/18.2` | ✓ | ✓ | ✓ |

Debian 14 (forky) is Debian's current testing release. Only `amd64` packages
are published; `arm64` is not available yet. Debug (`-dbg`) packages are not
provided.

## Setup

The examples use Tentacle 20.2. For another series, replace `tentacle/20.2`
with its path from the table.

### 1. Install the signing key

```sh
sudo apt install curl ca-certificates gpg
sudo curl -fsSL https://ceph.apt.cytrinox.net/repo/ceph-apt.asc -o /usr/share/keyrings/ceph-apt.asc
gpg --show-keys /usr/share/keyrings/ceph-apt.asc
```

Check that the fingerprint of the key matches:

```
F844 037D BE0E 9385 6475  B95A 9FDA 52CB 9EDE 279E
```

### 2. Add the repository

This picks up your Debian release automatically:

```sh
sudo tee /etc/apt/sources.list.d/ceph-apt.sources <<EOF
Types: deb
URIs: https://ceph.apt.cytrinox.net/repo/tentacle/20.2
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: main
Signed-By: /usr/share/keyrings/ceph-apt.asc
EOF
```

Or, in the classic one-line `sources.list` format:

```sh
echo "deb [signed-by=/usr/share/keyrings/ceph-apt.asc] https://ceph.apt.cytrinox.net/repo/tentacle/20.2 $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
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
   `ceph-apt.list`) from `…/squid/19.2` to `…/tentacle/20.2`.
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
