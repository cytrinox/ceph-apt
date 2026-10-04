# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-only
# Helpers shared by ceph-deb: Ceph release names and distro version tags.

# ceph_release_name <version>  ->  squid, tentacle, ...
ceph_release_name() {
    case "${1%%.*}" in
        16) echo pacific ;;
        17) echo quincy ;;
        18) echo reef ;;
        19) echo squid ;;
        20) echo tentacle ;;
        21) echo umbrella ;;
        *) return 1 ;;
    esac
}

# debian_version <codename>  ->  12, 13, 14, ...
# Debian testing has no VERSION_ID in os-release, so the number it will get
# on release comes from here.
debian_version() {
    case "$1" in
        bullseye) echo 11 ;;
        bookworm) echo 12 ;;
        trixie) echo 13 ;;
        forky) echo 14 ;;
        duke) echo 15 ;;
        *) return 1 ;;
    esac
}

# distro_tag  ->  deb12, deb13, ubuntu24.04, ...
# Numeric so that versions sort correctly across distribution upgrades
# (codenames do not: "forky" < "trixie").
distro_tag() {
    local ID VERSION_ID VERSION_CODENAME
    # shellcheck disable=SC1091
    . /etc/os-release
    if [ "$ID" = debian ]; then
        # Testing has no VERSION_ID yet; use the number it will be released as.
        [ -n "${VERSION_ID:-}" ] || VERSION_ID=$(debian_version "$VERSION_CODENAME") || return 1
        echo "deb${VERSION_ID}"
    else
        [ -n "${VERSION_ID:-}" ] || return 1
        echo "${ID}${VERSION_ID}"
    fi
}

# codename_tag <codename>  ->  deb12, ubuntu24.04, ...
# The same tag distro_tag computes inside a container of that distribution,
# for use outside of it (e.g. ceph-apt-cloudbuild).
codename_tag() {
    case "$1" in
        jammy) echo ubuntu22.04 ;;
        noble) echo ubuntu24.04 ;;
        resolute) echo ubuntu26.04 ;;
        *) local v; v=$(debian_version "$1") || return 1; echo "deb$v" ;;
    esac
}

# distro_codename  ->  bookworm, trixie, noble, ...
distro_codename() {
    local VERSION_CODENAME
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "$VERSION_CODENAME"
}
