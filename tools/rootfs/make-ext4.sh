#!/usr/bin/env bash
# Populate a NEW regular-file filesystem; no loop mount, block-device access or partition writes.
set -euo pipefail
fail() { echo "ERROR: $*" >&2; exit 2; }
usage() { echo 'Usage: make-ext4.sh ROOTFS OUTPUT.img [SIZE_MiB=1024] [--dry-run]'; }
[[ ${1:-} != --help && ${1:-} != -h ]] || { usage; exit 0; }
(($# >= 2 && $# <= 4)) || { usage; fail 'invalid arguments'; }
root=$(realpath -e -- "$1")
output=$(realpath -m -- "$2")
size=${3:-1024}
dry=${4:-}
[[ "$size" =~ ^[0-9]+$ && "$size" -ge 256 && "$size" -le 8192 ]] || fail 'size must be 256..8192 MiB'
[[ -z "$dry" || "$dry" == --dry-run ]] || fail 'unknown option'
[[ -d "$root/etc" && -x "$root/sbin/init" ]] || fail 'missing rootfs/etc or executable sbin/init'
[[ ! -e "$output" && ! -L "$output" && "$output" != /dev/* ]] || fail 'output must be a NEW regular file outside /dev'
[[ "$output" != "$root"/* ]] || fail 'image must be outside rootfs'
printf 'Create %s MiB ext4 image: %s, label=Q11ROOT, source=%s\n' "$size" "$output" "$root"
[[ "$dry" != --dry-run ]] || exit 0
for command in python3 mkfs.ext4 e2fsck sha256sum timeout; do command -v "$command" >/dev/null || fail "missing $command"; done
mkdir -p -- "$(dirname "$output")"
exec > >(tee "$output.build.log") 2>&1
finish() { local code=$?; printf 'result_exit_code=%s timestamp=%s\n' "$code" "$(date -u +%FT%TZ)"; }
trap finish EXIT
repo=$(realpath -- "$(dirname "$0")/../..")
commit=$(git -c safe.directory="$repo" -C "$repo" rev-parse HEAD) || fail 'cannot determine git commit'
printf 'operation=make-ext4 tool_version=1.0 timestamp=%s git_commit=%s port=N/A baud=N/A\n' "$(date -u +%FT%TZ)" "$commit"
# Exclusive creation prevents a pre-existing device/symlink from being followed.
python3 - "$output" "$size" <<'PY'
import os, sys
fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'wb') as stream:
    stream.truncate(int(sys.argv[2]) * 1024 * 1024)
PY
# Compatibility with Linux 3.18; current e2fsprogs enables unsupported features by default.
timeout 600 mkfs.ext4 -F -L Q11ROOT -O '^64bit,^metadata_csum,^metadata_csum_seed,^orphan_file' -d "$root" "$output"
timeout 120 e2fsck -fn "$output"
sha256sum "$output" >"$output.sha256"
echo 'Host filesystem validated; ext4 driver availability on Q11 is UNKNOWN.'
