# shellcheck shell=bash
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

# distro_tag  ->  deb12, deb13, ubuntu24.04, ...
# Numeric so that versions sort correctly across distribution upgrades
# (codenames do not: "forky" < "trixie").
distro_tag() {
    local ID VERSION_ID VERSION_CODENAME
    # shellcheck disable=SC1091
    . /etc/os-release
    if [ -z "${VERSION_ID:-}" ]; then
        # testing/unstable have no VERSION_ID
        echo "${ID}${VERSION_CODENAME}"
        return
    fi
    case "$ID" in
        debian) echo "deb${VERSION_ID}" ;;
        *) echo "${ID}${VERSION_ID}" ;;
    esac
}

# distro_codename  ->  bookworm, trixie, noble, ...
distro_codename() {
    local VERSION_CODENAME
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "$VERSION_CODENAME"
}
