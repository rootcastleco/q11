#!/usr/bin/env python3
"""Read one ext superblock from a regular image; never mount or access devices."""
from __future__ import annotations

import argparse
import os
import stat
import struct
import sys
import uuid
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lab import cli, emit, metadata, sha256


def inspect_super(data: bytes) -> dict[str, Any]:
    if len(data) != 1024 or struct.unpack_from('<H', data, 56)[0] != 0xef53:
        raise ValueError('missing/truncated ext superblock')
    log_block = struct.unpack_from('<I', data, 24)[0]
    if log_block > 6:
        raise ValueError('invalid ext block size')
    u32 = lambda off: struct.unpack_from('<I', data, off)[0]
    u16 = lambda off: struct.unpack_from('<H', data, off)[0]
    text = lambda off, length: data[off:off+length].split(b'\0', 1)[0].decode('utf-8', 'replace')
    return {'superblock_sha256': sha256(data), 'label': text(120, 16),
            'uuid': str(uuid.UUID(bytes=data[104:120])), 'last_mounted': text(136, 64),
            'block_size': 1024 << log_block, 'mount_count': u16(52),
            'mount_time_unix': u32(44), 'write_time_unix': u32(48),
            'state': u16(58), 'feature_compat': hex(u32(92)),
            'feature_incompat': hex(u32(96)), 'feature_ro_compat': hex(u32(100)),
            'needs_journal_recovery': bool(u32(96) & 4)}


def read_super(path: Path, offset: int) -> dict[str, Any]:
    if offset < 0 or offset > 8192 * 1024**2 or offset % 512:
        raise ValueError('partition offset must be sector aligned and within 8 GiB')
    # lstat rejects the final symlink; fstat checks the opened object again.
    if not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError('only regular image files are supported')
    fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
    with os.fdopen(fd, 'rb') as stream:
        opened = os.fstat(stream.fileno())
        if not stat.S_ISREG(opened.st_mode) or opened.st_size < offset + 2048:
            raise ValueError('image is not regular or too short')
        stream.seek(offset + 1024)
        return inspect_super(stream.read(1024))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('--partition-offset', type=int, default=0)
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    current = read_super(args.image, args.partition_offset)
    result = {**metadata('ext-superblock'), 'superblock': current,
              'result': 'ok', 'exit_code': 0,
              'boundary': 'Counters/path are evidence, not proof of switch_root. Times may use an unset device clock; no journal replay is performed.'}
    if args.baseline:
        original = read_super(args.baseline, args.partition_offset)
        if current['uuid'] != original['uuid']:
            raise ValueError('baseline/current filesystem UUID mismatch')
        result['baseline'] = original
        result['changed_fields'] = {key: {'before': original[key], 'after': value}
                                    for key, value in current.items() if original[key] != value}
    emit(result, args.output)


if __name__ == '__main__':
    cli(main)
