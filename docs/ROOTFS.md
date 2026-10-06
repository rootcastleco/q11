# External Debian armhf and initramfs

Host tooling produces a Debian **bookworm armhf** rootfs with SysV init, Bash,
SSH, ifupdown/DHCP, iproute2/ping, e2fsprogs, kmod, udev, procps and static BusyBox.
This is a userspace candidate for the existing kernel; it does not install a Debian
kernel or change Q11 boot firmware. Kernel3.18 compatibility must be tested on Q11:
QEMU user emulation uses the host kernel and cannot establish that compatibility.

Root's password is locked. SSH root/password login is disabled. `developer` accepts
only the supplied public key. Serial ttyAMA0 **automatically logs in as root** for
local lab administration; physical console access therefore grants root. SSH host
keys are generated per installation by q11-firstboot before SSH startup. No private
keys/passwords are committed. DNS comes from DHCP via isc-dhcp-client hooks; verify
`/etc/resolv.conf`, routes and name resolution during hardware bring-up.

## Build on Linux or WSL

Use a Linux filesystem for the rootfs: Windows drive mounts cannot reliably preserve
device nodes, owners and Unix links. Dependencies on an Ubuntu build host:

```bash
sudo apt-get install debootstrap debian-archive-keyring qemu-user-static binfmt-support e2fsprogs gcc-arm-linux-gnueabihf cpio squashfs-tools shellcheck
```

Enable an installed qemu-arm binfmt handler before a cross-build. On Ubuntu 24.04
WSL, when systemd has not registered it, the installed package's exact config can
be registered as root:

```bash
test -e /proc/sys/fs/binfmt_misc/qemu-arm || sudo sh -c 'cat /usr/lib/binfmt.d/qemu-arm.conf > /proc/sys/fs/binfmt_misc/register'
```

The builder checks the handler before starting. `configure-rootfs.sh` re-registers
the installed qemu-arm config if a WSL startup has reset the shared handler. Native
armv7 hosts do not require binfmt. Choose a **new** output path and your SSH public
key. Use `--dry-run` to validate selection without building:

```bash
sudo bash tools/rootfs/build-debian.sh --output /var/tmp/q11-debian --ssh-key /path/to/developer.pub
bash tools/rootfs/make-ext4.sh /var/tmp/q11-debian artifacts/q11-root.ext4 2048
python3 tools/rootfs/make_disk_image.py artifacts/q11-root.ext4 artifacts/q11-usb.img
```

No block device is formatted by these commands. The last command creates an MBR
file with one Linux partition starting at 1 MiB. Images and checksums stay in
gitignored `artifacts/`. Ext4 disables64bit, metadata_csum, metadata_csum_seed and
orphan_file so modern e2fsprogs does not silently select features beyond3.18.
`e2fsck -fn` checks the populated image. Label=Q11ROOT. A 2 GiB image leaves the rest
of a16 GB stick unused initially; it can be rebuilt larger after bring-up.

APT Release signatures/package hashes are checked. Rootfs package versions are
recorded in `.packages.tsv`; live bookworm mirrors change with updates, so this
builder is not claimed byte reproducible across dates. The initramfs is reproducible
for identical input binaries, scripts and modules (fixed archive IDs/timestamps).

Configuration is factored into `configure-rootfs.sh ROOTFS PUBLIC_KEY [--dry-run]`.
It accepts only a rootfs with the builder's `.q11-lab-build` marker, checks armhf,
and executes target shebang scripts through a target shell under QEMU. An interrupted
configuration of a known lab build can be rerun; this is not a live-system installer.

## Build the RAM handoff

Debian's static BusyBox supplies the shell/mount/mdev/switch_root applets, but this
package omits blkid. The dedicated root-probe reads only ext filesystem UUID/label
from removable block devices (or a regular fixture with `--image`). Compile it:

