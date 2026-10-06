#!/usr/bin/env python3
"""Inventory an extracted stock rootfs; never execute vendor files."""
from __future__ import annotations

import argparse
import itertools
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lab import cli, emit, metadata, read_file, sha256

TERMS = re.compile(r"getty|telnetd|user_debug|USB|mmcblk|/dev/sd|hotplug|appdata|switch_root|pivot_root|loader\.rc|set_mount|debug", re.I)


def audit(root: Path) -> dict:
    root = root.resolve(strict=True)
    if not root.is_dir() or not (root / "etc").is_dir():
        raise ValueError("expected an extracted rootfs with etc/")
    files = sorted(itertools.islice(root.rglob("*"), 100001))
    if len(files) > 100000:
        raise ValueError("rootfs exceeds 100000 entries")
    startup = []
    modules = []
    for path in files:
        rel = path.relative_to(root).as_posix()
        if path.is_symlink():
            continue  # Absolute vendor symlinks must never resolve into the host.
        if path.suffix == ".ko":
            modules.append(rel)
        if not path.is_file() or not (rel == "etc/inittab" or rel.startswith(("etc/init.d/", "etc/udev/", "etc/hotplug"))
                                      or path.name in ("rcS", "S99init", "loader.rc", "local.rc", "set_mount.sh", "set_mount_new.sh", "hmw_mount.sh", "init.sh")):
            continue
        if path.stat().st_size > 1024 * 1024:
            startup.append({"path": rel, "skipped": "larger than 1 MiB"})
            continue
        data = read_file(path, 1024 * 1024)
        startup.append({"path": rel, "sha256": sha256(data),
                        "matches": [{"line": i, "terms": sorted(set(m.group(0) for m in TERMS.finditer(line)))}
                                    for i, line in enumerate(data.decode("utf-8", errors="replace").splitlines(), 1) if TERMS.search(line)]})
    return {"startup_files": startup, "module_paths": modules,
            "interpretation": "Matches locate review targets; they do not prove a script execution hook."}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rootfs", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    emit({**metadata("audit-rootfs"), **audit(args.rootfs), "result": "ok", "exit_code": 0}, args.output)


if __name__ == "__main__":
    cli(main)
