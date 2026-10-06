"""Shared bounded, read-only lab I/O and CLI error reporting (Python >=3.10)."""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

VERSION = "1.0"
MAX_INPUT = 256 * 1024 * 1024


def read_file(path: Path, limit: int = MAX_INPUT) -> bytes:
    if not path.is_file():
        raise ValueError(f"not a regular file: {path}")
    if path.stat().st_size > limit:
        raise ValueError(f"input exceeds {limit} bytes: {path}")
    with path.open("rb") as stream:
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise ValueError("input grew beyond size limit")
    return data


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def metadata(operation: str) -> dict[str, Any]:
    try:
        repo = Path(__file__).resolve().parents[1]
        commit = subprocess.run(
            ["git", "-c", f"safe.directory={repo}", "rev-parse", "HEAD"], cwd=repo,
            capture_output=True, text=True, timeout=5, check=True,
        ).stdout.strip()
        dirty = bool(subprocess.run(["git", "-c", f"safe.directory={repo}", "status", "--porcelain"], cwd=repo,
                                    capture_output=True, text=True, timeout=5, check=True).stdout.strip())
    except (OSError, subprocess.SubprocessError):
        commit = "unavailable"
        dirty = None
    return {"timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "git_commit": commit, "git_dirty": dirty, "tool_version": VERSION, "operation": operation,
            "port": None, "baud": None}


def emit(value: Any, output: Path | None = None) -> None:
    text = json.dumps(value, indent=2, sort_keys=True) + "\n"
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("x", encoding="utf-8", newline="\n") as stream:
            stream.write(text)
    else:
        print(text, end="")


def cli(main: Callable[[], None]) -> None:
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(json.dumps({"result": "error", "error": str(exc), "exit_code": 2}), file=sys.stderr)
        raise SystemExit(2) from exc
