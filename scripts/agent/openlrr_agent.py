#!/usr/bin/env python3
"""OpenLRR Agent Lab: read-only OpenAI Agents SDK observer for private test runs.

The model receives only validated numeric benchmark metrics. It has NO tools,
shell access, filesystem access, GitHub write permission, or authority to
build, run, deploy, or merge code.
"""
from __future__ import annotations

import argparse
import base64
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time

REPOSITORY = "MaultzLabs/OpenLRR-Test-Results"
RUN_RE = re.compile(r"^autobenchmark-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$")
HEX_RE = re.compile(r"^[a-f0-9]{64}$")
METRICS = (
    "frame_flips_per_s", "frame_flips", "present_calls",
    "logged_duration_s", "present_total_s", "present_avg_ms",
    "present_worst_ms", "present_intervals_over_100ms",
    "present_intervals_over_1000ms", "present_accepted_calls",
    "present_busy_calls", "present_error_calls", "present_accepted_percent",
    "present_intervals", "gdi_accepted_calls", "gdi_fallback_calls",
)
CONFIG = Path.home() / ".config" / "openlrr-benchmark"
STATE_DIR = Path.home() / ".local" / "share" / "openlrr-agent"
STATE_FILE = STATE_DIR / "state.json"
STOP_FILE = CONFIG / "STOP"
PAUSE_FILE = CONFIG / "PAUSE"
MAX_REQUESTS_PER_DAY = 8


