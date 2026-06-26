#!/usr/bin/env python3
"""Build a patched netplan.io package with the atomic+durable YAML write fix.

Fetches the distribution's netplan.io source (deb-src must be enabled), applies
packaging/atomic-durable-yaml-write.patch as a quilt patch, bumps the changelog
and builds binary .deb packages into the parent directory.

Build on the SAME distribution/architecture you intend to install on, so the
resulting libnetplan1 is ABI-compatible. Run from a checkout of this branch:

    ./packaging/build-deb.py            # uses sudo for apt steps

The test suite is skipped (DEB_BUILD_OPTIONS=nocheck); the fix is a localized
write-path change verified by inspection and by direct strace testing.
"""
import os
import sys
import glob
import shutil
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
PATCH = os.path.join(HERE, "atomic-durable-yaml-write.patch")
WORK = os.path.join(HERE, os.pardir, "build")
LOCAL_SUFFIX = "+atomic1"


def run(cmd, cwd=None, env=None):
    print("+ " + " ".join(cmd) + (f"   (cwd={cwd})" if cwd else ""), flush=True)
    subprocess.run(cmd, cwd=cwd, env=env, check=True)


def main():
    if not os.path.exists(PATCH):
        sys.exit(f"patch not found: {PATCH}")
    os.makedirs(WORK, exist_ok=True)

    # Build dependencies + tooling (quilt to apply the patch, devscripts for dch).
    run(["sudo", "apt-get", "build-dep", "-y", "netplan.io"])
    run(["sudo", "apt-get", "install", "-y", "quilt", "devscripts"])

    # Fetch + extract the distro source package.
    for d in glob.glob(os.path.join(WORK, "netplan.io-*")):
        if os.path.isdir(d):
            shutil.rmtree(d)
    run(["apt-get", "source", "netplan.io"], cwd=WORK)
    srcdir = sorted(glob.glob(os.path.join(WORK, "netplan.io-*")))[0]

    # Apply our patch via quilt (verifies it applies on top of the distro series).
    env = dict(os.environ, QUILT_PATCHES="debian/patches")
    run(["quilt", "import", PATCH], cwd=srcdir, env=env)
    run(["quilt", "push", "-a"], cwd=srcdir, env=env)
    run(["quilt", "refresh"], cwd=srcdir, env=env)

    # Bump the changelog with a local revision.
    env_dch = dict(os.environ, DEBEMAIL="me@mith.ro", DEBFULLNAME="Tim Ansell")
    run(["dch", "--local", LOCAL_SUFFIX,
         "src/netplan.c: write /etc/netplan/*.yaml atomically and durably "
         "(mkstemp + fsync + rename) to prevent 0-byte YAML files."],
        cwd=srcdir, env=env_dch)

    # Build binary packages (skip the heavy test suite).
    run(["dpkg-buildpackage", "-b", "-us", "-uc"],
        cwd=srcdir, env=dict(os.environ, DEB_BUILD_OPTIONS="nocheck"))

    print("\nBuilt packages:")
    for deb in sorted(glob.glob(os.path.join(WORK, "*.deb"))):
        print("  " + deb)


if __name__ == "__main__":
    main()
