# Observed boot flow and control points

References below are one-based lines in `logs/boot_01.clean.txt`.

| Evidence | Status | Implication |
|---|---|---|
| 16,802 ms between initial NUL receive chunk and first text chunk; timing TSV | CONFIRMED capture observation | Bootloader emits no visible text in that window; firmware console configuration UNKNOWN |
| Linux 3.18.13_s40, gcc 4.9.2; L2 | CONFIRMED | Preserve this kernel/modules for the first external-userspace attempt |
| `user_debug=31`; L12 | CONFIRMED | This is already enabled; it has not produced a shell. It is not a demonstrated maintenance flag |
| Initramfs unpack attempted, archive rejected, legacy initrd selected; L92–94 | CONFIRMED | Stock payload is a block filesystem; a real newc archive is a plausible alternative, subject to loader acceptance |
| SquashFS mounted read-only on device 1:0; L190–192 | CONFIRMED | Actual root is RAM disk, not a directly mounted NAND partition |
| rcS, S00devs, S01udev, S80network, S90modules, S99init; L194–200, L275 | CONFIRMED | BusyBox-style startup is LIKELY; actual inittab/init binary must be inspected |
| USB platform host controllers initialize after S90modules; L236–267 | CONFIRMED ordering | LIKELY module dependency: direct USB root may stall before those drivers load |
| `set_mount_new.sh`, `hmw_mount.sh`, `loader.rc`; L276–283 | CONFIRMED names in output | File paths, writable appdata influence, removable-media execution semantics UNKNOWN |
| `local.rc: ./init.sh: line 89`; L451 | CONFIRMED | Inspect `/usr/local/bin/fullapp/local.rc` and its referenced init script |
| Missing `passwdTelnet`; L453; release management CLI disabled; L528 | CONFIRMED messages | No demonstrated login or maintenance shell |

Exact captured command line (spacing normalized only):

```text
mem=1G console=ttyAMA0,115200 root=/dev/romblock14 rootfstype=squashfs rootwait mtdparts=hinand:1M(fastboot),512K(bootargs),512K(bootargsBak),2M(reserve0),2M(reserve0Bak),512K(loaderdb),512K(loaderdbbak),1M(baseparam),1M(pqparam),4M(logo),8M(loader),8M(loaderbak),8M(kernel),100M(rootfs),512K(Misc),25M(Factory),90M(appdata),-(others) mmz=ddr,0,0,380M user_debug=31 initrd=0x2500110,0x386f800 root=/dev/ram ramdisk_size=102400 rootfstype=squashfs
```

Last `root=` and `rootfstype=` win, consistent with the mount log. Changing only
the first occurrence cannot switch root. Firmware appending the last group is
LIKELY, not confirmed. `init=/bin/sh` changes the executable on a mounted legacy
root; `rdinit=/init` concerns initramfs. Neither option supplies an image load path.
An initramfs `/init` takes precedence over the normal root-mount path and must
perform its own bounded external-root wait; kernel `rootwait` does not do that for it.

`initrd=0x02500110,0x0386f800` describes 59,176,960 bytes (56.44 MiB), ending
at physical 0x05d6f910 (exclusive). The 0x110 displacement is not proof of a
signature. No proprietary header bytes are available. The initial address also
falls inside the reported DSP reservation: do not reuse it for a new image without
checking image lifetime and the complete live RAM map. See [MEMORY](MEMORY.md).

## Bootargs and loader partitions

Partition labels and offsets are CONFIRMED by L118–136. Their contents, checksum
scheme, active-copy selection, recovery trigger and signature policy are UNKNOWN.
The public SDK candidate uses CRC32 environment data and has backup-selection and
USB-host-bootstrap branches. Some branches repair the primary environment using
`saveenv`. This is **source evidence about that SDK**, not proof of Q11 behavior.
Do not invalidate a primary copy to force fallback.

Primary source: [candidate env_common.c](https://github.com/glinuz/hi3798mv100/blob/12aa0504880d518a9fa15800d4f7a305a1f94dc6/HiSTBLinuxV100R005C00SPC041B020/source/boot/fastboot/common/env_common.c).
`tools/analysis/stock_image.py` checks conventional 4/5-byte CRC headers against the
whole supplied file, reports keys only, and never writes an environment. If an
environment is smaller than its partition, carve the exact candidate first;
failure of the whole-file CRC does not disprove an environment within the partition.

## Stock image analysis when an artifact becomes available

```powershell
python tools/analysis/stock_image.py artifacts/vendor-rootfs.bin --extract-squashfs artifacts/stock.sqfs --output artifacts/stock-image.json
```

On a disposable Linux analysis directory, not on Q11:

```bash
timeout 600 unsquashfs -d /var/tmp/q11-stock-root artifacts/stock.sqfs
python3 tools/analysis/audit_rootfs.py /var/tmp/q11-stock-root --output artifacts/stock-audit.json
```

Inspect inittab, rcS, S99init, udev/hotplug, the mount scripts, loader.rc, local.rc,
init.sh and loader/update entry points as text. Determine whether any ordinary
maintenance hook accepts an external script, how its path is chosen, and whether
it writes internal partitions. No such hook is established yet. No supplied file
is executed by the audit tool. CA, protected credentials and signature bypass
remain outside scope.