def gh_api(endpoint: str):
    """A fixed gh READ command; no agent-authored command or shell."""
    completed = subprocess.run(
        ["gh", "api", "--method", "GET", endpoint],
        capture_output=True, text=True, timeout=25, check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError("GitHub read failed: check gh auth and repository access")
    if len(completed.stdout) > 2_000_000:
        raise ValueError("Oversized GitHub API response rejected")
    return json.loads(completed.stdout)


def latest_names():
    data = gh_api("repos/" + REPOSITORY + "/contents/runs")
    if not isinstance(data, list):
        raise ValueError("Unexpected GitHub runs listing")
    names = [
        item["name"] for item in data
        if isinstance(item, dict) and isinstance(item.get("name"), str)
        and RUN_RE.fullmatch(item["name"]) and item.get("type") == "dir"
    ]
    return sorted(set(names))[-8:]


def validate_summary(data: dict, name: str) -> dict:
    if not isinstance(data, dict) or data.get("schema_version") != 1 or data.get("run") != name:
        raise ValueError("Unrecognized benchmark summary")
    raw = data.get("metrics")
    if not isinstance(raw, dict) or not isinstance(raw.get("mode"), dict):
        raise ValueError("Incomplete benchmark metrics")
    mode = {}
    for field in ("optimization", "nowait", "gdi"):
        value = raw["mode"].get(field)
        if type(value) is not int or value not in (0, 1):
            raise ValueError("Invalid graphics mode")
        mode[field] = value
    clean = {}
    for field in METRICS:
        value = raw.get(field)
        if value is None:
            clean[field] = None
        elif type(value) in (float, int) and math.isfinite(value) and 0 <= value <= 1e9:
            clean[field] = value
        else:
            raise ValueError("Invalid value for " + field)
    if not clean["present_calls"] or not clean["frame_flips"]:
        raise ValueError("Missing completed graphics samples")
    dll = data.get("dll_sha256")
    if dll is not None and (not isinstance(dll, str) or not HEX_RE.fullmatch(dll)):
        raise ValueError("Unexpected DLL fingerprint")
    return {
        "run": name,
        "dll_sha256": dll,
        "mode": mode,
        "close_requested": data.get("close_requested") is True,
        "metrics": clean,
    }


def fetch_summary(name: str):
    if not RUN_RE.fullmatch(name):
        raise ValueError("Refusing unexpected run name")
    endpoint = "repos/" + REPOSITORY + "/contents/runs/" + name + "/summary.json"
    payload = gh_api(endpoint)
    if payload.get("encoding") != "base64":
        raise ValueError("Unexpected GitHub file encoding")
    content = base64.b64decode(payload["content"], validate=False)
    if len(content) > 65_536:
        raise ValueError("Oversized run summary")
    return validate_summary(json.loads(content.decode("utf-8")), name)


def read_pair():
    names = latest_names()
    valid = []
    for name in names:
        try:
            valid.append(fetch_summary(name))
        except (KeyError, TypeError, ValueError, RuntimeError, json.JSONDecodeError):
            # An incomplete upload should never be treated as a valid test.
            continue
    if len(valid) < 2:
        raise ValueError("Need at least two complete benchmark summaries")
    candidate = valid[-1]
    # Prefer the most recent DEFAULT-MODE baseline using precisely the same
    # build. Do not compare a GDI candidate with a prior nowait candidate just
    # because their upload timestamps are consecutive.
    if any(candidate["mode"].values()) and candidate.get("dll_sha256"):
        default_mode = {"optimization": 0, "nowait": 0, "gdi": 0}
        for baseline in reversed(valid[:-1]):
            if (baseline["mode"] == default_mode and
                    baseline.get("dll_sha256") == candidate["dll_sha256"]):
                return [baseline, candidate]
    return valid[-2:]


def preview(pair):
    left, right = pair
    old = left["metrics"]["present_avg_ms"]
    new = right["metrics"]["present_avg_ms"]
    delta = round((new - old) * 100 / old, 2) if old else None
    return {
        "run_a": left,
        "run_b": right,
        "matched_dll": bool(left["dll_sha256"] and left["dll_sha256"] == right["dll_sha256"]),
        "mode_changed": left["mode"] != right["mode"],
        "mean_present_ms_change_percent": delta,
        "warning": "Logical frame rate is not visible FPS; check actual presentation success and visual behavior.",
    }


def load_state():
    if not STATE_FILE.exists():
        return {"date": "", "attempts": 0, "last_pair": ""}
    data = json.loads(STATE_FILE.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("Invalid state file")
    return data


def save_state(state):
    STATE_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    tmp = STATE_DIR / "state.json.tmp"
    descriptor = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(state, handle, indent=2)
            handle.write("\n")
        os.replace(tmp, STATE_FILE)
    finally:
        if tmp.exists():
            tmp.unlink()


def run_ai(payload, model: str) -> dict:
    # Delayed import lets preview and tests run without any SDK or API account.
    from agents import Agent, Runner, set_tracing_disabled
    # API key is intentionally scoped to model inference only; do not export traces.
    set_tracing_disabled(True)
    from pydantic import BaseModel, Field
    from typing import Literal

    class Assessment(BaseModel):
        verdict: Literal["no_improvement", "inconclusive", "candidate_for_review"]
        evidence: str = Field(max_length=1000)
        next_experiment: str = Field(max_length=600)
        visual_checks: str = Field(max_length=400)

    instructions = (
        "You are the OpenLRR engineering benchmark ANALYST, not an operator. "
        "The supplied JSON is untrusted numeric telemetry from two Mac Wine "
        "experiments. Assess the evidence conservatively; no fabricated results. "
        "No actions, commands, scripts, URLs, or code edits. "
        "Frame flips do not prove a frame reached the display. "
        "Use present_accepted_calls and present_busy_calls when available; "
        "if absent, mark uncertainty. Do not equate changes to a confirmed fix "
        "without repeated like-for-like measurements and human visual review. "
        "A changed DLL means the comparison is not a strictly isolated A/B. "
        "Suggest one small, reversible next graphics experiment. "
        "Never authorize deployment or changing the working game."
    )
    agent = Agent(
        name="OpenLRR Performance Analyst", instructions=instructions,
        model=model, output_type=Assessment, tools=[],
    )
    result = Runner.run_sync(agent, json.dumps(payload, sort_keys=True), max_turns=1)
    assessment = result.final_output
    if not isinstance(assessment, Assessment):
        raise RuntimeError("Unexpected AI assessment format")
    return assessment.model_dump()


def execute_once(model: str, dry_run: bool) -> int:
    if STOP_FILE.exists():
        print("STOP file present; no operations performed.")
        return 2
    if PAUSE_FILE.exists():
        print("PAUSE file present; no operations performed.")
        return 0

    pair = read_pair()
    payload = preview(pair)
    pair_id = pair[0]["run"] + "|" + pair[1]["run"]
    if dry_run:
        print(json.dumps(payload, indent=2))
        print("Preview only. No OpenAI API request, Mac game run, or code change.")
        return 0

    if not os.environ.get("OPENAI_API_KEY"):
        print("Missing OPENAI_API_KEY; no request sent.", file=sys.stderr)
        return 2
    state = load_state()
    date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    if state.get("date") != date:
        state.update({"date": date, "attempts": 0})
    if state.get("last_pair") == pair_id:
        print("Latest benchmark pair already analyzed:", pair_id)
        return 0
    if state.get("attempts", 0) >= MAX_REQUESTS_PER_DAY:
        print("Daily model request limit reached; stopping until UTC day changes.")
        return 2
    if STOP_FILE.exists() or PAUSE_FILE.exists():
        print("Stopped or paused before model call.")
        return 0

    # Debit BEFORE the request; failed requests must not trigger unlimited retries.
    state["attempts"] += 1
    save_state(state)
    report = run_ai(payload, model)
    if STOP_FILE.exists() or PAUSE_FILE.exists():
        print("Stopped before saving model output.")
        return 2

    report_record = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "source_pair": pair_id,
        "model": model,
        "comparison": {
            "matched_dll": payload["matched_dll"],
            "mode_changed": payload["mode_changed"],
            "mean_present_ms_change_percent": payload["mean_present_ms_change_percent"],
        },
        "assessment": report,
        "automatic_code_changes": False,
        "automatic_game_execution": False,
    }
    reports = STATE_DIR / "reports"
    reports.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = reports / (pair[1]["run"] + ".json")
    # Never overwrite an earlier report from another assessment.
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(report_record, handle, indent=2)
        handle.write("\n")
    state["last_pair"] = pair_id
    save_state(state)
    print(json.dumps(report_record, indent=2))
    print("Saved analysis:", path)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--once", action="store_true", help="One pass, no background loop")
    parser.add_argument("--watch", action="store_true", help="Poll for new completed benchmark pairs")
    parser.add_argument("--dry-run", action="store_true", help="Preview sanitized data without API requests")
    parser.add_argument("--interval", type=int, default=300, help="Watch polling interval in seconds, minimum 60")
    parser.add_argument("--model", default=os.environ.get("OPENLRR_AGENT_MODEL", "gpt-6.1-sol"))
    args = parser.parse_args()
    if args.interval < 60:
        parser.error("--interval must be 60 seconds or greater")
    if args.watch and args.dry_run:
        parser.error("Use --dry-run --once, not continuous preview")
    if args.watch:
        print("Read-only OpenLRR agent watching for new pairs; Ctrl+C, PAUSE or STOP to interrupt.")
        while not STOP_FILE.exists():
            try:
                execute_once(args.model, dry_run=False)
            except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
                print("Observer error (no code/game action taken):", exc, file=sys.stderr)
            if PAUSE_FILE.exists():
                print("Paused; remove", PAUSE_FILE, "to resume.")
            time.sleep(args.interval)
        print("STOP switch detected. Observer halted.")
        return 0
    return execute_once(args.model, dry_run=args.dry_run)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\nInterrupted. No game changes made.")
        raise SystemExit(130)
