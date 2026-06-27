#!/bin/sh
# Runs INSIDE the Raspbian/RPi-OS rootfs prepared by ci-build-raspbian.sh (apt
# sources + keyring already set up there). Fetches the netplan.io source from the
# Raspbian/RPi archive, applies the atomic-write patch, and builds binary .deb
# files into /build/out. RPI_ARCH + GITHUB_RUN_NUMBER come in via the chroot env.
set -eux
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get build-dep -y netplan.io

cd /build
apt-get source netplan.io
src="$(ls -d netplan.io-*/)"
cd "$src"

cp /build/atomic-durable-yaml-write.patch debian/patches/
echo atomic-durable-yaml-write.patch >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push -a

base="$(dpkg-parsechangelog -S Version)"
newver="${base}+welland${GITHUB_RUN_NUMBER}"
DEBEMAIL="me@mith.ro" DEBFULLNAME="Tim Ansell" \
  dch -b -v "$newver" -D trixie \
  "Atomic+durable /etc/netplan/*.yaml write (mkstemp+fsync+rename); CI build (Raspbian ${RPI_ARCH})."

DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -us -uc

mkdir -p /build/out
cp ../*.deb /build/out/
ls -l /build/out/
