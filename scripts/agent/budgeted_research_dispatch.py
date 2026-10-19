#!/usr/bin/env python3
"""One bounded, explicit AI research request after private A/B verification.

MODEL EXECUTION IS DISABLED BY DEFAULT. --run-model plus a separate opt-in
environment variable and private GitHub write authorization are required.

Two immutable, exclusive private-GitHub reservations are made BEFORE calling
the model: one per UTC day across the lab, and one per ticket for all time.
A failure consumes a reservation rather than risking surprise retries.
Nothing here compiles, executes or deploys any game binary.
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

import private_research_inbox as inbox

REPO = inbox.REPO
MODEL = "gpt-6-luna"
ENABLE_FLAG = "OPENLRR_RESEARCH_EXECUTION_ENABLED"
DAY_RE = re.compile(r"^[0-9]{8}$")
MAX_MODEL_CALLS_PER_UTC_DAY = 1
MAX_MODEL_TURNS_PER_REQUEST = 1


def git_blob(content: bytes) -> str:
    return hashlib.sha1(
        b"blob " + str(len(content)).encode("ascii") + b"\x00" + content
    ).hexdigest()


def gh_write_json(path: str, document: dict) -> dict:
    """Atomically CREATE a previously nonexistent private record.

    The GitHub Contents API requires the old blob SHA to update a file;
    deliberately never provide one. Existing paths cannot be overwritten.
    """
    if not re.fullmatch(r"research-dispatches/[a-zA-Z0-9_-]{8,82}\.json", path):
        raise ValueError("Unexpected private reservation path")
    raw = (json.dumps(document, sort_keys=True, separators=(",", ":")) + "\n").encode()
    payload = {
        "message": "Reserve one OpenLRR research request " + path.rsplit("/", 1)[-1],
        "content": base64.b64encode(raw).decode("ascii"),
        "branch": inbox.REF,
    }
    with tempfile.TemporaryDirectory(prefix="openlrr-private-reservation-") as temp:
        input_file = Path(temp) / "reservation.json"
        input_file.write_text(json.dumps(payload))
        response = subprocess.run(
            ["gh", "api", "--method", "PUT",
             "repos/" + REPO + "/contents/" + path,
             "--input", str(input_file)],
            capture_output=True, text=True, timeout=65, check=False,
        )
    if response.returncode:
        raise RuntimeError(
            "Private budget slot already consumed, or GitHub rejected creation; no model call"
        )
    try:
        ack = json.loads(response.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError("Malformed private budget reservation acknowledgement") from exc
    if (type(ack) is not dict or
            ack.get("content", {}).get("path") != path or
            ack.get("content", {}).get("sha") != git_blob(raw)):
        raise RuntimeError("Private reservation acknowledgement invalid; no model call")
    return document


def reserve_one_model_call(ticket: dict, *, now: datetime | None = None) -> dict:
    """One model call per UTC day and one call per unique verified ticket.

    GitHub exclusive file creations are the only reservation mechanism.
    Another process may race but cannot create the same daily slot; the first
    creation consumes the day even if subsequent steps fail.
    """
    if not inbox.TICKET_ID.fullmatch(ticket.get("ticket_id", "")):
        raise ValueError("Invalid verified ticket")
    if (ticket.get("verification_only") is not True or
            ticket.get("automatic_model_execution_allowed") is not False or
            ticket.get("automatic_game_execution_allowed") is not False):
        raise ValueError("Cannot reserve from unverified or overprivileged ticket")
    if ticket.get("verified_research_next_step") not in {
        "improve_instrumentation", "new_hypothesis", "isolate_regression"
    }:
        raise ValueError("Only nonreviewer research actions may dispatch")
    now = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    day = now.strftime("%Y%m%d")
    if not DAY_RE.fullmatch(day):
        raise ValueError("Invalid UTC day")
    # Do not trust remote tickets as authority; a separate human-approved
    # workflow opt-in is required before ANY private write or AI expense.
    if os.environ.get(ENABLE_FLAG) != "true":
        raise RuntimeError("Paid research execution not enabled")
    if not os.environ.get("GH_TOKEN") or not os.environ.get("OPENAI_API_KEY"):
        raise RuntimeError("Missing dedicated private GitHub or AI key")
    inbox.private_repo_only()
    record = {
        "schema_version": 1,
        "reservation_day": day,
        "ticket_id": ticket["ticket_id"],
        "evidence_fingerprint": ticket["evidence_fingerprint"],
        "policy": "one_paid_model_request_per_utc_day_max",
        "model": MODEL,
        "max_model_turns": MAX_MODEL_TURNS_PER_REQUEST,
        "game_execution": False,
        "automatic_deployment": False,
    }
    # Atomic creation of shared day slot prevents races between distinct
    # tickets, including independent CLI processes and GitHub runners.
    gh_write_json("research-dispatches/daily_" + day + ".json", record)
    # Cross-day retry of the same ticket is blocked independently.
    gh_write_json("research-dispatches/ticket_" + ticket["ticket_id"] + ".json", record)
    return record


def produce_research_plan(ticket: dict) -> dict:
    """Single tool-free structured model call. Do not send raw private logs."""
    from agents import Agent, Runner, set_tracing_disabled
    from pydantic import BaseModel, Field
    from typing import Literal

    set_tracing_disabled(True)

    class ProposedResearch(BaseModel):
        next_experiment: Literal[
            "instrument_present_cpu_wait", "inspect_wine_path",
            "instrument_present_geometry", "inspect_graphics_compositor",
            "review_source_data", "other_instrumentation"
        ]
        causal_hypothesis: str = Field(min_length=25, max_length=700)
        falsifying_measurement: str = Field(min_length=25, max_length=700)
        controlled_test_plan: str = Field(min_length=30, max_length=900)
        risk_and_uncertainty: str = Field(min_length=30, max_length=700)

    instructions = (
        "You are a read-only research planner for OpenLRR's isolated Wine/DirectDraw "
        "graphics laboratory. Produce ONE falsifiable next experiment with a "
        "specific discriminating measurement. Only the provided validated "
        "aggregate context is evidence. No fake FPS gains, no pretending to "
        "identify a driver root cause, no model tools, commands, code patches, "
        "deployment or requests to run another uncontrolled game test. "
        "You cannot approve a binary or expense. Only propose research."
    )
    agent = Agent(name="Bounded OpenLRR Researcher", model=MODEL,
                  instructions=instructions, output_type=ProposedResearch,
                  tools=[])
    context = {
        "verified_status": ticket["verified_evidence_status"],
        "policy_action": ticket["verified_research_next_step"],
        "matched_pairs": ticket["verified_matched_pairs"],
        "source": "independently_recomputed_private_mac_benchmarks",
        "visible_fps_confirmed": False,
        "candidate_executable_authorized": False,
    }
    result = Runner.run_sync(
        agent, json.dumps(context, sort_keys=True),
        max_turns=MAX_MODEL_TURNS_PER_REQUEST,
    ).final_output
    if not isinstance(result, ProposedResearch):
        raise RuntimeError("Unexpected structured research response")
    return {
        "schema_version": 1,
        "source_ticket": ticket["ticket_id"],
        "experiment_id": ticket["experiment_id"],
        "verified_evidence_fingerprint": ticket["evidence_fingerprint"],
        "research_plan": result.model_dump(),
        "requires_review_before_code_execution": True,
        "model_calls_requested": MAX_MODEL_CALLS_PER_UTC_DAY,
        "model_turns_per_request": MAX_MODEL_TURNS_PER_REQUEST,
        "actual_api_cost_usd": None,
        "game_executed": False,
        "source_code_modified": False,
        "deployment_authorized": False,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ticket-id", required=True)
    parser.add_argument("--run-model", action="store_true",
                        help="Opt in to ONE paid, verified research call, consuming daily slot")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)
    if not inbox.TICKET_ID.fullmatch(args.ticket_id):
        raise ValueError("Invalid research selector")
    if args.out is not None and not args.run_model:
        parser.error("--out requires explicit --run-model")
    if not args.run_model:
        print(json.dumps({
            "ticket_id": args.ticket_id,
            "phase": "offline_dry_run",
            "model_invoked": False,
            "private_reservation_created": False,
            "game_executed": False,
        }, sort_keys=True))
        return 0
    if args.out is None or args.out.exists() or args.out.is_symlink():
        raise ValueError("Unique --out report required before paid invocation")
    if os.environ.get(ENABLE_FLAG) != "true":
        raise RuntimeError("Paid model research disabled; no private reads or costs")
    if not os.environ.get("GH_TOKEN") or not os.environ.get("OPENAI_API_KEY"):
        raise RuntimeError("Dedicated private GitHub and AI credentials are required")
    verified = inbox.get_verified_ticket(args.ticket_id)
    reservation = reserve_one_model_call(verified)
    result = produce_research_plan(verified)
    result["reserved_utc_day"] = reservation["reservation_day"]
    args.out.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with args.out.open("x", encoding="utf-8") as destination:
        destination.write(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print("Verified research plan saved; no game executed. Review required.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, TypeError, json.JSONDecodeError,
            subprocess.SubprocessError) as exc:
        print("MODEL DISPATCH BLOCKED:", exc, file=sys.stderr)
        raise SystemExit(2)
