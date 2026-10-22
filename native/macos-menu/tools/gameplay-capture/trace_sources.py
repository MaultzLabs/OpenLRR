#!/usr/bin/env python3
"""Default, fail-closed sources for a FULL integrated OpenLRR lab capture.

These files must be written by the isolated, instrumented game launcher.
Normal Wine/OpenLRR binaries cannot magically emit internal function calls.
Do not silently substitute a video-only session or tail arbitrary system logs.
"""
from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path
import stat
import time

import capture

TRACE_DIR = capture.CACHE / "active-traces"
MAX_SOURCE_AGE_SECONDS = 900


@dataclass(frozen=True)
class TraceSources:
    wine: Path
    nerps: Path


def inspect_source(path: Path, *, now: float) -> str:
    if path.is_symlink() or not path.is_file():
        return "missing"
    meta = path.stat()
    if not stat.S_ISREG(meta.st_mode):
        return "missing"
    if meta.st_mode & 0o077:
        return "not_private"
    if meta.st_size > capture.MAX_LOCAL_TRACE_BYTES * 50:
        return "oversized"
    if meta.st_mtime > now + 60 or now - meta.st_mtime > MAX_SOURCE_AGE_SECONDS:
        return "stale"
    return "ready_to_follow"


def discover(*, root: Path = TRACE_DIR, now: float | None = None) -> tuple[TraceSources | None, dict[str, str]]:
    """Always resolve both streams, without user-facing opt-in flags.

    'ready_to_follow' verifies a recent, private source file exists. It is NOT
    proof the game actually emitted Wine or NERPs events; the final manifest
    checks that separately.
    """
    now = time.time() if now is None else now
    keys = ("wine-debug.log", "nerps-events.jsonl")
    if root.is_symlink() or not root.is_dir() or root.stat().st_mode & 0o077:
        return None, {"wine": "unavailable", "nerps": "unavailable"}
    checks = {name: inspect_source(root / filename, now=now)
              for name, filename in zip(("wine", "nerps"), keys)}
    if any(value != "ready_to_follow" for value in checks.values()):
        return None, checks
    return TraceSources(root / keys[0], root / keys[1]), checks


def require(*, root: Path = TRACE_DIR) -> TraceSources:
    sources, status = discover(root=root)
    if sources is None:
        raise capture.CaptureError(
            "Full laboratory recording requires BOTH active Wine/DirectDraw "
            "and instrumented OpenLRR NERPs/menu streams. Status: " +
            ", ".join(f"{key}={value}" for key, value in status.items()) +
            ". No game was launched and no incomplete recording was started. "
            "An isolated instrumented launcher must create both streams in "
            "~/Library/Caches/OpenLRR-GameplayCapture/active-traces/. "
            "The unmodified retail game cannot emit NERPs calls.")
    return sources
