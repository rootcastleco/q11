#!/usr/bin/env python3
"""Build a reproducible gzip/newc ARM initramfs from a verified static BusyBox."""
from __future__ import annotations

import argparse
import gzip
import re
import stat
import struct
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lab import cli, emit, metadata, read_file, sha256

APPLETS = "sh mount umount mkdir mknod mdev sleep cat ln switch_root setsid cttyhack modprobe".split()


def validate_busybox(data: bytes) -> None:
    if len(data) < 52 or data[:7] != b"\x7fELF\x01\x01\x01":
        raise ValueError("BusyBox must be ELF32 little endian")
    kind, machine = struct.unpack_from("<HH", data, 16)
    if kind != 2 or machine != 40:
        raise ValueError("BusyBox must be an ARM executable")
    phoff = struct.unpack_from("<I", data, 28)[0]
    entsize, count = struct.unpack_from("<HH", data, 42)
    if entsize != 32 or count == 0 or phoff + count * entsize > len(data):
        raise ValueError("invalid ELF program headers")
    if any(struct.unpack_from("<I", data, phoff + i * entsize)[0] in (2, 3) for i in range(count)):
        raise ValueError("BusyBox must be statically linked (no INTERP/DYNAMIC)")


def entry(name: str, mode: int, data: bytes, inode: int, major: int = 0, minor: int = 0) -> bytes:
    filename = name.encode("utf-8") + b"\0"
    values = (inode, mode, 0, 0, 2 if stat.S_ISDIR(mode) else 1, 0, len(data), 0, 0, major, minor, len(filename), 0)
    header = b"070701" + b"".join(f"{value:08x}".encode("ascii") for value in values)
    result = header + filename
    result += b"\0" * (-len(result) % 4)
    result += data + b"\0" * (-len(data) % 4)
    return result


def build(busybox: bytes, init: bytes, root_probe: bytes, extras: dict[str, bytes] | None = None, compression: str = "gzip") -> bytes:
    validate_busybox(busybox)
    validate_busybox(root_probe)
    members: dict[str, tuple[int, bytes, int, int]] = {}
    def add(name: str, mode: int, data: bytes = b"", major: int = 0, minor: int = 0) -> None:
        for parent in reversed(Path(name).parents):
            if str(parent) != ".":
                members.setdefault(parent.as_posix(), (stat.S_IFDIR | 0o755, b"", 0, 0))
        members[name] = mode, data, major, minor
    for name in ("bin", "sbin", "proc", "sys", "dev", "newroot", "etc/q11", "usr/bin", "usr/sbin"):
        add(name, stat.S_IFDIR | 0o755)
    add("bin/busybox", stat.S_IFREG | 0o755, busybox)
    add("bin/q11-root-probe", stat.S_IFREG | 0o755, root_probe)
    add("init", stat.S_IFREG | 0o755, init)
    add("dev/console", stat.S_IFCHR | 0o600, major=5, minor=1)
    add("dev/null", stat.S_IFCHR | 0o666, major=1, minor=3)
    for applet in APPLETS:
        add(f"bin/{applet}", stat.S_IFLNK | 0o777, b"busybox")
    for name, data in sorted((extras or {}).items()):
        if name.startswith("/") or ".." in Path(name).parts or name in members:
            raise ValueError(f"invalid/duplicate archive path: {name}")
        add(name, stat.S_IFREG | 0o644, data)
    archive = b"".join(entry(name, *value[:2], i, *value[2:]) for i, (name, value) in enumerate(sorted(members.items()), 1))
    archive += entry("TRAILER!!!", 0, b"", len(members) + 1)
    archive += b"\0" * (-len(archive) % 512)
    if compression == "none":
        return archive
    if compression != "gzip":
        raise ValueError("compression must be gzip or none")
    # Fixed gzip header, including OS byte, gives identical outputs on Windows/Linux.
    import io
    buffer = io.BytesIO()
    with gzip.GzipFile(fileobj=buffer, mode="wb", filename="", mtime=0, compresslevel=9) as stream:
        stream.write(archive)
    return buffer.getvalue()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--busybox", required=True, type=Path)
    parser.add_argument("--busybox-sha256", required=True)
    parser.add_argument("--root-probe", required=True, type=Path)
    parser.add_argument("--root-probe-sha256", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--compression", choices=("none", "gzip"), default="none", help="none works without CONFIG_RD_GZIP; default: none")
    parser.add_argument("--modules", type=Path, help="directory containing a matching lib/modules tree")
    parser.add_argument("--load-module", action="append", default=[])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    data = read_file(args.busybox, 16 * 1024 * 1024)
    if not re.fullmatch(r"[0-9a-fA-F]{64}", args.busybox_sha256) or sha256(data) != args.busybox_sha256.lower():
        raise ValueError("BusyBox SHA256 mismatch/invalid digest")
    probe = read_file(args.root_probe, 16 * 1024 * 1024)
    if not re.fullmatch(r"[0-9a-fA-F]{64}", args.root_probe_sha256) or sha256(probe) != args.root_probe_sha256.lower():
        raise ValueError("root-probe SHA256 mismatch/invalid digest")
    extras: dict[str, bytes] = {}
    if args.load_module and not args.modules:
        raise ValueError("--load-module requires --modules")
    if args.modules:
        if not (args.modules / "lib/modules").is_dir():
            raise ValueError("--modules requires lib/modules/")
        total = 0
        for path in sorted((args.modules / "lib/modules").rglob("*")):
            if path.is_symlink():
                raise ValueError(f"module symlinks unsupported; stage runtime files only: {path}")
            if path.is_file():
                if re.search(r"advca|verimatrix|vmx_ca|otp|cipher", path.name, re.I):
                    raise ValueError("CA/OTP modules are outside bring-up scope")
                payload = read_file(path, 16 * 1024 * 1024)
                total += len(payload)
                if total > 64 * 1024 * 1024:
                    raise ValueError("modules exceed 64 MiB")
                extras[path.relative_to(args.modules).as_posix()] = payload
    if not all(re.fullmatch(r"[a-zA-Z0-9_-]+", name) for name in args.load_module):
        raise ValueError("invalid module name")
    extras["etc/q11/modules"] = ("\n".join(args.load_module) + "\n").encode()
    init = read_file(Path(__file__).with_name("init"))
    image = build(data, init, probe, extras, args.compression)
    if args.output.exists():
        raise ValueError("output already exists")
    if not args.dry_run:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("xb") as stream:
            stream.write(image)
    emit({**metadata("build-initramfs"), "busybox_sha256": sha256(data), "root_probe_sha256": sha256(probe), "image_sha256": sha256(image),
          "image_bytes": len(image), "compression": args.compression, "dry_run": args.dry_run, "result": "ok", "exit_code": 0,
          "bootability": "Host-built only; requires an authorized RAM image load path, matching storage modules and ext4 support."})


if __name__ == "__main__":
    cli(main)
