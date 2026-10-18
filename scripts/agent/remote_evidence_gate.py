#!/usr/bin/env python3
"""Deterministic private A/B evidence evaluation on GitHub (no game/model).

Only accepts verified uploaded supervisor receipts and exact distinct-DLL
manifests. Cloud reports are read-only decision support, not permissions for
unreviewed executable deployment or assertions about displayed FPS.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import evidence_gate
import lab_policy

MAX_MANIFEST_SIZE = 100_000
MAX_REPORT_SIZE = 100_000


def evaluate(manifest: Path, runs_root: Path) -> dict:
    if manifest.is_symlink() or not manifest.is_file() or manifest.stat().st_size > MAX_MANIFEST_SIZE:
        raise ValueError("Missing, symlinked or oversized experiment manifest")
    if runs_root.is_symlink() or not runs_root.is_dir():
        raise ValueError("Invalid private results directory")
    blob = manifest.read_bytes()
    if not blob or b"\x00" in blob:
        raise ValueError("Invalid manifest encoding")
    doc = json.loads(blob.decode("utf-8"))
    if type(doc) is not dict:
        raise ValueError("Malformed experiment manifest")
    # evidence_gate re-opens EVERY declared run, enforces exact lifecycle
    # receipts, checks distinct DLLs and flags, applies conservative
    # throughput/correctness guards, and requires >=5 comparable A/B pairs.
    gate = evidence_gate.decision(doc, runs_root)
    transition = lab_policy.decide(gate)
    if gate["status"] == "candidate_for_review":
        if (transition["next_step"] != "hold_for_review" or
            gate["visual_fps_verified"] is not False):
            raise ValueError("Promising results lack required human review")
    return {
        "schema_version": 1,
        "experiment_id": gate["experiment_id"],
        "source_manifest_sha256": hashlib.sha256(blob).hexdigest(),
        "evidence_gate": gate,
        "research_policy": transition,
        "source_of_run_evidence": "private_supervisor_uploads",
        "computer_or_game_executed": False,
        "openai_model_invoked": False,
        "may_execute_candidate": False,
        "may_change_working_game": False,
        "may_deploy_automatically": False,
        "next_owner_action": (
            "human_visual_review" if gate["status"] == "candidate_for_review"
            else "continue_research_without_promotion"
        ),
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--runs-dir", type=Path, required=True)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)
    outcome = evaluate(args.manifest, args.runs_dir)
    data = json.dumps(outcome, indent=2, sort_keys=True) + "\n"
    if len(data.encode("utf-8")) > MAX_REPORT_SIZE:
        raise ValueError("Remote evidence report unexpectedly large")
    if args.out:
        if args.out.exists():
            raise RuntimeError("Output already exists; avoid overwriting evidence")
        args.out.parent.mkdir(parents=True, exist_ok=True)
        with args.out.open("x", encoding="utf-8") as output:
            output.write(data)
    print(data, end="")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, OSError, json.JSONDecodeError) as exc:
        print("PRIVATE EVIDENCE REJECTED:", exc, file=sys.stderr)
        raise SystemExit(2)
