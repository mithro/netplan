# Building a patched `netplan.io` package

This branch fixes a crash-safety bug in libnetplan's YAML writer.

## The bug

NetworkManager's netplan integration rewrites `/etc/netplan/90-NM-<uuid>.yaml`
on **every** connection activation (to persist `connection.timestamp`, and for
Wi-Fi `seen-bssids`) — even when the content is unchanged. libnetplan did this
with an in-place `fopen()` / `open(O_WRONLY|O_CREAT|O_TRUNC)` followed by a
separate `write()`, with **no temporary file and no `fsync`**.

`O_TRUNC` zeroes the file before the data is written, and without `fsync` the
new bytes can sit in the page cache for many seconds on slow storage (e.g. SD
cards). If the machine loses power, reboots, or the process is killed in that
window, the YAML is left at **0 bytes**, which breaks networking on the next
boot. This was observed repeatedly on a Raspberry Pi fleet whose YAML files are
rewritten on every boot by NetworkManager's timestamp write-back.

## The fix

`src/netplan.c`: `netplan_netdef_write_yaml()`,
`netplan_state_update_yaml_hierarchy()` and `netplan_state_write_yaml_file()`
now write via the **`mkstemp` + `fsync` + atomic `rename`** idiom (plus a
best-effort directory `fsync`), mirroring the temp+rename pattern that
`netplan_state_write_yaml_file()` already used and that libnetplan already uses
for the NetworkManager keyfiles. Only the YAML emitter path was unsafe.

The change is in the commit *"netplan: write /etc/netplan/\*.yaml atomically and
durably"* and is also captured as a DEP-3 quilt patch in
[`atomic-durable-yaml-write.patch`](atomic-durable-yaml-write.patch) for distros
that build from the released `netplan.io` source package.

## Quick build (Debian / Ubuntu / Raspberry Pi OS)

Requires `deb-src` enabled for your distribution. From a checkout of this branch:

```sh
./packaging/build-deb.py
```

This fetches the distro's `netplan.io` source, applies the patch, bumps the
changelog and builds binary packages into the parent directory. Install the
**matched set** (the companion packages pin the exact `libnetplan1` version):

```sh
sudo apt-get install ./libnetplan1_*.deb ./netplan.io_*.deb \
    ./netplan-generator_*.deb ./python3-netplan_*.deb
```

## Manual build

```sh
sudo apt-get build-dep netplan.io
sudo apt-get install quilt devscripts
apt-get source netplan.io
cd netplan.io-*/
cp ../packaging/atomic-durable-yaml-write.patch debian/patches/
echo atomic-durable-yaml-write.patch >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push -a          # verify it applies
dch --local +atomic 'Atomic+durable /etc/netplan/*.yaml write (no 0-byte files)'
DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -us -uc
```

## Upstream

This fix is intended for upstream `netplan` as well; once it lands and reaches
your distribution, the local rebuild can be dropped.
