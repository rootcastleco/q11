"""Offline success, malformed-input and missing-file coverage for lab tools."""
from __future__ import annotations

import gzip
import importlib.util
import json
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "tools"), str(ROOT / "tools/dtb")]


def module(name: str, relative: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    assert spec and spec.loader
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


boot = module("boot_report", "tools/analysis/boot_report.py")
fdt = module("find_dtb", "tools/dtb/find_dtb.py")
stock = module("stock_image", "tools/analysis/stock_image.py")
audit = module("audit_rootfs", "tools/analysis/audit_rootfs.py")
initramfs = module("build_initramfs", "tools/rootfs/build_initramfs.py")
disk = module("make_disk_image", "tools/rootfs/make_disk_image.py")
from lab import read_file, sha256


def fdt_fixture() -> bytes:
    return struct.pack(">10I", 0xd00dfeed, 72, 56, 72, 40, 17, 16, 0, 0, 16) + bytes(16) + struct.pack(">4I", 1, 0, 2, 9)


def elf_fixture() -> bytes:
    data = bytearray(84)
    data[:7] = b"\x7fELF\x01\x01\x01"
    struct.pack_into("<HH", data, 16, 2, 40)
    struct.pack_into("<I", data, 28, 52)
    struct.pack_into("<HH", data, 42, 32, 1)
    struct.pack_into("<I", data, 52, 1)
    return bytes(data)


def squash_fixture() -> bytes:
    data = bytearray(96)
    struct.pack_into("<5I6H", data, 0, 0x73717368, 1, 0, 4096, 0, 1, 12, 0, 1, 4, 0)
    struct.pack_into("<Q", data, 40, 96)
    return bytes(data)


def unpack_newc(data: bytes) -> dict:
    result = {}
    pos = 0
    while True:
        assert data[pos:pos + 6] == b"070701"
        values = [int(data[pos + 6 + i * 8:pos + 14 + i * 8], 16) for i in range(13)]
        start = pos + 110
        name = data[start:start + values[11] - 1].decode()
        payload = (start + values[11] + 3) & ~3
        if name == "TRAILER!!!":
            return result
        result[name] = values, data[payload:payload + values[6]]
        pos = (payload + values[6] + 3) & ~3


class LabTests(unittest.TestCase):
    def test_captured_boot(self):
        item = boot.analyze((ROOT / "logs/boot_01.clean.txt").read_bytes())
        self.assertEqual(item["root_arguments"], [["/dev/romblock14", "/dev/ram"]])
        self.assertEqual(len(item["partitions"]), 18)
        self.assertEqual(item["partitions"][-1]["end_exclusive"], 256 * 1024 * 1024)
        mmc = [value["text"] for value in item["evidence"]["mmc"]]
        self.assertIn('f9820000.himciv200.SD: eMMC/MMC/SD Device NOT detected!', mmc)
        self.assertIn('f9830000.himciv200.MMC: eMMC/MMC/SD Device NOT detected!', mmc)

    def test_partial_capture_not_boot(self):
        self.assertFalse(boot.analyze((ROOT / "logs/boot_02.log").read_bytes())["boot_marker"])

    def test_all_captured_timings(self):
        for path in (ROOT / "logs").glob("*.timing.tsv"):
            if path.name.startswith("experiment_"):
                continue  # Generated missing-device tests are not original capture fixtures.
            item = boot.timing(path.read_bytes(), Path(str(path).removesuffix(".timing.tsv")).stat().st_size)
            self.assertGreater(item["chunks"], 0)
        first = boot.timing((ROOT / "logs/boot_01.log.timing.tsv").read_bytes(), 137868)
        self.assertEqual(first["initial_gap_ms"], 16802)

    def test_bad_timing(self):
        for value in (b"bad", b"0\t1\t1", b"0\t0\t2", b"0\t0\t1\n-1\t1\t1"):
            with self.assertRaises(ValueError):
                boot.timing(value, 1)

    def test_redaction(self):
        self.assertNotIn("01:02:03:04:05:06", boot.sanitize("MAC=01:02:03:04:05:06"))

    def test_fdt_offset(self):
        valid, rejected = fdt.find(b"head" + fdt_fixture())
        self.assertEqual(valid[0]["offset"], 4)
        self.assertFalse(rejected)

    def test_fdt_invalid(self):
        for value in (b"", fdt_fixture()[:-1], fdt_fixture()[:56] + struct.pack(">4I", 1, 0, 9, 9)):
            with self.assertRaises(ValueError):
                fdt.validate_fdt(value)

    def test_fdt_false_positive(self):
        valid, rejected = fdt.find(b"\xd0\x0d\xfe\xed" + bytes(40))
        self.assertFalse(valid)
        self.assertEqual(len(rejected), 1)

    def test_squash_offset(self):
        self.assertEqual(stock.squashfs(bytes(0x110) + squash_fixture())[0]["offset"], 0x110)
        self.assertFalse(stock.squashfs(b"hsqs" + bytes(92)))
        self.assertFalse(stock.squashfs(squash_fixture()[:-1]))

    def test_env_crc_and_redaction(self):
        payload = b"bootargs=root=/dev/ram\0password=do-not-output\0\0" + bytes(16)
        fixture = struct.pack("<I", zlib.crc32(payload)) + payload
        self.assertEqual(stock.environment(fixture)[0]["keys"], ["bootargs", "password"])
        self.assertNotIn("do-not-output", json.dumps(stock.environment(fixture)))
        self.assertFalse(stock.environment(fixture[:-1]))

    def test_static_elf_reject_dynamic_wrong_arch(self):
        initramfs.validate_busybox(elf_fixture())
        for offset, number in ((18, 62), (52, 3), (52, 2)):
            value = bytearray(elf_fixture())
            struct.pack_into("<H" if offset == 18 else "<I", value, offset, number)
            with self.assertRaises(ValueError):
                initramfs.validate_busybox(value)
        with self.assertRaises(ValueError):
            initramfs.validate_busybox(b"not an executable")

    def test_archive_reproducible_and_console_nodes(self):
        one = initramfs.build(elf_fixture(), b"#!/bin/sh\n", elf_fixture())
        self.assertEqual(one, initramfs.build(elf_fixture(), b"#!/bin/sh\n", elf_fixture()))
        files = unpack_newc(gzip.decompress(one))
        self.assertEqual(files["dev/console"][0][9:11], [5, 1])
        self.assertTrue(stat.S_ISCHR(files["dev/console"][0][1]))
        self.assertEqual(files["bin/sh"][1], b"busybox")
        self.assertEqual(files["init"][0][1] & 0o777, 0o755)
        self.assertIn("bin/q11-root-probe", files)

    def test_archive_no_traversal(self):
        with self.assertRaises(ValueError):
            initramfs.build(elf_fixture(), b"init", elf_fixture(), {"../bad": b"x"})

    def test_mbr(self):
        value = disk.mbr(256 * 1024 * 1024)
        self.assertEqual(value[510:], b"\x55\xaa")
        self.assertEqual(struct.unpack_from("<I", value, 454)[0], 2048)
        for size in (0, 1, 256 * 1024 * 1024 + 1, 2**42):
            with self.assertRaises(ValueError):
                disk.mbr(size)

    def test_rootfs_audit_does_not_follow_symlinks(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "etc/init.d").mkdir(parents=True)
            (root / "etc/inittab").write_text("ttyAMA0::respawn:/sbin/getty\n")
            self.assertEqual(audit.audit(root)["startup_files"][0]["matches"][0]["terms"], ["getty"])
            if sys.platform != "win32":
                (root / "etc/init.d/rcS").symlink_to("/etc/passwd")
                self.assertEqual(len(audit.audit(root)["startup_files"]), 1)
        with self.assertRaises((ValueError, OSError)):
            audit.audit(Path("no-such-rootfs"))

    def test_bounded_read(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "blob"
            path.write_bytes(b"1234")
            self.assertEqual(read_file(path, 4), b"1234")
            with self.assertRaises(ValueError):
                read_file(path, 3)
            with self.assertRaises(ValueError):
                read_file(path.with_name("missing"))


class CliTests(unittest.TestCase):
    def run_tool(self, script: str, *args: str, expected: int = 0):
        process = subprocess.run([sys.executable, str(ROOT / script), *map(str, args)], capture_output=True, text=True, timeout=30)
        self.assertEqual(process.returncode, expected, process.stderr)
        return process

    def test_missing_files_every_python_tool(self):
        cases = [
            ("tools/analysis/boot_report.py", ["does-not-exist"]),
            ("tools/analysis/stock_image.py", ["does-not-exist"]),
            ("tools/analysis/audit_rootfs.py", ["does-not-exist"]),
            ("tools/dtb/find_dtb.py", ["does-not-exist"]),
            ("tools/dtb/extract_dtb.py", ["does-not-exist", "0", "unused"]),
            ("tools/rootfs/build_initramfs.py", ["--busybox", "does-not-exist", "--busybox-sha256", "0"*64, "--root-probe", "missing", "--root-probe-sha256", "0"*64, "--output", "unused"]),
            ("tools/rootfs/make_disk_image.py", ["does-not-exist", "unused"]),
        ]
        for script, args in cases:
            with self.subTest(script=script):
                self.assertEqual(json.loads(self.run_tool(script, *args, expected=2).stderr)["exit_code"], 2)

    def test_fdt_extract_success_invalid_no_overwrite(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "blob"
            output = Path(folder) / "out.dtb"
            path.write_bytes(b"head" + fdt_fixture())
            self.run_tool("tools/dtb/find_dtb.py", path)
            self.run_tool("tools/dtb/extract_dtb.py", path, "4", output)
            self.assertEqual(output.read_bytes(), fdt_fixture())
            self.run_tool("tools/dtb/extract_dtb.py", path, "0", output, expected=2)
            self.run_tool("tools/dtb/extract_dtb.py", path, "4", output, expected=2)

    def test_stock_extract_success_invalid(self):
        with tempfile.TemporaryDirectory() as folder:
            path, output = Path(folder) / "blob", Path(folder) / "root.sqfs"
            path.write_bytes(b"header" + squash_fixture())
            self.run_tool("tools/analysis/stock_image.py", path, "--extract-squashfs", output)
            self.assertEqual(output.read_bytes(), squash_fixture())
            path.write_bytes(b"bad")
            self.run_tool("tools/analysis/stock_image.py", path, "--extract-squashfs", output, expected=2)

    def test_initramfs_cli_success_bad_checksum(self):
        with tempfile.TemporaryDirectory() as folder:
            path, output = Path(folder) / "busybox", Path(folder) / "initramfs.gz"
            path.write_bytes(elf_fixture())
            args = ["--busybox", path, "--busybox-sha256", sha256(elf_fixture()), "--root-probe", path, "--root-probe-sha256", sha256(elf_fixture()), "--output", output, "--compression", "gzip"]
            self.run_tool("tools/rootfs/build_initramfs.py", *args)
            self.assertIn("init", unpack_newc(gzip.decompress(output.read_bytes())))
            args[3] = "0"*64
            self.run_tool("tools/rootfs/build_initramfs.py", *args, expected=2)

    def test_report_success_empty_invalid(self):
        self.run_tool("tools/analysis/boot_report.py", ROOT / "logs")
        with tempfile.TemporaryDirectory() as folder:
            self.run_tool("tools/analysis/boot_report.py", folder, expected=2)

    def test_audit_cli(self):
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / "etc").mkdir()
            self.run_tool("tools/analysis/audit_rootfs.py", folder)
            (Path(folder) / "etc").rmdir()
            self.run_tool("tools/analysis/audit_rootfs.py", folder, expected=2)

    def test_disk_image_dryrun_success_invalid(self):
        with tempfile.TemporaryDirectory() as folder:
            path, output = Path(folder) / "ext4", Path(folder) / "disk.img"
            with path.open("wb") as stream:
                stream.truncate(256 * 1024 * 1024)
                stream.seek(1080)
                stream.write(b"\x53\xef")
            self.run_tool("tools/rootfs/make_disk_image.py", path, output, "--dry-run")
            self.assertFalse(output.exists())
            path.write_bytes(b"bad")
            self.run_tool("tools/rootfs/make_disk_image.py", path, output, expected=2)


if __name__ == "__main__":
    unittest.main()
