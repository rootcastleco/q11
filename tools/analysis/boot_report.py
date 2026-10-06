#!/usr/bin/env python3
"""Analyze every captured boot log and timing file, without probing hardware."""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lab import cli, emit, metadata, read_file, sha256

PATTERNS = {
    "kernel": r"Linux version ", "cmdline": r"Kernel command line:",
    "memory": r"Memory: |cma: Reserved|DSP run memory",
    "root_mount": r"VFS: Mounted root|rootfs image is not initramfs|RAMDISK: squashfs",
    "mmc": r"himciv200|mmcblk|sdhci", "usb_storage": r"usb-storage|sd[a-z]:|sd[a-z][0-9]|SCSI.*disk",
    "startup": r"\[RCS\]|set_mount|hmw_mount|loader\.rc|local\.rc|CMD_RUNLEVEL",
    "shell": r"telnetd:|passwdTelnet|release STBBOX|login:",
    "ethernet": r"libphy:|hieth:", "graphics": r"Load hi_fb|Load hi_hdmi|HIGO Version|HDMI event",
}


def sanitize(text: str) -> str:
    text = re.sub(r"\b(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b", "<MAC redacted>", text)
    text = re.sub(r"(?i)((?:serial|dieid|deviceid|macaddr)\s*[=:]\s*)\S+", r"\1<redacted>", text)
    return text


def analyze(data: bytes) -> dict[str, Any]:
    lines = data.decode("utf-8", errors="replace").replace("\r", "").replace("\0", "").splitlines()
    evidence = {key: [{"line": i, "text": sanitize(line), "status": "CONFIRMED"}
                      for i, line in enumerate(lines, 1) if re.search(pattern, line)]
                for key, pattern in PATTERNS.items()}
    cmdlines = [line.split("Kernel command line:", 1)[1].strip() for line in lines if "Kernel command line:" in line]
    roots = [re.findall(r"(?:^|\s)root=(\S+)", line) for line in cmdlines]
    partitions = [{"name": name, "start": int(start, 16), "end_exclusive": int(end, 16)}
                  for start, end, name in re.findall(r'0x([0-9a-f]+)-0x([0-9a-f]+)\s*:\s*"([^"]+)"', "\n".join(lines))]
    return {"bytes": len(data), "sha256": sha256(data), "boot_marker": "Booting Linux" in "\n".join(lines),
            "evidence": evidence, "root_arguments": roots,
            "effective_root_candidates": [values[-1] if values else None for values in roots],
            "partitions": partitions}


def timing(data: bytes, raw_size: int) -> dict[str, Any]:
    rows: list[tuple[int, int, int]] = []
    expected = 0
    last_ms = -1
    for i, line in enumerate(data.decode("utf-8").splitlines(), 1):
        if not line or line.startswith("#") or line == "ms\toffset\tbytes":
            continue
        fields = line.split("\t")
        if len(fields) != 3:
            raise ValueError(f"timing line {i}: expected three columns")
        ms, offset, count = map(int, fields)
        if ms < last_ms or offset != expected or count <= 0 or offset + count > raw_size:
            raise ValueError(f"timing line {i}: noncontiguous/out-of-range offset or invalid time/count")
        rows.append((ms, offset, count))
        expected += count
        last_ms = ms
    if not rows or expected != raw_size:
        raise ValueError("timing rows must cover the entire raw capture")
    return {"chunks": len(rows), "first_ms": rows[0][0], "last_ms": rows[-1][0],
            "initial_gap_ms": rows[1][0] - rows[0][0] if len(rows) > 1 else None,
            "note": "Gap is between receive chunks; power-on interpretation needs capture evidence."}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", type=Path)
    parser.add_argument("--output", type=Path, help="new JSON file; existing files are never overwritten")
    args = parser.parse_args()
    if not args.logs.is_dir():
        raise ValueError(f"missing logs directory: {args.logs}")
    report: dict[str, Any] = {}
    for path in sorted(args.logs.iterdir()):
        if path.suffix not in (".log", ".txt") or path.name == "HASHES.txt" or path.name.startswith(("experiment_", "build_")):
            continue
        data = read_file(path)
        item = analyze(data)
        tsv = Path(str(path) + ".timing.tsv")
        if tsv.exists():
            item["timing"] = timing(read_file(tsv), len(data))
        report[path.name] = item
    if not report:
        raise ValueError("no captured logs found")
    emit({**metadata("boot-report"), "captures": report, "result": "ok", "exit_code": 0}, args.output)


if __name__ == "__main__":
    cli(main)
