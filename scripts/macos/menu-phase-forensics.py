#!/usr/bin/env python3
"""Read-only phase/cadence analysis of reviewed OpenLRR menuperf CSV files.

Does NOT launch Wine, choose an optimization, or assert visible FPS. A repeated
CSV 'seconds' value is an interval duration, never an interval identifier.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
from collections import Counter
from pathlib import Path
import re
import sys

HEADER = ["seconds", "optimization", "nowait", "gdi", "operation",
          "calls", "total_ms", "max_ms"]
LAST_METRIC = "window_blt_slow_low_cpu"
REQUIRED = {"movie_update", "frame_flip", "window_present_blt",
            "window_blt_over_1000ms", "window_blt_slow_thread_cpu",
            "frame_outside_flip", LAST_METRIC}
MAX_CSV_BYTES = 3_000_000
MAX_INTERVALS = 1000
NAME = re.compile(r"^autobenchmark-\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d$")


def read_intervals(csv_path: Path) -> list[dict]:
    """Build separate groups by last known metric; reject partial/alien groups."""
    if csv_path.is_symlink() or not csv_path.is_file():
        raise ValueError("Missing or unsafe telemetry CSV")
    if not 0 < csv_path.stat().st_size <= MAX_CSV_BYTES:
        raise ValueError("Missing, empty or oversized telemetry CSV")
    groups = []
    current = {}
    current_sec = None
    current_mode = None
    with csv_path.open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames != HEADER:
            raise ValueError("Unrecognized telemetry columns")
        for row in reader:
            if None in row or any(v is None for v in row.values()):
                raise ValueError("Malformed telemetry row")
            op = row["operation"]
            if not re.fullmatch(r"[a-z0-9_]{1,48}", op) or op in current:
                raise ValueError("Unexpected or duplicated operation")
            try:
                seconds = float(row["seconds"])
                mode = tuple(int(row[k]) for k in ("optimization", "nowait", "gdi"))
                calls = int(row["calls"])
                total_ms = float(row["total_ms"])
                max_ms = float(row["max_ms"])
            except (TypeError, ValueError) as err:
                raise ValueError("Invalid telemetry value") from err
            if (not all(math.isfinite(v) for v in (seconds, total_ms, max_ms))
                    or not 0 < seconds < 1000 or calls < 0
                    or min(total_ms, max_ms) < 0
                    or any(value not in (0, 1) for value in mode)):
                raise ValueError("Out-of-range telemetry value")
            if current_sec is None:
                current_sec, current_mode = seconds, mode
            elif current_sec != seconds or current_mode != mode:
                raise ValueError("Inconsistent interval mode or duration")
            current[op] = {"calls": calls, "total_ms": total_ms, "max_ms": max_ms}
            if op == LAST_METRIC:
                if not REQUIRED.issubset(current):
                    raise ValueError("Missing expected instrumentation")
                groups.append({"interval": len(groups), "seconds": seconds,
                               "mode": mode, "measurements": current})
                if len(groups) > MAX_INTERVALS:
                    raise ValueError("Too many intervals")
                current = {}
                current_sec = None
                current_mode = None
    if current:
        raise ValueError("Incomplete final telemetry interval")
    if len(groups) < 4:
        raise ValueError("Insufficient completed telemetry intervals")
    if len({g["mode"] for g in groups}) != 1:
        raise ValueError("Mixed graphics modes within one run")
    return groups


def metric(g: dict, name: str, key="calls") -> float:
    return g["measurements"][name][key]


def quantile(data: list[float], fraction: float) -> float | None:
    if not data:
        return None
    ordered = sorted(data)
    if len(ordered) == 1:
        return ordered[0]
    idx = fraction * (len(ordered) - 1)
    lower = math.floor(idx)
    return ordered[lower] + (ordered[math.ceil(idx)] - ordered[lower]) * (idx - lower)


def summarise(intervals: list[dict], *, label: str) -> dict:
    if not NAME.fullmatch(label):
        raise ValueError("Benchmark run must use its verified run directory name")
    movie_indices = [i for i, g in enumerate(intervals) if metric(g, "movie_update") > 0]
    if not movie_indices:
        raise ValueError("Movie phase not identified; cannot claim post-movie result")
    last_movie = max(movie_indices)
    movie = intervals[:last_movie + 1]
    post_movie = intervals[last_movie + 1:]
    # Avoid treating the first two zero-movie transition intervals as a stable
    # menu phase. No screenshots: this is ONLY a post-movie telemetry proxy.
    steady = post_movie[2:]
    if len(steady) < 3:
        raise ValueError("Insufficient steady post-movie intervals")
    long = [g for g in steady if metric(g, "window_blt_over_1000ms") > 0]
    maxima = [metric(g, "window_present_blt", "max_ms") for g in long]
    total_seconds = sum(g["seconds"] for g in steady)
    present_ms = sum(metric(g, "window_present_blt", "total_ms") for g in steady)
    flips = sum(metric(g, "frame_flip") for g in steady)
    blits = sum(metric(g, "window_present_blt") for g in steady)
    slow_count = sum(metric(g, "window_blt_over_1000ms") for g in steady)
    outside_ms = sum(metric(g, "frame_outside_flip", "total_ms") for g in steady)
    cpu_long = sum(metric(g, "window_blt_slow_thread_cpu", "total_ms") for g in steady)
    cpu_count = sum(metric(g, "window_blt_slow_thread_cpu") for g in steady)
    histogram = Counter(str(int(metric(g, "window_present_blt"))) for g in long)
    return {
        "schema_version": 1,
        "run": label,
        "graphics_mode": dict(zip(("optimization", "nowait", "gdi"), intervals[0]["mode"])),
        "reviewed_caution": "CPU-side logical presentation, NOT visible FPS or a driver root-cause attribution",
        "complete_interval_count": len(intervals),
        "movie_update_calls": sum(metric(g, "movie_update") for g in movie),
        "movie_phase_interval_count": len(movie),
        "transition_zero_movie_intervals_excluded": min(len(post_movie), 2),
        "steady_post_movie_proxy_interval_count": len(steady),
        "steady_post_movie_proxy_duration_s": round(total_seconds, 3),
        "steady_post_movie_proxy_logical_flips_per_s": round(flips / total_seconds, 4),
        "steady_post_movie_proxy_present_time_fraction": round(present_ms / (total_seconds * 1000), 4),
        "steady_post_movie_proxy_outside_flip_fraction": round(outside_ms / (total_seconds * 1000), 4),
        "steady_post_movie_proxy_blt_calls": blits,
        "steady_post_movie_proxy_blt_calls_over_1000ms": slow_count,
        "steady_post_movie_proxy_intervals_with_long_blt": len(long),
        "steady_post_movie_proxy_long_interval_fraction": round(len(long) / len(steady), 4),
        "steady_post_movie_proxy_slow_blt_max_median_ms": round(quantile(maxima, .5), 3) if maxima else None,
        "steady_post_movie_proxy_slow_blt_max_p10_ms": round(quantile(maxima, .1), 3) if maxima else None,
        "steady_post_movie_proxy_slow_blt_max_p90_ms": round(quantile(maxima, .9), 3) if maxima else None,
        "steady_post_movie_proxy_blt_calls_per_long_interval": dict(sorted(histogram.items(), key=lambda p: int(p[0]))),
        "slow_blt_calling_thread_cpu_valid_samples": cpu_count,
        "slow_blt_calling_thread_cpu_avg_ms": round(cpu_long / cpu_count, 3) if cpu_count else None,
        "phase_is_screen_verified": False,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=Path,
                        help="Existing local .../autobenchmark-YYYY-MM-DD_HH-MM-SS/menuperf.csv")
    args = parser.parse_args(argv)
    reports = []
    for path in args.paths:
        if path.name != "menuperf.csv" or not NAME.fullmatch(path.parent.name):
            parser.error("Each input must be a benchmark run's menuperf.csv")
        reports.append(summarise(read_intervals(path), label=path.parent.name))
    print(json.dumps({"schema_version": 1, "read_only": True,
                      "files_processed": len(reports),
                      "reports": reports}, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, UnicodeError, csv.Error) as exc:
        print("TELEMETRY ANALYSIS BLOCKED:", exc, file=sys.stderr)
        raise SystemExit(2)
