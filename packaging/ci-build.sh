#!/bin/sh
# Build the patched netplan.io inside a debian:trixie container of the target
# architecture. Invoked by .github/workflows/deb.yml as:
#
#   docker run --rm --platform=linux/<arch> -e GITHUB_RUN_NUMBER \
#       -v "$PWD:/src" -w /src debian:trixie bash packaging/ci-build.sh
#
# It builds natively for the container's architecture (emulated via QEMU for
# non-host arches) and writes the resulting binary .deb files to /src/built-debs,
# which is a bind mount back to the runner workspace.
set -eux

export DEBIAN_FRONTEND=noninteractive

# Enable deb-src on the container's existing Debian source so it inherits that
# source's signing keyring (avoids a Signed-By conflict from a second file).
sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources
apt-get update
apt-get install -y --no-install-recommends ca-certificates quilt devscripts dpkg-dev
apt-get build-dep -y netplan.io

work="$(mktemp -d)"
cd "$work"
apt-get source netplan.io
src="$(ls -d netplan.io-*/)"
cd "$src"

# Apply the atomic+durable YAML-write fix on top of the distro patch series.
cp /src/packaging/atomic-durable-yaml-write.patch debian/patches/
echo atomic-durable-yaml-write.patch >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push -a

# Version: <distro version>+welland<run number>. Same across arches (one source
# version, per-arch binaries); monotonic and > the distro's own +rpt1/-N.
base="$(dpkg-parsechangelog -S Version)"
newver="${base}+welland${GITHUB_RUN_NUMBER}"
DEBEMAIL="me@mith.ro" DEBFULLNAME="Tim Ansell" \
  dch -b -v "$newver" -D trixie \
  "Atomic+durable /etc/netplan/*.yaml write (mkstemp+fsync+rename); prevents 0-byte files. CI build."

DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -us -uc

mkdir -p /src/built-debs
cp ../*.deb /src/built-debs/
ls -l /src/built-debs/
