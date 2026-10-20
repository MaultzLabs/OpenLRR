#!/usr/bin/env python3
"""Bounded, human-enabled OpenLRR Mac test supervisor (approved DLLs only).

No model-selected commands, new binaries, self-updates, or working-game writes.
By default it prints a preflight plan and does not start the game.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

HOME = Path.home()
CONFIG = HOME / ".config" / "openlrr-benchmark"
STATE = HOME / ".local" / "share" / "openlrr-agent"
GAME = HOME / "Applications" / "Sikarugir" / "OpenLRR Menu Test.app" / "Contents" / "SharedSupport" / "prefix" / "drive_c" / "Program Files" / "Rock Raiders OpenLRR"
RESULTS = HOME / "Downloads" / "OpenLRR Benchmark Runs"
DLL = HOME / "Downloads" / "openlrr.dll"
RUNNER = HOME / "Downloads" / "run-autobenchmark.sh"
ANALYZER = HOME / "Downloads" / "analyze-benchmark.py"
AGENT = HOME / "OpenLRR-Agent" / "scripts" / "agent" / "openlrr_agent.py"
STOP = CONFIG / "STOP"
PAUSE = CONFIG / "PAUSE"
LOCK = CONFIG / "supervisor.lock"
AUDIT = STATE / "supervisor-events.jsonl"
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
RUN_RE = re.compile(r"^autobenchmark-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$")
REPO = "MaultzLabs/OpenLRR-Test-Results"


def fingerprint(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_plan(value: str) -> list[str]:
    parts = value.split(",")
    if not 1 <= len(parts) <= 4 or parts[0] != "baseline" or any(
            x not in {"baseline", "nowait", "gdi", "dib"} for x in parts):
        raise ValueError("Plan must start with baseline and contain 1..4 approved modes")
    return parts


def audit(kind: str, **details) -> None:
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    record = {"utc": datetime.now(timezone.utc).isoformat(), "event": kind, **details}
    descriptor = os.open(AUDIT, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as out:
        out.write(json.dumps(record, sort_keys=True) + "\n")
        out.flush()
        os.fsync(out.fileno())


def switches() -> str:
    if STOP.exists():
        return "stop"
    if PAUSE.exists():
        return "pause"
    return "ready"


def wait_unpaused(limit_seconds: int = 1800) -> bool:
    start = time.monotonic()
    while True:
        status = switches()
        if status == "stop":
            return False
        if status == "ready":
            return True
        if time.monotonic() - start >= limit_seconds:
            raise RuntimeError("PAUSE wait exceeded configured maximum")
        time.sleep(2)


def known_runs() -> set[str]:
    if not RESULTS.exists():
        return set()
    return {p.name for p in RESULTS.iterdir() if p.is_dir() and RUN_RE.fullmatch(p.name)}


def verify_upload(run_name: str, filename: str) -> None:
    local = RESULTS / run_name / filename
    remote = subprocess.run(
        ["gh", "api", "--method", "GET",
         f"repos/{REPO}/contents/runs/{run_name}/{filename}", "--jq", ".sha"],
        capture_output=True, text=True, timeout=40, check=False,
    )
    if remote.returncode != 0:
        raise RuntimeError(f"Private upload missing: {run_name}/{filename}")
    expected = subprocess.run(
        ["git", "hash-object", "--no-filters", str(local)],
        capture_output=True, text=True, timeout=20, check=True,
    ).stdout.strip()
    if remote.stdout.strip() != expected:
        raise RuntimeError(f"Private upload hash mismatch: {run_name}/{filename}")


def verify_result(run_name: str, mode: str, expected_sha: str) -> Path:
    if not RUN_RE.fullmatch(run_name):
        raise RuntimeError("Unexpected benchmark directory name")
    run = RESULTS / run_name
    receipt = run / "lifecycle.verified"
    if not receipt.is_file() or receipt.read_text(encoding="utf-8") != (
            "wrapper_wait_exited=yes\ntest_game_handles=none\n"):
        raise RuntimeError("No verified app-exit receipt; refusing another test")
    summary = json.loads((run / "summary.json").read_text(encoding="utf-8"))
    if summary.get("schema_version") != 1 or summary.get("run") != run_name:
        raise RuntimeError("Invalid run summary")
    if summary.get("dll_sha256") != expected_sha:
        raise RuntimeError("Test did not use the approved binary")
    graphics = summary.get("metrics", {}).get("mode")
    wanted = {"optimization": 0, "nowait": int(mode == "nowait"),
              "gdi": int(mode == "gdi")}
    if mode == "dib":
        wanted["dib"] = 1
    if graphics != wanted or summary.get("close_requested") is not True:
        raise RuntimeError("Wrong graphics mode or missing close-request evidence")
    metrics = summary["metrics"]
    if (not isinstance(metrics.get("present_calls"), int)
            or metrics["present_calls"] < 1
            or not isinstance(metrics.get("logged_duration_s"), (float, int))
            or metrics["logged_duration_s"] < 10):
        raise RuntimeError("Incomplete benchmark metrics")
    if mode == "dib":
        if (metrics.get("present_path") != "dib_cpu"
                or type(metrics.get("dib_accepted_calls")) is not int
                or type(metrics.get("dib_fallback_calls")) is not int
                or metrics["dib_accepted_calls"] + metrics["dib_fallback_calls"] !=
                    metrics["present_calls"]):
            raise RuntimeError("CPU bitmap experiment lacks accepted/fallback evidence")
    verify_upload(run_name, "menuperf.csv")
    verify_upload(run_name, "summary.json")
    verify_upload(run_name, "lifecycle.verified")
    return run / "menuperf.csv"


def run_one(mode: str, approved_sha: str, seconds: int, baseline: Path | None) -> tuple[str, Path]:
    if switches() != "ready":
        raise RuntimeError("PAUSE or STOP active before game launch")
    if fingerprint(DLL) != approved_sha:
        raise RuntimeError("Approved test DLL changed; aborting")
    before = known_runs()
    env = {k: v for k, v in os.environ.items()
           if not k.startswith("OPENAI_") and k not in
           {"GITHUB_TOKEN", "GH_TOKEN", "GIT_ASKPASS", "SSH_ASKPASS"}}
    env.update(OPENLRR_SUPERVISED="1", OPENLRR_BENCH_MODE=mode,
               OPENLRR_BENCH_SECONDS=str(seconds))
    env.pop("OPENLRR_BASELINE_CSV", None)
    if baseline:
        env["OPENLRR_BASELINE_CSV"] = str(baseline)
    command = ["bash", str(RUNNER)]
    audit("run_start", mode=mode, approved_sha=approved_sha)
    child = subprocess.Popen(command, env=env)
    started = time.monotonic()
    deadline = seconds + 430
    try:
        while child.poll() is None:
            if time.monotonic() - started > deadline:
                STOP.touch(exist_ok=True)
                audit("timeout_stop_requested", mode=mode)
                try:
                    child.wait(timeout=75)
                except subprocess.TimeoutExpired:
                    raise RuntimeError(
                        "Runner still active after STOP; do NOT start another run. "
                        "Close the TEST game manually.")
                raise RuntimeError("Runner timed out; STOP remains set")
            if STOP.exists():
                audit("user_stop_requested", mode=mode)
                try:
                    child.wait(timeout=75)
                except subprocess.TimeoutExpired:
                    raise RuntimeError(
                        "STOP pending: TEST game may still run. No forced kill; check Mac.")
                raise RuntimeError("STOP received. No more tests.")
            time.sleep(2)
        if child.returncode != 0:
            raise RuntimeError(f"Benchmark exited {child.returncode}; no more tests")
        if switches() == "stop":
            raise RuntimeError("STOP set at end of benchmark")
        candidates = known_runs() - before
        if len(candidates) != 1:
            raise RuntimeError("Cannot uniquely identify completed benchmark")
        run_name = candidates.pop()
        csv = verify_result(run_name, mode, approved_sha)
        audit("run_verified", mode=mode, run=run_name)
        return run_name, csv
    finally:
        if child.poll() is None:
            audit("runner_still_active", mode=mode)


def handoff_verified_pair(runs: list[str], plan: list[str], approved_sha: str) -> Path:
    """Hand a completed, genuine two-arm supervisor trial to the policy controller.

    This only creates a manifest and reads validated run evidence. No model,
    patch, game execution or extra benchmark is scheduled.
    """
    if len(runs) != 2 or len(plan) != 2 or plan[0] != "baseline" or plan[1] not in ("nowait", "gdi"):
        raise ValueError("Automatic policy handoff requires exactly baseline,nowait or baseline,gdi")
    if any(not RUN_RE.fullmatch(run) for run in runs) or runs[0] == runs[1]:
        raise ValueError("Invalid or reused run identity")
    if not SHA_RE.fullmatch(approved_sha):
        raise ValueError("Invalid reviewed DLL identity")
    if switches() != "ready":
        raise RuntimeError("STOP or PAUSE before verified policy handoff")

    # The supervisor already checked these after each run. Check again here:
    # the controller must never trust an unverified filename.
    for name, mode in zip(runs, plan):
        verify_result(name, mode, approved_sha)

    checkout = HOME / "OpenLRR-Agent"
    controller = checkout / "scripts" / "agent" / "experiment_controller.py"
    python = HOME / ".local/share/openlrr-agent/venv/bin/python"
    if not controller.is_file() or not python.is_file():
        raise RuntimeError("Verified policy controller not installed in local lab checkout")
    experiments = STATE / "experiments"
    experiments.mkdir(parents=True, exist_ok=True, mode=0o700)
    experiment_id = "paired_" + runs[0][-19:].replace("-", "_") + "_" + runs[1][-19:].replace("-", "_")
    if len(experiment_id) > 64:
        raise RuntimeError("Pair identity exceeded manifest format")
    manifest = {
        "schema_version": 1,
        "experiment_id": experiment_id,
        "hypothesis": (
            "Test whether the " + plan[1] +
            " windowed presentation variant improves timing without regressions."
        ),
        "controlled_scene": "menu_boot_autotest_v1",
        "pairs": [{"baseline": runs[0], "candidate": runs[1]}],
    }
    target = experiments / (experiment_id + ".json")
    if target.exists():
        raise RuntimeError("Experiment handoff already exists; refusing to overwrite")
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as output:
        output.write(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        output.flush()
        os.fsync(output.fileno())

    decision_path = experiments / (experiment_id + "-decision.json")
    env = {k: v for k, v in os.environ.items()
           if not k.startswith("OPENAI_") and k not in
           {"GH_TOKEN", "GITHUB_TOKEN", "GIT_ASKPASS", "SSH_ASKPASS"}}
    command = [
        str(python), str(controller), "--manifest", str(target),
        "--runs-dir", str(RESULTS), "--ledger",
        str(STATE / "research-controller.json"),
        "--output", str(decision_path), "--commit",
    ]
    audited = subprocess.run(command, env=env, timeout=60, check=False)
    if audited.returncode != 0 or not decision_path.is_file():
        raise RuntimeError("Verified A/B handoff failed; do not advance the experiment")
    decision = json.loads(decision_path.read_text(encoding="utf-8"))
    if (decision.get("experiment_id") != experiment_id or
        decision.get("manifest_verified") is not True or
        decision.get("may_install_or_run_candidate") is not False):
        raise RuntimeError("Policy handoff did not establish safe boundaries")
    if (decision.get("disposition") == "ready_for_new_research" and
            decision.get("ledger_committed") is True):
        # Queue data, never execute a model or launch a cloud workflow here.
        ticket_builder = checkout / "scripts" / "agent" / "research_ticket.py"
        if not ticket_builder.is_file():
            raise RuntimeError("Research ticket builder missing after recorded policy decision")
        ticket_path = experiments / (experiment_id + "-research-ticket.json")
        request = [
            str(python), str(ticket_builder),
            "--decision", str(decision_path),
            "--ledger", str(STATE / "research-controller.json"),
            "--out", str(ticket_path),
        ]
        queued = subprocess.run(request, env=env, timeout=30, check=False)
        if queued.returncode != 0 or not ticket_path.is_file():
            raise RuntimeError("Research ticket creation failed; do not invoke AI automatically")
        ticket = json.loads(ticket_path.read_text(encoding="utf-8"))
        if (ticket.get("experiment_id") != experiment_id or
                ticket.get("approved_to_invoke_model") is not False or
                ticket.get("approved_to_execute_game") is not False):
            raise RuntimeError("Research ticket did not preserve authority boundary")
        audit("research_ticket_queued", experiment_id=experiment_id,
              ticket_id=ticket.get("ticket_id"))
    audit("policy_handoff_completed", experiment_id=experiment_id,
          next_step=decision.get("next_step"))
    return decision_path


def preflight(sha: str, plan: list[str], seconds: int, do_run: bool):
    if not SHA_RE.fullmatch(sha):
        raise ValueError("Expected a full lowercase SHA256 checksum")
    if not DLL.is_file() or fingerprint(DLL) != sha:
        raise RuntimeError("Approved DLL missing or SHA256 does not match")
    if not GAME.is_dir() or not (GAME / "LegoRR.exe").is_file():
        raise RuntimeError("Dedicated TEST game installation missing")
    if not RUNNER.is_file() or not ANALYZER.is_file():
        raise RuntimeError("Expected trusted Mac benchmark scripts are missing")
    if not 30 <= seconds <= 300:
        raise ValueError("Supervised tests must last 30..300 seconds")
    if do_run and (STOP.exists() or LOCK.exists()):
        raise RuntimeError("STOP or stale/concurrent supervisor lock present; fail closed")
    return {
        "test_only": str(GAME), "modes": plan,
        "seconds_per_run": seconds, "approved_sha256": sha,
        "will_run": do_run, "automatic_code_changes": False,
        "automatic_new_builds": False,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--approved-sha", required=True)
    parser.add_argument("--plan", default="baseline,gdi")
    parser.add_argument("--seconds", type=int, default=210)
    parser.add_argument("--run", action="store_true",
                        help="Actually launch approved fixed tests; otherwise preflight only")
    parser.add_argument("--analyze", action="store_true",
                        help="After two or more verified runs, call the read-only OpenAI agent once")
    parser.add_argument("--model", default="gpt-6-luna")
    parser.add_argument("--coordinate", action="store_true",
                        help="After two verified A/B runs, record one policy decision; no AI or extra game execution")
    args = parser.parse_args(argv)
    plan = parse_plan(args.plan)
    if args.coordinate and (not args.run or len(plan) != 2 or plan[1] == "baseline"):
        parser.error("--coordinate requires --run and exactly baseline,nowait or baseline,gdi")
    if args.analyze and not args.run:
        parser.error("--analyze requires --run")
    if args.analyze and len(plan) < 2:
        parser.error("--analyze requires two benchmark modes")
    info = preflight(args.approved_sha, plan, args.seconds, args.run)
    print(json.dumps(info, indent=2), flush=True)
    if not args.run:
        print("DRY RUN ONLY. Add --run after inspecting the plan.")
        return 0
    CONFIG.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        LOCK.mkdir(mode=0o700)
    except FileExistsError:
        raise RuntimeError("Concurrent/stale supervisor.lock. No test launched.")
    completed_safely = False
    try:
        audit("supervisor_started", plan=plan, approved_sha=args.approved_sha)
        baseline = None
        completed = []
        for mode in plan:
            if not wait_unpaused():
                audit("supervisor_stopped")
                return 2
            run_name, csv = run_one(mode, args.approved_sha, args.seconds, baseline)
            completed.append(run_name)
            if mode == "baseline":
                baseline = csv
        if args.analyze:
            if not os.environ.get("OPENAI_API_KEY"):
                raise RuntimeError("No OPENAI_API_KEY in this Terminal; tests are preserved")
            if switches() != "ready":
                raise RuntimeError("STOP/PAUSE before AI analysis")
            agent = HOME / ".local/share/openlrr-agent/venv/bin/python"
            command = [str(agent), str(AGENT), "--once", "--model", args.model]
            audit("analysis_started")
            completed_ai = subprocess.run(command, timeout=180, check=False)
            if completed_ai.returncode:
                raise RuntimeError("AI analysis failed; benchmark data was preserved")
            audit("analysis_completed")
        if args.coordinate:
            policy_output = handoff_verified_pair(completed, plan, args.approved_sha)
            print("Verified experiment policy record:", policy_output)
        audit("supervisor_completed", runs=completed)
        print("Verified test plan finished:", ", ".join(completed))
        completed_safely = True
        return 0
    finally:
        if completed_safely:
            LOCK.rmdir()
        else:
            print("SAFETY HOLD: supervisor.lock retained; verify TEST game is closed, "
                  "then remove the lock manually before any restart.", file=sys.stderr)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError,
            subprocess.SubprocessError) as exc:
        print("SAFETY STOP:", exc, file=sys.stderr)
        sys.exit(2)
    except KeyboardInterrupt:
        # A user Ctrl+C must block further starts; the runner watches STOP
        # and requests a graceful quit. No force-kill of a Wine process.
        CONFIG.mkdir(parents=True, exist_ok=True)
        STOP.touch(exist_ok=True)
        print("\nSTOP requested. Check that the TEST game exits before restarting.", file=sys.stderr)
        sys.exit(130)
