#!/usr/bin/env python3
"""Safely discover and quarantine new compiled OpenLRR candidates, never run them."""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import re
import sys

SCRIPT = Path(__file__).resolve().with_name("candidate-inbox.py")
SPEC = importlib.util.spec_from_file_location("candidate_inbox", SCRIPT)
inbox = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inbox)

WORKFLOW_FILES = ("lab-ai-proposal.yml", "lab-evidence-proposal.yml")
VALID = re.compile(r"^[0-9]{8,14}$")


def list_recent():
    seen = set()
    for workflow in WORKFLOW_FILES:
        try:
            raw = inbox.gh(
                "run", "list", "--repo", inbox.REPO, "--workflow", workflow,
                "--limit", "15", "--json", "databaseId,status,conclusion")
            runs = json.loads(raw)
        except (RuntimeError, ValueError, json.JSONDecodeError):
            # Workflow may not exist on the default branch yet.
            continue
        if not isinstance(runs, list):
            continue
        for run in runs:
            if not isinstance(run, dict):
                continue
            candidate = str(run.get("databaseId", ""))
            if not VALID.fullmatch(candidate) or candidate in seen:
                continue
            if run.get("status") == "completed" and run.get("conclusion") == "success":
                seen.add(candidate)
                yield candidate


def scan(*, dry_run: bool = True):
    if (inbox.CONFIG / "STOP").exists() or (inbox.CONFIG / "PAUSE").exists():
        raise RuntimeError("STOP/PAUSE active")
    successes = []
    inspected = []
    for run_id in list_recent():
        if len(inspected) >= 8:
            break
        if (inbox.INBOX / ("run-" + run_id)).exists():
            continue
        inspected.append(run_id)
        if dry_run:
            continue
        try:
            staged = inbox.stage(run_id)
        except ValueError as exc:
            # Successful research abstention intentionally lacks a DLL.
            # Any other unexpected artifact is surfaced, not silently used.
            if "No compiled candidate artifact" in str(exc):
                continue
            raise
        successes.append({"run_id": run_id, **staged})
    return {"inspected": inspected, "quarantined": successes,
            "executed_anything": False, "modified_game": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quarantine", action="store_true",
                        help="Actually retrieve and quarantine eligible artifacts")
    args = parser.parse_args()
    print(json.dumps(scan(dry_run=not args.quarantine), indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
        print("INBOX SCAN STOP:", exc, file=sys.stderr)
        raise SystemExit(2)
