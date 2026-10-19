#!/usr/bin/env python3
"""Evidence gate for OpenLRR experimental benchmark trials.

Offline and deterministic. This does not call OpenAI, execute a game, merge code,
or make a claim about visible FPS. It reads verified local Mac supervisor runs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import re
import statistics
import sys

RUN_RE = re.compile(r"^autobenchmark-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$")
ID_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_-]{2,63}$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
MIN_PAIRS = 5
MAX_PAIRS = 12
REVIEW_MIN_EFFECT = 0.10  # median presentation-time reduction of >=10%
BOOTSTRAP_UPPER_LIMIT = -0.05  # 95% upper percentile still indicates >5% gain
MAX_SLOWDOWN_FPS = 0.02
LIFECYCLE_RECEIPT = "wrapper_wait_exited=yes\ntest_game_handles=none\n"


def finite_number(value, label, *, minimum=0, maximum=1e9) -> float:
    if type(value) not in (float, int) or not math.isfinite(value):
        raise ValueError("Missing/non-numeric " + label)
    if not minimum <= value <= maximum:
        raise ValueError("Out-of-range " + label)
    return float(value)


def load_verified_run(folder: Path, name: str) -> dict:
    """Read an ordinary run produced by our Mac supervisor, never model text."""
    if not RUN_RE.fullmatch(name):
        raise ValueError("Unsafe run identifier")
    base = folder.resolve()
    run = (folder / name).resolve()
    if run.parent != base:
        raise ValueError("Run escapes results directory")
    receipt = run / "lifecycle.verified"
    if not receipt.is_file() or receipt.read_text(encoding="utf-8") != LIFECYCLE_RECEIPT:
        raise ValueError("Unverified Mac test lifecycle: " + name)
    data = json.loads((run / "summary.json").read_text(encoding="utf-8"))
    if data.get("schema_version") != 1 or data.get("run") != name:
        raise ValueError("Mismatched benchmark summary")
    if data.get("close_requested") is not True:
        raise ValueError("Game did not request a clean close")
    sha = data.get("dll_sha256")
    if not isinstance(sha, str) or not SHA_RE.fullmatch(sha):
        raise ValueError("Unverified DLL identity")
    raw = data.get("metrics")
    if not isinstance(raw, dict):
        raise ValueError("Metrics missing")
    mode = raw.get("mode")
    if type(mode) is not dict or set(mode) != {"optimization", "nowait", "gdi"} or any(
        type(v) is not int or v not in (0, 1) for v in mode.values()
    ):
        raise ValueError("Unrecognized graphics mode")
    for field in ("present_avg_ms", "frame_flips_per_s", "logged_duration_s",
                  "present_calls", "present_accepted_percent",
                  "present_error_calls", "present_busy_calls",
                  "present_intervals_over_1000ms"):
        finite_number(raw.get(field), field)
    if not 30 <= raw["logged_duration_s"] <= 305:
        raise ValueError("Run duration outside controlled experiment bounds")
    if raw["present_avg_ms"] <= 0 or raw["present_calls"] < 30:
        raise ValueError("Not enough presentation measurements")
    return {
        "run": name, "sha": sha, "mode": mode,
        "present_ms": float(raw["present_avg_ms"]),
        "fps_proxy": float(raw["frame_flips_per_s"]),
        "duration_s": float(raw["logged_duration_s"]),
        "accepted_pct": float(raw["present_accepted_percent"]),
        "busy": float(raw["present_busy_calls"]),
        "errors": float(raw["present_error_calls"]),
        "slow_intervals": float(raw["present_intervals_over_1000ms"]),
    }


def quantile(sorted_numbers: list[float], q: float) -> float:
    position = (len(sorted_numbers) - 1) * q
    low = int(position)
    high = min(low + 1, len(sorted_numbers) - 1)
    if high == low:
        return sorted_numbers[low]
    return sorted_numbers[low] * (high - position) + sorted_numbers[high] * (position - low)


def upper_bootstrap(changes: list[float]) -> float:
    rng = random.Random(99171)
    medians = []
    for _ in range(4000):
        sample = [changes[rng.randrange(len(changes))] for _ in changes]
        medians.append(statistics.median(sample))
    medians.sort()
    return quantile(medians, 0.95)


def decision(bundle: dict, folder: Path) -> dict:
    if type(bundle) is not dict or bundle.get("schema_version") != 1:
        raise ValueError("Unsupported experiment manifest")
    experiment_id = bundle.get("experiment_id")
    if not isinstance(experiment_id, str) or not ID_RE.fullmatch(experiment_id):
        raise ValueError("Invalid experiment identifier")
    hypothesis = bundle.get("hypothesis")
    if not isinstance(hypothesis, str) or not 15 <= len(hypothesis) <= 500:
        raise ValueError("Experiment must state a specific, bounded hypothesis")
    pairs = bundle.get("pairs")
    if not isinstance(pairs, list) or not 1 <= len(pairs) <= MAX_PAIRS:
        raise ValueError("Expected 1..12 paired tests")
    baseline, candidate = [], []
    used = set()
    for pair in pairs:
        if not isinstance(pair, dict) or set(pair) != {"baseline", "candidate"}:
            raise ValueError("Expected baseline/candidate pair")
        for key, into in (("baseline", baseline), ("candidate", candidate)):
            name = pair[key]
            if type(name) is not str or name in used:
                raise ValueError("Duplicate/invalid trial identifier")
            used.add(name)
            into.append(load_verified_run(folder, name))

    base_shas = {r["sha"] for r in baseline}
    candidate_shas = {r["sha"] for r in candidate}
    base_modes = {tuple(sorted(r["mode"].items())) for r in baseline}
    candidate_modes = {tuple(sorted(r["mode"].items())) for r in candidate}
    if len(base_shas) != 1 or len(candidate_shas) != 1 or len(base_modes) != 1 or len(candidate_modes) != 1:
        raise ValueError("Each arm must use a consistent DLL and graphics mode")
    if base_shas == candidate_shas and base_modes == candidate_modes:
        raise ValueError("No experimental intervention (identical DLL and flags)")
    if bundle.get("controlled_scene") != "menu_boot_autotest_v1":
        raise ValueError("Scene/load condition is not certified by the harness")
    if any(abs(b["duration_s"] - c["duration_s"]) > max(7, 0.1 * b["duration_s"])
           for b, c in zip(baseline, candidate)):
        raise ValueError("Paired tests have incomparable durations")

    deltas = [(c["present_ms"] / b["present_ms"]) - 1 for b, c in zip(baseline, candidate)]
    fps_delta = [(c["fps_proxy"] / b["fps_proxy"]) - 1
                 for b, c in zip(baseline, candidate) if b["fps_proxy"] > 0]
    common = {
        "schema_version": 1,
        "experiment_id": experiment_id,
        "hypothesis": hypothesis,
        "pairs": len(pairs),
        "baseline_sha": next(iter(base_shas)),
        "candidate_sha": next(iter(candidate_shas)),
        "median_present_change_pct": round(100 * statistics.median(deltas), 2),
        "bootstrap_upper95_change_pct": round(100 * upper_bootstrap(deltas), 2),
        "median_logical_fps_change_pct": round(100 * statistics.median(fps_delta), 2)
        if fps_delta else None,
        "visual_fps_verified": False,
        "automatic_promotion_allowed": False,
    }

    def conclude(status: str, reason: str, next_action: str):
        return {**common, "status": status, "reason": reason, "next_action": next_action,
                "notify_human": status == "candidate_for_review"}

    if any(c["errors"] or c["busy"] or c["accepted_pct"] < 99.5 for c in candidate):
        return conclude("regression", "New present errors, busy calls or rejected frames.",
                        "Do not promote; investigate failed presentation and try a different hypothesis.")
    if any(c["fps_proxy"] < b["fps_proxy"] * (1 - MAX_SLOWDOWN_FPS)
           for b, c in zip(baseline, candidate)):
        return conclude("regression", "Logical frame throughput declined >2% in a paired run.",
                        "Investigate throughput loss; do not infer visual FPS from this proxy.")
    if any(c["slow_intervals"] > b["slow_intervals"] + 2
           for b, c in zip(baseline, candidate)):
        return conclude("regression", "Severe presentation stalls increased.",
                        "Investigate stalled frames before any additional optimization.")
    if len(pairs) < MIN_PAIRS:
        return conclude("needs_more_data", "Insufficient repeated paired trials.",
                        f"Collect {MIN_PAIRS - len(pairs)} more matched A/B trials only if this hypothesis is still plausible.")
    median_change = statistics.median(deltas)
    upper = upper_bootstrap(deltas)
    if median_change <= -REVIEW_MIN_EFFECT and upper < BOOTSTRAP_UPPER_LIMIT:
        return conclude("candidate_for_review",
                        "Consistent, material presentation-time benefit across paired runs; "
                        "still NOT proof of display smoothness.",
                        "Create a private review issue. Ask human to test on-screen quality; do not merge.")
    if median_change >= 0.05:
        return conclude("no_improvement",
                        "Presentations were slower, with no actionable gain.",
                        "Reject this hypothesis and choose a different bottleneck or architecture.")
    if abs(median_change) < 0.05 and abs(upper) < 0.1:
        return conclude("no_improvement",
                        "Measured difference is smaller than a useful effect threshold.",
                        "Do not endlessly repeat unchanged tests; find a different explanation.")
    return conclude("inconclusive",
                    "Results are noisy or the uncertainty interval does not support a meaningful gain.",
                    "Investigate variability and improve instrumentation before another candidate.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--runs-dir", type=Path, default=Path.home() / "Downloads" / "OpenLRR Benchmark Runs")
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args(argv)
    data = json.loads(args.manifest.read_text(encoding="utf-8"))
    result = decision(data, args.runs_dir)
    content = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(content, encoding="utf-8")
    print(content, end="")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print("EVIDENCE REJECTED:", exc, file=sys.stderr)
        raise SystemExit(2)
