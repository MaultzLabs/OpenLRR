#!/usr/bin/env python3
"""Create one AI-authored OpenLRR graphics experiment for offline review/build.

No GitHub write access, no shell tool for the model, no Mac/game execution.
The only output is an allowlisted C++ diff and a small JSON experiment note.
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


def generate(source: str, model: str) -> dict:
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
        "If uncertain, propose diagnostic instrumentation in this narrow block "
        "rather than an ungrounded performance change."
    )
    agent = Agent(name="OpenLRR Candidate Author", model=model,
                  instructions=instructions, tools=[], output_type=Suggestion)
    input_data = {
        "historical_evidence": REFERENCE_CONTEXT,
        "surrounding_function": region[:12000],
        "allowed_original_block": current,
    }
    result = Runner.run_sync(agent, json.dumps(input_data), max_turns=1).final_output
    if not isinstance(result, Suggestion):
        raise ValueError("Unexpected model output type")
    return result.model_dump()


def write_proposal(source_file: Path, output_dir: Path, proposal: dict) -> None:
    source = source_file.read_text(encoding="utf-8")
    revised = validate_replacement(source, proposal["replacement_block"])
    patch = make_patch(source, revised)
    if not patch.startswith("--- a/" + SOURCE_REL + "\n+++ b/" + SOURCE_REL + "\n"):
        raise ValueError("Patch path validation failed")
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "proposal.patch").write_text(patch, encoding="utf-8")
    note = {k: proposal[k] for k in (
        "hypothesis", "expected_measurement", "possible_regression")}
    note.update({
        "source_file": SOURCE_REL, "review_required": True,
        "compiled": False, "host_execution_authorized": False,
        "based_on": REFERENCE_CONTEXT,
    })
    (output_dir / "proposal.json").write_text(
        json.dumps(note, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(SOURCE_REL))
    parser.add_argument("--out", type=Path, default=Path("candidate-output"))
    parser.add_argument("--model", default="gpt-6-luna")
    parser.add_argument("--preflight", action="store_true")
    args = parser.parse_args(argv)
    source = args.source.read_text(encoding="utf-8")
    _, _, block, _ = extract_block(source)
    if args.preflight:
        print(json.dumps({
            "mode": "offline_preflight", "source": str(args.source),
            "editable_block_size": len(block), "api_called": False,
            "game_executed": False, "working_game_modified": False,
        }, indent=2))
        return 0
    if not os.getenv("OPENAI_API_KEY"):
        raise RuntimeError("Missing restricted OpenAI API key; no model request made")
    result = generate(source, args.model)
    write_proposal(args.source, args.out, result)
    print("AI proposal saved for remote compilation/review; Mac execution disabled.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, KeyError) as exc:
        print("AI PROPOSAL REJECTED:", exc, file=sys.stderr)
        raise SystemExit(2)
