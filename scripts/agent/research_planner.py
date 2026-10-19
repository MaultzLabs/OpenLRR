#!/usr/bin/env python3
"""Research-only AI planner for OpenLRR: proposes falsifiable next experiments."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys

from generate_candidate import (
    EVIDENCE_REL, SOURCE_REL, extract_block, validate_research_evidence
)


def propose(evidence: dict, code: str, model: str) -> dict:
    from agents import Agent, Runner, set_tracing_disabled
    from pydantic import BaseModel, Field
    from typing import Literal

    set_tracing_disabled(True)

    class Plan(BaseModel):
        next_action: Literal[
            "inspect_wine_implementation", "instrument_driver_boundary",
            "instrument_present_geometry", "change_directdraw_present",
            "investigate_compositor", "other_research"
        ]
        working_hypothesis: str = Field(min_length=20, max_length=650)
        evidence_and_uncertainty: str = Field(min_length=20, max_length=900)
        falsifying_observation: str = Field(min_length=20, max_length=650)
        concrete_next_experiment: str = Field(min_length=30, max_length=900)
        source_region_to_study: str = Field(min_length=15, max_length=350)
        expected_measurement: str = Field(min_length=15, max_length=650)
        regression_risk: str = Field(min_length=20, max_length=550)
        why_not_repeat_prior_tests: str = Field(min_length=20, max_length=550)

    instruction = (
        "Act as an experienced C++ and Wine graphics research engineer. "
        "Provide a single high-value, falsifiable next experiment, not a patch. "
        "The Mac baseline repeatedly showed 31 windowed DirectDraw Blt calls "
        "taking more than a second; no time-outside-Flip period exceeded a second. "
        "Nowait changed almost nothing and GDI was slower. "
        "Determine what could explain a synchronous, approximately 1.26-second "
        "worst-call stall. Can be inside Wine, composition, or driver; do not "
        "pretend the source of delay is proven. New CPU probes recorded "
        "31 long Blt calls in each of two more baseline runs, each with 31 "
        "valid long-call CPU samples and only 0 or 1 low-CPU stall. Investigate "
        "active CPU work or spin in the Wine presentation path, not just "
        "passive waits. Scope differences and CPU timing overhead remain "
        "unresolved, so do not attribute the culprit to a specific library. "
        "Inspect provided local C++ "
        "context and identify what measurements would distinguish mechanisms. "
        "Do NOT request another identical benchmark without a new measurable "
        "independent variable. No invented sources, claims of FPS, terminal "
        "instructions or code modifications. You have no tools. "
        "Stay within research and diagnostic work. Nothing you say authorizes "
        "executing a binary, accessing the Mac or changing a production game."
    )
    agent = Agent(
        name="OpenLRR Graphics Researcher", model=model,
        instructions=instruction, output_type=Plan, tools=[]
    )
    prompt = {
        "reviewed_aggregate": evidence,
        "current_directdraw_context": code[:11000],
    }
    plan = Runner.run_sync(
        agent, json.dumps(prompt, sort_keys=True), max_turns=1
    ).final_output
    if not isinstance(plan, Plan):
        raise ValueError("Unexpected model research output")
    return {
        "schema_version": 1,
        "experiment": evidence["experiment"],
        "plan": plan.model_dump(),
        "evidence_based": True,
        "code_modified": False,
        "game_executed": False,
        "automatic_deploy_allowed": False,
        "human_review_required_for_new_execution": True,
    }


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, default=Path(EVIDENCE_REL))
    parser.add_argument("--source", type=Path, default=Path(SOURCE_REL))
    parser.add_argument("--out", type=Path, default=Path("research-output"))
    parser.add_argument("--model", default="gpt-6-luna")
    parser.add_argument("--preflight", action="store_true")
    args = parser.parse_args(argv)

    evidence = validate_research_evidence(args.evidence)
    _, _, _, code = extract_block(args.source.read_text(encoding="utf-8"))
    if args.preflight:
        print(json.dumps({
            "evidence": evidence["experiment"],
            "validated": True,
            "code_context_bytes": len(code),
            "model_called": False,
        }))
        return 0
    if not os.environ.get("OPENAI_API_KEY"):
        raise ValueError("No model key; research not started")
    result = propose(evidence, code, args.model)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "plan.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError) as exc:
        print("RESEARCH PLANNER STOPPED:", exc, file=sys.stderr)
        sys.exit(2)
