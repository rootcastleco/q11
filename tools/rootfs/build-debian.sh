#!/usr/bin/env bash
# Build on native Linux/WSL Linux filesystem. Never partitions/formats a device.
set -euo pipefail
usage() { echo 'Usage: build-debian.sh --output DIR --ssh-key FILE [--dry-run]'; }
fail() { echo "ERROR: $*" >&2; exit 2; }
target='' key='' dry=0
while (($#)); do
    case "$1" in
        --output|--ssh-key) (($# >= 2)) || fail "missing value for $1"; case "$1" in --output) target=$2 ;; --ssh-key) key=$2 ;; esac; shift 2 ;;
        --dry-run) dry=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) fail "unknown argument: $1" ;;
    esac
done
[[ -n "$target" && -n "$key" ]] || { usage; fail 'output and SSH public key required'; }
[[ -f "$key" ]] || fail "missing key file: $key"
[[ $(wc -c <"$key") -le 16384 ]] || fail 'key file exceeds 16 KiB'
[[ $(grep -c . "$key") == 1 ]] || fail 'provide exactly one public key'
grep -Eq '^(ssh-|ecdsa-|sk-)[^ ]+ [A-Za-z0-9+/]+=*([[:space:]].*)?$' "$key" || fail 'public key text required; private keys are rejected'
ssh-keygen -lf "$key" >/dev/null || fail 'invalid SSH public key'
target=$(realpath -m -- "$target")
[[ "$target" != / && "$target" != /home && "$target" != /root && "$target" != /usr && "$target" != /var && "$target" != /tmp ]] || fail 'unsafe target'
[[ "$target" != /mnt/* ]] || fail 'rootfs must live on a Linux filesystem, not a Windows mount'
[[ ! -e "$target" ]] || fail "output already exists: $target"
printf 'Debian bookworm armhf, SysV init, output=%s, root SSH disabled, serial root autologin\n' "$target"
((dry == 0)) || exit 0
[[ $EUID == 0 ]] || fail 'run as root on Linux/WSL'
for command in debootstrap qemu-arm-static chroot timeout git; do command -v "$command" >/dev/null || fail "missing dependency: $command"; done
keyring=/usr/share/keyrings/debian-archive-keyring.gpg
[[ -f "$keyring" ]] || fail 'install debian-archive-keyring'
if [[ $(uname -m) != armv7l ]]; then
    if [[ ! -f /proc/sys/fs/binfmt_misc/qemu-arm ]] || ! grep -q enabled /proc/sys/fs/binfmt_misc/qemu-arm; then
        fail 'enable the qemu-arm binfmt handler on the host first'
    fi
fi
mkdir -p -- "$target"
echo Q11_DEBIAN_ARMHF_LAB_V1 >"$target/.q11-lab-build"
log="$target.build.log"
exec > >(tee -a "$log") 2>&1
finish() { local code=$?; printf 'result_exit_code=%s timestamp=%s\n' "$code" "$(date -u +%FT%TZ)"; }
trap finish EXIT
repo=$(realpath -- "$(dirname "$0")/../..")
commit=$(git -c safe.directory="$repo" -C "$repo" rev-parse HEAD) || fail 'cannot determine git commit'
printf 'operation=build-debian tool_version=1.0 timestamp=%s git_commit=%s port=N/A baud=N/A\n' "$(date -u +%FT%TZ)" "$commit"
packages=sysvinit-core,sysv-rc,initscripts,udev,ifupdown,isc-dhcp-client,openssh-server,iproute2,iputils-ping,ca-certificates,e2fsprogs,kmod,busybox-static,procps
timeout 1200 debootstrap --arch=armhf --foreign --variant=minbase --keyring="$keyring" --include="$packages" bookworm "$target" https://deb.debian.org/debian
install -m 0755 "$(command -v qemu-arm-static)" "$target/usr/bin/qemu-arm-static"
printf '#!/bin/sh\nexit 101\n' >"$target/usr/sbin/policy-rc.d"
chmod 0755 "$target/usr/sbin/policy-rc.d"
run_target() { timeout 600 chroot "$target" /usr/bin/qemu-arm-static "$@"; }
run_target /bin/sh /debootstrap/debootstrap --second-stage
bash "$(dirname "$0")/configure-rootfs.sh" "$target" "$key"
