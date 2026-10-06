#!/usr/bin/env bash
set -euo pipefail
fail() { echo "ERROR: $*" >&2; exit 2; }
usage() { echo 'Usage: build.sh SOURCE OUT CROSS_COMPILE_PREFIX [--dry-run]'; }
[[ ${1:-} != --help && ${1:-} != -h ]] || { usage; exit 0; }
(($# >= 3 && $# <= 4)) || { usage; fail 'invalid arguments'; }
source_tree=$(realpath -e -- "$1")
out=$(realpath -m -- "$2")
cross=$3
dry=${4:-}
[[ -z "$dry" || "$dry" == --dry-run ]] || fail 'unknown option'
[[ -f "$source_tree/arch/arm/configs/hi3798mv100_defconfig" && -f "$source_tree/Makefile" ]] || fail 'missing Hi3798MV100 kernel source/defconfig'
[[ ! -e "$out" && "$out" != "$source_tree"/* && "$out" != /dev/* ]] || fail 'OUT must be new and outside SOURCE and /dev'
[[ "$cross" =~ ^[a-zA-Z0-9_./+-]+-$ ]] || fail 'invalid toolchain prefix'
echo "Build candidate hi3798mv100_defconfig + bringup.config; source=$source_tree out=$out cross=$cross"
[[ "$dry" != --dry-run ]] || exit 0
command -v "${cross}gcc" >/dev/null || fail "missing ${cross}gcc"
command -v timeout >/dev/null || fail 'missing timeout'
fragment=$(realpath -- "$(dirname "$0")/bringup.config")
mkdir -p "$out"
exec > >(tee "$out/build.log") 2>&1
finish() { local code=$?; printf 'result_exit_code=%s timestamp=%s\n' "$code" "$(date -u +%FT%TZ)"; }
trap finish EXIT
printf 'operation=kernel-build tool_version=1.0 timestamp=%s source_commit=%s compiler=%s port=N/A baud=N/A\n' "$(date -u +%FT%TZ)" "$(git -C "$source_tree" rev-parse HEAD)" "$("${cross}gcc" -dumpversion)"
make_args=(-C "$source_tree" O="$out" ARCH=arm CROSS_COMPILE="$cross")
timeout 120 make "${make_args[@]}" hi3798mv100_defconfig
# merge_config operates within the source tree but writes only to OUT.
(cd "$source_tree"; ARCH=arm CROSS_COMPILE="$cross" KCONFIG_CONFIG="$out/.config" timeout 120 bash scripts/kconfig/merge_config.sh -m -O "$out" "$out/.config" "$fragment")
timeout 120 make "${make_args[@]}" olddefconfig
while IFS= read -r setting; do grep -qxF "$setting" "$out/.config" || fail "required setting was dropped: $setting"; done <"$fragment"
jobs=${Q11_JOBS:-4}
[[ "$jobs" =~ ^[1-9][0-9]?$ && "$jobs" -le 32 ]] || fail 'Q11_JOBS must be 1..32'
timeout 1800 make "${make_args[@]}" -j"$jobs" zImage zImage-dtb dtbs modules
timeout 300 make "${make_args[@]}" INSTALL_MOD_PATH="$out/staging" modules_install
find "$out/arch/arm/boot" -type f \( -name zImage -o -name zImage-dtb -o -name '*.dtb' \) -exec sha256sum {} + >"$out/SHA256SUMS"
echo 'Candidate artifacts built; Q11 DTB, PHY, vendor module ABI and RAM load path still need validation.'
