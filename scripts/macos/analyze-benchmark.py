#!/usr/bin/env python3
"""Summarize OpenLRR telemetry without exposing Mac paths or game assets.

Usage: python3 analyze-benchmark.py RUN_DIR [--baseline BASELINE_CSV]
Only two text artifacts are created: report.txt and summary.json.
"""
import argparse
import csv
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
    present = totals.get("window_present_blt", {})
    if not frames.get("calls") or not present.get("calls"):
        raise ValueError("CSV has no completed frame flips or window presentations")
    if len(modes) != 1:
        raise ValueError("CSV contains inconsistent graphics-mode flags")
    fps = frames["calls"] / frames["logged_seconds"] if frames["logged_seconds"] else 0
    mode = next(iter(modes))
    return {
        "rows": row_count,
        "mode": {"optimization": mode[0], "nowait": mode[1], "gdi": mode[2]},
        "logged_duration_s": round(frames["logged_seconds"], 3),
        "frame_flips": frames["calls"],
        "frame_flips_per_s": round(fps, 4),
        "present_calls": present["calls"],
        "present_total_s": round(present["total_ms"] / 1000, 4),
        "present_avg_ms": round(present["total_ms"] / present["calls"], 4),
        "present_worst_ms": round(present["max_ms"], 4),
        "present_intervals": present["intervals"],
        "present_intervals_over_100ms": present["slow_100ms"],
        "present_intervals_over_1000ms": present["slow_1000ms"],
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
        "Window presentation calls: {}".format(current["present_calls"]),
        "Total window presentation time (s): {:.3f}".format(current["present_total_s"]),
        "Average window presentation (ms): {:.3f}".format(current["present_avg_ms"]),
        "Worst window presentation (ms): {:.3f}".format(current["present_worst_ms"]),
        "Sampling intervals with >100ms presentation: {}".format(current["present_intervals_over_100ms"]),
        "Sampling intervals with >1000ms presentation: {}".format(current["present_intervals_over_1000ms"]),
    ]
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
