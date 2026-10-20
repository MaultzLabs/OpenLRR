#!/usr/bin/env python3
"""Fail-closed whitelist for the only benchmark files permitted in private GitHub.

No network, credentials, home-path telemetry, Wine logs, screenshots or executable
bytes are inspected or transmitted. Return nonzero before ANY file is uploaded.
"""
import csv
import json
import math
from pathlib import Path
import re
import sys

RUN = re.compile(r"autobenchmark-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\Z")
SHA = re.compile(r"[0-9a-f]{64}\Z")
NUMBER = re.compile(r"(?:0|[1-9][0-9]{0,8})(?:\.[0-9]{1,8})?\Z")
INT = re.compile(r"(?:0|[1-9][0-9]{0,8})\Z")
HEADER = ["seconds", "optimization", "nowait", "gdi", "operation",
          "calls", "total_ms", "max_ms"]
OPS = set((
    "flic_surface_lock flic_decode flic_surface_unlock flic_backbuffer_blt "
    "image_blt frame_flip movie_update window_coordinate window_present_blt "
    "fullscreen_flip gdi_surface_getdc gdi_stretchblt gdi_surface_releasedc "
    "window_present_accepted window_present_busy window_present_error "
    "gdi_window_attempt gdi_present_accepted gdi_present_fallback "
    "frame_start_gap frame_outside_flip window_blt_over_100ms "
    "window_blt_over_1000ms frame_outside_over_100ms frame_outside_over_1000ms "
    "window_blt_thread_cpu window_blt_slow_thread_cpu window_blt_cpu_unavailable "
    "window_blt_slow_low_cpu game_mainloop d3drm_device_update "
    "dib_window_attempt dib_backbuffer_lock dib_stretchdibits "
    "dib_backbuffer_unlock dib_present_accepted dib_present_fallback"
).split())
MODE = {"optimization", "nowait", "gdi"}
COUNTERS = set((
    "rows logged_duration_s frame_flips frame_flips_per_s present_calls "
    "present_total_s present_avg_ms present_worst_ms present_intervals "
    "present_intervals_over_100ms present_intervals_over_1000ms "
    "present_accepted_calls present_busy_calls present_error_calls "
    "present_accepted_percent gdi_accepted_calls gdi_fallback_calls "
    "frame_start_gap_calls frame_start_gap_avg_ms frame_start_gap_worst_ms "
    "frame_outside_flip_calls frame_outside_flip_avg_ms frame_outside_flip_worst_ms "
    "window_blt_calls_over_100ms window_blt_calls_over_1000ms "
    "outside_flip_calls_over_100ms outside_flip_calls_over_1000ms "
    "blit_thread_cpu_samples blit_thread_cpu_unavailable blit_thread_cpu_avg_ms "
    "blit_slow_cpu_samples blit_slow_thread_cpu_avg_ms blit_slow_low_cpu_calls "
    "dib_accepted_calls dib_fallback_calls dib_lock_max_ms dib_copy_max_ms "
    "game_mainloop_calls game_mainloop_avg_ms game_mainloop_worst_ms "
    "d3drm_update_calls d3drm_update_avg_ms d3drm_update_worst_ms"
).split())
BOOLEANS = {"present_worst_is_exact", "frame_timing_diagnostics_available",
            "blit_cpu_probe_available", "game_phase_diagnostics_available"}
STRINGS = {
    "present_path": {"directdraw", "gdi", "dib_cpu"},
    "game_mainloop_observation":
        {"state_mainloop_observed", "state_mainloop_not_observed", "unavailable"},
}
CHANGES = {"frame_flips_per_s", "present_avg_ms", "present_worst_ms",
           "present_intervals_over_1000ms"}
RECEIPT = "wrapper_wait_exited=yes\ntest_game_handles=none\n"

def demand(ok, reason):
    if not ok:
        raise ValueError(reason)

def regular(path, limit):
    demand(not path.is_symlink() and path.is_file(), "Unsafe/missing telemetry artifact")
    demand(0 < path.stat().st_size <= limit, "Telemetry artifact exceeds fixed size")

def number(value, *, signed=False):
    return (value is None or (
        type(value) in (int, float) and math.isfinite(value)
        and (abs(value) <= 1e9 if signed else 0 <= value <= 1e9)))