```bash
arm-linux-gnueabihf-gcc -static -Os -Wall -Wextra -Werror -o artifacts/q11-root-probe tools/rootfs/root_probe.c
cp /var/tmp/q11-debian/bin/busybox artifacts/busybox-armhf
q11_bb_hash=$(sha256sum artifacts/busybox-armhf | cut -d' ' -f1)
q11_probe_hash=$(sha256sum artifacts/q11-root-probe | cut -d' ' -f1)
python3 tools/rootfs/build_initramfs.py --busybox artifacts/busybox-armhf --busybox-sha256 "$q11_bb_hash" --root-probe artifacts/q11-root-probe --root-probe-sha256 "$q11_probe_hash" --output artifacts/q11-initramfs.cpio
```

Default is uncompressed newc, avoiding an assumption about stock CONFIG_RD_GZIP.
`--compression gzip` creates deterministic gzip when that support is established.
Builder validates ELF32 little-endian ARM static linkage and both input checksums;
it cannot prove applet behavior without execution. Check required applets under
qemu-arm-static against `APPLETS` in the builder. Do not use a synthetic test ELF
on hardware. Includes console/null nodes so logging works before devtmpfs mounting.

The `/init` script mounts proc/sys/dev, populates devices, loads only explicitly
listed matching storage modules, waits up to30 seconds for LABEL=Q11ROOT, mounts
ext4, moves virtual filesystems and `switch_root`s into `/sbin/init`. `q11.wait=0..120`
changes the bound; `q11.ro=1` uses ro,noload; `q11.rescue=1` opens a RAM rescue shell.
`q11.root=` accepts Q11ROOT label, UUID or explicit sd/mmc partition. It refuses
NAND roots and duplicate labels. Bootloader arguments must contain the intended
final `initrd` and cannot still point at the old stock SquashFS payload.

Module staging, if required: supply `--modules /path/to/stage` with only matching
runtime `lib/modules/<release>/` and depmod metadata, plus repeated `--load-module`
names. Resolve dependencies offline. No stock module binaries are currently
available. Do not force-load, include CA/OTP modules, or assume USB initialized
without the platform host driver. MMC is a preferable direct-root candidate if a
card enumerates because its host driver probes before root mount.

## Write the authorized USB on Windows

`write-usb.ps1` is the only new physical-media writer. It requires administrator
PowerShell, image checksum, **exact disk capacity**, a unique volume label, one
MBR partition, USB bus,512-byte sectors, and a non-system/non-boot disk. It locks
and dismounts that volume, writes only the image extent and checks readback SHA256.
It does not erase unused trailing data or access Q11 NAND. Dry-run performs all
selection/image checks without write handles:

```powershell
$q11Hash = (Get-FileHash artifacts/q11-usb.img -Algorithm SHA256).Hash
pwsh -NoProfile -File tools/rootfs/write-usb.ps1 -Image artifacts/q11-usb.img -Sha256 $q11Hash -TargetLabel REI -ExpectedDiskSizeBytes 15833497600 -DryRun
# In Administrator PowerShell, after the same target validates:
pwsh -NoProfile -File tools/rootfs/write-usb.ps1 -Image artifacts/q11-usb.img -Sha256 $q11Hash -TargetLabel REI -ExpectedDiskSizeBytes 15833497600
```

The capacity above is the observed authorized REI stick in this session, not a
generic Q11 value. Other media requires its own verified capacity/authorization.
`REI` is the historical target volume label, not project branding; do not replace
it with the website name or rename a physical disk as part of documentation edits.
Windows cannot mount ext4 afterwards; decline formatting prompts. Booting custom
Linux remains conditional on [BOOT_FLOW](BOOT_FLOW.md); this is not an auto-upgrade stick.

The Q11 stock USB/ext4 mount was subsequently confirmed; see [BRINGUP](BRINGUP.md).
After that trial the stick's journal recovery flag is set. `read-usb-probe.ps1`
captures only its first 2 MiB with a read-only handle; `ext4_super.py` compares the
superblock against a regular baseline image without mounting/replaying a journal.
These evidence tools do not clean the stick or prove that its Debian init ran.

---

Maintained by [Batuhan Ayrıbaş](https://batuhanayribas.com) · Q11 Linux Bring-up
