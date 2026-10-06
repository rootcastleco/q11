# Host validation record

Session:2026-10-06. Hardware custom boot is **not** validated.

| Check | Result / boundary |
|---|---|
| Python unittest suite |23 tests: captured boot/timing fixtures; valid/truncated/false-positive FDT; SquashFS/environment fixtures; CRC redaction; bounded I/O; newc device nodes/reproducibility; MBR; CLI success/invalid/missing/no-overwrite |
| Linux host suite |Real256 MiB ext4 checked by e2fsck; actual MBR image generated; ARM static root-probe exercised under QEMU; shell tool valid dry-runs/invalid/missing checks |
| ShellCheck |Build, configure, filesystem, kernel and test scripts; POSIX init separately |
| PowerShell parser |All `.ps1` files parsed; receive-only dry-run passed |
| UART absent-device test |COM999,5-second bound, zero bytes -> failure metadata; actual COM8 was not transmitted to |
| Windows USB writer dry-run |REI/E:, one USB/MBR disk,15,833,497,600 bytes, non-system/non-boot,512-byte sectors, image checksum/header/capacity checks passed |
| Windows physical USB write |2,148,532,224 bytes written and readback SHA256 matched at23:36 Istanbul; result `written-and-verified`, exit0; user-authorized REI stick only |
| PowerShell transfer regression |Int64 sizing at >2 GiB and1 TiB, zero/final512-byte chunk, invalid negative size and missing module checks passed |
| Debian rootfs |Release signature verified; package installation completed; SysV init/SSH/serial/DHCP/key configuration checked under QEMU; no private keys in Git |
|2 GiB populated ext4 |e2fsck -fn passed,9,072 inodes,87,630 blocks used at creation; exact files can change on a rebuild |
|RAM archive |Uncompressed newc,1,740,288 bytes; real ARM BusyBox plus static root-probe; no stock storage modules available |
|Kernel build |Source/defconfig and driver/DT candidates inspected; CLI guards tested; complete compilation/hardware boot unverified |

Actual generated images and manifests are private/gitignored under `artifacts/`;
build logs and device experiments under `logs/experiment_*` are not published.
Package versions are recorded next to the Linux rootfs in `.packages.tsv`.

Two host setup problems were corrected before preparing physical media: an edit to
a running build script interrupted the first attempt, and direct QEMU execution of
a shebang script failed. Build/configuration are now separate; target scripts run
through the ARM shell, with explicit errors and bounded execution. Failed outputs
were not written to USB. The completed image was checked independently afterward.

The configured rootfs is in the WSL Ubuntu Linux filesystem at
`/var/tmp/q11-debian-v2-20261006`; images are in the Windows repository's `artifacts/`.
QEMU user emulation validates userspace execution on the host kernel, not
compatibility with the Q11's3.18 vendor kernel, MMIO, boot chain or actual storage.
Physical USB write success requires the writer's `written-and-verified` result log.
That result is now recorded privately in
`logs/experiment_20261006_233032_usb-write.json`. An earlier attempt stopped before
writing any bytes due to an Int32 overload selection error; the transfer helper
now uses explicit Int64 operands and records write/verification progress.
Stock startup-script names were also searched in public GitHub code without a
matching result; this bounded search does not establish that no firmware artifact
exists elsewhere. The stock-rootfs/loading-control dependency remains open.
