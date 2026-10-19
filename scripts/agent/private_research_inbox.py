#!/usr/bin/env python3
"""Read-only independent verification of OpenLRR private research tickets.

Reconstructs the A/B evidence from GitHub-hosted benchmark receipts and
checks the ticket against the current deterministic controller policy.
Never treats a remotely uploaded ticket as authority to invoke a model,
run a DLL, or modify the game. Default is offline preflight.
"""
from __future__ import annotations

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

import evidence_gate
import experiment_controller
import remote_evidence_gate
import research_ticket

REPO = "MaultzLabs/OpenLRR-Test-Results"
REF = "main"
TICKET_ID = re.compile(r"^research_[a-f0-9]{24}$")
FILE_SHA = re.compile(r"^[a-f0-9]{40}$")
TICKET_FIELDS = frozenset({
    "schema_version", "ticket_id", "experiment_id",
    "evidence_fingerprint", "next_step", "reason", "requested_utc_day",
    "request_kind", "approved_to_invoke_model",
    "approved_to_dispatch_cloud_workflow", "approved_to_compile",
    "approved_to_execute_game", "approved_to_deploy",
    "requires_separate_budget_and_dispatch_review",
})
MAX_TOTAL_BYTES = 12_000_000
MAX_RUNS = 24


def gh(*args: str) -> str:
    process = subprocess.run(
        ["gh", *args], capture_output=True, text=True,
        timeout=60, check=False,
    )
    if process.returncode:
        raise RuntimeError("Private GitHub evidence unavailable; intake remains blocked")
    if len(process.stdout) > 3_200_000:
        raise RuntimeError("Private GitHub response exceeded maximum")
    return process.stdout


def private_repo_only() -> None:
    visible = gh("repo", "view", REPO, "--json", "visibility", "--jq", ".visibility").strip()
    if visible != "PRIVATE":
        raise RuntimeError("Research intake must come from private GitHub repository")


def git_blob_sha(content: bytes) -> str:
    return hashlib.sha1(
        b"blob " + str(len(content)).encode("ascii") + b"\x00" + content
    ).hexdigest()


def remote_blob(path: str, *, max_size: int) -> bytes:
    # Paths are generated exclusively from validated IDs and fixed filenames.
    if not re.fullmatch(r"[a-zA-Z0-9_./-]{1,170}", path) or ".." in path:
        raise ValueError("Unsafe research evidence path")
    response = gh("api", "repos/" + REPO + "/contents/" + path + "?ref=" + REF)
    record = json.loads(response)
    if (type(record) is not dict or record.get("type") != "file"
            or record.get("path") != path or record.get("encoding") != "base64"):
        raise ValueError("Unexpected GitHub evidence blob response")
    size = record.get("size")
    if type(size) is not int or not 0 <= size <= max_size:
        raise ValueError("Remote evidence size out of bounds")
    source = record.get("content")
    sha = record.get("sha")
    if not isinstance(source, str) or not isinstance(sha, str) or not FILE_SHA.fullmatch(sha):
        raise ValueError("Invalid private GitHub blob metadata")
    try:
        content = base64.b64decode("".join(source.split()), validate=True)
    except (ValueError, base64.binascii.Error) as exc:
        raise ValueError("Invalid base64 evidence") from exc
    if len(content) != size or git_blob_sha(content) != sha:
        raise ValueError("Private evidence blob checksum mismatch")
    return content


def checked_ticket(ticket: dict, ticket_id: str) -> None:
    if type(ticket) is not dict or set(ticket) != TICKET_FIELDS:
        raise ValueError("Unsupported private research ticket schema")
    if (ticket["schema_version"] != 1 or ticket["ticket_id"] != ticket_id
            or ticket["request_kind"] != "research_only"):
        raise ValueError("Ticket schema or identity mismatch")
    experiment = ticket["experiment_id"]
    digest = ticket["evidence_fingerprint"]
    if (type(experiment) is not str or not research_ticket.SAFE_ID.fullmatch(experiment)
            or type(digest) is not str or not research_ticket.HEX64.fullmatch(digest)
            or ticket_id != "research_" + digest[:24]):
        raise ValueError("Ticket fingerprint is not bound to experiment")
    if ticket["next_step"] not in research_ticket.RESEARCH_ACTIONS:
        raise ValueError("Non-research action in private inbox")
    if not isinstance(ticket["reason"], str) or not 10 <= len(ticket["reason"]) <= 600:
        raise ValueError("Ticket reason invalid")
    if not isinstance(ticket["requested_utc_day"], str) or not re.fullmatch(
        r"\d{4}-\d{2}-\d{2}", ticket["requested_utc_day"]
    ):
        raise ValueError("Unbounded ticket date")
    try:
        datetime.fromisoformat(ticket["requested_utc_day"]).date()
    except ValueError as exc:
        raise ValueError("Malformed UTC day") from exc
    for key in (
        "approved_to_invoke_model", "approved_to_dispatch_cloud_workflow",
        "approved_to_compile", "approved_to_execute_game", "approved_to_deploy"
    ):
        if ticket[key] is not False:
            raise ValueError("Ticket attempted privilege escalation")
    if ticket["requires_separate_budget_and_dispatch_review"] is not True:
        raise ValueError("Missing separate budget review requirement")


