#!/usr/bin/env python3
"""Finite, opt-in local OpenLRR diagnostic worker (NO AI candidate execution).

This is a safely bounded first unattended Mac execution stage. It only repeats
one *specific, previously reviewed* diagnostic build in the isolated TEST app.
Enrollment is explicit and does not launch the game. No model decides commands.
Automatic AI-authored DLL execution remains blocked until real VM containment.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

HOME = Path.home()
ROOT = HOME / "OpenLRR-Agent"
CONFIG = HOME / ".config/openlrr-benchmark"
STATE = HOME / ".local/share/openlrr-agent"
APP = HOME / "Applications/Sikarugir/OpenLRR Menu Test.app"
ENROLLMENT = CONFIG / "approved-diagnostic-worker.json"
RUN_LOCK = STATE / "approved-diagnostic-worker.lock"
HISTORY = STATE / "approved-diagnostic-worker-history.json"
VENV = STATE / "venv/bin/python"
SCRIPT = ROOT / "scripts/macos/diagnostic-one-shot.sh"
TRUSTED_FILES = (
    "scripts/macos/approved-diagnostic-worker.py",
    "scripts/macos/diagnostic-one-shot.sh",
    "scripts/macos/lab-supervisor.py",
    "scripts/macos/run-autobenchmark.sh",
    "scripts/macos/publish-benchmark.sh",
    "scripts/macos/analyze-benchmark.py",
)
APPROVED_RUN = "39184097578"
APPROVED_REVISION = "c3f8d2a81661a7626be0e8628d90c54898688c43"
APPROVED_DLL_SHA = "1179323074e03caf22f89ecbf05b9234f8ef5e18f2c1d6b8d797c2cf31c5b4ff"
MAX_ATTEMPTS = 2
MAX_SECONDS = 1500
ENROLL_HOURS = 168  # one week; no indefinite game launches
ENABLE_SCHEMA = 1


def checksum(file: Path) -> str:
    if file.is_symlink() or not file.is_file() or file.stat().st_size > 2_000_000:
        raise RuntimeError("Trusted worker file is missing, symlinked or oversized")
    return hashlib.sha256(file.read_bytes()).hexdigest()


def current_source() -> dict:
    if ROOT.is_symlink() or not ROOT.is_dir():
        raise RuntimeError("Dedicated OpenLRR lab checkout missing")
    # Exact revision binding: user enrollment pins all executable local
    # scripts; code cannot self-update in an unattended launch.
    result = subprocess.run(
        ["git", "-C", str(ROOT), "rev-parse", "--verify", "HEAD"],
        capture_output=True, text=True, check=False, timeout=15)
    if result.returncode or not re.fullmatch("[0-9a-f]{40}", result.stdout.strip()):
        raise RuntimeError("Cannot determine trusted checkout revision")
    commit = result.stdout.strip()
    status = subprocess.run(
        ["git", "-C", str(ROOT), "status", "--porcelain", "--untracked-files=no"],
        capture_output=True, text=True, check=False, timeout=15)
    if status.returncode or status.stdout.strip():
        raise RuntimeError("Lab checkout has unreviewed local changes")
    files = {relative: checksum(ROOT / relative) for relative in TRUSTED_FILES}
    return {"checkout_sha": commit, "file_sha256": files}


def switches() -> None:
    for flag in ("STOP", "PAUSE", "supervisor.lock"):
        if (CONFIG / flag).exists():
            raise RuntimeError("STOP/PAUSE or supervisor lock prevents unattended tests")
    for flag in ("paired-eval.lock", "candidate-test.lock"):
        if (STATE / flag).exists():
            raise RuntimeError("Another lab experiment is active")
    if RUN_LOCK.exists():
        raise RuntimeError("Unresolved worker lock; manual inspection required")


def preflight() -> dict:
    switches()
    if APP.is_symlink() or not APP.is_dir():
        raise RuntimeError("Dedicated OpenLRR Menu Test.app not installed")
    isolated = (APP / "Contents/SharedSupport/prefix/drive_c/Program Files/Rock Raiders OpenLRR")
    if (isolated.is_symlink() or not (isolated / "LegoRR.exe").is_file()
            or not (isolated / "openlrr.dll").is_file()):
        raise RuntimeError("Expected TEST game binary layout missing")
    if not isolated.resolve().is_relative_to(APP.resolve()):
        raise RuntimeError("TEST game folder escapes isolated application")
    if VENV.is_symlink() or not VENV.is_file():
        raise RuntimeError("Dedicated Python interpreter unavailable")
    if not SCRIPT.is_file():
        raise RuntimeError("Pinned diagnostic runner unavailable")
    for cmd in ("gh", "shasum", "lsof"):
        check = subprocess.run(
            ["/bin/sh", "-c", "command -v " + cmd],
            capture_output=True, text=True, timeout=10, check=False)
        if check.returncode:
            raise RuntimeError("Missing required command: " + cmd)
    return current_source()


def read_json(path: Path, maximum: int = 12000) -> dict:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > maximum:
        raise RuntimeError("State file missing, symlinked or oversized")
    data = json.loads(path.read_text(encoding="utf-8"))
    if type(data) is not dict:
        raise ValueError("Invalid worker state object")
    return data


def write_new(path: Path, data: dict) -> None:
    if path.exists() or path.is_symlink() or path.parent.is_symlink():
        raise RuntimeError("State file exists or is an unsafe symlink")
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    blob = json.dumps(data, indent=2, sort_keys=True) + "\n"
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600),
                   "w", encoding="utf-8") as stream:
        stream.write(blob)
        stream.flush()
        os.fsync(stream.fileno())


def enroll(*, now: datetime | None = None) -> dict:
    if ENROLLMENT.exists() or ENROLLMENT.is_symlink():
        raise RuntimeError("Existing worker enrollment cannot be overwritten")
    if HISTORY.exists() or HISTORY.is_symlink():
        raise RuntimeError("Existing run history requires review before re-enrollment")
    source = preflight()
    when = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    record = {
        "schema_version": ENABLE_SCHEMA,
        "kind": "user_enabled_known_diagnostic_only",
        "approved_run_id": APPROVED_RUN,
        "approved_source_revision": APPROVED_REVISION,
        "approved_dll_sha256": APPROVED_DLL_SHA,
        "allowed_max_attempts": MAX_ATTEMPTS,
        "user_enrolled_utc": when.isoformat(),
        "expires_utc": (when + timedelta(hours=ENROLL_HOURS)).isoformat(),
        "working_game_writes_allowed": False,
        "ai_generated_candidate_execution_allowed": False,
        "automatic_dll_replacement_allowed": False,
        **source,
    }
    write_new(ENROLLMENT, record)
    return {
        "enrolled": True, "expires_utc": record["expires_utc"],
        "max_unattended_diagnostic_attempts": MAX_ATTEMPTS,
        "automatic_ai_candidate_execution": False,
        "game_launched": False,
    }


def validate_enrollment(*, now: datetime | None = None) -> dict:
    record = read_json(ENROLLMENT)
    required = {
        "schema_version", "kind", "approved_run_id",
        "approved_source_revision", "approved_dll_sha256",
        "allowed_max_attempts", "user_enrolled_utc", "expires_utc",
        "working_game_writes_allowed", "ai_generated_candidate_execution_allowed",
        "automatic_dll_replacement_allowed", "checkout_sha", "file_sha256",
    }
    if set(record) != required or record["schema_version"] != ENABLE_SCHEMA:
        raise ValueError("Unexpected unattended authorization schema")
    if (record["kind"] != "user_enabled_known_diagnostic_only"
            or record["approved_run_id"] != APPROVED_RUN
            or record["approved_source_revision"] != APPROVED_REVISION
            or record["approved_dll_sha256"] != APPROVED_DLL_SHA
            or type(record["allowed_max_attempts"]) is not int
            or record["allowed_max_attempts"] != MAX_ATTEMPTS
            or record["working_game_writes_allowed"] is not False
            or record["ai_generated_candidate_execution_allowed"] is not False
            or record["automatic_dll_replacement_allowed"] is not False):
        raise ValueError("Unattended worker authority exceeds reviewed diagnostic")
    now = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    try:
        issued = datetime.fromisoformat(record["user_enrolled_utc"])
        expiry = datetime.fromisoformat(record["expires_utc"])
        if issued.tzinfo is None or expiry.tzinfo is None:
            raise ValueError("Untrusted timestamp")
        issued, expiry = issued.astimezone(timezone.utc), expiry.astimezone(timezone.utc)
    except (TypeError, ValueError) as exc:
        raise ValueError("Invalid approval lifetime") from exc
    if expiry - issued != timedelta(hours=ENROLL_HOURS) or now < issued or now >= expiry:
        raise ValueError("Unattended user approval expired or not yet valid")
    source = preflight()
    if record["checkout_sha"] != source["checkout_sha"] or record["file_sha256"] != source["file_sha256"]:
        raise RuntimeError("Trusted lab code changed since user enrollment")
    return record


def history() -> dict:
    if not HISTORY.exists():
        return {"schema_version": 1, "attempts": []}
    data = read_json(HISTORY)
    if set(data) != {"schema_version", "attempts"} or data["schema_version"] != 1:
        raise ValueError("Unexpected worker history")
    attempts = data["attempts"]
    if type(attempts) is not list or len(attempts) > MAX_ATTEMPTS:
        raise ValueError("Invalid worker history length")
    for e in attempts:
        if type(e) is not dict or set(e) != {"utc_day", "status"}:
            raise ValueError("Invalid worker history event")
        if not isinstance(e["utc_day"], str) or not re.fullmatch(r"\d{4}-\d\d-\d\d", e["utc_day"]):
            raise ValueError("Invalid history day")
        if e["status"] not in ("claimed", "success", "error"):
            raise ValueError("Unrecognized worker outcome")
    return data


def replace_history(data: dict) -> None:
    if HISTORY.is_symlink() or HISTORY.parent.is_symlink():
        raise RuntimeError("Unsafe worker state symlink")
    HISTORY.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if HISTORY.exists() and not HISTORY.is_file():
        raise RuntimeError("Invalid existing worker history")
    temporary = HISTORY.with_name(HISTORY.name + "." + str(os.getpid()) + ".tmp")
    write_new(temporary, data)
    os.replace(temporary, HISTORY)


def work(*, execute: bool = False, now: datetime | None = None) -> dict:
    now = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    authorization = validate_enrollment(now=now)
    past = history()
    day = now.date().isoformat()
    if len(past["attempts"]) >= MAX_ATTEMPTS:
        return {"decision": "maximum_attempts_reached", "ran_game": False}
    if any(a["utc_day"] == day for a in past["attempts"]):
        return {"decision": "already_attempted_today", "ran_game": False}
    if not execute:
        return {
            "decision": "approved_diagnostic_available",
            "run_id": authorization["approved_run_id"],
            "will_launch": False,
            "ai_generated_candidate_execution_allowed": False,
        }
    if RUN_LOCK.exists() or RUN_LOCK.is_symlink():
        raise RuntimeError("Concurrent/stale unattended worker lock")
    RUN_LOCK.mkdir(parents=True, mode=0o700)
    new_event = {"utc_day": day, "status": "claimed"}
    # Record the claim *before* launching Wine: a crash cannot cause a blind
    # automatic retry. Any failure retains a lock requiring human inspection.
    attempted = False
    try:
        switches() if False else None  # locked by this worker; no reentrant preflight
        replace_history({"schema_version": 1, "attempts": [*past["attempts"], new_event]})
        attempted = True
        env = {k: v for k, v in os.environ.items()
               if not k.startswith("OPENAI_") and k not in (
                   "GH_TOKEN", "GITHUB_TOKEN", "GIT_ASKPASS", "SSH_ASKPASS")}
        command = ["/bin/bash", str(SCRIPT), APPROVED_RUN, APPROVED_REVISION]
        completed = subprocess.run(
            command, env=env, timeout=MAX_SECONDS, check=False,
        )
        if completed.returncode:
            raise RuntimeError("Reviewed TEST-only diagnostic did not finish cleanly")
        if (CONFIG / "STOP").exists() or (CONFIG / "PAUSE").exists():
            raise RuntimeError("STOP/PAUSE after game; do not approve result")
        new_event["status"] = "success"
        replace_history({"schema_version": 1, "attempts": [
            *past["attempts"], new_event
        ]})
        RUN_LOCK.rmdir()
        return {"decision": "completed_verified_diagnostic",
                "ran_game": True, "ai_candidates_executed": False}
    except BaseException:
        # The original 'claimed' record is retained if a failure occurs.
        # No automatic retry. Keep lock until TEST Wine process is inspected.
        if attempted:
            print("WORKER SAFETY HOLD: inspect TEST app; lock retained", file=sys.stderr)
        raise


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument("--enroll-known-diagnostic", action="store_true",
                         help="Explicit one-time owner opt-in, DOES NOT RUN the game")
    actions.add_argument("--run", action="store_true",
                         help="Run one pre-approved diagnostic when within owner limits")
    args = parser.parse_args(argv)
    if args.enroll_known_diagnostic:
        result = enroll()
    else:
        result = work(execute=args.run)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, ValueError, TypeError,
            json.JSONDecodeError, subprocess.SubprocessError) as exc:
        print("APPROVED DIAGNOSTIC WORKER REFUSED:", exc, file=sys.stderr)
        raise SystemExit(2)
