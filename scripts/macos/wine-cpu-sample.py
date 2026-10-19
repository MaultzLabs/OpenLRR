#!/usr/bin/env python3
"""Safe opt-in macOS sample() sidecar for already-running OpenLRR TEST Wine.

This tool NEVER launches, terminates, changes or installs a game process.
It refuses non-Wine PIDs or ambiguous ownership, bounds sampling time and
stores raw potentially-sensitive macOS stacks LOCALLY only. The summary is
categorical and is not proof of Wine/driver root cause or displayed FPS.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys

HOME = Path.home()
APP = HOME / "Applications/Sikarugir/OpenLRR Menu Test.app"
GAME = APP / "Contents/SharedSupport/prefix/drive_c/Program Files/Rock Raiders OpenLRR"
CONFIG = HOME / ".config/openlrr-benchmark"
STATE = HOME / ".local/share/openlrr-agent/wine-cpu-profiles"
SAMPLE_BINARY = Path("/usr/bin/sample")
SYMBOLS = (
    "ddraw", "wined3d", "win32u", "wine", "quartz",
    "coreanimation", "metal", "libsystem_kernel", "pthread",
)
PID = re.compile(r"^[1-9][0-9]{0,9}$")
MAX_RAW_BYTES = 8_000_000
MAX_DISCOVERED_PIDS = 16
SECONDS = 3
SAMPLE_INTERVAL_MS = 20


def stop_check() -> None:
    if (CONFIG / "STOP").exists() or (CONFIG / "PAUSE").exists():
        raise RuntimeError("STOP/PAUSE active; CPU sampling disabled")


def validate_test_target() -> None:
    if APP.is_symlink() or GAME.is_symlink() or not APP.is_dir() or not GAME.is_dir():
        raise RuntimeError("Dedicated TEST game is unavailable")
    if not GAME.resolve(strict=True).is_relative_to(APP.resolve(strict=True)):
        raise RuntimeError("TEST directory resolves outside the isolated app")
    if not (GAME / "LegoRR.exe").is_file():
        raise RuntimeError("TEST executable missing")


def checked_run(args: list[str], *, timeout: int) -> str:
    proc = subprocess.run(
        args, capture_output=True, text=True,
        check=False, timeout=timeout,
    )
    if proc.returncode:
        raise RuntimeError("CPU sampling process lookup or profiling failed")
    if len(proc.stdout) > 8192:
        raise RuntimeError("Excessive Mac process lookup output")
    return proc.stdout


def find_test_wine_pid() -> str:
    stop_check()
    validate_test_target()
    # Bind PID candidates to files currently open inside the specifically
    # installed TEST game. Never discover unrelated Wine sessions by name.
    raw = checked_run(
        ["/usr/sbin/lsof", "-nP", "-t", "+D", str(GAME)], timeout=20
    )
    candidates = set(raw.split())
    if not candidates or len(candidates) > MAX_DISCOVERED_PIDS:
        raise RuntimeError("No unique bounded TEST process found")
    if any(not PID.fullmatch(candidate) for candidate in candidates):
        raise RuntimeError("Untrusted TEST process identifier")
    wine_pids = []
    for candidate in sorted(candidates, key=int):
        description = checked_run(
            ["/bin/ps", "-p", candidate, "-o", "comm="], timeout=10
        ).strip().lower()
        if any(marker in description for marker in ("wine", "legorr", "rock raiders")):
            wine_pids.append(candidate)
    if len(wine_pids) != 1:
        raise RuntimeError("Cannot attribute exactly one running Wine process to TEST")
    return wine_pids[0]


def sanitized_summary(data: str, pid: str) -> dict:
    if not PID.fullmatch(pid) or not isinstance(data, str):
        raise ValueError("Invalid local CPU trace")
    # Counts are counts of text occurrences, NOT sampling percentages or
    # attributed function execution time. No raw line/path is ever published.
    low = data.lower()
    counts = {
        name: len(re.findall(r"(?<![a-z0-9_])" + re.escape(name)
                             + r"(?![a-z0-9_])", low))
        for name in SYMBOLS
    }
    return {
        "schema_version": 1,
        "source": "local_mac_sample_cpu_stack_trace",
        "test_process_pid_verified": True,
        "pid_redacted": True,
        "seconds_requested": SECONDS,
        "sample_interval_ms_requested": SAMPLE_INTERVAL_MS,
        "symbol_mention_counts": counts,
        "has_driver_attribution": False,
        "is_verified_visible_fps": False,
        "safe_to_upload_raw_trace": False,
        "started_game": False,
        "executed_ai_candidate": False,
        "modified_working_game": False,
    }


def capture(*, now: datetime | None = None) -> dict:
    stop_check()
    if not SAMPLE_BINARY.is_file():
        raise RuntimeError("macOS sample tool unavailable")
    target = find_test_wine_pid()
    stop_check()
    # Recheck the same TEST-only PID immediately before attachment; avoid
    # targeting a process that disappeared or changed during preflight.
    if find_test_wine_pid() != target:
        raise RuntimeError("TEST process identity changed during profiler preflight")
    now = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    folder = STATE / ("sample_" + now.strftime("%Y%m%dT%H%M%SZ") + "_" + target)
    if STATE.is_symlink() or folder.exists() or folder.is_symlink():
        raise RuntimeError("CPU profiler output directory unsafe or already exists")
    folder.mkdir(parents=True, mode=0o700)
    raw = folder / "raw-local-only.sample"
    # sample is a macOS system profiler. It attaches to one already-running
    # TEST Wine process. It does not create or authorize a new game process.
    completed = subprocess.run(
        [str(SAMPLE_BINARY), target, str(SECONDS), str(SAMPLE_INTERVAL_MS),
         "-file", str(raw)],
        capture_output=True, text=True,
        check=False, timeout=SECONDS + 20,
    )
    if completed.returncode:
        raise RuntimeError("Mac CPU sampling failed; inspect local profiler folder")
    stop_check()
    if raw.is_symlink() or not raw.is_file() or not 0 < raw.stat().st_size <= MAX_RAW_BYTES:
        raise RuntimeError("Unusable or oversized local sample trace")
    raw.chmod(0o600)
    report = sanitized_summary(raw.read_text(encoding="utf-8", errors="replace"), target)
    summary = folder / "summary.json"
    with summary.open("x", encoding="utf-8") as stream:
        json.dump(report, stream, indent=2, sort_keys=True)
        stream.write("\n")
    summary.chmod(0o600)
    return {
        "status": "local_sample_recorded",
        "summary_path": str(summary),
        "raw_trace_path": str(raw),
        "raw_trace_uploaded": False,
        **report,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", action="store_true",
                        help="Explicitly attach to an ALREADY RUNNING TEST Wine process")
    args = parser.parse_args(argv)
    if not args.capture:
        print(json.dumps({
            "mode": "offline_preflight",
            "native_sample_started": False,
            "game_started": False,
            "raw_trace_uploaded": False,
        }, sort_keys=True))
        return 0
    print(json.dumps(capture(), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError,
            subprocess.SubprocessError) as exc:
        print("TEST CPU SAMPLING BLOCKED:", exc, file=sys.stderr)
        raise SystemExit(2)
