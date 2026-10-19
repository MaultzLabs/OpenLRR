#!/usr/bin/env python3
"""Deterministic research state transitions for OpenLRR lab.

Outputs the NEXT KIND of investigation, never a command, test executable,
GitHub merge or permission to modify the working game. Inputs may include a
validated evidence_gate report and a review_queue feedback record.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

STATES = frozenset({
    "needs_more_data", "inconclusive", "no_improvement",
    "regression", "candidate_for_review"
})
REVIEWS = frozenset({"awaiting_human", "good", "continue", "reject"})


def decide(report: dict, feedback: dict | None = None) -> dict:
    if not isinstance(report, dict) or report.get("status") not in STATES:
        raise ValueError("Requires a validated evidence-gate result")
    if feedback is None:
        feedback = {
            "decision": "awaiting_human", "reason": "",
            "automatic_deploy_allowed": False,
        }
    if not isinstance(feedback, dict) or feedback.get("decision") not in REVIEWS:
        raise ValueError("Invalid feedback state")
    if feedback.get("automatic_deploy_allowed") is not False:
        raise ValueError("Cannot accept feedback that allows automatic deployment")
    reason = feedback.get("reason", "")
    if not isinstance(reason, str) or len(reason) > 1000:
        raise ValueError("Reviewer reason must be bounded text")
    experiment_id = report.get("experiment_id", "")
    if not isinstance(experiment_id, str) or len(experiment_id) > 64:
        raise ValueError("Invalid experiment identity")
    status = report["status"]
    base = {
        "experiment_id": experiment_id,
        "evidence_status": status,
        "review_decision": feedback["decision"],
        "reviewer_reason": reason,
        "may_touch_working_game": False,
        "may_run_unreviewed_binary": False,
        "may_deploy_automatically": False,
    }

    def choose(step: str, explanation: str, request_review: bool = False):
        return {**base, "next_step": step, "why": explanation,
                "request_human_review": request_review}

    if status == "candidate_for_review":
        if feedback["decision"] == "awaiting_human":
            return choose("hold_for_review",
                          "Material benchmark result awaits a human visual check.", True)
        if feedback["decision"] == "good":
            return choose("prepare_manual_acceptance_check",
                          "Reviewer found the experiment promising. A separate manual acceptance "
                          "and safety review is still required.")
        if feedback["decision"] == "continue":
            if not reason.strip():
                raise ValueError("Continue requires a specific reviewer reason")
            return choose("revise_hypothesis_from_feedback",
                          "Reviewer found a visible deficiency; propose a DIFFERENT targeted "
                          "experiment that directly addresses the reason.")
        if feedback["decision"] == "reject":
            if not reason.strip():
                raise ValueError("Reject requires reviewer reason")
            return choose("abandon_experiment_family",
                          "Reviewer rejected this approach; record why and do not repeat it.")
    if feedback["decision"] != "awaiting_human":
        raise ValueError("Human review feedback must refer to a reviewable candidate")
    if status == "needs_more_data":
        return choose("complete_paired_measurement",
                      "The hypothesis has insufficient matched A/B repeats; collect only "
                      "the missing runs, with the same declared workload.")
    if status == "inconclusive":
        return choose("improve_instrumentation",
                      "A noisy signal calls for identifying uncontrolled variables, "
                      "not another blind repeat or a new random patch.")
    if status == "no_improvement":
        return choose("new_hypothesis",
                      "This experiment did not provide a meaningful gain; record negative "
                      "evidence and investigate a different bottleneck.")
    if status == "regression":
        return choose("isolate_regression",
                      "A correctness or throughput regression blocks this candidate; "
                      "investigate and roll back the experimental approach.")
    raise ValueError("Unexpected state")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--feedback", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)
    report = json.loads(args.report.read_text(encoding="utf-8"))
    feedback = json.loads(args.feedback.read_text(encoding="utf-8")) if args.feedback else None
    output = json.dumps(decide(report, feedback), sort_keys=True, indent=2) + "\n"
    if args.out:
        args.out.write_text(output, encoding="utf-8")
    print(output, end="")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print("RESEARCH POLICY STOPPED:", exc, file=sys.stderr)
        raise SystemExit(2)
