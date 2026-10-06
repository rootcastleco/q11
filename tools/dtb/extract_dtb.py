#!/usr/bin/env python3
"""Extract one validated FDT without changing the source file."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lab import cli, emit, metadata, read_file
from find_dtb import validate_fdt


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("offset", type=lambda value: int(value, 0))
    parser.add_argument("output", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    data = read_file(args.image)
    item = validate_fdt(data, args.offset)
    if args.output.exists():
        raise ValueError(f"output exists: {args.output}")
    if not args.dry_run:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("xb") as stream:
            stream.write(data[args.offset:args.offset + item["size"]])
    emit({**metadata("extract-dtb"), **item, "dry_run": args.dry_run, "result": "ok", "exit_code": 0})


if __name__ == "__main__":
    cli(main)
