# Current blocker and exact next hardware experiment

No usable shell or custom Linux boot is confirmed. Completed Ctrl+C, Space and
`set` experiments are closed; none should be repeated. NAND backup work is not
required. The REI USB was detected by the Q11 on 2026-10-06. Loading control for
our initramfs remains UNKNOWN; preparing external storage does not redirect boot.

## Q11 USB probe result — 2026-10-06 23:40–23:42 Istanbul

Private capture: `logs/experiment_20261006_234020_media-probe.log` with timing and
metadata, COM8/115200, receive-only, exit 0. All 116,547 bytes have contiguous timing
coverage and the recorded SHA256 matches. Initial lines are the already-running
stock system; the user-confirmed power cycle starts a single kernel boot at L182.
Line references here count LF-delimited raw lines, without expanding extra CRs.

* CONFIRMED, L462–464: high-speed USB device on `5-1` using xhci-hcd, mass storage.
* CONFIRMED, L486–495: Generic Flash Disk, 30,924,800 sectors of 512 bytes
  (15,833,497,600 bytes); `/dev/sda`, one `/dev/sda1` partition.
* CONFIRMED, L766/L788: vendor HAL emits `MOUNTED` callback for one partition.
  L769–785 shows PVR tag/open/subscriber-matching failures; L927 onward shows
  repeated `HMW_disk_umount` errors. These are stock application messages, not
  proof of a particular filesystem mount, and are unrelated to our SSH configuration.
* UNKNOWN: actual mount path/type, whether the stock firmware wrote the USB,
  ext4 runtime compatibility, and any legitimate removable-media execution hook.
  No custom-initramfs marker, switch_root, Debian shell, or SSH success was seen.

The follow-up read-only prefix capture at 23:45 resolves part of that uncertainty:
`logs/experiment_20261006_234545_usb-read.json` (2,097,152 bytes, exit 0) and
`artifacts/q11-usb-super_20261006_234545.json`, compared to `artifacts/q11-usb.img`.
The filesystem UUID and Q11ROOT label match; mount_count changed from0 to3,
mount/write times changed to1, and the ext journal recovery bit changed toset.
**CONFIRMED:** stock Q11 mounted and wrote this ext4 filesystem. **UNKNOWN:** mount
path (last_mounted remains empty), exact options, file changes, early-root module
availability and execution hook. The stock clock is unset; these timestamps must
not be interpreted as wall-clock time. The stick now requires journal recovery
after power removal; do not call it a fresh/clean image. No device write or journal
recovery was performed by the host reader. A clean lab image can later be rewritten
once this evidence is preserved and a loading path is established.

The next host check reads just a 2 MiB prefix of this external USB and compares
its ext superblock with the prepared image. It neither mounts the filesystem nor
replays its journal. With Q11 power removed, move the REI stick to a normal PC USB
socket; retain UART wiring and decline Windows formatting. No VCC, A-to-A cable,
Ethernet connection or PCB-pad manipulation is needed. Expected output is a new
private prefix file plus JSON, not a new boot.

```powershell
# Administrator PowerShell, after moving REI to the PC; uniquely matched USB only.
pwsh -NoProfile -File tools/rootfs/read-usb-probe.ps1 -ExpectedDiskSizeBytes 15833497600 -DryRun
pwsh -NoProfile -File tools/rootfs/read-usb-probe.ps1 -ExpectedDiskSizeBytes 15833497600
# Replace the timestamp with the printed output; reads regular files only.
python tools/analysis/ext4_super.py artifacts/q11-usb-probe_TIMESTAMP.bin --partition-offset 1048576 --baseline artifacts/q11-usb.img --output artifacts/q11-usb-super_TIMESTAMP.json
```

Return the printed `logs/experiment_TIMESTAMP_usb-read.json` and superblock report.
Snapshots stay private/gitignored. A changed mount count/path can establish a
stock mount, but not loading control or switch_root. If the superblock no longer
matches the baseline UUID, stop interpreting it as the prepared filesystem.

## Remote-control recovery entry: one trial completed

