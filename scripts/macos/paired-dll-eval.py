#!/usr/bin/env python3
"""Explicitly approved, isolated A/B tests of two DIFFERENT OpenLRR DLLs.

This closes the code-change experimental gap that menu baseline/nowait tests
cannot address. Default mode is dry-run. It never downloads new code, accepts
an LLM instruction, or modifies the working game. Candidate must already be
in the independently validated quarantine inbox.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

HOME = Path.home()
STATE = HOME / ".local/share/openlrr-agent"
CONFIG = HOME / ".config/openlrr-benchmark"
RESULTS = HOME / "Downloads/OpenLRR Benchmark Runs"
DOWNLOAD_DLL = HOME / "Downloads/openlrr.dll"
BACKUP = HOME / "Downloads/.openlrr-paired-eval-original.dll"
TEMP = HOME / "Downloads/.openlrr-paired-eval-pending.dll"
BASELINE = STATE / "approved-baselines/openlrr.dll"
INBOX = STATE / "candidate-inbox"
LOCK = STATE / "paired-eval.lock"
SUPERVISOR = HOME / "OpenLRR-Agent/scripts/macos/lab-supervisor.py"
CONTROLLER = HOME / "OpenLRR-Agent/scripts/agent/experiment_controller.py"
PYTHON = STATE / "venv/bin/python"
SHA = re.compile(r"^[a-f0-9]{64}$")
RUN_ID = re.compile(r"^[0-9]{8,14}$")
BENCH_ID = re.compile(r"^autobenchmark-\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d$")


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def assert_safe_file(path: Path, expected: str) -> None:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 10_000_000:
        raise ValueError("Untrusted or missing source DLL")
    if not SHA.fullmatch(expected) or digest(path) != expected:
        raise ValueError("Source DLL hash disagrees with explicitly reviewed SHA256")
    with path.open("rb") as handle:
        header = handle.read(4096)
    if len(header) < 256 or header[:2] != b"MZ":
        raise ValueError("Not a Windows DLL")
    pe = int.from_bytes(header[0x3c:0x40], "little")
    if pe + 6 > len(header) or header[pe:pe + 4] != b"PE\0\0":
        raise ValueError("Invalid Windows PE header")
    if int.from_bytes(header[pe + 4:pe + 6], "little") != 0x14c:
        raise ValueError("Expected 32-bit x86 DLL")


def candidate_source(run_id: str, candidate_sha: str) -> Path:
    if not RUN_ID.fullmatch(run_id):
        raise ValueError("Invalid candidate cloud run ID")
    root = INBOX / ("run-" + run_id)
    if root.is_symlink() or not root.is_dir() or root.resolve().parent != INBOX.resolve():
        raise ValueError("Candidate is not in the fixed quarantine")
    module_path = Path(__file__).resolve().with_name("candidate-inbox.py")
    spec = importlib.util.spec_from_file_location("openlrr_candidate_quarantine", module_path)
    inbox = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(inbox)
    # No provenance claims supplied by the model override a SHA mismatch.
    verified = inbox.validate_bundle(root)
    metadata = json.loads((root / "provenance.json").read_text(encoding="utf-8"))
    if (metadata.get("run_id") != run_id or
        metadata.get("candidate_sha256") != candidate_sha or
        metadata.get("automatic_execution") is not False or
        verified["candidate_sha256"] != candidate_sha):
        raise ValueError("Candidate provenance is incomplete or does not match approval")
    return root / "openlrr.dll"


def preflight(base_sha: str, candidate_sha: str, run_id: str, pairs: int, seconds: int) -> dict:
    if not SHA.fullmatch(base_sha) or not SHA.fullmatch(candidate_sha) or base_sha == candidate_sha:
        raise ValueError("A/B requires two distinct, explicitly reviewed DLL hashes")
    if pairs not in (1, 2, 3, 4, 5) or not 30 <= seconds <= 180:
        raise ValueError("Limited to 1..5 pairs, each run 30..180 seconds")
    if (CONFIG / "STOP").exists() or (CONFIG / "PAUSE").exists():
        raise RuntimeError("STOP or PAUSE active")
    if LOCK.exists() or (CONFIG / "supervisor.lock").exists():
        raise RuntimeError("Experiment lock exists; do not launch another test")
    if BACKUP.exists() or TEMP.exists():
        raise RuntimeError("Unrecovered staged DLL backup exists; manual inspection required")
    if DOWNLOAD_DLL.is_symlink():
        raise ValueError("Refuse to replace a symlinked Downloads DLL")
    if any(not path.is_file() for path in (SUPERVISOR, CONTROLLER, PYTHON)):
        raise RuntimeError("Trusted supervisor/controller/Python checkout missing")
    assert_safe_file(BASELINE, base_sha)
    baseline_metadata = BASELINE.parent / "provenance.json"
    if baseline_metadata.is_symlink() or not baseline_metadata.is_file() or baseline_metadata.stat().st_size > 4096:
        raise ValueError("Baseline lacks bounded, reviewed GitHub build provenance")
    origin = json.loads(baseline_metadata.read_text(encoding="utf-8"))
    if (origin.get("dll_sha256") != base_sha or
        origin.get("reviewed_source_workflow") != "OpenLRR Menu Diagnostics Win32" or
        origin.get("approved_for_automatic_execution") is not False or
        origin.get("tested_in_game") is not False or
        not RUN_ID.fullmatch(str(origin.get("source_run", ""))) or
        not re.fullmatch(r"[a-f0-9]{40}", str(origin.get("head_sha", "")))):
        raise ValueError("Baseline provenance does not match the reviewed hash")
    assert_safe_file(candidate_source(run_id, candidate_sha), candidate_sha)
    return {
        "baseline_sha256": base_sha, "candidate_sha256": candidate_sha,
        "candidate_cloud_run_id": run_id, "pairs": pairs,
        "seconds_per_run": seconds, "max_game_runs": 2 * pairs,
        "isolated_test_only": True, "working_game_modified": False,
        "execution_requires_explicit_run_flag": True, "automatic_deployment": False,
    }


def names() -> set[str]:
    if not RESULTS.exists():
        return set()
    return {p.name for p in RESULTS.iterdir() if p.is_dir() and BENCH_ID.fullmatch(p.name)}


def stage_source(source: Path, sha: str):
    assert_safe_file(source, sha)
    if TEMP.exists():
        raise RuntimeError("Unrecovered staging file")
    shutil.copyfile(source, TEMP)
    if digest(TEMP) != sha:
        raise RuntimeError("Staged DLL differs from approved source")
    os.replace(TEMP, DOWNLOAD_DLL)


def invoke_supervisor(sha: str, seconds: int, *, run=subprocess.run) -> str:
    if (CONFIG / "STOP").exists() or (CONFIG / "PAUSE").exists():
        raise RuntimeError("STOP/PAUSE before test")
    before = names()
    environment = {k: v for k, v in os.environ.items() if
                   not k.startswith("OPENAI_") and k not in (
                       "GH_TOKEN", "GITHUB_TOKEN", "GIT_ASKPASS", "SSH_ASKPASS")}
    argv = [str(PYTHON), str(SUPERVISOR), "--approved-sha", sha,
            "--plan", "baseline", "--seconds", str(seconds), "--run"]
    complete = run(argv, env=environment, timeout=seconds + 690, check=False)
    if complete.returncode != 0:
        raise RuntimeError("Trusted supervisor did not confirm successful game exit")
    added = names() - before
    if len(added) != 1:
        raise RuntimeError("Cannot uniquely identify newly verified benchmark")
    name = added.pop()
    folder = RESULTS / name
    receipt = folder / "lifecycle.verified"
    if not receipt.is_file() or receipt.read_text(encoding="utf-8") != (
        "wrapper_wait_exited=yes\ntest_game_handles=none\n"
    ):
        raise RuntimeError("Missing verified process-exit receipt")
    summary = json.loads((folder / "summary.json").read_text(encoding="utf-8"))
    if (summary.get("dll_sha256") != sha or summary.get("run") != name or
        summary.get("close_requested") is not True or
        summary.get("metrics", {}).get("mode") !=
            {"optimization": 0, "nowait": 0, "gdi": 0}):
        raise RuntimeError("Result does not prove the expected binary and baseline graphics mode")
    return name


def execute(base_sha: str, cand_sha: str, run_id: str,
            pairs: int, seconds: int, *, run=subprocess.run) -> dict:
    preflight(base_sha, cand_sha, run_id, pairs, seconds)
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    LOCK.mkdir(mode=0o700)
    originally_present = DOWNLOAD_DLL.exists()
    completed_safely = False
    staged = False
    recorded = []
    try:
        if originally_present:
            os.replace(DOWNLOAD_DLL, BACKUP)
        staged = True
        candidate = candidate_source(run_id, cand_sha)
        for i in range(pairs):
            # Reverse AB order every other pair to reduce temporal bias.
            order = [("baseline", BASELINE, base_sha),
                     ("candidate", candidate, cand_sha)]
            if i % 2:
                order.reverse()
            observation = {}
            for arm, source, expected in order:
                if (CONFIG / "STOP").exists() or (CONFIG / "PAUSE").exists():
                    raise RuntimeError("STOP/PAUSE between runs")
                stage_source(source, expected)
                observation[arm] = invoke_supervisor(expected, seconds, run=run)
            recorded.append(observation)
        if (CONFIG / "STOP").exists() or (CONFIG / "PAUSE").exists():
            raise RuntimeError("STOP/PAUSE before policy handoff")
        experiment_id = ("dll_" + base_sha[:12] + "_" + cand_sha[:12] + "_" +
                         datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S"))
        root = STATE / "experiments"
        root.mkdir(parents=True, exist_ok=True, mode=0o700)
        manifest = root / (experiment_id + ".json")
        output = root / (experiment_id + "-decision.json")
        doc = {
            "schema_version": 1, "experiment_id": experiment_id,
            "hypothesis": "The explicitly approved candidate source revision reduces "
                          "windowed DirectDraw present latency relative to the base DLL.",
            "controlled_scene": "menu_boot_autotest_v1", "pairs": recorded,
        }
        with manifest.open("x", encoding="utf-8") as handle:
            json.dump(doc, handle, indent=2, sort_keys=True)
            handle.write("\n")
        command = [str(PYTHON), str(CONTROLLER), "--manifest", str(manifest),
                   "--runs-dir", str(RESULTS), "--ledger",
                   str(STATE / "research-controller.json"),
                   "--output", str(output), "--commit"]
        environment = {k: v for k, v in os.environ.items() if
                       not k.startswith("OPENAI_") and k not in (
                           "GH_TOKEN", "GITHUB_TOKEN", "GIT_ASKPASS", "SSH_ASKPASS")}
        result = run(command, env=environment, timeout=90, check=False)
        if result.returncode != 0 or not output.is_file():
            raise RuntimeError("Evidence controller rejected experiment; preserve all runs")
        classification = json.loads(output.read_text(encoding="utf-8"))
        if classification.get("manifest_verified") is not True or (
                classification.get("may_install_or_run_candidate") is not False):
            raise RuntimeError("Policy output failed closed")
        completed_safely = True
        return {
            "experiment_id": experiment_id, "manifest": str(manifest),
            "classification": classification.get("disposition"),
            "next_step": classification.get("next_step"),
            "pairs": len(recorded), "game_changes_promoted": False,
        }
    finally:
        # The trusted supervisor exits only after verifying isolated game
        # shutdown and restores that game's original DLL. Downloads is separate.
        if staged:
            if originally_present and BACKUP.is_file():
                os.replace(BACKUP, DOWNLOAD_DLL)
            elif not originally_present and DOWNLOAD_DLL.exists():
                DOWNLOAD_DLL.unlink()
            if TEMP.exists():
                TEMP.unlink()
        if completed_safely:
            LOCK.rmdir()
        else:
            # A failed test may leave a Wine process running; keep the lock so
            # no second experiment starts until a human inspects the TEST app.
            print("SAFETY HOLD: paired-eval.lock retained; inspect the TEST app", file=sys.stderr)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-sha", required=True)
    parser.add_argument("--candidate-sha", required=True)
    parser.add_argument("--candidate-run-id", required=True)
    parser.add_argument("--pairs", type=int, default=1)
    parser.add_argument("--seconds", type=int, default=60)
    parser.add_argument("--run", action="store_true",
                        help="Explicitly execute the two reviewed DLLs in TEST app")
    args = parser.parse_args(argv)
    if not args.run:
        info = preflight(args.baseline_sha, args.candidate_sha,
                         args.candidate_run_id, args.pairs, args.seconds)
        print(json.dumps(info, indent=2, sort_keys=True))
        print("DRY RUN ONLY. No game executed.")
        return 0
    print(json.dumps(execute(args.baseline_sha, args.candidate_sha,
                             args.candidate_run_id, args.pairs, args.seconds),
                     indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError,
            subprocess.SubprocessError) as exc:
        print("PAIRED TEST STOP:", exc, file=sys.stderr)
        raise SystemExit(2)
