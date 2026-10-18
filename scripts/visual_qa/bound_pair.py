#!/usr/bin/env python3
"""Register and analyze visuals attached to existing verified TEST benchmarks.

Offline tool: never launches games, takes screenshots, makes network requests,
executes candidate binaries, changes game files or grants deployment authority.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys

AGENT = Path(__file__).resolve().parents[1] / "agent"
if str(AGENT) not in sys.path:
    sys.path.insert(0, str(AGENT))

import evidence_gate
from visual_capture_binding import (
    bounded_json, regular_unlinked, sha256_file,
    verified_capture_binding, verify_bound_report,
)
from qa import report_for

SWITCHES = Path.home() / ".config/openlrr-benchmark"


def require_lab_active() -> None:
    if (SWITCHES / "STOP").exists() or (SWITCHES / "PAUSE").exists():
        raise ValueError("Lab STOP or PAUSE active; no further capture processing")


def validate_experiment(experiment: Path, runs_dir: Path) -> dict:
    bundle = bounded_json(experiment)
    # Rebuild benchmark conclusions from independently checked Mac lifecycle
    # receipts. Do not accept a user-supplied 'verified' status.
    evidence_gate.decision(bundle, runs_dir)
    return bundle


def save_new_json(out: Path, doc: dict) -> None:
    raw = out.absolute()
    if any(p.is_symlink() for p in (raw, *raw.parents)):
        raise ValueError("Manifest output cannot pass through a symlink")
    if any((folder / "LegoRR.exe").exists() for folder in (raw.parent, *raw.parents)):
        raise ValueError("Refusing to write inside original game installation")
    out.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as writer:
        writer.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
        writer.flush()
        os.fsync(writer.fileno())


def register(experiment: Path, runs_dir: Path, pair_index: int,
             baseline_file: str, candidate_file: str, out: Path) -> dict:
    require_lab_active()
    bundle = validate_experiment(experiment, runs_dir)
    if type(pair_index) is not int or not 0 <= pair_index < len(bundle["pairs"]):
        raise ValueError("Experiment pair index invalid")
    pair = bundle["pairs"][pair_index]
    captures = {}
    for arm, filename in (("baseline", baseline_file), ("candidate", candidate_file)):
        name = pair[arm]
        if not isinstance(filename, str):
            raise ValueError("Invalid media filename")
        # This path is subsequently validated against the strict media
        # allowlist before any file is opened.
        from visual_capture_binding import CAPTURE_FILE
        if not CAPTURE_FILE.fullmatch(filename):
            raise ValueError("Capture must be located under run/visual/")
        run = runs_dir / name
        summary = regular_unlinked(run / "summary.json")
        capture = regular_unlinked(run / filename)
        captures[arm] = {
            "run": name, "file": filename,
            "sha256": sha256_file(capture),
            "summary_sha256": sha256_file(summary),
        }
    manifest = {
        "schema_version": 1,
        "experiment_id": bundle["experiment_id"],
        "pair_index": pair_index,
        "scene": bundle["controlled_scene"],
        "captures": captures,
    }
    verified_capture_binding(bundle, runs_dir, manifest)
    save_new_json(out, manifest)
    return manifest


def analyze(experiment: Path, runs_dir: Path, captures: Path, out: Path,
            fps: int = 2, tolerance: int = 12, min_score: float = 94) -> dict:
    require_lab_active()
    bundle = validate_experiment(experiment, runs_dir)
    media_manifest = bounded_json(captures)
    binding, reference, candidate = verified_capture_binding(
        bundle, runs_dir, media_manifest)
    result = report_for(reference, candidate, out, bundle["experiment_id"],
                        bundle["controlled_scene"], fps=fps,
                        tolerance=tolerance, min_score=min_score)
    # File hashing is repeated AFTER processing to catch changed inputs. A
    # later controller call rechecks all hashes independently.
    result["capture_binding"] = binding
    verify_bound_report(bundle, runs_dir, media_manifest, result, recheck_pixels=False)
    destination = out / "report.json"
    temp = out / "report-bound.tmp"
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as writer:
            writer.write(json.dumps(result, indent=2, sort_keys=True) + "\n")
            writer.flush()
            os.fsync(writer.fileno())
        os.replace(temp, destination)
    finally:
        temp.unlink(missing_ok=True)
    return result


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    cmds = parser.add_subparsers(dest="command", required=True)
    for mode in ("register", "analyze"):
        sub = cmds.add_parser(mode)
        sub.add_argument("--experiment", type=Path, required=True)
        sub.add_argument("--runs-dir", type=Path, required=True)
        sub.add_argument("--out", type=Path, required=True)
        if mode == "register":
            sub.add_argument("--pair-index", type=int, default=0)
            sub.add_argument("--baseline-file", required=True)
            sub.add_argument("--candidate-file", required=True)
        else:
            sub.add_argument("--captures", type=Path, required=True)
            sub.add_argument("--fps", type=int, default=2)
            sub.add_argument("--tolerance", type=int, default=12)
            sub.add_argument("--min-score", type=float, default=94)
    opts = parser.parse_args(argv)
    try:
        if opts.command == "register":
            record = register(opts.experiment, opts.runs_dir, opts.pair_index,
                              opts.baseline_file, opts.candidate_file, opts.out)
            print(json.dumps({"registered": record["experiment_id"],
                              "pair_index": record["pair_index"],
                              "automatic_deployment": False}))
        else:
            report = analyze(opts.experiment, opts.runs_dir, opts.captures,
                             opts.out, fps=opts.fps, tolerance=opts.tolerance,
                             min_score=opts.min_score)
            print(json.dumps({"status": report["status"], "score": report["score"],
                              "report": str(opts.out / "report.json"),
                              "capture_origin_authenticated": False}))
        return 0
    except (OSError, ValueError, RuntimeError, TypeError, json.JSONDecodeError) as exc:
        print("CAPTURE BINDING STOPPED: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