[Q11 owner callagne, 2025-08-11, post29](https://forum.benchmark.rs/threads/huawei-stb-q11.486226/#post-7524681)
reports recovery and UART access using remote OK during startup on MTS/m:tel
firmware. [Owner g-man, 2026-06-12, post32](https://forum.benchmark.rs/threads/huawei-stb-q11.486226/page-2)
reports OK failed on another Q11. Entry is **UNKNOWN** for our firmware. No image
was obtained. Unrelated EC6108 Android packages are not Q11 loading evidence.

**Actual result,2026-10-07:** the user found a Xiaomi IR remote profile that
controls Q11. COM8 receive-only capture ran00:15:44–00:18:44 Istanbul,106,805 bytes,
SHA256 `97274b4e70c088fac13facbc81d56a838cdc874c60e0aa88cd408d6fadf8c13c`.
Private files: `logs/experiment_20261007_001544_recovery-probe.log`, timing TSV and
metadata. L135–146 show the same stock kernel/cmdline; L741 and L1002 onward show
application key events (`0x300`; association with reported OK is likely, no raw IR
decode). The user connected HDMI and reported OK/Home indicators but no recovery.
No UART shell appeared. The direct PC LAN remained connected, evidenced by a
DHCP ACK at 00:17:10; no network upgrade endpoint/package was provided. At00:18:21
UART access was lost, so the tail is incomplete despite the capture's exit 0.
The earlier boot/application evidence remains usable. Do not repeat random keys.

The following is the historical recipe for the completed bounded trial, not an
instruction to repeat it. Recovery remains firmware-dependent.

Prerequisites: compatible remote, optional HDMI display. Q11 stays off while
wiring. Remove USB/microSD and Ethernet so no removable/network upgrade package
is present. Keep REI on the PC. Preserve existing CH341 crossed RX/TX and GND;
never attach VCC/5 V, a PC-host A-to-A cable, or short a pad.

1. If available, connect Q11 HDMI to an ordinary HDMI input with Q11 power removed;
   select that input. HDMI is useful for identifying a recovery menu.
2. Start the receive-only120-second capture below before powering Q11.
3. After COM8 opens, point the remote at the front IR receiver; restore Q11's own
   power adapter and press only OK about twice per second for 20 seconds. Stop
   when a recovery menu appears. Leave it idle; do not choose update/reset/erase/
   format. This is one bounded IR trial, with no UART TX.
4. Expected result: recovery/loader output or an alternate startup trace. If stock
   boot continues, record failed entry; do not try random keys.
5. Return the printed `.log`, `.timing.tsv`, `.metadata.json`, and exact HDMI menu
   text if visible. Inspect a genuine console prompt before sending commands.

```powershell
cd C:\Appdev\q11
pwsh -NoProfile -File tools/uart/capture_experiment.ps1 -Port auto -Operation recovery-probe -DurationSec 120
```

Start/collect the capture after physical setup is ready; do not start a second
capture against an occupied port. A legitimate Q11 stock-rootfs or loading
artifact remains an alternative offline dependency; none is currently available.

## Board identification completed; electrical entry evidence still missing

The owner supplied [26 Q11 photographs](../resimler/README.md), reviewed on
2026-10-07. Both PCB faces, U1/U16 package markings and UART labels are visible.
J15 is a two-hole footprint labelled `GND BOOT`, between the two USB-A sockets.
That is a **LIKELY** boot-strap candidate, not a verified shorting recipe. The
actual U1 has no accessible gull-wing leads; the other-board “upper-right two
legs / 107–108” instruction does not apply to this package.

The next dependency is measured electrical identity of J15 and a documented entry
mechanism, followed by a board-compatible loader/identification protocol. No new
UART transmission, USB rewrite, strap or power-cycle experiment is specified here.

The owner later reported briefly bridging/releasing J15, with Q11 lights on.
The adapter initially enumerated as CH341 programmer `1a86:5512`, so no UART was
available for that interval. After the owner restored jumper 2–3 and reconnected
the adapter USB, UART enumerated as COM10 and a receive-only passive capture
started at 00:57:32 Istanbul. It showed stock HMW middleware; the initial entry/
power-on interval was missed. Current stock execution is confirmed, while J15
entry behavior remains unknown. See the [trial record](../Q11_RECORD.md#owner-reported-j15-trial).

Subsequent owner-reported meter readings were 0 ohms for the probe baseline and
`GND` to UART GND, 3.661 megohms for unpowered `BOOT` to UART GND, and 3.317 V
for powered `BOOT` to UART GND with J15 open. These support the ground association
and establish a reported voltage, but do not identify the SoC net, pull network
or selected boot mode. See the [meter record](../Q11_RECORD.md#owner-reported-j15-meter-readings).

For resistance/continuity identification, first unplug Q11's own power adapter
and disconnect HDMI, LAN, USB/media and UART leads; disconnect CH341 from the PC
before moving its leads. Some supplied photos show attached DC/UART, so do not
assume the photographed board was unpowered. Identify the hole labelled `GND`
against the previously measured UART GND, and record meter/probe resistance and
both J15 holes' resistance to that reference. A continuity beep alone does not
identify the other hole as the SoC's USB_BOOT input; routing/pull-network evidence
is still required. Do not perform these measurements while powered, bridge J15,
connect VCC/5 V or attach a PC-host A-to-A cable.

A legitimate Q11 firmware artifact remains an alternative for offline hook/DDR
analysis. No compatible RAM loader or stock-rootfs artifact is currently supplied;
no NAND backup is required. See [BOOTROM](BOOTROM.md) for the entry and payload
boundaries.

## Reproducing USB storage detection (completed once; no repeat needed)

This session's REI stick was **written and fully readback-verified** at
2026-10-06 23:36 Istanbul time. A 2 GiB ext4 root partition is ready; Windows cannot
mount it. No reformat/rewrite is needed for the next probe. The private record is
`logs/experiment_20261006_233032_usb-write.json` (exit 0, matching SHA256).
This validates USB preparation on the PC, not a Q11 custom boot.

First validate/build the USB image and run the separately authorized media writer
in [ROOTFS](ROOTFS.md). Do not move a stick during an active write/readback. Proceed
only after its result says `written-and-verified`. If no write has occurred, an
ordinary blank USB stick with no upgrade files can be used for enumeration instead.

* Connector/device: Q11's normal USB-A **host** socket; use the prepared REI stick.
  If several sockets exist, record which labelled socket you used; controller to
  physical-socket mapping is UNKNOWN. No PCB strap/test pad is required.
* Power state: unplug Q11's own power adapter before moving the stick or touching
  UART wiring. Keep CH341A on USB; its UART mode jumper remains2–3.
* Connect: Q11 GND → CH341A GND; Q11 TX → CH341A RX; Q11 RX → CH341A TX, with the
  already measured3.3 V interface. Insert only the USB stick into Q11's USB socket.
* Do not connect: Q11 VCC to adapter, CH341A3.3 V/5 V to Q11, PC USB host to Q11
  USB host using an A-to-A cable, or any NAND/test-pad short. Keep Ethernet unplugged
  for this stock-firmware probe; an isolated LAN is used later for custom Linux.
* Start capture from `C:\Appdev\q11` **before** restoring Q11 power:

```powershell
pwsh -NoProfile -File tools/uart/capture_experiment.ps1 -Port auto -Operation media-probe -DurationSec 120
```

* Restore Q11 power once capture says the COM port is open. Capture is receive-only:
  no keys, commands, modem-control toggles or repeated UART experiments.
* Expected result: normal kernel/stock startup, then USB mass-storage discovery,
  SCSI disk capacity and an `sda`/`sda1` (or another sdX) partition. An ext4 mount or
  mount error is useful evidence. Neither outcome implies script execution or a
  shell. If kernel output does not appear, check capture connection/power first.
* Output to return: the printed `logs/experiment_YYYYMMDD_HHMMSS_media-probe.log`,
  its `.timing.tsv`, and `.metadata.json`. Include socket identity. Generated raw
  logs stay private/gitignored because USB/firmware may print unique identifiers.

If the user instead has a known working microSD card, insert it into the Q11 card
slot with power removed and run the same capture (record media type as microSD in
notes). Expect himciv200 card detection and `mmcblkX`, then partition discovery.
Card formatting is unnecessary for detecting the controller/card. Do not assume
the external slot maps to mmcblk0: record the actual enumeration.

## What that experiment resolves

It determines which transport is actually usable under the stock drivers, and
whether normal mount scripts react to external ext4. It cannot resolve final
bootargs control or a maintenance hook by itself. Once transport is confirmed,
the remaining offline dependency is a legitimate stock rootfs/firmware artifact
for the named startup scripts, or an established board-compatible RAM loader path.
No pad short or blind USB update is warranted by current evidence.

## Acceptance after an authorized RAM boot becomes possible

Capture distinct milestones: `Q11: custom initramfs reached`, external partition
mount, `switch_root`, SysV startup and ttyAMA0 root shell. Then run locally:

```sh
uname -a
cat /proc/cmdline
cat /proc/filesystems
findmnt /
cat /proc/meminfo
ip -br link
ip -br addr
ip route
cat /etc/resolv.conf
```

Use an isolated Ethernet switch/DHCP server first. Confirm PHY link, DHCP, route,
DNS, SSH public-key login, and persistence across a controlled restart. Record MAC
behavior privately; do not publish the address or assume it is stable without a
second boot. If firmware supplied no valid MAC, select a per-install locally
administered address outside Git only after inspecting driver behavior. Never read
Factory/CA partitions merely to retrieve it. Add HDMI/fbdev only afterwards; see
[HARDWARE](HARDWARE.md) and [MEMORY](MEMORY.md).

## Offline verification

```powershell
python -m unittest discover -s tests -v
python tools/analysis/boot_report.py logs --output artifacts/boot-report-new.json
pwsh -NoProfile -File tools/uart/capture_experiment.ps1 -DryRun
pwsh -NoProfile -File tests/test_powershell.ps1
```

Linux: `shellcheck tools/rootfs/*.sh tools/kernel/build.sh` and
`shellcheck -s sh tools/rootfs/init`. CLI tools reject invalid/missing inputs and
existing outputs. Image parsing uses synthetic fixtures; boot parsing uses all
captured log/timing files. `tests/test_host_tools.sh` covers shell build selections,
root-probe fixtures, and filesystem/disk-image creation without physical devices.
USB writer dry-run validates selection; physical success requires its readback log.

---

Maintained by [Batuhan Ayrıbaş](https://batuhanayribas.com) · Q11 Linux Bring-up
