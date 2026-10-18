#!/usr/bin/env python3
"""Summarize OpenLRR telemetry without exposing Mac paths or game assets.

Usage: python3 analyze-benchmark.py RUN_DIR [--baseline BASELINE_CSV]
Only two text artifacts are created: report.txt and summary.json.
"""
import argparse
import csv
import hashlib
import json
import math
import re
from pathlib import Path

HEADER = ["seconds", "optimization", "nowait", "gdi",
          "operation", "calls", "total_ms", "max_ms"]
MAX_CSV_BYTES = 2_000_000
RUN_PATTERN = re.compile(r"^autobenchmark-[0-9A-Za-z._-]+$")


def analyze_csv(source):
    source = Path(source)
    if not source.is_file() or source.stat().st_size > MAX_CSV_BYTES:
        raise ValueError("CSV missing or larger than the 2MB safety limit")
    totals = {}
    modes = set()
    row_count = 0
    with source.open("r", newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != HEADER:
            raise ValueError("CSV has an unexpected header")
        for row in reader:
            if None in row or any(v is None for v in row.values()):
                raise ValueError("CSV contains a malformed row")
            try:
                seconds = float(row["seconds"])
                calls = int(row["calls"])
                total_ms = float(row["total_ms"])
                max_ms = float(row["max_ms"])
                mode = tuple(int(row[k]) for k in ("optimization", "nowait", "gdi"))
            except (TypeError, ValueError) as exc:
                raise ValueError("CSV contains an invalid numeric field") from exc
            if not all(math.isfinite(v) and v >= 0 for v in (seconds, total_ms, max_ms)):
                raise ValueError("CSV contains negative or non-finite timings")
            if calls < 0 or any(v not in (0, 1) for v in mode):
                raise ValueError("CSV contains invalid counters or mode flags")
            operation = row["operation"]
            if not re.fullmatch(r"[a-z][a-z0-9_]*", operation):
                raise ValueError("CSV contains an unexpected operation name")
            stat = totals.setdefault(operation, dict(calls=0, total_ms=0.0, max_ms=0.0,
                                                     intervals=0, slow_100ms=0,
                                                     slow_1000ms=0, logged_seconds=0.0))
            stat["calls"] += calls
            stat["total_ms"] += total_ms
            stat["max_ms"] = max(stat["max_ms"], max_ms)
            stat["intervals"] += 1
            stat["slow_100ms"] += max_ms > 100
            stat["slow_1000ms"] += max_ms > 1000
            stat["logged_seconds"] += seconds
            modes.add(mode)
            row_count += 1

    frames = totals.get("frame_flip", {})
    if not frames.get("calls"):
        raise ValueError("CSV has no completed frame flips")
    if len(modes) != 1:
        raise ValueError("CSV contains inconsistent graphics-mode flags")
    mode = next(iter(modes))
    dd = totals.get("window_present_blt", {})
    dd_calls = dd.get("calls", 0)
    dd_accepted = totals.get("window_present_accepted", {}).get("calls", 0)
    dd_busy = totals.get("window_present_busy", {}).get("calls", 0)
    dd_errors = totals.get("window_present_error", {}).get("calls", 0)
    dd_outcomes = dd_accepted + dd_busy + dd_errors
    if dd_outcomes and dd_outcomes != dd_calls:
        raise ValueError("DirectDraw outcome counters disagree with Blt calls")

    gdi = totals.get("gdi_window_attempt", {})
    gdi_accepted = totals.get("gdi_present_accepted", {}).get("calls", 0)
    gdi_fallback = totals.get("gdi_present_fallback", {}).get("calls", 0)
    if mode[2]:
        # The alternative path does not invoke the DirectDraw window Blt on
        # success. Analyzing only window_present_blt would report a false zero.
        if not gdi.get("calls"):
            raise ValueError("GDI mode requires instrumented gdi_window_attempt counters")
        if gdi_accepted + gdi_fallback != gdi["calls"]:
            raise ValueError("GDI outcome counters disagree with GDI attempts")
        if dd_calls != gdi_fallback:
            raise ValueError("GDI fallback counters disagree with DirectDraw calls")
        present_calls = gdi["calls"]
        present_total_ms = gdi["total_ms"] + dd.get("total_ms", 0)
        # Exact for the expected zero-fallback GDI case; if fallback occurs,
        # each timer is a distinct phase and a combined worst call is unknown.
        present_worst_ms = max(gdi["max_ms"], dd.get("max_ms", 0))
        present_intervals = gdi["intervals"]
        slow_100ms = min(present_intervals, gdi["slow_100ms"] + dd.get("slow_100ms", 0))
        slow_1000ms = min(present_intervals, gdi["slow_1000ms"] + dd.get("slow_1000ms", 0))
        path = "gdi"
    else:
        if not dd_calls:
            raise ValueError("CSV has no completed window presentations")
        present_calls = dd_calls
        present_total_ms = dd["total_ms"]
        present_worst_ms = dd["max_ms"]
        present_intervals = dd["intervals"]
        slow_100ms = dd["slow_100ms"]
        slow_1000ms = dd["slow_1000ms"]
        path = "directdraw"

    fps = frames["calls"] / frames["logged_seconds"] if frames["logged_seconds"] else 0
    accepted = dd_accepted + gdi_accepted
    busy = dd_busy
    errors = dd_errors
    outcome_samples = dd_outcomes + gdi_accepted
    return {
        "rows": row_count,
        "mode": {"optimization": mode[0], "nowait": mode[1], "gdi": mode[2]},
        "present_path": path,
        "logged_duration_s": round(frames["logged_seconds"], 3),
        "frame_flips": frames["calls"],
        "frame_flips_per_s": round(fps, 4),
        "present_calls": present_calls,
        "present_total_s": round(present_total_ms / 1000, 4),
        "present_avg_ms": round(present_total_ms / present_calls, 4),
        "present_worst_ms": round(present_worst_ms, 4),
        "present_worst_is_exact": not bool(gdi_fallback),
        "present_intervals": present_intervals,
        "present_intervals_over_100ms": slow_100ms,
        "present_intervals_over_1000ms": slow_1000ms,
        "present_accepted_calls": accepted if outcome_samples else None,
        "present_busy_calls": busy if outcome_samples else None,
        "present_error_calls": errors if outcome_samples else None,
        "present_accepted_percent": round(100.0 * accepted / present_calls, 2) if outcome_samples else None,
        "gdi_accepted_calls": gdi_accepted if mode[2] else None,
        "gdi_fallback_calls": gdi_fallback if mode[2] else None,
    }


def make_comparison(candidate, baseline):
    measures = ("frame_flips_per_s", "present_avg_ms", "present_worst_ms",
                "present_intervals_over_1000ms")
    changes = {}
    for key in measures:
        old = baseline[key]
        new = candidate[key]
        changes[key] = round(100 * (new - old) / old, 2) if old else None
    return {
        "baseline_mode": baseline["mode"],
        "graphics_modes_match": candidate["mode"] == baseline["mode"],
        "percentage_change": changes,
        "baseline_metrics": baseline,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("run_dir", type=Path)
    parser.add_argument("--baseline", type=Path, default=None)
    args = parser.parse_args()
    if not RUN_PATTERN.fullmatch(args.run_dir.name):
        parser.error("run directory must be named autobenchmark-TIMESTAMP")
    current = analyze_csv(args.run_dir / "menuperf.csv")
    finished = (args.run_dir / "menuperf.finished").exists()
    summary = {
        "schema_version": 1,
        "run": args.run_dir.name,
        "close_requested": finished,
        "metrics": current,
    }
    # Fingerprint the reviewed test DLL without sending its executable bytes.
    benchmark_dll = args.run_dir / "benchmark-openlrr.dll"
    if benchmark_dll.is_file():
        digest = hashlib.sha256()
        with benchmark_dll.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        summary["dll_sha256"] = digest.hexdigest()
    if args.baseline:
        baseline = analyze_csv(args.baseline)
        summary["comparison"] = make_comparison(current, baseline)
        summary["baseline_run"] = args.baseline.parent.name

    report = [
        "OpenLRR unattended benchmark",
        "Run: " + args.run_dir.name,
        "Close request posted: " + ("yes (not proof of process exit)" if finished else "no"),
        "Graphics flags (optimization/nowait/gdi): {}/{}/{}".format(*current["mode"].values()),
        "Logged duration (s): {:.3f}".format(current["logged_duration_s"]),
        "Frame flips: {}".format(current["frame_flips"]),
        "Frame flips per second: {:.3f}".format(current["frame_flips_per_s"]),
        "Window presentation path: {}".format(current["present_path"]),
        "Window presentation calls: {}".format(current["present_calls"]),
        "Total window presentation time (s): {:.3f}".format(current["present_total_s"]),
        "Average window presentation (ms): {:.3f}".format(current["present_avg_ms"]),
        "Worst window presentation (ms): {:.3f}".format(current["present_worst_ms"]),
        "Sampling intervals with >100ms presentation: {}".format(current["present_intervals_over_100ms"]),
        "Sampling intervals with >1000ms presentation: {}".format(current["present_intervals_over_1000ms"]),
    ]
    if current["present_accepted_calls"] is not None:
        report.extend([
            "Accepted DirectDraw presentations: {}".format(current["present_accepted_calls"]),
            "Busy/rejected DirectDraw presentations: {}".format(current["present_busy_calls"]),
            "Other DirectDraw presentation failures: {}".format(current["present_error_calls"]),
            "Accepted presentation calls (%): {:.2f}".format(current["present_accepted_percent"]),
        ])
    if current["gdi_accepted_calls"] is not None:
        report.extend([
            "Successful GDI presentations: {}".format(current["gdi_accepted_calls"]),
            "GDI fallback-to-DirectDraw calls: {}".format(current["gdi_fallback_calls"]),
        ])
        if not current["present_worst_is_exact"]:
            report.append("Warning: worst GDI presentation timing is approximate when fallback occurs")
    if "dll_sha256" in summary:
        report.append("Reviewed test DLL SHA256: " + summary["dll_sha256"])
    if "comparison" in summary:
        comparison = summary["comparison"]
        report.extend([
            "Baseline: " + summary["baseline_run"],
            "Graphics mode flags match baseline: " + str(comparison["graphics_modes_match"]).lower(),
        ])
        for key, change in comparison["percentage_change"].items():
            report.append("Change in {} vs baseline (%): {}".format(
                key, "n/a" if change is None else "{:+.2f}".format(change)))
    (args.run_dir / "report.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    (args.run_dir / "summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("\n".join(report))


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, ValueError, csv.Error) as exc:
        raise SystemExit("Benchmark summary failed: " + str(exc))
