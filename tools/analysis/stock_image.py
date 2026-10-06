#!/usr/bin/env python3
"""Locate validated SquashFS v4 payloads and inspect CRC32 environment candidates."""
from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lab import cli, emit, metadata, read_file, sha256


def squashfs(data: bytes) -> list[dict[str, Any]]:
    found: list[dict[str, Any]] = []
    pos = 0
    while (pos := data.find(b"hsqs", pos)) >= 0:
        if len(found) >= 64:
            raise ValueError("too many SquashFS payloads")
        if pos + 96 <= len(data):
            _, inodes, _, block_size, _, compression, block_log, _, _, major, minor = struct.unpack_from("<5I6H", data, pos)
            used = struct.unpack_from("<Q", data, pos + 40)[0]
            if (major == 4 and minor == 0 and inodes > 0 and 1 <= compression <= 6
                    and 12 <= block_log <= 20 and block_size == 1 << block_log
                    and 96 <= used <= len(data) - pos):
                found.append({"offset": pos, "offset_hex": hex(pos), "size": used,
                              "compression_id": compression, "sha256": sha256(data[pos:pos + used])})
        pos += 4
    return found


def environment(data: bytes) -> list[dict[str, Any]]:
    results = []
    if len(data) < 8:
        return results
    for header in (4, 5):
        for endian, label in (("<", "little"), (">", "big")):
            expected = struct.unpack_from(endian + "I", data)[0]
            if expected != zlib.crc32(data[header:]) & 0xffffffff:
                continue
            end = data.find(b"\0\0", header)
            if end < 0:
                continue
            items = data[header:end].split(b"\0")
            if not all(b"=" in item for item in items):
                continue
            # Values may contain device identifiers or credentials; report names only.
            keys = sorted(item.split(b"=", 1)[0].decode("ascii", errors="replace") for item in items)
            results.append({"header_bytes": header, "crc_endian": label, "keys": keys,
                            "status": "CONFIRMED", "note": "CRC matches this file length; device selection semantics UNKNOWN"})
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--extract-squashfs", type=Path, help="write a new file; requires exactly one payload")
    args = parser.parse_args()
    data = read_file(args.image)
    matches = squashfs(data)
    if args.extract_squashfs:
        if len(matches) != 1:
            raise ValueError("extraction requires exactly one valid SquashFS payload")
        match = matches[0]
        args.extract_squashfs.parent.mkdir(parents=True, exist_ok=True)
        with args.extract_squashfs.open("xb") as stream:
            stream.write(data[match["offset"]:match["offset"] + match["size"]])
    emit({**metadata("stock-image"), "input_sha256": sha256(data), "squashfs": matches,
          "environment_candidates": environment(data), "result": "ok", "exit_code": 0,
          "header": "Bytes before detected payload remain uninterpreted; no signature inference."}, args.output)


if __name__ == "__main__":
    cli(main)