def validate_metrics(value):
    demand(type(value) is dict, "Invalid metrics object")
    demand(set(value) <= COUNTERS | BOOLEANS | set(STRINGS) | {"mode"},
           "Unapproved metrics field")
    demand({"mode", "frame_flips", "present_calls", "present_path",
            "logged_duration_s", "present_avg_ms"} <= set(value),
           "Missing required metrics")
    flags = value["mode"]
    demand(type(flags) is dict and
           set(flags) in (MODE, MODE | {"dib"}) and
           all(type(x) is int and x in (0, 1) for x in flags.values()),
           "Unexpected graphics mode")
    for key, val in value.items():
        if key in COUNTERS:
            demand(number(val), "Invalid numeric metric")
        elif key in BOOLEANS:
            demand(type(val) is bool, "Invalid Boolean metric")
        elif key in STRINGS:
            demand(type(val) is str and val in STRINGS[key],
                   "Unapproved text in metrics")

def validate_summary(obj, run):
    demand(type(obj) is dict and
           set(obj) <= {"schema_version", "run", "close_requested", "metrics",
                        "dll_sha256", "comparison", "baseline_run"},
           "Unexpected benchmark summary fields")
    demand(type(obj.get("schema_version")) is int and obj["schema_version"] == 1
           and obj.get("run") == run and
           type(obj.get("close_requested")) is bool,
           "Invalid benchmark summary identity")
    validate_metrics(obj.get("metrics"))
    if "dll_sha256" in obj:
        demand(type(obj["dll_sha256"]) is str and SHA.fullmatch(obj["dll_sha256"]),
               "Invalid DLL digest")
    if "baseline_run" in obj:
        demand(type(obj["baseline_run"]) is str and RUN.fullmatch(obj["baseline_run"]),
               "Invalid baseline name")
    if "comparison" in obj:
        obj2 = obj["comparison"]
        demand(type(obj2) is dict and
               set(obj2) == {"baseline_mode", "graphics_modes_match",
                            "percentage_change", "baseline_metrics"} and
               type(obj2["graphics_modes_match"]) is bool, "Invalid comparison")
        validate_metrics(obj2["baseline_metrics"])
        mode = obj2["baseline_mode"]
        demand(type(mode) is dict and
               set(mode) in (MODE, MODE | {"dib"}) and
               all(type(v) is int and v in (0, 1) for v in mode.values()),
               "Invalid baseline mode")
        changes = obj2["percentage_change"]
        demand(type(changes) is dict and set(changes) == CHANGES
               and all(number(v, signed=True) for v in changes.values()),
               "Unexpected percentage comparison")
    return obj

def validate_csv(path):
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle, strict=True)
        demand(next(reader, None) == HEADER, "Unexpected telemetry columns")
        count = 0
        ops = set()
        for row in reader:
            count += 1
            demand(count <= 60000 and len(row) == 8,
                   "Unexpected telemetry row dimensions")
            second, opt, nowait, gdi, operation, calls, total, maximum = row
            demand(NUMBER.fullmatch(second) and float(second) <= 7200,
                   "Invalid time column")
            demand(all(x in ("0", "1") for x in (opt, nowait, gdi)),
                   "Unexpected graphics flag")
            demand(operation in OPS and INT.fullmatch(calls),
                   "Unexpected telemetry operation/count")
            demand(NUMBER.fullmatch(total) and NUMBER.fullmatch(maximum),
                   "Unexpected timing value")
            ops.add(operation)
        demand(count > 0 and "frame_flip" in ops and "window_present_blt" in ops,
               "Missing required renderer telemetry")
    return count

def validate(run: Path, supervised: bool):
    demand(RUN.fullmatch(run.name) and run.is_dir() and not run.is_symlink(),
           "Invalid telemetry run directory")
    csv_path = run / "menuperf.csv"
    summary_path = run / "summary.json"
    regular(csv_path, 2_000_000)
    regular(summary_path, 65536)
    validate_csv(csv_path)
    validate_summary(json.loads(summary_path.read_text(encoding="utf-8")), run.name)
    if supervised:
        receipt = run / "lifecycle.verified"
        regular(receipt, 128)
        demand(receipt.read_text(encoding="ascii") == RECEIPT,
               "TEST clean-exit evidence invalid")
    # Deliberately no report.txt, process stacks, machine paths, screenshots,
    # credentials, logs, Wine configuration, EXEs or DLLs in this upload set.

def main():
    demand(len(sys.argv) in (2, 3), "Expected run directory and --supervised")
    supervised = len(sys.argv) == 3 and sys.argv[2] == "--supervised"
    demand(len(sys.argv) == 2 or supervised, "Invalid privacy guard option")
    validate(Path(sys.argv[1]), supervised)
    print("Privacy preflight passed: numeric telemetry, bounded summary"
          " and verified exit receipt only.")

if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, UnicodeError, json.JSONDecodeError, csv.Error) as error:
        print("PRIVACY STOP:", error, file=sys.stderr)
        sys.exit(2)
