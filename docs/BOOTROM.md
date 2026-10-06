# BootROM and recovery: mechanisms versus evidence

**UNKNOWN on this Q11:** ROM download entry state, electrical strap/pad function, native USB
device capability/VID/PID, acceptance of a RAM image, secure-boot policy and DDR
initialization blob. There is no confirmed board-specific RAM bootstrap recipe.
The stock log exposes USB **host** controllers, not a native USB download interface.

**CONFIRMED in public implementation:** [HiLoot](https://github.com/histb-mainline/hiloot/tree/56b598ab7fd62a2b7ddce6e7b3770d93c40f4801)
boots HiSTB images through a **USB-to-UART adapter**. This must not be confused
with native USB BootROM enumeration. Its serial protocol uses framed requests,
including HEAD/DATA/TAIL, with address/length and checksum handling. Its README
requires an applicable boot image and sometimes board chip properties. Those
requirements are not satisfied by the current repository.

Public SDK fastboot has conditional `CONFIG_USB_BOOTSTRAP` and
`CONFIG_USB_HOST_BOOTSTRAP` paths. Their presence in source does not prove those
options are enabled in Q11, or that a consumer USB-upgrade path is RAM-only.
HiSilicon "fastboot" partition naming does not establish Android fastboot protocol.
No confirmed Huawei Q11 official recovery package is locally available.

## Newly supplied MV100 pin-short sources (2026-10-07)

The user's two URLs provide useful **community evidence**, not Q11-specific
validation. [Histb discussion, gbsadmin's first-hand YMB0310-CW report](https://bbs.histb.com/d/501/23)
corrects the informal "CPU1–2" naming to physical107–108. Its
[annotated source photograph](https://raw.histb.eu.org/histb/pic/master/2022/09/03/91240607.jpg)
shows `Hi3798 MRQCV101000` with visible leads and identifies the two upper pins
on the right edge in that photograph. It also marks pin1 at the opposite corner.
This is not a Q11 board photograph or an official electrical pinout. The actual
[Q11 photographs](../resimler/README.md), supplied afterward, show U1 marked
`Hi3798 MRBCV100MD2`, no accessible gull-wing leads and lettered/numbered PCB
coordinate labels consistent with BGA. Thus the other-board “upper-right two
legs” instruction cannot be transferred to this Q11. Electrical ball/net mapping
remains UNKNOWN; USB-port/shield orientation cannot supply that mapping.

[Histb-mainline bootstrap documentation](https://histb-mainline.github.io/software/bootrom/bootstrap.html)
describes USB_BOOT pulled to GND selecting a USB **host-storage** boot path:
FAT32 root `fastboot.bin`. It separately describes fallback when no internal
storage is found. The supplied pin-short report does not establish whether107
or108 is USB_BOOT/GND on this package; do not describe the short as NAND data
corruption without a pinout/measurement. No special native USB device socket or
PC-visible VID/PID is established by this host-storage mechanism.

The [Histb USB OpenWrt procedure](https://bbs.histb.com/d/501/1) requires a matching
board `reg` loader plus bootargs/kernel on a FAT boot partition and ext4 root on
another partition. Its authors report external boot, but its actual payload has
not been audited here. Our current REI image has one ext4 partition and no FAT
`fastboot.bin`/bootargs/kernel loading set; inserting it does not satisfy this
BootROM recipe. Preserve that already prepared Debian filesystem for now.

**Different payload boundary:** the supplied
[Ekoo USB-flash guide](https://ecoo.top/docs/tutorial-basics/usb-flash/) explicitly
performs automatic internal eMMC installation and gives `mmc write.ext4sp` in its
boot command example. It is not a RAM-only procedure; Q11 has raw NAND, not that
eMMC layout. No Ekoo flash package was downloaded, copied to USB or executed.
BootROM entry itself and the subsequent loader's actions must be assessed
separately. Same SoC name is insufficient: the
[vendor-fastboot notes](https://histb-mainline.github.io/software/vendor/fastboot.html)
require board-specific DDR/reg values as well.

The board photographs establish a candidate labelled pad; next evidence is its
electrical identity, then an audited board-compatible, non-writing loader. No
instruction to short the Q11 SoC or upload a package has been issued.

## Actual Q11 pad candidate: J15 `GND BOOT`

[20261007_003643.jpg](../resimler/20261007_003643.jpg) clearly shows an unpopulated
two-hole J15 footprint between the USB-A sockets, beside R40, with `GND BOOT`
silkscreen. **CONFIRMED:** location and printed label. **LIKELY:** intended
ground/boot strap. **UNKNOWN:** ground continuity, boot-input routing, pull network,
voltage, active level, sampling timing and resulting ROM/loader behavior.

With the text upright in that image, `GND` is above the left hole and `BOOT` above
the right. This is a visual locator only. No resistance/continuity measurement has
established either net. The owner subsequently reported briefly bridging/releasing
J15; a later receive-only capture showed stock middleware, but did not record the
entry/power-on interval. See the [trial record](../Q11_RECORD.md#owner-reported-j15-trial).
This does not establish the strap's selected mode. The label alone is insufficient to bridge
J15 or promise USB/UART download entry. This candidate is also separate from J9's
`VCC DM DP GND` footprint, whose USB role/routing are unmeasured.

Some photos show attached DC/UART leads. Their power state is not established by
the images; disconnect all power and connected peripherals before resistance or
continuity work. The current ext4-only USB still lacks the FAT/loader files for
the documented host-storage bootstrap. Entry testing is not useful as a blind
automatic-flash attempt.

## Stock recovery candidate after USB detection

[Q11 owner callagne, 2025-08-11, post29](https://forum.benchmark.rs/threads/huawei-stb-q11.486226/#post-7524681)
reports remote OK at startup led to recovery and UART root access. [Owner g-man,
2026-06-12, post32](https://forum.benchmark.rs/threads/huawei-stb-q11.486226/page-2)
reports failure with OK on another Q11. These primary accounts are not proof for
our firmware. Our one Xiaomi IR trial on 2026-10-07 reached the stock kernel and
IPTV application; the user subsequently connected HDMI and reported no recovery.
UART saw application key events, no alternate loader or console. This records a
failed entry trial, not proof that every recovery mechanism is disabled. The
direct LAN remained active in this actual trial (DHCP ACK during boot), despite
the isolation instructions; no router/update service was present. No package,
reset selection or NAND command was involved. See [BRINGUP](BRINGUP.md).

The pinned [HiLoot implementation](https://github.com/histb-mainline/hiloot/blob/56b598ab7fd62a2b7ddce6e7b3770d93c40f4801/hiloot.py)
was reviewed for an identification-only path: TYPE/BOARD query methods exist, but
CLI has no chip-info-only mode; it requires a boot-image argument even for `--break`.
`wait_boot` first requires `Bootrom start\r\n`; `connect` then sends a zero-length
HEAD before queries. No captured Q11 log contains that greeting. `--timeout`
bounds frame communication, not the initial indefinite boot wait. Thus the
unmodified CLI is not a bounded identification experiment for current evidence.
No binary protocol packet or loader image was transmitted in this session.

| Question | Current status |
|---|---|
| Can ROM be interrupted by the documented binary bootstrap protocol? | UNKNOWN; different mechanism from the completed UART key tests |
| Does Q11 require a strap, failed boot medium or button? | UNKNOWN; J15 `GND BOOT` is a photographed candidate, electrically unverified |
| Does an official loader start arbitrary userspace? | UNKNOWN; inspect loader package/startup scripts when available |
| Is arbitrary unsigned RAM code permitted? | UNKNOWN; if authorized tool reports rejection, record it and stop that path |
| Do OTP/hi_advca/Verimatrix messages prove ROM signature enforcement? | No. Those are indicators; the actual enforcement state is UNKNOWN |
| Native Q11 ROM USB VID/PID | UNKNOWN; do not invent a HiSilicon ID |
| Adapter IDs | CH341 UART 1a86:5523; programmer 1a86:5512, CONFIRMED historical inventory |

## Safe sequence

1. Establish ordinary removable-storage enumeration using [BRINGUP](BRINGUP.md).
2. Obtain an applicable, legitimate Q11 image or stock-rootfs artifact if available;
   inspect it offline using the image and DTB tools. No full-NAND backup project is
   required. DDR parameters from an unrelated eMMC STB are not a substitute.
3. Review/pin the complete bootstrap implementation and confirm it performs only
   the intended RAM transfer. A read-only chip identification handshake may be a
   later bounded experiment, but is not implemented/authorized as a blind upload.
4. With an established entry mechanism and compatible loader, load into validated
   free RAM and preserve firmware's signature checks. Do not select erase/burn or
   an updater that automatically writes flash.
5. Boot kernel + initramfs with temporary final arguments; capture serial evidence.

No NAND pin shorts, guessed test pads, OTP operations, key extraction, signature
patches or full firmware flashing are included. If secure boot requires signed
images, use vendor-authorized signed loading/maintenance or document the blocker.

---

Maintained by [Batuhan Ayrıbaş](https://batuhanayribas.com) · Q11 Linux Bring-up
