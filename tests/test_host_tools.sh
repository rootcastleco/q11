#!/usr/bin/env bash
# Real regular-file filesystem tests, no physical devices, no network required.
set -euo pipefail
repo=$(realpath -- "$(dirname "$0")/..")
sandbox=$(mktemp -d /tmp/q11-host-tests.XXXXXX)
[[ "$sandbox" == /tmp/q11-host-tests.* ]] || exit 2
trap 'rm -rf -- "$sandbox"' EXIT
expect_error() {
    if "$@" >"$sandbox/expected-error.log" 2>&1; then
        echo "ERROR: unexpectedly succeeded: $*" >&2; exit 1
    fi
}
ssh-keygen -q -t ed25519 -N '' -f "$sandbox/key"
bash "$repo/tools/rootfs/build-debian.sh" --output "$sandbox/debian" --ssh-key "$sandbox/key.pub" --dry-run
expect_error bash "$repo/tools/rootfs/build-debian.sh" --output / --ssh-key "$sandbox/key.pub" --dry-run
expect_error bash "$repo/tools/rootfs/build-debian.sh" --output "$sandbox/debian" --ssh-key "$sandbox/missing" --dry-run
expect_error bash "$repo/tools/rootfs/build-debian.sh" --bogus
expect_error bash "$repo/tools/rootfs/build-debian.sh" --output "$sandbox/debian" --ssh-key "$sandbox/key" --dry-run
mkdir -p "$sandbox/root/etc" "$sandbox/root/sbin"
echo Q11_DEBIAN_ARMHF_LAB_V1 >"$sandbox/root/.q11-lab-build"
echo 12.0 >"$sandbox/root/etc/debian_version"
bash "$repo/tools/rootfs/configure-rootfs.sh" "$sandbox/root" "$sandbox/key.pub" --dry-run
expect_error bash "$repo/tools/rootfs/configure-rootfs.sh" "$sandbox/missing" "$sandbox/key.pub" --dry-run
expect_error bash "$repo/tools/rootfs/configure-rootfs.sh" "$sandbox/root" "$sandbox/missing" --dry-run
expect_error bash "$repo/tools/rootfs/configure-rootfs.sh" "$sandbox/root" "$sandbox/key.pub" --bogus
expect_error bash "$repo/tools/rootfs/configure-rootfs.sh" "$sandbox/root" "$sandbox/key" --dry-run
printf '#!/bin/sh\nexit 0\n' >"$sandbox/root/sbin/init"
chmod 0755 "$sandbox/root/sbin/init"
bash "$repo/tools/rootfs/make-ext4.sh" "$sandbox/root" "$sandbox/root.ext4" 256
expect_error bash "$repo/tools/rootfs/make-ext4.sh" "$sandbox/root" "$sandbox/root.ext4" 256
expect_error bash "$repo/tools/rootfs/make-ext4.sh" "$sandbox/root" "$sandbox/other.ext4" 1
expect_error bash "$repo/tools/rootfs/make-ext4.sh" "$sandbox/missing" "$sandbox/other.ext4" 256
python3 "$repo/tools/rootfs/make_disk_image.py" "$sandbox/root.ext4" "$sandbox/disk.img"
test "$(stat -c %s "$sandbox/disk.img")" -eq 269484032
arm-linux-gnueabihf-gcc -static -Os -Wall -Wextra -Werror -o "$sandbox/probe" "$repo/tools/rootfs/root_probe.c"
qemu-arm-static "$sandbox/probe" --image "$sandbox/root.ext4" | grep -q 'LABEL="Q11ROOT"'
expect_error qemu-arm-static "$sandbox/probe" --image "$sandbox/missing"
expect_error qemu-arm-static "$sandbox/probe" --image "$sandbox/key.pub"
expect_error qemu-arm-static "$sandbox/probe" /dev/mtdblock0
expect_error qemu-arm-static "$sandbox/probe" --bogus unused
mkdir -p "$sandbox/source/arch/arm/configs"
touch "$sandbox/source/Makefile" "$sandbox/source/arch/arm/configs/hi3798mv100_defconfig"
bash "$repo/tools/kernel/build.sh" "$sandbox/source" "$sandbox/kernel-out" arm-none-eabi- --dry-run
expect_error bash "$repo/tools/kernel/build.sh" "$sandbox/source" "$sandbox/kernel-out" 'bad;prefix' --dry-run
expect_error bash "$repo/tools/kernel/build.sh" "$sandbox/missing" "$sandbox/kernel-out" arm-none-eabi- --dry-run
expect_error bash "$repo/tools/kernel/build.sh" "$sandbox/source" "$sandbox/kernel-out" no-such-compiler-
echo 'PASS: shell tools, root probe, real ext4 and MBR image success/invalid/missing checks'
