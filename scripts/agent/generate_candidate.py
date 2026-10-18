#!/usr/bin/env python3
"""Create one AI-authored OpenLRR graphics experiment for offline review/build.

No GitHub write access, no shell tool for the model, no Mac/game execution.
The output is an allowlisted C++ diff or a structured request for missing evidence.
"""
from __future__ import annotations

import argparse
import difflib
import json
import os
from pathlib import Path
import re
import sys

SOURCE_REL = "src/openlrr/engine/drawing/DirectDraw.cpp"
FUNCTION_START = "void __cdecl Gods98::DirectDraw_BlitBuffers(void)"
FUNCTION_END = "// <LegoRR.exe @0047cfb0>"
BLOCK_START = "\tconst DWORD flags = MenuPerf::NonblockingWindowBlt() ? 0 : DDBLT_WAIT;"
BLOCK_END = "\n\n/*\t\twhile (true){"
EVIDENCE_REL = "scripts/agent/evidence/approved-menu-aggregate.json"
REFERENCE_CONTEXT = {
    "date": "2026-10-18",
    "summary": "The Mac Wine menu test has a very slow DirectDraw windowed present. GDI presentation was slower. Nowait=1 versus 0 was inconclusive in paired benchmarks. Logical flip counts do not confirm displayed FPS.",
    "goal": "Propose one small reversible change around windowed DirectDraw presentation. This is NOT evidence of improvement until the Mac runs controlled paired tests.",
}
FORBIDDEN = re.compile(
    r"(#\s*(include|define|pragma|if|endif)|\b(system|popen|WinExec|ShellExecute|"
    r"CreateProcess|LoadLibrary|GetProcAddress|ExitProcess|TerminateProcess|"
    r"DeleteFile|MoveFile|RegSetValue|RegCreateKey|CreateFile|"
    r"fopen|fwrite|ofstream|send|recv|socket)\s*\(|"
    r"\b(asm|__asm|__declspec)\b|menuperf\.(enable|autotest|finished|stop)|"
    r"OPENAI_API_KEY|GITHUB_TOKEN)",
    re.IGNORECASE,
)


def validate_research_evidence(path: Path) -> dict:
    """Accept one reviewed, bounded aggregate; never raw private benchmark data."""
    if not path.is_file() or path.stat().st_size > 4096:
        raise ValueError("Reviewed aggregate missing or too large")
    doc = json.loads(path.read_text(encoding="utf-8"))
    expected = {
        "schema_version", "kind", "experiment", "workload",
        "repeated_baselines", "same_binary_and_graphics_mode",
        "mean_present_ms", "long_directdraw_blits_per_run",
        "long_outside_flip_periods_per_run", "present_wall_fraction",
        "prior_negative_tests", "interpretation", "important_limits"
    }
    if type(doc) is not dict or set(doc) != expected:
        raise ValueError("Unexpected aggregate fields")
    if doc["schema_version"] != 1 or doc["kind"] != "reviewed_aggregate":
        raise ValueError("Unsupported research evidence")
    if doc["experiment"] != "windowed_directdraw_stalls_2026_10_18":
        raise ValueError("Unreviewed experiment")
    if doc["workload"] != "isolated_mac_wine_menu":
        raise ValueError("Unreviewed workload")
    if doc["repeated_baselines"] != 2 or doc["same_binary_and_graphics_mode"] is not True:
        raise ValueError("Comparison is not verified")
    for key, hi in (
        ("mean_present_ms", 5000),
        ("long_directdraw_blits_per_run", 1000),
        ("long_outside_flip_periods_per_run", 1000),
        ("present_wall_fraction", 1),
    ):
        values = doc[key]
        if type(values) is not list or len(values) != 2:
            raise ValueError("Invalid evidence measurements")
        for value in values:
            if type(value) not in (int, float) or not 0 <= value <= hi or not float(value) < float("inf"):
                raise ValueError("Invalid aggregate metric")
    if any(type(x) is not int for x in doc["long_directdraw_blits_per_run"] + doc["long_outside_flip_periods_per_run"]):
        raise ValueError("Nonintegral call count")
    history = doc["prior_negative_tests"]
    if type(history) is not list or history != ["gdi_slower_in_single_pair", "nowait_inconclusive"]:
        raise ValueError("Unreviewed experiment history")
    if doc["interpretation"] != (
        "Each of two ~63-second baseline runs showed 31 individual >1000ms Windows DirectDraw Blt calls while none of the periods outside DirectDraw_Flip were >1000ms. API-side durations do not prove visible frame rate or isolate the cause inside Wine."
    ):
        raise ValueError("Aggregate interpretation is not reviewed")
    if doc["important_limits"] != (
        "A repeated baseline is not an A/B improvement. The original nonblocking experiment was inconclusive. Do not assume a driver root cause or invent speedups."
    ):
        raise ValueError("Aggregate limits are not reviewed")
    return doc


