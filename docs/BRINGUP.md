# Current blocker and exact next hardware experiment

No usable shell or custom Linux boot is confirmed. Completed Ctrl+C, Space and
`set` experiments are closed; none should be repeated. NAND backup work is not
required. The next physical experiment is **removable-media detection**, not a
claim that the prepared rootfs boots automatically.

## USB storage probe (user has authorized erasing the REI stick)

This session's REI stick was **written and fully readback-verified** at
2026-10-06 23:36 Istanbul time. A2 GiB ext4 root partition is ready; Windows cannot
mount it. No reformat/rewrite is needed for the next probe. The private record is
`logs/experiment_20261006_233032_usb-write.json` (exit0, matching SHA256).
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
