#!/usr/bin/env python3
"""Idempotently publish a validated INERT research ticket to private GitHub.

Requires the corresponding A/B manifest and every run receipt to already be
verified remotely. Default is dry-run. No AI call, game run, binary or key leak.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import tempfile
import base64

import publish_experiment
import research_ticket

REPO = publish_experiment.REPO
TICKET_NAME = re.compile(r"^research_[a-f0-9]{24}$")


def prepare(ticket: Path, decision: Path, ledger: Path, manifest: Path,
            runs: Path) -> tuple[dict, bytes, str]:
    request = research_ticket.ticket_from_decision(
        research_ticket.load_json(decision),
        research_ticket.load_json(ledger),
    )
    if ticket.is_symlink() or not ticket.is_file() or ticket.stat().st_size > 20_000:
        raise ValueError("Missing or unsafe reviewed research ticket")
    actual = json.loads(ticket.read_text(encoding="utf-8"))
    if actual != request:
        raise ValueError("Ticket disagrees with committed experiment decision")
    if manifest.is_symlink() or not manifest.is_file() or manifest.stat().st_size > 100_000:
        raise ValueError("Missing reviewed A/B experiment")
    m = json.loads(manifest.read_text(encoding="utf-8"))
    if m.get("experiment_id") != request["experiment_id"]:
        raise ValueError("Ticket and verified paired experiment do not match")
    # Revalidate ORIGINAL A/B receipts locally, without trusting model text.
    report = publish_experiment.remote_evidence_gate.evaluate(manifest, runs)
    if report["may_execute_candidate"] is not False or report["may_deploy_automatically"] is not False:
        raise ValueError("Unsafe gate authority")
    if request["next_step"] not in research_ticket.RESEARCH_ACTIONS:
        raise ValueError("Review candidates cannot enter the automatic research outbox")
    if not TICKET_NAME.fullmatch(request["ticket_id"]):
        raise ValueError("Invalid ticket identity")
    source = ticket.read_bytes()
    path = "research-tickets/" + request["ticket_id"] + ".json"
    return request, source, path


def publish(ticket: Path, decision: Path, ledger: Path, manifest: Path,
            runs: Path, *, commit: bool = False) -> dict:
    request, source, target = prepare(ticket, decision, ledger, manifest, runs)
    answer = {
        "ticket_id": request["ticket_id"],
        "experiment_id": request["experiment_id"],
        "remote_path": target,
        "ticket_sha256": hashlib.sha256(source).hexdigest(),
        "private_ticket_published": False,
        "model_invoked": False,
        "new_game_executed": False,
        "automatic_execution_allowed": False,
    }
    if not commit:
        return answer
    # The experiment publisher requires all private run receipts to match,
    # including the exact exit evidence; cannot publish only a model summary.
    verified = publish_experiment.publish(manifest, runs, commit=True)
    if not verified["published"] or verified["experiment_id"] != request["experiment_id"]:
        raise RuntimeError("Private paired experiment was not verified")
    publish_experiment.ensure_private_repo()
    existing = publish_experiment.remote_sha(target)
    expected = publish_experiment.local_git_sha(ticket)
    if existing is not None:
        if existing != expected:
            raise RuntimeError("Remote research ticket differs; refuse overwrite")
        return {**answer, "private_ticket_published": True, "already_published": True}
    payload = {
        "message": "Queue read-only OpenLRR research request " + request["ticket_id"],
        "content": base64.b64encode(source).decode("ascii"),
    }
    with tempfile.TemporaryDirectory(prefix="openlrr-research-outbox-") as tmp:
        upload = Path(tmp) / "request.json"
        upload.write_text(json.dumps(payload))
        publish_experiment.gh(
            "api", "--method", "PUT",
            "repos/" + REPO + "/contents/" + target,
            input_file=upload,
        )
    if publish_experiment.remote_sha(target) != expected:
        raise RuntimeError("Private research ticket publication was not verified")
    return {**answer, "private_ticket_published": True, "already_published": False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ticket", type=Path, required=True)
    parser.add_argument("--decision", type=Path, required=True)
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--runs-dir", type=Path, required=True)
    parser.add_argument("--publish", action="store_true",
                        help="Upload reviewed metadata only, to private repository")
    args = parser.parse_args(argv)
    print(json.dumps(publish(args.ticket, args.decision, args.ledger,
                             args.manifest, args.runs_dir,
                             commit=args.publish), indent=2, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, TypeError, json.JSONDecodeError) as exc:
        print("PRIVATE RESEARCH OUTBOX REFUSED:", exc, file=sys.stderr)
        raise SystemExit(2)
