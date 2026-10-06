#!/usr/bin/env python3
"""Wrap an ext4 file in a new MBR disk image (1 MiB partition alignment)."""
from __future__ import annotations

import argparse
import hashlib
import os
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lab import cli, emit, metadata


def mbr(size: int) -> bytes:
    if size < 256 * 1024 * 1024 or size % 512 or size // 512 + 2048 > 0xffffffff:
        raise ValueError("ext4 size must be sector aligned, >=256 MiB, and fit MBR")
    result = bytearray(512)
    result[446:462] = struct.pack("<B3sB3sII", 0, b"\xfe\xff\xff", 0x83, b"\xfe\xff\xff", 2048, size // 512)
    result[510:512] = b"\x55\xaa"
    return bytes(result)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ext4", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if not args.ext4.is_file() or args.ext4.is_symlink():
        raise ValueError("ext4 must be a regular file")
    size = args.ext4.stat().st_size
    header = mbr(size)
    with args.ext4.open("rb") as source:
        source.seek(1024 + 56)
        if source.read(2) != b"\x53\xef":
            raise ValueError("missing ext4 superblock magic")
    if args.output.exists() or args.output.is_symlink():
        raise ValueError("output exists")
    digest = hashlib.sha256()
    if not args.dry_run:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        # Sparse prefix consists of zero bytes; include them in checksum.
        prefix = header + bytes(1024 * 1024 - 512)
        digest.update(prefix)
        with args.output.open("xb") as output, args.ext4.open("rb") as source:
            output.write(prefix)
            remaining = size
            while remaining:
                chunk = source.read(min(1024 * 1024, remaining))
                if not chunk:
                    raise ValueError("source truncated during copy")
                output.write(chunk)
                digest.update(chunk)
                remaining -= len(chunk)
            if source.read(1):
                raise ValueError("source grew during copy")
            output.flush()
            os.fsync(output.fileno())
        with Path(str(args.output) + ".sha256").open("x", encoding="ascii") as stream:
            stream.write(f"{digest.hexdigest()}  {args.output.name}\n")
    emit({**metadata("make-disk-image"), "partition_start_sector": 2048,
          "partition_bytes": size, "disk_image_bytes": size + 1024 * 1024,
          "image_sha256": digest.hexdigest() if not args.dry_run else None,
          "dry_run": args.dry_run, "result": "ok", "exit_code": 0})


if __name__ == "__main__":
    cli(main)
