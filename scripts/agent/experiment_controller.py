#!/usr/bin/env python3
"""Verified, single-cycle coordinator for the OpenLRR AI laboratory.

The coordinator evaluates an actual manifest through evidence_gate, chooses a
policy action, and writes a deduplicated, bounded durable decision ledger.
It never trusts model-provided "verified" flags. It never runs a game, shells
out to an AI, downloads DLLs, merges source or deploys anything.

A future trusted worker may consume the action/next_step fields. This module
DOES NOT authorize the worker to execute a new DLL.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sys

import evidence_gate
import lab_policy

LEDGER_SCHEMA = 1
MAX_LEDGER_ROWS = 1000
MAX_DAILY_RESEARCH_REQUESTS = 3
MAX_REPORT_BYTES = 100_000
MAX_LEDGER_BYTES = 1_000_000
STOP_DIR = Path.home() / ".config/openlrr-benchmark"
DEFAULT_LEDGER = Path.home() / ".local/share/openlrr-agent/research-controller.json"
IDENTITY = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_-]{2,63}$")
SUPPORTED_ACTIONS = frozenset({
    "complete_paired_measurement", "improve_instrumentation",
    "new_hypothesis", "isolate_regression", "hold_for_review",
    "prepare_manual_acceptance_check", "revise_hypothesis_from_feedback",
    "abandon_experiment_family",
})
# These decisions spend no API credits themselves, but are budgeted because
# future model work could be requested to follow them.
RESEARCH_ACTIONS = frozenset({
    "improve_instrumentation", "new_hypothesis",
    "isolate_regression", "revise_hypothesis_from_feedback"
})


def canonical(value: dict) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def bounded_json(path: Path, *, limit: int = MAX_REPORT_BYTES) -> dict:
    if not path.is_file() or path.stat().st_size > limit:
        raise ValueError("Input is missing or exceeds maximum size")
    doc = json.loads(path.read_text(encoding="utf-8"))
    if type(doc) is not dict:
        raise ValueError("Expected a JSON object")
    return doc


def validated_feedback(feedback: dict | None, experiment_id: str):
    if feedback is None:
        return None
    if type(feedback) is not dict:
        raise ValueError("Feedback must be an object")
    if feedback.get("experiment_id") != experiment_id:
        raise ValueError("Review feedback belongs to another experiment")
    if feedback.get("automatic_deploy_allowed") is not False:
        raise ValueError("Review must prohibit auto-deployment")
    # Feedback MUST come from trusted review_queue retrieval and be checked
    # against the matching experiment ID. The local-file CLI cannot attest to
    # GitHub comment identity; do not grant it any code-execution powers.
    return {
        "decision": feedback.get("decision"),
        "reason": feedback.get("reason", ""),
        "automatic_deploy_allowed": False,
    }


def read_ledger(path: Path) -> dict:
    if not path.exists():
        return {"schema_version": LEDGER_SCHEMA, "events": []}
    if path.is_symlink():
        raise ValueError("Controller ledger cannot be a symlink")
    raw = bounded_json(path, limit=MAX_LEDGER_BYTES)
    if set(raw) != {"schema_version", "events"} or raw["schema_version"] != LEDGER_SCHEMA:
        raise ValueError("Unknown ledger schema")
    rows = raw["events"]
    if type(rows) is not list or len(rows) > MAX_LEDGER_ROWS:
        raise ValueError("Invalid ledger length")
    fingerprints = set()
    for event in rows:
        if type(event) is not dict or set(event) != {
            "fingerprint", "experiment_id", "next_step", "utc_day"
        }:
            raise ValueError("Malformed ledger event")
        token = event["fingerprint"]
        if not isinstance(token, str) or not re.fullmatch(r"[a-f0-9]{64}", token):
            raise ValueError("Invalid ledger fingerprint")
        if token in fingerprints:
            raise ValueError("Duplicate event in ledger")
        fingerprints.add(token)
        if not isinstance(event["experiment_id"], str) or not IDENTITY.fullmatch(event["experiment_id"]):
            raise ValueError("Invalid stored experiment identity")
        if event["next_step"] not in SUPPORTED_ACTIONS:
            raise ValueError("Invalid stored action")
        if not isinstance(event["utc_day"], str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", event["utc_day"]):
            raise ValueError("Invalid stored event date")
    return raw


def decision_for(report: dict, ledger: dict, *, feedback=None, now: datetime | None = None):
    if type(report) is not dict or report.get("schema_version") != 1:
        raise ValueError("Requires verified evidence-gate report")
    exp = report.get("experiment_id")
    if not isinstance(exp, str) or not IDENTITY.fullmatch(exp):
        raise ValueError("Missing experiment identity")
    if report.get("automatic_promotion_allowed") is not False or report.get("visual_fps_verified") is not False:
        raise ValueError("Unsupported evidence authority")
    if report.get("status") == "candidate_for_review" and report.get("notify_human") is not True:
        raise ValueError("Promising candidate missing review marker")
    if report.get("status") != "candidate_for_review" and report.get("notify_human") is not False:
        raise ValueError("Unexpected human notification")
    cleaned = validated_feedback(feedback, exp)
    step = lab_policy.decide(report, cleaned)
    action = step["next_step"]
    if action not in SUPPORTED_ACTIONS:
        raise ValueError("Unknown policy action")
    decision_input = {"report": report, "feedback": cleaned}
    fingerprint = hashlib.sha256(canonical(decision_input).encode("ascii")).hexdigest()
    day = (now or datetime.now(timezone.utc)).astimezone(timezone.utc).date().isoformat()
    past = ledger["events"]
    duplicate = any(p["fingerprint"] == fingerprint for p in past)
    if duplicate:
        disposition = "already_processed"
    else:
        today_requests = sum(
            p["utc_day"] == day and p["next_step"] in RESEARCH_ACTIONS for p in past
        )
        if action in RESEARCH_ACTIONS and today_requests >= MAX_DAILY_RESEARCH_REQUESTS:
            disposition = "daily_research_budget_exhausted"
        elif action == "hold_for_review":
            disposition = "ready_to_notify_privately"
        elif action in RESEARCH_ACTIONS:
            disposition = "ready_for_new_research"
        else:
            disposition = "requires_safe_worker_or_human"
    return {
        "schema_version": 1,
        "experiment_id": exp,
        "fingerprint": fingerprint,
        "disposition": disposition,
        "next_step": action,
        "why": step["why"],
        "request_human_review": step["request_human_review"],
        "utc_day": day,
        "may_install_or_run_candidate": False,
        "may_touch_working_game": False,
        "may_deploy_automatically": False,
        "model_invoked": False,
        "candidate_compiled": False,
    }


def append_ledger(path: Path, ledger: dict, decision: dict):
    if decision["disposition"] not in {
        "ready_to_notify_privately", "ready_for_new_research",
        "requires_safe_worker_or_human",
    }:
        raise ValueError("Cannot record duplicate or budget-exhausted decision")
    if path.exists() and path.is_symlink():
        raise ValueError("Ledger symlink refused")
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.parent.is_symlink():
        raise ValueError("Ledger parent cannot be a symlink")
    if len(ledger["events"]) >= MAX_LEDGER_ROWS:
        raise ValueError("Ledger full: archive manually")
    updated = {"schema_version": LEDGER_SCHEMA, "events": [
        *ledger["events"],
        {key: decision[key] for key in ("fingerprint", "experiment_id", "next_step", "utc_day")}
    ]}
    # A single invocation is protected by an adjacent exclusive lock file.
    # No lock is removed on failure; stale locks require manual inspection.
    lock = path.with_name(path.name + ".lock")
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError as exc:
        raise RuntimeError("Controller is already locked; stop and inspect") from exc
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write(str(os.getpid()))
        # Recheck against another invocation that may have written before lock.
        current = read_ledger(path)
        if current != ledger:
            raise RuntimeError("Controller ledger changed concurrently")
        temporary = path.with_name(path.name + ".tmp-" + str(os.getpid()))
        try:
            d = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(d, "w", encoding="utf-8") as handle:
                handle.write(json.dumps(updated, indent=2, sort_keys=True) + "\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, path)
        finally:
            if temporary.exists():
                temporary.unlink()
    finally:
        lock.unlink(missing_ok=True)


def coordinate(manifest: Path, runs_dir: Path, ledger_file: Path, *,
               feedback: dict | None = None, commit: bool = False,
               switches_dir: Path = STOP_DIR, now: datetime | None = None) -> dict:
    if (switches_dir / "STOP").exists() or (switches_dir / "PAUSE").exists():
        raise RuntimeError("Lab STOP or PAUSE is active")
    manifest_data = bounded_json(manifest)
    # Crucially: reconstruct evidence from actual local Mac receipts, metric
    # summaries, and the declared A/B pair manifest; never trust input status.
    report = evidence_gate.decision(manifest_data, runs_dir)
    ledger = read_ledger(ledger_file)
    result = decision_for(report, ledger, feedback=feedback, now=now)
    result["manifest_verified"] = True
    result["ledger_committed"] = False
    if commit and result["disposition"] not in (
        "already_processed", "daily_research_budget_exhausted"
    ):
        append_ledger(ledger_file, ledger, result)
        result["ledger_committed"] = True
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--runs-dir", type=Path, required=True)
    parser.add_argument("--ledger", type=Path, default=DEFAULT_LEDGER)
    review_input = parser.add_mutually_exclusive_group()
    review_input.add_argument("--feedback", type=Path,
                              help="Local feedback file for offline tests only (not authenticated)")
    review_input.add_argument("--review-issue", type=int,
                              help="Fetch private GitHub feedback and verify experiment identity")
    parser.add_argument("--commit", action="store_true",
                        help="Write one safe decision to the ledger (still no execution)")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    feedback = bounded_json(args.feedback) if args.feedback else None
    if args.review_issue is not None:
        from review_queue import fetch_feedback
        feedback = fetch_feedback(args.review_issue)
    answer = coordinate(args.manifest, args.runs_dir, args.ledger,
                        feedback=feedback, commit=args.commit)
    result = json.dumps(answer, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(result, encoding="utf-8")
    print(result, end="")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, TypeError,
            json.JSONDecodeError) as exc:
        print("LAB CONTROLLER STOPPED:", exc, file=sys.stderr)
        raise SystemExit(2)
