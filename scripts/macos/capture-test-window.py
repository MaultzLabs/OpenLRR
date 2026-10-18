#!/usr/bin/env python3
"""Opt-in, TEST-window-only screenshot collector for OpenLRR Mac experiments.

Preflight only by default. Never launches games or uploads captures.
Requires the caller to explicitly select an on-screen window whose owning
process is verified to have the dedicated TEST game's files open, and a
matching already-approved DLL SHA. Desktop/full-screen capture is forbidden.
This component has NOT been tested against a real Mac/Wine window.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import struct
import subprocess
import sys

HOME = Path.home()
APP = HOME / "Applications/Sikarugir/OpenLRR Menu Test.app"
GAME = APP / "Contents/SharedSupport/prefix/drive_c/Program Files/Rock Raiders OpenLRR"
RUNS = HOME / "Downloads/OpenLRR Benchmark Runs"
SWITCHES = HOME / ".config/openlrr-benchmark"
SHA = re.compile(r"^[0-9a-f]{64}$")
RUN = re.compile(r"^autobenchmark-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$")
PNG = b"\x89PNG\r\n\x1a\n"
MAX_IMAGE_BYTES = 50_000_000


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def no_links(path: Path) -> None:
    absolute = path.absolute()
    if any(part.is_symlink() for part in (absolute, *absolute.parents)):
        raise ValueError("Symlinks prohibited in TEST capture path")


def stop_check() -> None:
    if (SWITCHES / "STOP").exists() or (SWITCHES / "PAUSE").exists():
        raise RuntimeError("STOP or PAUSE blocks TEST capture")


def test_install_preflight(approved_sha: str, run_id: str) -> Path:
    stop_check()
    if not SHA.fullmatch(approved_sha):
        raise ValueError("Full lowercase approved DLL SHA256 required")
    if not RUN.fullmatch(run_id):
        raise ValueError("Expected an existing supervised benchmark run ID")
    for target in (APP, GAME, GAME / "LegoRR.exe", GAME / "openlrr.dll",
                   RUNS, RUNS / run_id):
        no_links(target)
    if not APP.is_dir() or not (GAME / "LegoRR.exe").is_file():
        raise RuntimeError("Dedicated OpenLRR Menu Test.app not available")
    if not (GAME / "openlrr.dll").is_file() or digest(GAME / "openlrr.dll") != approved_sha:
        raise RuntimeError("TEST installation DLL does not match approved SHA256")
    run_folder = RUNS / run_id
    if not run_folder.is_dir():
        raise RuntimeError("The named TEST benchmark run does not exist")
    benchmark_copy = run_folder / "benchmark-openlrr.dll"
    no_links(benchmark_copy)
    if not benchmark_copy.is_file() or digest(benchmark_copy) != approved_sha:
        raise RuntimeError("Benchmark run DLL is missing or not the approved DLL")
    return run_folder


def window_info() -> list[dict]:
    if sys.platform != "darwin":
        raise RuntimeError("macOS-only capture helper")
    try:
        import Quartz
    except ImportError as exc:
        raise RuntimeError("PyObjC Quartz is required for TEST-window preflight") from exc
    mask = Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements
    return list(Quartz.CGWindowListCopyWindowInfo(mask, Quartz.kCGNullWindowID) or [])


def normalize_window(raw: dict) -> dict | None:
    if type(raw) is not dict or type(raw.get("kCGWindowNumber")) is not int:
        return None
    if type(raw.get("kCGWindowOwnerPID")) is not int or raw["kCGWindowOwnerPID"] <= 0:
        return None
    if raw.get("kCGWindowLayer") != 0:
        return None
    bounds = raw.get("kCGWindowBounds")
    if type(bounds) is not dict:
        return None
    width, height = bounds.get("Width"), bounds.get("Height")
    if (type(width) not in (int, float) or type(height) not in (int, float)
            or not math.isfinite(width) or not math.isfinite(height)
            or not 320 <= width <= 8192 or not 200 <= height <= 8192):
        return None
    return {
        "window_id": raw["kCGWindowNumber"],
        "pid": raw["kCGWindowOwnerPID"],
        "width": float(width),
        "height": float(height),
        "owner_name": str(raw.get("kCGWindowOwnerName", ""))[:100],
        "title": str(raw.get("kCGWindowName", ""))[:100],
    }


def process_uses_test_game(pid: int) -> bool:
    if type(pid) is not int or pid <= 0:
        return False
    proc = subprocess.run(["lsof", "-nP", "-Fn", "-p", str(pid)],
                          capture_output=True, text=True, timeout=10, check=False)
    if proc.returncode != 0 or len(proc.stdout) > 1_000_000:
        return False
    # lsof's -Fn prefixes each path with 'n'. Match an exact TEST program
    # file. An ordinary Wine app on the desktop is NOT sufficient.
    wanted = {str(GAME / "LegoRR.exe"), str(GAME / "openlrr.dll")}
    paths = {line[1:] for line in proc.stdout.splitlines()
             if line.startswith("n")}
    return bool(wanted & paths)


def eligible_window(selected: int, observed: list[dict]) -> dict:
    if type(selected) is not int or selected <= 0:
        raise ValueError("Choose an explicit positive TEST window ID")
    valid = [w for entry in observed if (w := normalize_window(entry)) is not None
             and w["window_id"] == selected]
    if len(valid) != 1:
        raise ValueError("Window is missing or not a visible ordinary app window")
    selected_window = valid[0]
    if not process_uses_test_game(selected_window["pid"]):
        raise RuntimeError("Window owner has no verified TEST game files open")
    return selected_window


def inspect_png(path: Path, window: dict) -> tuple[int, int]:
    if not path.is_file() or not 24 <= path.stat().st_size <= MAX_IMAGE_BYTES:
        raise ValueError("Screen capture absent or suspicious size")
    with path.open("rb") as handle:
        header = handle.read(24)
    if header[:8] != PNG or header[12:16] != b"IHDR":
        raise ValueError("Capture is not a PNG screenshot")
    width, height = struct.unpack(">II", header[16:24])
    # Retina scaling and optional window shadows can expand dimensions.
    if (not 250 <= width <= min(16000, window["width"] * 3 + 200)
            or not 150 <= height <= min(16000, window["height"] * 3 + 200)):
        raise ValueError("Screenshot dimensions inconsistent with TEST window")
    return width, height


def capture_once(approved_sha: str, run_id: str, window_id: int,
                 *, confirm_test_only: bool = False) -> dict:
    if not confirm_test_only:
        raise ValueError("Explicit --confirm-test-only required to capture")
    if sys.platform != "darwin":
        raise RuntimeError("TEST capture may run only on macOS")
    run = test_install_preflight(approved_sha, run_id)
    first = eligible_window(window_id, window_info())
    if first["pid"] <= 0:
        raise RuntimeError("Missing TEST window owner")
    visual = run / "visual"
    no_links(visual)
    visual.mkdir(exist_ok=True, mode=0o700)
    target = visual / "menu.png"
    no_links(target)
    if target.exists() or target.is_symlink():
        raise FileExistsError("Existing TEST capture must never be overwritten")
    # Reserve the pathname exclusively: screencapture is never allowed to
    # overwrite another process's file. No display/desktop capture fallback.
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(fd)
    success = False
    try:
        stop_check()
        second = eligible_window(window_id, window_info())
        if second["pid"] != first["pid"]:
            raise RuntimeError("TEST window owner changed during capture preflight")
        proc = subprocess.run(["screencapture", "-x", "-o", "-l", str(window_id), str(target)],
                              capture_output=True, text=True, timeout=30, check=False)
        if proc.returncode:
            raise RuntimeError("Window-only screencapture failed; no full-screen fallback")
        dimensions = inspect_png(target, second)
        stop_check()
        third = eligible_window(window_id, window_info())
        if third["pid"] != first["pid"]:
            raise RuntimeError("Window owner changed during TEST screenshot")
        if digest(GAME / "openlrr.dll") != approved_sha:
            raise RuntimeError("Approved TEST binary changed during capture")
        success = True
        return {
            "schema_version": 1,
            "run": run_id,
            "window_id": window_id,
            "owner_pid": first["pid"],
            "size": {"width": dimensions[0], "height": dimensions[1]},
            "sha256": digest(target),
            "relative_file": "visual/menu.png",
            "window_owner_checked": True,
            "capture_origin_authenticated": False,
            "may_touch_working_game": False,
            "may_deploy_automatically": False,
        }
    finally:
        if not success:
            # Only remove our own reserved file inside the dedicated RUN folder;
            # never attempt to delete or edit a game file.
            target.unlink(missing_ok=True)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--approved-sha", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--window-id", type=int, required=True)
    parser.add_argument("--capture", action="store_true",
                        help="Actually invoke window-ID-only screenshot command")
    parser.add_argument("--confirm-test-only", action="store_true")
    opts = parser.parse_args(argv)
    try:
        test_install_preflight(opts.approved_sha, opts.run_id)
        eligible = eligible_window(opts.window_id, window_info())
        if not opts.capture:
            print(json.dumps({"preflight_only": True, "window": eligible,
                              "will_capture": False, "test_only": True}, indent=2))
            return 0
        result = capture_once(opts.approved_sha, opts.run_id, opts.window_id,
                              confirm_test_only=opts.confirm_test_only)
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
        print("TEST WINDOW CAPTURE STOPPED: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
