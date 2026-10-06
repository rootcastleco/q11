#!/usr/bin/env python3
"""Find structurally valid uncompressed FDT blobs in a regular file."""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lab import cli, emit, metadata, read_file, sha256

MAGIC = b"\xd0\x0d\xfe\xed"


def validate_fdt(data: bytes, offset: int = 0) -> dict[str, Any]:
    if offset < 0 or offset + 40 > len(data):
        raise ValueError("truncated FDT header")
    magic, size, off_struct, off_strings, off_reserve, version, compatible, _, strings_size, struct_size = struct.unpack_from(
        ">10I", data, offset)
    if magic != 0xD00DFEED or version != 17 or compatible > 17:
        raise ValueError("unsupported FDT (requires version 17)")
    if size < 40 or offset + size > len(data):
        raise ValueError("truncated FDT payload")
    if off_struct % 4 or off_reserve % 8:
        raise ValueError("unaligned FDT blocks")
    for start, length in ((off_struct, struct_size), (off_strings, strings_size)):
        if start < 40 or start + length > size:
            raise ValueError("invalid FDT block bounds")
    pos = off_reserve
    while True:
        if pos < 40 or pos + 16 > size:
            raise ValueError("unterminated reservation map")
        address, length = struct.unpack_from(">QQ", data, offset + pos)
        pos += 16
        if address == length == 0:
            break
    ranges = sorted([(off_reserve, pos), (off_struct, off_struct + struct_size), (off_strings, off_strings + strings_size)])
    if any(a[1] > b[0] for a, b in zip(ranges, ranges[1:])):
        raise ValueError("overlapping FDT blocks")
    pos, depth, seen_root, ended = off_struct, 0, False, False
    while pos + 4 <= off_struct + struct_size:
        token = struct.unpack_from(">I", data, offset + pos)[0]
        pos += 4
        if token == 1:  # FDT_BEGIN_NODE
            end = data.find(b"\0", offset + pos, offset + off_struct + struct_size)
            if end < 0 or (depth == 0 and seen_root):
                raise ValueError("invalid node name/root")
            if not seen_root and end != offset + pos:
                raise ValueError("root node name must be empty")
            seen_root = True
            depth += 1
            pos = (end - offset + 4) & ~3
        elif token == 2:  # FDT_END_NODE
            depth -= 1
            if depth < 0:
                raise ValueError("unbalanced nodes")
        elif token == 3:  # FDT_PROP
            if depth == 0 or pos + 8 > off_struct + struct_size:
                raise ValueError("invalid property header")
            length, name = struct.unpack_from(">II", data, offset + pos)
            pos += 8
            if name >= strings_size or data.find(b"\0", offset + off_strings + name, offset + off_strings + strings_size) < 0:
                raise ValueError("invalid property name")
            pos = (pos + length + 3) & ~3
        elif token == 4:
            pass
        elif token == 9:
            if depth != 0 or not seen_root:
                raise ValueError("premature FDT_END")
            ended = True
            break
        else:
            raise ValueError(f"invalid FDT token {token}")
        if pos > off_struct + struct_size:
            raise ValueError("FDT structure exceeds block")
    if not ended:
        raise ValueError("missing FDT_END")
    return {"offset": offset, "offset_hex": hex(offset), "size": size, "version": version,
            "sha256": sha256(data[offset:offset + size])}


def find(data: bytes) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    valid, rejected = [], []
    pos = 0
    while (pos := data.find(MAGIC, pos)) >= 0:
        if len(valid) + len(rejected) >= 4096:
            raise ValueError("more than 4096 magic hits; refine input")
        try:
            valid.append(validate_fdt(data, pos))
        except ValueError as exc:
            rejected.append({"offset": pos, "reason": str(exc)})
        pos += 4
    return valid, rejected


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    data = read_file(args.image)
    valid, rejected = find(data)
    emit({**metadata("find-dtb"), "input_sha256": sha256(data), "valid": valid,
          "rejected": rejected, "result": "ok", "exit_code": 0,
          "scope": "Uncompressed v17 FDT only; compressed kernels require decompression first."}, args.output)


if __name__ == "__main__":
    cli(main)
