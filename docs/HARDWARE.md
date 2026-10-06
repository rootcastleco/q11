# Hardware evidence and address map

This is not a complete reconstructed Q11 DTS. Log-confirmed addresses and public
SoC source candidates have distinct status. Reference log is `boot_01.clean.txt`.

| Function | Address / detail | Status and source |
|---|---|---|
| CPU | Hi3798MV100, four Cortex-A7, ARMv7/VFP; 1 GiB RAM | CONFIRMED L3, L21, L50–58 |
| UART0 | 0xf8b00000; Linux IRQ 81, ttyAMA0, 115200 | CONFIRMED L63 |
| UART1 / UART2 | 0xf8006000 / 0xf8b02000 | CONFIRMED L65–66 |
| NAND | hinfc610, Toshiba 256 MiB, 2 KiB + 64 B OOB, 128 KiB erase, ECC 4/512 | CONFIRMED L111–116 |
| NAND registers / buffer | 0xf9810000 / 0xfe000000 | LIKELY Q11: public candidate DTS, not printed in stock log |
| EHCI | 0xf9890000 IRQ98, 0xf9930000 IRQ94 | CONFIRMED L237–246 |
| OHCI | 0xf9880000 IRQ99, 0xf9920000 IRQ95 | CONFIRMED L249–258 |
| xHCI | 0xf98a0000 IRQ101 | CONFIRMED L260–267 |
| Ethernet | hieth/himii, port0, PHY address1, Generic PHY | CONFIRMED L137–138; link, IP, routing and MAC source UNKNOWN |
| Ethernet registers | 0xf9840000 | LIKELY Q11: candidate DTS |
| SD / MMC | 0xf9820000 / 0xf9830000; himciv200 | CONFIRMED probe addresses L161–163; no media detected |
| GIC distributor / CPU | 0xf8a01000 / 0xf8a02000 | LIKELY Q11: candidate DTS |
| Timer / local timers | 0xf8a29000 / 0xf8a2a000, 0xf8a2a020, 0xf8a2b000, 0xf8a2b020 | LIKELY Q11: candidate DTS; 24 MHz clock CONFIRMED L85 |
| GPIO | PL061, banks at 0xf8b20000..0xf8b24000, 0xf8004000, 0xf8b26000 | LIKELY Q11: candidate DTS; slot card-detect/pinmux UNKNOWN |
| HDMI / framebuffer | hi_hdmi.ko / hi_fb.ko loaded | CONFIRMED L216, L224; MMIO, fb0, display initialization UNKNOWN |

Primary source: [Hi3798MV100 candidate DTS](https://github.com/glinuz/hi3798mv100/blob/12aa0504880d518a9fa15800d4f7a305a1f94dc6/HiSTBLinuxV100R005C00SPC041B020/source/kernel/linux-3.18.y/arch/arm/boot/dts/hi3798mv100.dts).
It describes PHY address **2**, whereas Q11 reports **1**. This concrete mismatch
prevents treating the generic DTS as a drop-in board description. GIC SPI numbers
in DTS are not Linux IRQ numbers; e.g. UART SPI49 plus32 matches IRQ81.

## DTB location

CONFIRMED: stock Linux receives a Device Tree. UNKNOWN: separate loader argument,
kernel-partition wrapper, appended zImage, embedded blob, or loader fixups.
The public candidate enables `CONFIG_ARM_APPENDED_DTB` and creates `zImage-dtb`.
That establishes a candidate packaging convention, not the Q11's actual packaging.

```powershell
python tools/dtb/find_dtb.py artifacts/kernel.bin --output artifacts/dtb-scan.json
python tools/dtb/extract_dtb.py artifacts/kernel.bin 0xOFFSET artifacts/q11.dtb --dry-run
```

Replace `0xOFFSET` with a valid candidate from the first command. Remove `--dry-run`
to create a new DTB file, then use `dtc -I dtb -O dts` on Linux. The scanner validates
v17 header/block bounds, reservations and structure/property tokens. Compressed
kernel payloads require separate decompression; an empty scan is not proof that
DTB is absent. No UART or memory access is performed.

## Card slot

The driver is present and probes **before** the root mount. A card inserted with
power removed is the next way to establish wiring/card detection. No card in the
previous log does not prove absent eMMC or a disconnected slot. Photographing the
Q11 PCB and inspecting card-detect/power routing would be necessary only if a known
working card still fails. The supplied photos show the CH341A adapter, not the Q11
PCB; they cannot establish SD wiring or BootROM straps.

## Graphics after shell, storage and network

Do not start the IPTV middleware to get graphics. Preserve a matching vendor module
set only if obtainable without CA material; determine dependency ordering and
required userspace initialization. Check `/sys/class/graphics`, `/dev/fb0`, `fbset`
and HDMI hotplug locally. Driver loading alone does not establish a usable frame
buffer. No stock DRM/Mali acceleration is established. Once fb0 accepts normal
Linux framebuffer ioctls, Xorg fbdev + LXDE is a candidate. Measure resident memory
and idle CPU before adding a desktop. Proprietary HIGO's glibc userspace ABI is one
reason to start with Debian rather than musl; its actual reuse remains UNKNOWN.