def get_verified_ticket(ticket_id: str) -> dict:
    if type(ticket_id) is not str or not TICKET_ID.fullmatch(ticket_id):
        raise ValueError("Invalid ticket selector")
    private_repo_only()
    remote = remote_blob("research-tickets/" + ticket_id + ".json", max_size=20_000)
    if not remote or len(remote) > 20_000:
        raise ValueError("Ticket missing")
    ticket = json.loads(remote.decode("utf-8"))
    checked_ticket(ticket, ticket_id)
    experiment_id = ticket["experiment_id"]
    manifest_bytes = remote_blob("experiments/" + experiment_id + ".json", max_size=100_000)
    doc = json.loads(manifest_bytes.decode("utf-8"))
    if (type(doc) is not dict or doc.get("experiment_id") != experiment_id
            or doc.get("schema_version") != 1):
        raise ValueError("Research ticket experiment mismatch")
    pairs = doc.get("pairs")
    if type(pairs) is not list or not 1 <= len(pairs) <= 12:
        raise ValueError("Unsupported A/B experiment pair count")
    names = set()
    for pair in pairs:
        if type(pair) is not dict or set(pair) != {"baseline", "candidate"}:
            raise ValueError("Invalid A/B pair structure")
        for name in pair.values():
            if type(name) is not str or not evidence_gate.RUN_RE.fullmatch(name):
                raise ValueError("Invalid remote run name")
            if name in names:
                raise ValueError("Repeated benchmark run")
            names.add(name)
    if len(names) > MAX_RUNS:
        raise ValueError("Too many remote runs")
    with tempfile.TemporaryDirectory(prefix="openlrr-evidence-intake-") as temporary:
        folder = Path(temporary)
        manifest = folder / (experiment_id + ".json")
        manifest.write_bytes(manifest_bytes)
        runs = folder / "runs"
        runs.mkdir()
        total_size = len(manifest_bytes) + len(remote)
        for name in sorted(names):
            target = runs / name
            target.mkdir(mode=0o700)
            for filename, cap in (
                ("lifecycle.verified", 250),
                ("summary.json", 100_000),
                ("menuperf.csv", 2_000_000),
            ):
                payload = remote_blob("runs/" + name + "/" + filename, max_size=cap)
                total_size += len(payload)
                if total_size > MAX_TOTAL_BYTES:
                    raise ValueError("Research evidence exceeds aggregate cap")
                (target / filename).write_bytes(payload)
        # The same evidence gate used by the local supervisor independently
        # validates the uploaded receipts, two distinct binaries and result
        # quality; remote status, metadata and AI claims aren't trusted.
        evidence = remote_evidence_gate.evaluate(manifest, runs)
    gate = evidence["evidence_gate"]
    # Feedback-driven instructions require authenticated reviewer retrieval,
    # which is not part of this autonomous read-only intake. Fail closed.
    if ticket["next_step"] == "revise_hypothesis_from_feedback":
        raise ValueError("Reviewer feedback is not authenticated in remote research inbox")
    policy = evidence["research_policy"]
    if (policy["next_step"] != ticket["next_step"]
            or policy["request_human_review"] is not False
            or gate["notify_human"] is not False):
        raise ValueError("Research ticket disagrees with independently derived policy")
    expected_fingerprint = hashlib.sha256(
        experiment_controller.canonical({"report": gate, "feedback": None}).encode("ascii")
    ).hexdigest()
    if ticket["evidence_fingerprint"] != expected_fingerprint:
        raise ValueError("Research ticket fingerprint disagrees with real benchmarks")
    if ticket["reason"] != policy["why"]:
        raise ValueError("Research ticket reason differs from deterministic policy")
    return {
        "schema_version": 1,
        "ticket_id": ticket_id,
        "experiment_id": experiment_id,
        "evidence_fingerprint": expected_fingerprint,
        "verified_evidence_status": gate["status"],
        "verified_research_next_step": policy["next_step"],
        "verified_unique_runs": len(names),
        "verified_matched_pairs": gate["pairs"],
        "review_required": False,
        "automatic_model_execution_allowed": False,
        "automatic_game_execution_allowed": False,
        "automatic_deployment_allowed": False,
        "verification_only": True,
        "source": "private_github_run_uploads",
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ticket-id", required=True)
    parser.add_argument("--verify-private", action="store_true",
                        help="Fetch and independently verify private GitHub evidence")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)
    if not TICKET_ID.fullmatch(args.ticket_id):
        raise ValueError("Invalid ticket selector")
    if args.out is not None and not args.verify_private:
        parser.error("--out requires --verify-private")
    if not args.verify_private:
        print(json.dumps({
            "ticket_id": args.ticket_id,
            "will_fetch_private_evidence": False,
            "model_invoked": False, "game_executed": False,
        }, sort_keys=True))
        return 0
    result = get_verified_ticket(args.ticket_id)
    output = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.out is not None:
        args.out.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with args.out.open("x", encoding="utf-8") as stream:
            stream.write(output)
    print(output, end="")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, TypeError, json.JSONDecodeError) as exc:
        print("PRIVATE RESEARCH INTAKE STOPPED:", exc, file=sys.stderr)
        raise SystemExit(2)
