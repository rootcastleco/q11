# BootROM and recovery: mechanisms versus evidence

**UNKNOWN on this Q11:** ROM download entry state, straps/buttons/pads, native USB
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

## Stock recovery candidate after USB detection

[Q11 owner callagne, 2025-08-11, post29](https://forum.benchmark.rs/threads/huawei-stb-q11.486226/#post-7524681)
reports remote OK at startup led to recovery and UART root access. [Owner g-man,
2026-06-12, post32](https://forum.benchmark.rs/threads/huawei-stb-q11.486226/page-2)
reports failure with OK on another Q11. These primary accounts are not proof for
our firmware. Our one Xiaomi IR trial on2026-10-07 reached the stock kernel and
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
| Does Q11 require a strap, failed boot medium or button? | UNKNOWN; no pad/shorting instruction is justified |
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
