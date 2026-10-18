#!/usr/bin/env python3
"""One-shot visual QA research feedback from completed, verified TEST captures.

No capture, game launch, automatic patch, DLL install, model call, upload,
recurring watcher or network requests. Missing evidence stops the pipeline.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
AGENT = HERE.parent / "agent"
for path in (HERE, AGENT):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))

import bound_pair
import experiment_controller


def run_once(experiment: Path, runs_dir: Path, output: Path,
             *, pair_index: int = 0,
             baseline_file: str = "visual/menu.png",
             candidate_file: str = "visual/menu.png",
             fps: int = 2) -> dict:
    bound_pair.require_lab_active()
    destination = output.absolute()
    runs = runs_dir.resolve(strict=True)
    if destination == runs or runs in destination.parents:
        raise ValueError("QA diagnostics must stay outside source benchmark run directories")
    if destination.exists() and (not destination.is_dir() or any(destination.iterdir())):
        raise ValueError("Pipeline output must be absent or empty; refuse overwrite")
    captures_path = destination / "captures.json"
    media = bound_pair.register(experiment, runs, pair_index,
                                baseline_file, candidate_file,
                                captures_path)
    report = bound_pair.analyze(experiment, runs, captures_path,
                                destination / "analysis", fps=fps)
    # Controller rechecks receipts, hashes and score independently. This
    # deliberately does not write a research ledger or dispatch an experiment.
    decision = experiment_controller.coordinate(
        experiment, runs, destination / "read-only-ledger.json",
        visual_report=report, visual_captures=media,
        commit=False,
    )
    if decision.get("visual_capture_binding_verified") is not True or (
            decision.get("may_deploy_automatically") is not False or
            decision.get("may_touch_working_game") is not False):
        raise ValueError("Controller did not confirm isolated visual evidence")
    bound_pair.save_new_json(destination / "research-decision.json", decision)
    return {
        "experiment_id": report["experiment_id"],
        "visual_status": report["status"],
        "visual_score": report["score"],
        "research_next_step": decision["next_step"],
        "capture_origin_authenticated": False,
        "working_game_modified": False,
        "automatic_execution": False,
        "report_path": str(destination / "analysis/report.json"),
        "decision_path": str(destination / "research-decision.json"),
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--experiment", type=Path, required=True)
    parser.add_argument("--runs-dir", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--pair-index", type=int, default=0)
    parser.add_argument("--baseline-file", default="visual/menu.png")
    parser.add_argument("--candidate-file", default="visual/menu.png")
    parser.add_argument("--fps", type=int, default=2)
    args = parser.parse_args(argv)
    try:
        result = run_once(args.experiment, args.runs_dir, args.out,
                          pair_index=args.pair_index,
                          baseline_file=args.baseline_file,
                          candidate_file=args.candidate_file, fps=args.fps)
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except (ValueError, OSError, RuntimeError, TypeError, json.JSONDecodeError) as exc:
        print("VISUAL PIPELINE STOPPED: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