def extract_block(source: str) -> tuple[int, int, str, str]:
    if source.count(FUNCTION_START) != 1 or source.count(FUNCTION_END) != 1:
        raise ValueError("Cannot uniquely locate the reviewed presentation function")
    region_start = source.index(FUNCTION_START)
    region_end = source.index(FUNCTION_END, region_start)
    region = source[region_start:region_end]
    if region.count(BLOCK_START) != 1 or region.count(BLOCK_END) != 1:
        raise ValueError("Cannot uniquely locate the allowed DirectDraw presentation block")
    start = region_start + region.index(BLOCK_START)
    end = region_start + region.index(BLOCK_END)
    return start, end, source[start:end], region


def validate_replacement(source: str, replacement: str) -> str:
    start, end, old, _ = extract_block(source)
    if not isinstance(replacement, str) or not 100 <= len(replacement) <= 4200:
        raise ValueError("Invalid replacement size")
    if "\r" in replacement or "\0" in replacement or FORBIDDEN.search(replacement):
        raise ValueError("Disallowed code construct")
    if not replacement.startswith("\tconst DWORD flags = "):
        raise ValueError("Replacement must preserve the existing diagnostic entrypoint")
    if not replacement.endswith("\n\t}"):
        raise ValueError("Replacement must preserve the original block boundary")
    required = (
        "MenuPerf::NonblockingWindowBlt()", "MenuPerf::Scope",
        "MenuPerf::Metric::WindowBlt",
        "DirectDraw_fSurf()->Blt(&dest, DirectDraw_bSurf(), &src,",
        "MenuPerf::RecordWindowPresentOutcome(",
        "Error_Fatal(r == DDERR_SURFACELOST",
    )
    if any(replacement.count(x) != 1 for x in required):
        raise ValueError("Replacement removed or duplicated mandatory presentation telemetry")
    if replacement == old:
        raise ValueError("The experiment makes no change")
    if replacement.count("{") != replacement.count("}"):
        raise ValueError("Unbalanced braces in proposed block")
    revised = source[:start] + replacement + source[end:]
    if revised[:start] != source[:start] or revised[start + len(replacement):] != source[end:]:
        raise ValueError("Change escaped allowed block")
    return revised


def make_patch(source: str, revised: str) -> str:
    return "".join(difflib.unified_diff(
        source.splitlines(keepends=True), revised.splitlines(keepends=True),
        fromfile="a/" + SOURCE_REL, tofile="b/" + SOURCE_REL,
    ))


