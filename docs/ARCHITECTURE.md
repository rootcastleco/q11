# Linux bring-up architecture

Status as of 2026-10-07: host tools implemented; no custom code has booted on Q11.
Captured evidence remains in `logs/`; historical experiments remain in `Q11_RECORD.md`.
No NAND backup is a prerequisite for this work. No internal flash writer is provided.

```text
existing HiSilicon boot chain [firmware implementation UNKNOWN]
  -> stock 3.18.13_s40 kernel [CONFIRMED]
  -> replacement /init in RAM [implemented; loading mechanism UNKNOWN]
  -> external ext4, LABEL=Q11ROOT [stock mount confirmed; custom handoff untested]
  -> Debian bookworm armhf, SysV init
     -> ttyAMA0 local administrative shell
     -> eth0 DHCP -> developer SSH public-key login
     -> later: compatible vendor framebuffer/HDMI modules
```

The first unresolved dependency is **authorized execution/loading control**, not a
missing ARM distribution. A rootfs image on a USB stick does not change the stock
boot sequence. A mounted stick does not prove that firmware executes its scripts.
The actual USB/ext4 stock mount is now confirmed by UART enumeration and the
superblock mount counter, not just a vendor application event. A Xiaomi IR remote
trial reached stock IPTV startup and the user confirmed no recovery on HDMI.
Isolated wired DHCP and TCP inventory found HTTP/DIAL services, no SSH/telnet
console. The network does not supply loading control. Details remain in
[BRINGUP](BRINGUP.md) and [NETWORK](NETWORK.md).

| Rank | Approach | Feasibility now | Reversibility | Proprietary dependency / complexity |
|---|---|---|---|---|
| 1 | Stock rootfs startup/maintenance hook, then external userspace | UNKNOWN: named scripts exist in logs, contents absent | High if documented hook executes in RAM | Stock init/loader; lowest complexity if a hook exists |
| 2 | Stock kernel + RAM initramfs + external root | Kernel attempts initramfs unpacking; loading control and matching storage modules UNKNOWN | High | Stock loader and module ABI; implemented handoff |
| 3 | Stock kernel direct microSD root | Built-in MMC driver probes before root mount; card detection/ext4 UNKNOWN | High with temporary final bootargs | Final bootargs control still missing |
| 4 | BootROM serial RAM bootstrap, compatible loader, kernel/rootfs | Public protocol/tool exists; Q11 entry and DDR image UNKNOWN | High only when loader never writes flash | DDR/board configuration and authorization requirements; substantial work |
| 5 | Custom vendor-compatible kernel + external root | Public 3.18.24 and 4.4.35 candidates found; neither Q11-tested | High when loaded into RAM | Board DTB, compiler, vendor modules; highest complexity |

Success probability cannot be quantified from existing logs. Each approach remains
conditional on the dependency in its feasibility column. Internal flashing is not
an automatic fallback. Public eMMC installation recipes do not describe this raw-NAND Q11.

See [BOOT_FLOW](BOOT_FLOW.md), [BRINGUP](BRINGUP.md), [ROOTFS](ROOTFS.md), and [KERNEL](KERNEL.md).
