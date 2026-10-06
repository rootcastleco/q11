"""Bounded, read-only filesystem evidence parsing, including CLI failures."""
from __future__ import annotations

import importlib.util
import json
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tools/analysis/ext4_super.py'
spec = importlib.util.spec_from_file_location('ext_super', SCRIPT)
assert spec and spec.loader
ext = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ext)


def fixture(mount_count: int = 0) -> bytes:
    data = bytearray(2048)
    struct.pack_into('<H', data, 1024 + 56, 0xef53)
    struct.pack_into('<I', data, 1024 + 24, 2)
    struct.pack_into('<H', data, 1024 + 52, mount_count)
    data[1024 + 104:1024 + 120] = bytes(range(16))
    data[1024 + 120:1024 + 127] = b'Q11ROOT'
    return bytes(data)


class ExtSuperTests(unittest.TestCase):
    def test_realistic_counter_comparison_and_no_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = root / 'original.img'
            current = root / 'current.img'
            output = root / 'report.json'
            baseline.write_bytes(bytes(512) + fixture())
            current.write_bytes(bytes(512) + fixture(1))
            before = current.read_bytes()
            command = [sys.executable, str(SCRIPT), str(current), '--baseline', str(baseline),
                       '--partition-offset', '512', '--output', str(output)]
            run = subprocess.run(command, capture_output=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stderr)
            report = json.loads(output.read_text())
            self.assertEqual(report['changed_fields']['mount_count'], {'before': 0, 'after': 1})
            self.assertEqual(report['superblock']['label'], 'Q11ROOT')
            self.assertEqual(report['superblock']['block_size'], 4096)
            self.assertEqual(current.read_bytes(), before)
            repeat = subprocess.run(command, capture_output=True, timeout=20)
            self.assertNotEqual(repeat.returncode, 0)

    def test_invalid_short_missing_and_mismatched_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            current = root / 'current.img'
            current.write_bytes(fixture())
            for offset in (-512, 1, 8192 * 1024**2 + 512):
                with self.assertRaises(ValueError):
                    ext.read_super(current, offset)
            with self.assertRaises(ValueError):
                ext.inspect_super(bytes(1024))
            current.write_bytes(bytes(2047))
            with self.assertRaises(ValueError):
                ext.read_super(current, 0)
            missing = subprocess.run([sys.executable, str(SCRIPT), str(root / 'missing')],
                                     capture_output=True, timeout=20)
            self.assertNotEqual(missing.returncode, 0)
            self.assertEqual(json.loads(missing.stderr)['result'], 'error')
            current.write_bytes(fixture())
            bad = bytearray(fixture())
            bad[1024 + 104] ^= 1
            baseline = root / 'different.img'
            baseline.write_bytes(bad)
            mismatch = subprocess.run([sys.executable, str(SCRIPT), str(current), '--baseline', str(baseline)],
                                      capture_output=True, timeout=20)
            self.assertNotEqual(mismatch.returncode, 0)


if __name__ == '__main__':
    unittest.main()
