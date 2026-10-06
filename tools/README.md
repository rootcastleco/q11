# Lab tool reference

Tools for **Q11 Linux Bring-up**, maintained by
[Batuhan Ayrıbaş](https://batuhanayribas.com).

Python tools use structured reports, bounded inputs and explicit CLI errors.
New output files are not overwritten. Build/image tools create regular files;
physical USB writing is a separate Windows operation. Use each tool's help or
the linked guide before running a hardware command.

| Group | Tools | Purpose / output |
|---|---|---|
| Analysis | `analysis/boot_report.py` | Captured boot milestones, timing coverage and sanitized observations |
| Stock artifacts | `analysis/stock_image.py`, `analysis/audit_rootfs.py` | SquashFS/environment candidates and offline startup-script audit; supplied code is not executed |
| USB evidence | `analysis/ext4_super.py`, `rootfs/read-usb-probe.ps1` | Read-only 2 MiB external-media prefix and ext superblock comparison |
| Device Tree | `dtb/find_dtb.py`, `dtb/extract_dtb.py` | Validated FDT candidates and extraction to a new regular file |
| Debian | `rootfs/build-debian.sh`, `rootfs/configure-rootfs.sh` | Armhf/SysV userspace with a supplied SSH public key |
| External images | `rootfs/make-ext4.sh`, `rootfs/make_disk_image.py` | Linux 3.18-compatible ext4 and one-partition MBR image files |
| RAM handoff | `rootfs/build_initramfs.py`, `rootfs/root_probe.c`, `rootfs/init` | Deterministic newc, filesystem identity probe and bounded `switch_root` |
| USB preparation | `rootfs/write-usb.ps1`, `rootfs/usb-io.psm1` | Explicit external-disk selection, image write and full SHA256 readback |
| Kernel | `kernel/build.sh`, `kernel/bringup.config` | Pinned-source vendor-kernel candidate build; no image upload or flashing |
| UART experiments | `uart/capture_experiment.ps1` | Receive-only capture, timing TSV and experiment metadata |
| Isolated network | `network/isolated-dhcp.ps1`, `network/dhcp.psm1` | Temporary single-Q11 DHCP on the named direct Ethernet link, with cleanup |
| TCP inventory | `network/probe-ports.ps1`, `network/port-report.psm1` | Lease-gated bounded Nmap SYN scan and complete-coverage XML validation |
| HTTP inspection | `network/probe_services.py` | Bounded passive banner, `HEAD /`, or DIAL `GET /dd.xml`; no redirects/control calls |

Guides: [ROOTFS](../docs/ROOTFS.md), [BOOT_FLOW](../docs/BOOT_FLOW.md),
[HARDWARE](../docs/HARDWARE.md), [KERNEL](../docs/KERNEL.md),
[NETWORK](../docs/NETWORK.md), [BRINGUP](../docs/BRINGUP.md).

## Historical UART utilities

These original tools explain existing evidence. Their interruption experiments
have already failed on this firmware; do not repeat them without new evidence.

| Tool | Recorded behavior |
|---|---|
| `uart_capture.ps1` | Low-level receive-only raw/timing capture with reconnect handling; the bounded experiment wrapper is preferred |
| `uart_send.ps1` | One line/CR and response capture; a broad denylist is a guard, not a guarantee about an unknown console |
| `uart_interrupt.ps1` | Historical single-character interruption trial |
| `uart_string_flood.ps1` | Historical short stop-string trial, normally without CR |

Do not treat a serial echo or missing kernel text as proof of an interactive
shell. No UART transmission is part of the current physical-photo step. Keep
future captures private and use new filenames so historical evidence is preserved.
