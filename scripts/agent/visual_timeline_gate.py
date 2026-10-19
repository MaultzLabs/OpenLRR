"""Require consistency of opt-in TEST run timing and window capture receipts.

A local, unsigned correlation gate: validates time intervals, boot identity,
approved DLL, frame hash and run ownership. Does not authenticate provenance.
"""
from __future__ import annotations

from pathlib import Path
import sys

MACOS = Path(__file__).resolve().parents[1] / "macos"
if str(MACOS) not in sys.path:
    sys.path.insert(0, str(MACOS))

import visual_timeline as vt

MAX_CAPTURE_DURATION_NS = 60_000_000_000
MAX_RUN_LENGTH_NS = vt.MAX_SPAN_NS
MAX_CAPTURE_SIZE = 50_000_000


def read_timed_capture(run_dir: Path, *, run_id: str, filename: str,
                       image_sha: str, dll_sha: str, graphics_mode: dict) -> dict:
    """Return bounded metadata only if the screenshot was temporally correlated."""
    root = run_dir.absolute()
    vt.check_path(root)
    start_file = root / "run-timing.start.json"
    end_file = root / "run-timing.end.json"
    capture_file = root / filename
    receipt_file = capture_file.with_suffix(".capture.json")
    for p in (start_file, end_file, capture_file, receipt_file):
        vt.check_path(p)

    start = vt.read_bounded(start_file)
    beginning = vt.validate_start(start, run_id, dll_sha)
    mode = start["mode"]
    expected = {"optimization": 0, "nowait": int(mode == "nowait"),
                "gdi": int(mode == "gdi")}
    if graphics_mode != expected:
        raise ValueError("Timing start graphics mode does not match verified run")

    end = vt.read_bounded(end_file)
    if type(end) is not dict or set(end) != {
            "schema_version", "run", "start_sha256", "end", "clean_exit_checked"}:
        raise ValueError("Malformed supervised TEST timing end receipt")
    if end["schema_version"] != 1 or type(end["schema_version"]) is not int:
        raise ValueError("Unknown timing end receipt schema")
    if end["run"] != run_id or end["clean_exit_checked"] is not True:
        raise ValueError("Timing end is not for a clean verified TEST run")
    if end["start_sha256"] != vt.hashlib.sha256(start_file.read_bytes()).hexdigest():
        raise ValueError("TEST run timing start marker has changed")
    conclusion = end["end"]
    vt.same_boot(beginning, conclusion)
    elapsed = conclusion["mono_ns"] - beginning["mono_ns"]
    if not 0 < elapsed <= MAX_RUN_LENGTH_NS:
        raise ValueError("Invalid TEST run timing duration")
    if not (root / "lifecycle.verified").is_file() or (
        (root / "lifecycle.verified").read_text(encoding="utf-8") !=
            "wrapper_wait_exited=yes\ntest_game_handles=none\n"):
        raise ValueError("TEST game has not been verified closed")

    capture = vt.read_bounded(receipt_file)
    if type(capture) is not dict or set(capture) != {
            "schema_version", "run", "window_id", "owner_pid", "size",
            "sha256", "relative_file", "window_owner_checked",
            "capture_origin_authenticated", "may_touch_working_game",
            "may_deploy_automatically", "capture_started", "capture_finished",
            "approved_dll_sha256"}:
        raise ValueError("Missing or malformed timed capture receipt")
    if capture["schema_version"] != 1 or type(capture["schema_version"]) is not int:
        raise ValueError("Unknown timed capture schema")
    if (capture["run"] != run_id or capture["sha256"] != image_sha or
            capture["approved_dll_sha256"] != dll_sha or
            capture["relative_file"] != filename):
        raise ValueError("Timed capture does not match this run and image")
    if (type(capture["window_id"]) is not int or capture["window_id"] <= 0
            or type(capture["owner_pid"]) is not int or capture["owner_pid"] <= 0
            or capture["window_owner_checked"] is not True):
        raise ValueError("Capture window ownership is unverified")
    if any(capture[key] is not False for key in (
            "capture_origin_authenticated", "may_touch_working_game",
            "may_deploy_automatically")):
        raise ValueError("Capture timing receipt elevates authority")
    if (not capture_file.is_file()
            or not 0 < capture_file.stat().st_size <= MAX_CAPTURE_SIZE):
        raise ValueError("Timed screenshot absent or oversize")
    from visual_capture_binding import sha256_file
    if sha256_file(capture_file) != image_sha:
        raise ValueError("Capture was modified after its timing receipt")

    timing_start, timing_end = capture["capture_started"], capture["capture_finished"]
    vt.same_boot(beginning, timing_start, timing_end, conclusion)
    first = timing_start["mono_ns"]
    last = timing_end["mono_ns"]
    if not (beginning["mono_ns"] <= first <= last <= conclusion["mono_ns"]):
        raise ValueError("Visual capture occurred outside supervised TEST run window")
    if not 0 < last - first <= MAX_CAPTURE_DURATION_NS:
        raise ValueError("Capture duration is invalid")
    # Both monotonic and wall readings must be in agreement independently.
    if not (beginning["wall_ns"] - vt.MAX_CLOCK_DRIFT_NS <= timing_start["wall_ns"]
            <= timing_end["wall_ns"] <= conclusion["wall_ns"] + vt.MAX_CLOCK_DRIFT_NS):
        raise ValueError("Visual capture wall-clock outside TEST run window")
    return {
        "schema_version": 1,
        "timing_consistent": True,
        "window_owner_checked": True,
        "start_receipt_sha256": vt.hashlib.sha256(start_file.read_bytes()).hexdigest(),
        "end_receipt_sha256": vt.hashlib.sha256(end_file.read_bytes()).hexdigest(),
        "capture_receipt_sha256": vt.hashlib.sha256(receipt_file.read_bytes()).hexdigest(),
        "capture_origin_authenticated": False,
        "may_touch_working_game": False,
        "may_deploy_automatically": False,
    }
