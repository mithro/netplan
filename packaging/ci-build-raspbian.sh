#!/bin/bash
# Build the patched netplan.io for Raspberry Pi OS / Raspbian trixie inside a
# Raspbian/RPi-OS rootfs bootstrapped with mmdebstrap. Kept SEPARATE from the
# Debian builds (distinct rootfs, distinct artifact). RPI_ARCH selects the
# variant:
#   armhf -> 32-bit Raspbian, ARMv6 hard-float (Pi 1/Zero); base archive =
#            raspbian.raspberrypi.com (Debian armhf is ARMv7 and won't run there)
#   arm64 -> 64-bit Raspberry Pi OS; base = Debian arm64 + the RPi OS overlay
# Both layer the archive.raspberrypi.com (RPi OS) overlay. Runs with sudo -E;
# writes the resulting .deb files to ./built-debs.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
: "${RPI_ARCH:?set RPI_ARCH=armhf|arm64}"
SRC="$(pwd)"
ROOT=/tmp/rpi-rootfs
KEYRING=/usr/share/keyrings/rpi-bootstrap.gpg
OVERLAY_URL=http://archive.raspberrypi.com/debian
OVERLAY_COMP=main

apt-get update
apt-get install -y --no-install-recommends \
  mmdebstrap qemu-user-static binfmt-support ca-certificates curl gnupg arch-test \
  debian-archive-keyring

tmpk="$(mktemp -d)"
curl -fsSL "$OVERLAY_URL/raspberrypi.gpg.key" | gpg --dearmor > "$tmpk/rpi.gpg"
case "$RPI_ARCH" in
  armhf)
    BASE_URL=http://raspbian.raspberrypi.com/raspbian
    BASE_COMP="main contrib non-free rpi firmware"
    curl -fsSL http://raspbian.raspberrypi.com/raspbian.public.key | gpg --dearmor > "$tmpk/base.gpg"
    ;;
  arm64)
    BASE_URL=http://deb.debian.org/debian
    BASE_COMP="main"
    cp /usr/share/keyrings/debian-archive-keyring.gpg "$tmpk/base.gpg"
    ;;
  *) echo "unknown RPI_ARCH=$RPI_ARCH" >&2; exit 1 ;;
esac
cat "$tmpk/base.gpg" "$tmpk/rpi.gpg" > "$KEYRING"

mmdebstrap \
  --architectures="$RPI_ARCH" \
  --variant=apt \
  --include='ca-certificates,build-essential,dpkg-dev,devscripts,quilt,git,fakeroot' \
  --aptopt='Apt::Install-Recommends "false"' \
  --keyring="$KEYRING" \
  trixie "$ROOT" \
  "deb $BASE_URL trixie $BASE_COMP" \
  "deb $OVERLAY_URL trixie $OVERLAY_COMP"

# Rootfs apt sources: base (with deb-src for the source package) + RPi overlay,
# verified by the combined keyring (copied into the rootfs).
install -D "$KEYRING" "$ROOT$KEYRING"
rm -f "$ROOT"/etc/apt/sources.list.d/*.list "$ROOT"/etc/apt/sources.list.d/*.sources || true
cat > "$ROOT/etc/apt/sources.list" <<EOF
deb [signed-by=$KEYRING] $BASE_URL trixie $BASE_COMP
deb-src [signed-by=$KEYRING] $BASE_URL trixie $BASE_COMP
deb [signed-by=$KEYRING] $OVERLAY_URL trixie $OVERLAY_COMP
EOF

cp /etc/resolv.conf "$ROOT/etc/resolv.conf"
install -d "$ROOT/build"
cp packaging/atomic-durable-yaml-write.patch "$ROOT/build/"
cp packaging/ci-build-raspbian-inner.sh "$ROOT/build/"

# Bind the kernel filesystems for apt / dpkg-buildpackage inside the chroot.
for m in proc sys dev dev/pts; do mount --bind "/$m" "$ROOT/$m"; done
trap 'for m in dev/pts dev sys proc; do umount -l "$ROOT/$m" || true; done' EXIT

chroot "$ROOT" env GITHUB_RUN_NUMBER="${GITHUB_RUN_NUMBER:-0}" RPI_ARCH="$RPI_ARCH" \
  bash /build/ci-build-raspbian-inner.sh

mkdir -p "$SRC/built-debs"
cp "$ROOT"/build/out/*.deb "$SRC/built-debs/"
chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$SRC/built-debs"
ls -l "$SRC/built-debs/"
