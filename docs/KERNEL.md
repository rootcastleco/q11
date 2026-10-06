# Kernel source candidates and build tooling

Stock is **3.18.13_s40**, gcc4.9.2, SDK HiSTBLinuxV100R003C00SPC065. No exact source,
stock `.config`, stock DTB or module binaries are in this repository.

| Candidate | Confirmed source properties | Q11 status |
|---|---|---|
| [glinuz/hi3798mv100](https://github.com/glinuz/hi3798mv100/tree/12aa0504880d518a9fa15800d4f7a305a1f94dc6) | HiSTBLinuxV100R005C00SPC041B020; `source/kernel/linux-3.18.y/Makefile` is **3.18.24** | Close platform candidate, not a replacement for `_s40` modules |
| [tegzwn/HiSTBLinuxKernel](https://github.com/tegzwn/HiSTBLinuxKernel/tree/linux-4.4.y) | Makefile **4.4.35** | Later vendor candidate; board/module compatibility UNKNOWN |
| [07bug SPC060](https://github.com/07bug/HiSTBLinuxV100R005C00SPC060) | Repo describes Hi3798MV100/200/300 and kernel4.4.35 | Secondary candidate; no Q11 boot evidence |

Paths relative to the first candidate's `source/kernel/linux-3.18.y`:

| Component | Source/config candidate |
|---|---|
| Platform | `arch/arm/mach-hi3798mx/`, `CONFIG_ARCH_HI3798MX` |
| Defconfig | `arch/arm/configs/hi3798mv100_defconfig` |
| DTS | `arch/arm/boot/dts/hi3798mv100.dts` |
| UART | PL011, `CONFIG_SERIAL_AMBA_PL011` and console |
| NAND | hinfc610 family under `drivers/mtd/nand/`; autogeometry/ECC options |
| Ethernet | hieth/switch fabric, `CONFIG_HIETH_SWITCH_FABRIC` |
| SD/MMC | himciv200, `CONFIG_HIMCIV200_SDIO_SYNOPSYS` |
| USB | EHCI/OHCI generic platform + HiSilicon xHCI options |
| GPIO | ARM PL061 plus vendor GPIO modules |
| Graphics | Linux framebuffer framework; vendor hi_fb/hi_hdmi are SDK modules |

The candidate defconfig has ext2/3/4 and MMC built in, but USB platform host
drivers are modules. Stock log ordering is consistent with that arrangement,
but it does not reveal the stock configuration. Direct USB `rootwait` can wait
forever for a controller whose module is in the filesystem it is trying to mount.

## Required board and build review

* Change the generic DT's PHY address2 to Q11's observed address1 only after
  confirming driver/DT binding semantics and the actual board DTB. Clock/pinmux,
  MAC provenance, SD card-detect and any bootloader fixups still require comparison.
* Replace the candidate default `mem=128M` with the observed 1 GiB setting. The
  bringup fragment supplies `mem=1G console=ttyAMA0,115200`, without reducing MMZ/DSP.
* Build storage host, SCSI disk, ext4, MMC, PL011, initrd/newc and devtmpfs into the
  kernel for standalone root mounting, or supply matching modules in initramfs.
* Start with a compatible vendor ARM EABI/hard-float compiler near gcc4.9.2. Modern
  GCC may require separate host/compiler compatibility patches; none have been
  verified. Modules from 3.18.13_s40 must not be force-loaded into 3.18.24/4.4.35.

## Build command

Keep the large source checkout outside this repository; pin the first candidate
to the commit above. Pass its kernel subdirectory, a new output directory, and a
compiler prefix explicitly:

```bash
bash tools/kernel/build.sh /path/to/sdk/source/kernel/linux-3.18.y /var/tmp/q11-kernel arm-hisiv200-linux- --dry-run
bash tools/kernel/build.sh /path/to/sdk/source/kernel/linux-3.18.y /var/tmp/q11-kernel arm-hisiv200-linux-
```

`build.sh` validates paths and dependencies, merges `bringup.config`, checks that
every required setting survives `olddefconfig`, bounds each operation, records
compiler/source provenance, and builds zImage, zImage-dtb, dtbs and modules. It
does not fetch source, pack proprietary headers, generate DDR firmware or flash.
`Q11_JOBS` accepts1..32, default4. Outputs include `.config`, `build.log`,
`arch/arm/boot/zImage`, `zImage-dtb`, DTS-derived DTBs, staged modules and checksums.

**Validation:** dry-run/failure checks and shell static checks are host tests.
No complete kernel compilation or hardware boot is claimed. Missing compatible
vendor toolchain, Q11 DTB, matched media modules and RAM loading control remain
blockers to a reviewable hardware kernel candidate. Exact NAND support need not
be exercised for an external-root RAM boot.
