#!/usr/bin/env python3
"""Turn ONE recorded OpenLRR research decision into a bounded, inert job ticket.

No AI calls, network, processes, code changes or game access. The ticket is a
data-only handoff to a future separately reviewed, budget-limited dispatcher.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys

RESEARCH_ACTIONS = frozenset({
    "improve_instrumentation", "new_hypothesis", "isolate_regression",
    "revise_hypothesis_from_feedback"
})
HEX64 = re.compile(r"^[0-9a-f]{64}$")
SAFE_ID = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_-]{2,63}$")
MAX_BYTES = 200000


def load_json(path: Path) -> dict:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > MAX_BYTES:
        raise ValueError("Missing, symlinked or oversized research source")
    data = json.loads(path.read_text(encoding="utf-8"))
    if type(data) is not dict:
        raise ValueError("Expected JSON object")
    return data


def ticket_from_decision(decision: dict, ledger: dict) -> dict:
    if decision.get("schema_version") != 1:
        raise ValueError("Unexpected controller output schema")
    if decision.get("disposition") != "ready_for_new_research":
        raise ValueError("Controller did not authorize a research request")
    if decision.get("manifest_verified") is not True or decision.get("ledger_committed") is not True:
        raise ValueError("Controller evidence was not verified and recorded")
    if any(decision.get(key) is not False for key in (
        "may_install_or_run_candidate", "may_touch_working_game",
        "may_deploy_automatically", "model_invoked", "candidate_compiled"
    )):
        raise ValueError("Decision attempted to exceed safety authority")
    if decision.get("request_human_review") is not False:
        raise ValueError("Cannot send reviewable candidate to unsupervised researcher")
    experiment = decision.get("experiment_id")
    fingerprint = decision.get("fingerprint")
    action = decision.get("next_step")
    day = decision.get("utc_day")
    if not isinstance(experiment, str) or not SAFE_ID.fullmatch(experiment):
        raise ValueError("Invalid experiment identity")
    if not isinstance(fingerprint, str) or not HEX64.fullmatch(fingerprint):
        raise ValueError("Invalid evidence fingerprint")
    if action not in RESEARCH_ACTIONS:
        raise ValueError("Not an AI research next-step")
    if not isinstance(day, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", day):
        raise ValueError("Invalid decision day")
    if type(ledger) is not dict or set(ledger) != {"schema_version", "events"} or ledger["schema_version"] != 1:
        raise ValueError("Unknown decision ledger")
    events = ledger["events"]
    if type(events) is not list or len(events) > 1000:
        raise ValueError("Invalid recorded event list")
    matches = [e for e in events if type(e) is dict and e.get("fingerprint") == fingerprint]
    if len(matches) != 1 or any(matches[0].get(k) != v for k, v in (
        ("experiment_id", experiment), ("next_step", action), ("utc_day", day)
    )):
        raise ValueError("No unique matching committed research event")
    # A ticket contains only bound categorical action / identity and controller
    # explanation, not arbitrary instructions from untrusted experiments.
    why = decision.get("why")
    if not isinstance(why, str) or not 10 <= len(why) <= 600:
        raise ValueError("Invalid bounded reason")
    return {
        "schema_version": 1,
        "ticket_id": "research_" + fingerprint[:24],
        "experiment_id": experiment,
        "evidence_fingerprint": fingerprint,
        "next_step": action,
        "reason": why,
        "requested_utc_day": day,
        "request_kind": "research_only",
        "approved_to_invoke_model": False,
        "approved_to_dispatch_cloud_workflow": False,
        "approved_to_compile": False,
        "approved_to_execute_game": False,
        "approved_to_deploy": False,
        "requires_separate_budget_and_dispatch_review": True,
    }


def write_ticket(path: Path, ticket: dict) -> None:
    if path.exists() or path.is_symlink():
        raise ValueError("Existing ticket must never be replaced")
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.parent.is_symlink():
        raise ValueError("Unsafe ticket parent")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as output:
        output.write(json.dumps(ticket, sort_keys=True, indent=2) + "\n")
        output.flush()
        os.fsync(output.fileno())


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--decision", type=Path, required=True)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    ticket = ticket_from_decision(load_json(args.decision), load_json(args.ledger))
    write_ticket(args.out, ticket)
    print(json.dumps(ticket, indent=2, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, json.JSONDecodeError, TypeError) as exc:
        print("RESEARCH HANDOFF REJECTED:", exc, file=sys.stderr)
        raise SystemExit(2)
