#!/usr/bin/env python3
"""Opt-in local timing markers for a supervised, dedicated OpenLRR TEST run.

Markers correlate timestamps and a host boot identity. They are NOT signatures
or proof of image origin. Never launches games, writes game files, or uploads.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

RUN = re.compile(r"^autobenchmark-\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d$")
SHA = re.compile(r"^[0-9a-f]{64}$")
MODES = frozenset(("baseline", "nowait", "gdi"))
MAX_SPAN_NS = 1_200_000_000_000
MAX_CLOCK_DRIFT_NS = 2_000_000_000
MAX_CLOCK_READ_NS = 500_000_000
MAX_RECEIPT_BYTES = 20_000


def check_path(path: Path) -> Path:
    absolute = path.absolute()
    if any(item.is_symlink() for item in (absolute, *absolute.parents)):
        raise ValueError("Timing artifacts cannot pass through symlinks")
    return absolute


def boot_identity() -> str:
    """Stable across one host boot; absence means temporal evidence unavailable."""
    if sys.platform == "darwin":
        result = subprocess.run(["sysctl", "-n", "kern.boottime"], capture_output=True,
                                text=True, timeout=5, check=False)
        token = result.stdout.strip()
        if result.returncode:
            raise RuntimeError("Cannot read current macOS boot identity")
    elif sys.platform.startswith("linux"):
        token = Path("/proc/sys/kernel/random/boot_id").read_text(encoding="ascii").strip()
    else:
        raise RuntimeError("Unsupported host boot clock")
    if not token or len(token) > 160:
        raise RuntimeError("Host boot identity missing or invalid")
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def sample_clock() -> dict:
    before = time.monotonic_ns()
    wall = time.time_ns()
    after = time.monotonic_ns()
    if after < before or after - before > MAX_CLOCK_READ_NS:
        raise RuntimeError("Unreliable timing clock read")
    return {"wall_ns": wall, "mono_ns": (before + after) // 2,
            "boot_sha256": boot_identity()}


def require_clock(clock: dict) -> None:
    if type(clock) is not dict or set(clock) != {"wall_ns", "mono_ns", "boot_sha256"}:
        raise ValueError("Malformed timing sample")
    if any(type(clock[k]) is not int or clock[k] <= 0 for k in ("wall_ns", "mono_ns")):
        raise ValueError("Invalid timing clock")
    if not isinstance(clock["boot_sha256"], str) or not SHA.fullmatch(clock["boot_sha256"]):
        raise ValueError("Invalid boot identity")


def same_boot(*clocks: dict) -> None:
    for clock in clocks:
        require_clock(clock)
    if len({item["boot_sha256"] for item in clocks}) != 1:
        raise ValueError("Run and capture span different host boots")
    offsets = [item["wall_ns"] - item["mono_ns"] for item in clocks]
    if max(offsets) - min(offsets) > MAX_CLOCK_DRIFT_NS:
        raise ValueError("System clock stepped during experiment")


def write_exclusive(path: Path, payload: dict) -> None:
    path = check_path(path)
    if not path.parent.is_dir():
        raise ValueError("Timing output parent does not exist")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.write(json.dumps(payload, sort_keys=True, indent=2) + "\n")
        stream.flush()
        os.fsync(stream.fileno())


def read_bounded(path: Path) -> dict:
    path = check_path(path)
    if not path.is_file() or not 0 < path.stat().st_size <= MAX_RECEIPT_BYTES:
        raise ValueError("Missing/oversize timing receipt: " + path.name)
    result = json.loads(path.read_text(encoding="utf-8"))
    if type(result) is not dict:
        raise ValueError("Timing receipt must be an object")
    return result


def validate_start(doc: dict, run: str, dll_sha: str) -> dict:
    if type(doc) is not dict or set(doc) != {"schema_version", "run", "dll_sha256", "mode", "start"}:
        raise ValueError("Unrecognized TEST timing start schema")
    if doc["schema_version"] != 1 or type(doc["schema_version"]) is not int:
        raise ValueError("Unknown TEST timing schema")
    if doc["run"] != run or doc["dll_sha256"] != dll_sha or doc["mode"] not in MODES:
        raise ValueError("Timing start doesn't match supervised experiment")
    require_clock(doc["start"])
    return doc["start"]


def begin(run_dir: Path, dll_sha: str, mode: str, *, clock: dict | None = None) -> dict:
    run_dir = check_path(run_dir)
    if not RUN.fullmatch(run_dir.name) or not run_dir.is_dir() or (
            not SHA.fullmatch(dll_sha)) or mode not in MODES:
        raise ValueError("Invalid TEST run, DLL identity, or graphics mode")
    if (run_dir / "run-timing.end.json").exists():
        raise ValueError("Completed benchmark cannot be restarted")
    receipt = {"schema_version": 1, "run": run_dir.name,
               "dll_sha256": dll_sha, "mode": mode,
               "start": clock if clock is not None else sample_clock()}
    validate_start(receipt, run_dir.name, dll_sha)
    write_exclusive(run_dir / "run-timing.start.json", receipt)
    return receipt


def finish(run_dir: Path, *, clock: dict | None = None) -> dict:
    run_dir = check_path(run_dir)
    start = read_bounded(run_dir / "run-timing.start.json")
    start_clock = validate_start(start, run_dir.name, start.get("dll_sha256"))
    if not (run_dir / "lifecycle.verified").is_file() or (
            (run_dir / "lifecycle.verified").read_text(encoding="utf-8") !=
            "wrapper_wait_exited=yes\ntest_game_handles=none\n"):
        raise ValueError("TEST app has no verified clean lifecycle receipt")
    end_clock = clock if clock is not None else sample_clock()
    same_boot(start_clock, end_clock)
    elapsed = end_clock["mono_ns"] - start_clock["mono_ns"]
    if not 0 < elapsed <= MAX_SPAN_NS:
        raise ValueError("Invalid supervised TEST run time range")
    receipt = {"schema_version": 1, "run": run_dir.name,
               "start_sha256": hashlib.sha256(
                   (run_dir / "run-timing.start.json").read_bytes()).hexdigest(),
               "end": end_clock, "clean_exit_checked": True}
    write_exclusive(run_dir / "run-timing.end.json", receipt)
    return receipt


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("command", choices=("start", "finish"))
    p.add_argument("--run", type=Path, required=True)
    p.add_argument("--dll-sha")
    p.add_argument("--mode")
    args = p.parse_args(argv)
    try:
        if args.command == "start":
            if not args.dll_sha or not args.mode:
                raise ValueError("start needs --dll-sha and --mode")
            answer = begin(args.run, args.dll_sha, args.mode)
        else:
            if args.dll_sha is not None or args.mode is not None:
                raise ValueError("finish accepts no unverified identity overrides")
            answer = finish(args.run)
        print(json.dumps(answer, sort_keys=True))
        return 0
    except (ValueError, OSError, RuntimeError, json.JSONDecodeError,
            subprocess.TimeoutExpired) as error:
        print("VISUAL TIMING STOPPED: " + str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