def generate(source: str, model: str, evidence: dict | None = None) -> dict:
    from agents import Agent, Runner, set_tracing_disabled
    from pydantic import BaseModel, Field

    set_tracing_disabled(True)

    class Suggestion(BaseModel):
        hypothesis: str = Field(max_length=500)
        replacement_block: str = Field(max_length=4200)
        expected_measurement: str = Field(max_length=450)
        possible_regression: str = Field(max_length=450)

    _, _, current, region = extract_block(source)
    instructions = (
        "You are a cautious C++ performance engineer proposing ONE experiment "
        "for a 32-bit OpenLRR game under Wine on Apple Silicon. "
        "Your only output is structured data, NOT commands, shell scripts or files. "
        "Focus only on the existing windowed DirectDraw presentation bottleneck. "
        "Do not claim a speedup before paired benchmarks. "
        "Preserve DirectDraw fallback, MenuPerf timing, outcome counters, and fatal "
        "surface-lost detection. Produce the COMPLETE C++ replacement for only the "
        "existing const DWORD flags block, including its braces, tabs and whitespace; "
        "nothing before or after. Do not change other files, headers, telemetry "
        "definitions, source markers, app startup or process management. "
        "Never access credentials, resources, or use OS command execution. "
        "Two isolated baseline runs reported 31 windowed DirectDraw Blt calls "
        "taking over a second per run, but no periods outside DirectDraw_Flip "
        "over a second. The cause INSIDE Wine or DirectDraw is NOT established. "
        "Do not interpret baseline repeats as a performance improvement. "
        "Avoid re-running GDI or nowait without a new mechanism. "
        "The supported scope is narrow; no pre-existing fix is proven. "
        "If no specific, measurable and defensible change fits this scope, "
        "return the original block UNCHANGED. This is an accepted ABSTENTION, "
        "not failure. Use hypothesis to explain why the current evidence cannot "
        "justify a patch, and expected_measurement to specify which new evidence "
        "would change that decision. Never produce a cosmetic or speculative "
        "patch merely to satisfy the workflow."
    )
    agent = Agent(name="OpenLRR Candidate Author", model=model,
                  instructions=instructions, tools=[], output_type=Suggestion)
    input_data = {
        "historical_evidence": REFERENCE_CONTEXT,
        "reviewed_diagnostic_aggregate": evidence or {},
        "surrounding_function": region[:12000],
        "allowed_original_block": current,
    }
    result = Runner.run_sync(agent, json.dumps(input_data), max_turns=1).final_output
    if not isinstance(result, Suggestion):
        raise ValueError("Unexpected model output type")
    return result.model_dump()


def write_proposal(source_file: Path, output_dir: Path, proposal: dict) -> str:
    source = source_file.read_text(encoding="utf-8")
    _, _, original, _ = extract_block(source)
    output_dir.mkdir(parents=True, exist_ok=True)
    if proposal["replacement_block"] == original:
        # Abstaining from an ungrounded experiment is a valid research result.
        # Do not compile an identical build or charge the Mac for a blind test.
        note = {
            "status": "needs_better_evidence",
            "reason": proposal["hypothesis"][:500],
            "recommended_next_measurement": proposal["expected_measurement"][:450],
            "possible_regression": proposal["possible_regression"][:450],
            "source_file": SOURCE_REL,
            "compiled": False, "host_execution_authorized": False,
            "review_required": False, "based_on": REFERENCE_CONTEXT,
        }
        (output_dir / "proposal.json").write_text(
            json.dumps(note, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return "needs_better_evidence"
    revised = validate_replacement(source, proposal["replacement_block"])
    patch = make_patch(source, revised)
    if not patch.startswith("--- a/" + SOURCE_REL + "\n+++ b/" + SOURCE_REL + "\n"):
        raise ValueError("Patch path validation failed")
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "proposal.patch").write_text(patch, encoding="utf-8")
    note = {k: proposal[k] for k in (
        "hypothesis", "expected_measurement", "possible_regression")}
    note.update({
        "status": "patch_ready",
        "source_file": SOURCE_REL, "review_required": True,
        "compiled": False, "host_execution_authorized": False,
        "based_on": REFERENCE_CONTEXT,
    })
    (output_dir / "proposal.json").write_text(
        json.dumps(note, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return "patch_ready"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(SOURCE_REL))
    parser.add_argument("--out", type=Path, default=Path("candidate-output"))
    parser.add_argument("--model", default="gpt-6-luna")
    parser.add_argument("--preflight", action="store_true")
    parser.add_argument("--evidence", type=Path, default=Path(EVIDENCE_REL))
    args = parser.parse_args(argv)
    source = args.source.read_text(encoding="utf-8")
    _, _, block, _ = extract_block(source)
    evidence = validate_research_evidence(args.evidence)
    if args.preflight:
        print(json.dumps({
            "mode": "offline_preflight", "source": str(args.source),
            "editable_block_size": len(block),
            "evidence_id": evidence["experiment"], "api_called": False,
            "game_executed": False, "working_game_modified": False,
        }, indent=2))
        return 0
    if not os.getenv("OPENAI_API_KEY"):
        raise RuntimeError("Missing restricted OpenAI API key; no model request made")
    result = generate(source, args.model, evidence)
    status = write_proposal(args.source, args.out, result)
    if status == "needs_better_evidence":
        print("AI abstained: evidence request saved. No patch and no Mac execution.")
    else:
        print("AI proposal saved for remote compilation/review; Mac execution disabled.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, KeyError) as exc:
        print("AI PROPOSAL REJECTED:", exc, file=sys.stderr)
        raise SystemExit(2)
