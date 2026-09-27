# Build environment for Ceph .deb packages.
#
# One image per distribution release, built natively on each architecture:
#   podman build --build-arg BASE=debian:trixie -t localhost/ceph-apt-builder:trixie .
#
# Only the generic toolchain lives in the image; the Ceph build dependencies
# are version specific and get installed by `ceph-deb build` at run time.
ARG BASE=debian:bookworm
FROM docker.io/library/${BASE}

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        apt-utils \
        build-essential \
        ca-certificates \
        ccache \
        curl \
        devscripts \
        equivs \
        fakeroot \
        gnupg \
        libdistro-info-perl \
        patch \
        xz-utils \
 && rm -rf /var/lib/apt/lists/*

COPY scripts/ceph-deb /usr/local/bin/ceph-deb
COPY scripts/lib/ /usr/local/lib/ceph-deb/
COPY patches/ /usr/local/share/ceph-deb/patches/

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/ceph-deb"]
CMD ["help"]
