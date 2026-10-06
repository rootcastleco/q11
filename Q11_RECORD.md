# Huawei Q11 — Technical Record

**[Batuhan Ayrıbaş · Engineering & Research](https://batuhanayribas.com)**

Project: [Q11 Linux Bring-up](README.md) · Updated 2026-10-07

This record preserves measurements, failed trials and later corrections.
**No custom Linux boot or usable shell has been achieved on Q11.** Unless stated
otherwise, `Lnnn` refers to a one-based line in `logs/boot_01.clean.txt`.
Session times use Europe/Istanbul.

- **CONFIRMED:** directly observed in captured output, measurements or a completed test.
- **LIKELY:** an interpretation supported by evidence but not yet demonstrated.
- **UNKNOWN:** missing evidence or a dependency not tested on this Q11.
- **HOST VALIDATED:** executed on the PC/WSL/QEMU, not on the target device.

## Hardware and firmware inventory

| Item | Evidence / value | Status |
|---|---|---|
| Device | Huawei Q11; middleware `STB_model=Q11` (L504) | CONFIRMED |
| SoC | HiSilicon Hi3798MV100 (L50) | CONFIRMED |
| CPU | 4 × Cortex-A7 r0p5, `410fc075`, ARMv7 SMP (L3, L54) | CONFIRMED |
| RAM | 1 GiB DDR; physical base 0; `mem=1G`, `Memory: 566652K/1048576K` (L12, L21) | CONFIRMED |
| Reservations | 380 MiB CMA/MMZ at `0x18400000`; 4 MiB at `0x3fc00000`; 8 MiB DSP at `0x02000000` | CONFIRMED |
| Flash | Toshiba 256 MiB raw NAND, 8-bit, 3.3 V; no eMMC or SPI NOR detected in this boot | CONFIRMED observation |
| NAND ID / marking | `98 DA 90 15 F6 16 08 00` (L112); U16 photograph reads `TC58BVG1S3HBAI4` | CONFIRMED log ID / visual marking |
| NAND geometry | 2 KiB page, 64 B OOB, 128 KiB erase block, 2048 blocks; hardware-auto ECC 4-bit/512 B (L114) | CONFIRMED |
| NAND controller | HiSilicon `hinfc610` | CONFIRMED |
| UART header | `GND \| RX \| TX \| VCC` in the recorded board orientation | CONFIRMED on lab unit |
| UART console | PL011 `ttyAMA0` at `0xf8b00000`, IRQ 81, 115200 8N1 (L12, L63) | CONFIRMED |
| Other UARTs | `ttyAMA1` at `0xf8006000`, `ttyAMA2` at `0xf8b02000` | CONFIRMED |
| UART voltage | Q11 RX pad 3.29 V while powered; Q11 TX readable by measured 3.3 V adapter | CONFIRMED |
| Adapter | Black CH341A mini-programmer; header `1 2 3 TX RX GND 3.3V`; jumper 2–3 selects UART | CONFIRMED |
| Adapter idle levels | UART TX 3.29 V, RX 3.29 V | CONFIRMED |
| Bootloader family | HiSilicon fastboot, based on SDK and partition names | LIKELY |
| Bootloader output | About 16.8 s between the initial power-associated NUL and first kernel text | CONFIRMED observation |
| Bootloader shell | No prompt/autoboot message; Ctrl+C, space and `set` trials failed | Not obtained; configuration UNKNOWN |
| Kernel | Linux `3.18.13_s40`, gcc 4.9.2, build #4 SMP 2017-06-23 (L2) | CONFIRMED |
| SDK | HiSTBLinuxV100R003C00SPC065, from module versions | CONFIRMED |
| Root filesystem | SquashFS, read-only RAM disk device 1:0, `/dev/ram` (L190–192) | CONFIRMED |
| Application data | `appdata`, `mtdblock16`, YAFFS2 read/write (L279) | CONFIRMED |
| Filesystem support | SquashFS, JFFS2, YAFFS, FUSE, UDF and Tuxera NTFS messages | CONFIRMED in logs |
| Partition map | 18 MTD partitions; `mtdparts=hinand:` (L12, L118–136) | CONFIRMED |
| Device Tree | `Machine model: Hisilicon` (L5) | CONFIRMED use / location UNKNOWN |
| Secure-boot indicators | `hi_advca.ko` (L229), OTP `DieID is locked!` (L208), `vmx_ca` (L461) | CONFIRMED messages / enforcement UNKNOWN |
| TEE | No TEE/OP-TEE startup message observed | UNKNOWN |
| USB hosts | EHCI `0xf9890000`/`0xf9930000`, OHCI `0xf9880000`/`0xf9920000`, xHCI `0xf98a0000` | CONFIRMED |
| Ethernet | `hieth`, MDIO `himii`, port 0 → PHY 1 (L137–138); later direct 100 Mbps/DHCP test | CONFIRMED stock link / MAC source UNKNOWN |
| HDMI | `hi_hdmi.ko`; initially unplugged (L488); display connected during later IR trial | CONFIRMED stock observations / custom display untested |
| Graphics | `hi_fb`, `hi_tde`, HIGO 4.0; no usable Mali driver observed | CONFIRMED module messages |
| GPU | Mali-450-class block expected for this SoC family | LIKELY; acceleration unvalidated |
| Video | `hi_vfmw`, `hi_vdec`, `hi_vpss`, `hi_svdec` | CONFIRMED module messages |
| Shell | No login/prompt; `telnetd` missing (L200); release management CLI disabled (L528) | Not obtained |
| Middleware | Huawei HMT V100R003C89LTRT01SPC600B001, 2018-08-02, Blink browser (L475) | CONFIRMED |
| Operator profile | Turkcell Superonline IPTV profile (L688) | CONFIRMED |
| Recovery partitions | `loader` / `loaderbak` appear to contain upgrade loaders | LIKELY; contents unavailable |

## NAND partition map

Source: `boot_01.clean.txt`, L118–136. Total 256 MiB (`0x10000000`). End addresses
are **inclusive**. This is an observed map, not a flash plan.

| MTD | Name | Start | End | Size, hex | Bytes | MiB | Interpretation |
|---|---|---|---|---|---|---|---|
| 0 | fastboot | 0x00000000 | 0x000fffff | 0x00100000 | 1,048,576 | 1 | Bootloader, LIKELY |
| 1 | bootargs | 0x00100000 | 0x0017ffff | 0x00080000 | 524,288 | 0.5 | Environment, LIKELY |
| 2 | bootargsBak | 0x00180000 | 0x001fffff | 0x00080000 | 524,288 | 0.5 | Backup environment, LIKELY |
| 3 | reserve0 | 0x00200000 | 0x003fffff | 0x00200000 | 2,097,152 | 2 | UNKNOWN |
| 4 | reserve0Bak | 0x00400000 | 0x005fffff | 0x00200000 | 2,097,152 | 2 | UNKNOWN |
| 5 | loaderdb | 0x00600000 | 0x0067ffff | 0x00080000 | 524,288 | 0.5 | Loader flags/database, LIKELY |
| 6 | loaderdbbak | 0x00680000 | 0x006fffff | 0x00080000 | 524,288 | 0.5 | Loader database backup, LIKELY |
| 7 | baseparam | 0x00700000 | 0x007fffff | 0x00100000 | 1,048,576 | 1 | Display/output parameters, LIKELY |
| 8 | pqparam | 0x00800000 | 0x008fffff | 0x00100000 | 1,048,576 | 1 | Picture-quality parameters, LIKELY |
| 9 | logo | 0x00900000 | 0x00cfffff | 0x00400000 | 4,194,304 | 4 | Boot logo, LIKELY |
| 10 | loader | 0x00d00000 | 0x014fffff | 0x00800000 | 8,388,608 | 8 | Upgrade loader, LIKELY |
| 11 | loaderbak | 0x01500000 | 0x01cfffff | 0x00800000 | 8,388,608 | 8 | Backup loader, LIKELY |
| 12 | kernel | 0x01d00000 | 0x024fffff | 0x00800000 | 8,388,608 | 8 | Kernel; DTB packaging UNKNOWN |
| 13 | rootfs | 0x02500000 | 0x088fffff | 0x06400000 | 104,857,600 | 100 | SquashFS; possible 0x110 wrapper UNKNOWN |
| 14 | Misc | 0x08900000 | 0x0897ffff | 0x00080000 | 524,288 | 0.5 | UNKNOWN |
| 15 | Factory | 0x08980000 | 0x0a27ffff | 0x01900000 | 26,214,400 | 25 | Factory data, LIKELY; outside scope |
| 16 | appdata | 0x0a280000 | 0x0fc7ffff | 0x05a00000 | 94,371,840 | 90 | YAFFS2 read/write, CONFIRMED |
| 17 | others | 0x0fc80000 | 0x0fffffff | 0x00380000 | 3,670,016 | 3.5 | UNKNOWN |

Stock firmware prints `hisi_flash_write_partition` / `HI_Flash_Write` with
`DataLen=131072` twice (L691–696). The partition is UNKNOWN. Stock boots may
change internal data even though this project's tools issue no NAND writes.
No Factory/CA data was read or modified for bring-up.

## Baseline boot analysis

- Raw capture: `logs/boot_01.log`, 137,868 bytes.
- SHA256: `a12e513b8cfd5de36ce56b9bf9106b601a2d6e6f274490a711d028cbbaff3faf`.
- Readable view: `logs/boot_01.clean.txt`; CR/NUL/spinner cleanup only.
- Timing: power-associated NUL to kernel text has about 16.8 s of silence.
- Exact command line, spacing normalized:

```text
mem=1G console=ttyAMA0,115200 root=/dev/romblock14 rootfstype=squashfs rootwait mtdparts=hinand:1M(fastboot),512K(bootargs),512K(bootargsBak),2M(reserve0),2M(reserve0Bak),512K(loaderdb),512K(loaderdbbak),1M(baseparam),1M(pqparam),4M(logo),8M(loader),8M(loaderbak),8M(kernel),100M(rootfs),512K(Misc),25M(Factory),90M(appdata),-(others) mmz=ddr,0,0,380M user_debug=31 initrd=0x2500110,0x386f800 root=/dev/ram ramdisk_size=102400 rootfstype=squashfs
```

The last `root=` is effective, confirmed by RAM-disk mounting. Firmware appending
the final group is LIKELY. The initrd begins at `0x02500110`, size `0x0386f800` =
59,176,960 bytes (56.44 MiB). The 0x110 displacement may be a wrapper/header;
it does not establish a signature. Image bytes are unavailable.

Startup follows `rcS` → S00devs → S01udev → S80network → S90modules → S99init,
then vendor middleware. USB hosts initialize after S90modules. `set_mount_new.sh`,
`hmw_mount.sh`, `loader.rc`, `local.rc` and `init.sh` are inspection targets with
unavailable contents. Neither tty echo nor `user_debug=31` supplied a shell.
See [BOOT_FLOW](docs/BOOT_FLOW.md) for image/startup analysis requirements.

## Lab wiring and measurements

Use Q11's own adapter; leave VCC unconnected. Measured 3.3 V signaling is a
prerequisite for CH341 TX → Q11 RX. Wire with Q11 power removed. Power the UART
adapter first, then Q11; remove Q11 power before changing leads. Stock experiments
use no WAN. The direct PC link is isolated, without gateway/DNS/update service.

| Date | Measurement | Value | Context |
|---|---|---|---|
| 2026-10-06 | Initially unspecified adapter point | 3.3 V | Still in programmer mode |
| 2026-10-06 | CH341A TX → GND | 3.29 V | UART mode, idle |
| 2026-10-06 | CH341A RX → GND | 3.29 V | UART mode, idle |
| 2026-10-06 | Q11 RX pad → Q11 GND | 3.29 V | Q11 powered; TX-connection voltage prerequisite met |

## Chronology: UART setup and completed interruption trials

These entries explain historical evidence, not instructions to repeat trials.

| Date/time | Action and result |
|---|---|
| 2026-10-06, initial setup | CH340G replaced by CH341A; receive-only GND/TX wiring prepared. |
| Initial enumeration | `1a86:5512` was programmer mode with no UART COM port; COM3/4 were Bluetooth. |
| 21:42:22 | Jumper/USB change still showed programmer mode; photos showed jumper 1–2. |
| 21:48 | Jumper 2–3 enumerated `1a86:5523`, CH341 UART COM8, working driver. |
| 21:49:58–21:51:27 | First capture waited; adapter disappeared; zero bytes. |
| 21:53:05 | Reconnect/auto-port handling added; adapter TX/RX measured 3.29 V. |
| 21:54–21:56 | Adapter absent on PC despite reported reconnection. |
| 21:57:52 | Unwired adapter returned on COM8; wiring-related reset LIKELY. Adjacent supply-pin contact/ground transient was an unconfirmed explanation. |
| 22:00:00–22:00:51 | Adapter disconnected during wiring, then returned on COM10 in another PC USB port. |
| 22:02:18 | Receive-only capture started on COM10. |
| 22:02:51–22:03:08 | Power-associated NUL, then kernel text after about 16.8 s. |
| 22:06 | Baseline completed: 137,868 bytes; receive-only UART working. |
| About 22:13 | Q11 RX measured 3.29 V; blank external USB available. |
| 22:13:25–22:13:49 | Adapter moved COM10→COM8; auto-port selection added. |
| 22:18:31 | Second capture armed after 10 s silence for the next boot. |
| 22:19:43 | TX lead connected while Q11 was still running; future wiring must use power removed. |
| 22:20:22 | One authorized Enter sent; no prompt, only stock messages (`session_01.log`). |
| 22:24:56 | First 35-second Ctrl+C trial started (`break_01.log`). |
| 22:25–22:26 | Runtime echo observed; `uname -a` echoed but not executed. A boot occurred outside the shortened capture window. |
| 22:28–22:30 | Full 120-second Ctrl+C trial reached stock boot; autoboot not stopped (`break_ctrlc.log`). |
| 22:32–22:34 | Full 120-second space trial reached stock kernel (`break_space.log`). |
| 22:38–22:40 | `set`, without CR, repeated for 120 s; stock boot continued (`flood_set.log`). |

**Confirmed result:** all three completed candidates failed to expose a bootloader.
`bootdelay=0` or disabled UART interruption is LIKELY, not a read configuration
value. Early NAND-short/native-USB/programmer suggestions were speculative and
are superseded by [BOOTROM](docs/BOOTROM.md); they are not Q11 procedures.

## 2026-10-06: external Linux preparation

The selected path favors stock-kernel reuse, RAM initramfs and external rootfs.
A full-NAND backup workflow is not a prerequisite. The external stick had explicit
preparation authorization; internal NAND did not.

- **CONFIRMED:** `himciv200` probes SD `0xf9820000` and MMC `0xf9830000`
  before root mount (L161–163). No card detected; external-slot usability UNKNOWN.
- **CONFIRMED:** USB initialization follows S90modules (L236–267).
  Early-module dependency LIKELY; stock `.config`/matching modules missing.
- **UNKNOWN:** a legitimate stock external-userspace hook. Script names are
  known; no removable-media autorun/maintenance mechanism is established.
- **SOURCE CANDIDATE:** glinuz/hi3798mv100 at `12aa0504`, SDK R005 SPC041,
  kernel 3.18.24. Generic DTS PHY 2 differs from Q11 PHY 1; neither a drop-in board
  file nor a module ABI match for 3.18.13_s40.
- **HOST VALIDATED:** Debian bookworm armhf/SysV configured; 2 GiB ext4 checked
  by e2fsck; ARM executables checked under QEMU; 1,740,288-byte newc archive
  generated. No target boot implied. See [ROOTFS](docs/ROOTFS.md).

### External USB preparation and mount evidence

| Time | Experiment | Result |
|---|---|---|
| 23:36 | External write/readback | 2,148,532,224-byte MBR+ext4 image; full readback SHA256 matched; exit 0. |
| 23:40–23:42 | COM8/115200 RX-only USB boot | 116,547 bytes; hash/timing checked; one stock boot. xHCI → high-speed Generic Flash Disk, 15,833,497,600 bytes, `/dev/sda` and `/dev/sda1`. |
| 23:45 | PC read-only 2 MiB prefix comparison | Baseline UUID/label unchanged; mount_count 0→3, journal recovery 0→1. Stock Q11 mounted/wrote this ext4. |

Private evidence:

- `logs/experiment_20261006_233032_usb-write.json`
- `logs/experiment_20261006_234020_media-probe.log` and timing/metadata companions
- `logs/experiment_20261006_234545_usb-read.json`

USB boot-capture SHA256:
`452105a2e102cd1900c767a3900061d8aead805523c2550c78a52c706a9ba4e2`.
L182 begins stock boot; L462–495 enumerate storage; L766/L788 contain MOUNTED
callbacks, followed by PVR/open/unmount errors. Callbacks alone did not prove
ext4; the later superblock comparison did. Mount path/options and script execution
remain UNKNOWN. Journal recovery is pending; the host reader did not replay or
repair it. Debian/initramfs did not run.

### Recovery and BootROM research

A [first-hand Q11 report](https://forum.benchmark.rs/threads/huawei-stb-q11.486226/#post-7524681)
claims OK at startup led to recovery/UART access on MTS/m:tel firmware; another
owner reported failure. The initial trial was pending without an original remote;
a Xiaomi IR profile enabled the later trial.

Pinned HiLoot source has TYPE/BOARD queries but no chip-info-only CLI. Its initial
`Bootrom start` wait is not bounded by frame timeout; the greeting is absent from
Q11 captures. No binary UART packet or RAM image was sent. Signature enforcement
and compatible DDR/loader identity remain UNKNOWN.

## 2026-10-07: isolated Ethernet and IR recovery

### Wired network

Q11 LAN connected directly to the PC physical Realtek Ethernet port. Temporary
server 192.168.73.1/24 offered Q11 address 192.168.73.2 only on that link.

- **CONFIRMED:** 100 Mbps link, udhcpc ACK/ARP conflict check, reachable neighbour,
  two ICMP replies, TTL 64 and 1–2 ms latency.
- No gateway/DNS/update options or forwarding; Wi-Fi unchanged. Stock Ethernet
  validated; Debian networking and persistent MAC source remain untested/UNKNOWN.
- **CONFIRMED:** SYN inventory covered all 65,535 TCP ports: 7547,56789,56790 open;
  65,532 closed/reset. Earlier filtered/no-response results were not called closed.
- Nmap completed; wrapper XML-property lookup errored, exit 2. Original error
  retained; fixed XPath reader independently verified target/completion/coverage.
- **CONFIRMED:** 56790 `/dd.xml` returned HTTP 200 and DIAL Application-URL for
  device port 56789 `/apps/`. No application launch/SOAP/credentials attempted.
  Port 7547 is LIKELY CWMP; no control operation sent.
- No SSH/telnet console or verified recovery command found.
- Three DHCP sessions completed exit 0/restored=true; last 00:17:58. DHCP enabled,
  forwarding disabled/APIPA and temporary IP/firewall removal checked afterward.
  See [NETWORK](docs/NETWORK.md).

### Xiaomi IR trial

COM8/115200 RX-only capture ran 00:15:44–00:18:44; 106,805 bytes. Private log:
`logs/experiment_20261007_001544_recovery-probe.log` plus companions.
SHA256: `97274b4e70c088fac13facbc81d56a838cdc874c60e0aa88cd408d6fadf8c13c`.

L135–146 show the same stock kernel/cmdline. L741/L1002 onward show browser key
0x300 events. Association with reported OK is LIKELY; raw IR was not decoded.
HDMI was connected afterward: OK/Home indicators responded, but no recovery was
reported. Stock IPTV ran; no UART shell/recovery prompt appeared.

Direct LAN remained connected despite removal instructions (00:17:10 DHCP ACK).
Only the PC was connected; no update server/package. UART access was lost at
00:18:21: incomplete tail despite metadata exit 0. Earlier boot/key evidence and
byte/timing coverage were verified. One failed trial does not establish that all
recovery mechanisms are disabled.

### Newly supplied pin-short reports

A [YMB0310-CW owner's report](https://bbs.histb.com/d/501/23) corrects informal
"CPU 1–2" to physical 107–108 and supplies a MRQCV101000 package photo. This is
another-board evidence; Q11 package/pad mapping remains UNKNOWN.

The [Ekoo USB-flash guide](https://ecoo.top/docs/tutorial-basics/usb-flash/)
automatically writes eMMC; not a RAM-only recipe or raw-NAND Q11 compatibility
proof. HiSTB documentation describes USB_BOOT→GND/FAT32/`fastboot.bin` host boot
and board-specific DDR/reg requirements. Our stick is ext4-only, without those
boot files. No package downloaded/executed, USB rewritten or shorting performed.
See [BOOTROM](docs/BOOTROM.md).

## Current dependency

Verified execution/loading control is missing. Board identification photos are
now available; electrical entry evidence and a board-compatible RAM loader remain
missing. No Q11 shorting instruction or signed loading path is established.
A legitimate stock rootfs/firmware artifact would enable offline hook analysis;
no NAND backup is required.
Exact next steps: [BRINGUP](docs/BRINGUP.md).

### Q11 photographs supplied — 2026-10-07

[Image index and checksums](resimler/README.md): 26 supplied JPEG files, originals
preserved. Both PCB faces are visible. Some frames show attached DC/UART leads;
the electrical power state cannot be determined from the photographs.

- **CONFIRMED visual:** U1 `Hi3798 MRBCV100MD2`, with no accessible gull-wing leads
  and lettered/numbered PCB coordinate markings; BGA construction is LIKELY.
- **CONFIRMED visual:** U16 `TC58BVG1S3HBAI4`, complementing the captured NAND ID.
- **CONFIRMED visual:** UART `GND RX TX VCC` agrees with the measured wiring record.
- **CONFIRMED visual:** unpopulated J15 two-hole footprint between USB-A sockets,
  labelled `GND BOOT`, beside R40. Intended boot strap is **LIKELY**; electrical
  continuity, SoC net, pull network, voltage and selected boot mode are **UNKNOWN**.
- **CONFIRMED visual:** J9 `VCC DM DP GND`; native USB device/download capability
  does not follow from this label. The reverse footprint near `MAC` is not a
  confirmed JTAG connector. The visible card-style socket is not a verified SD slot.
- The other-board leaded-package “upper-right 107–108” recipe cannot map to this
  Q11 package. J15 has not been bridged or measured; no entry/loader trial resulted
  from this photographic inspection. See [BOOTROM](docs/BOOTROM.md).

---

Maintained by [Batuhan Ayrıbaş](https://batuhanayribas.com) · Q11 Linux Bring-up
