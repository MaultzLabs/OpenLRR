#!/usr/bin/env python3
"""Download and approve one provenance-pinned baseline x86 DLL (NO EXECUTION).

Baseline approval is a distinct action from approval of a candidate. No Wine,
game, model or shell script from the artifact is ever executed by this tool.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path.home() / ".local/share/openlrr-agent/approved-baselines"
CONFIG = Path.home() / ".config/openlrr-benchmark"
LOCK = ROOT / ".baseline-install.lock"
REPO = "MaultzLabs/OpenLRR"
RUN_RE = re.compile(r"^[0-9]{8,14}$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
ARTIFACT = "OpenLRR-menu-diagnostics-x86"
PERMITTED = {
    "openlrr.dll", "SHA256.txt", "BUILD-AND-TEST.md",
    "run-autobenchmark.sh", "publish-benchmark.sh",
    "analyze-benchmark.py", "autobenchmark.md",
}


def gh(*args: str) -> str:
    process = subprocess.run(["gh", *args], capture_output=True, text=True,
                             timeout=120, check=False)
    if process.returncode:
        raise RuntimeError("GitHub baseline verification/download failed")
    if len(process.stdout) > 2_000_000:
        raise RuntimeError("GitHub result too large")
    return process.stdout


def metadata(run_id: str, commit: str) -> dict:
    if not RUN_RE.fullmatch(run_id) or not COMMIT_RE.fullmatch(commit):
        raise ValueError("Invalid reviewed workflow identity")
    data = json.loads(gh("run", "view", run_id, "--repo", REPO,
                         "--json", "conclusion,status,headSha,headBranch,workflowName"))
    if (data.get("conclusion") != "success" or data.get("status") != "completed"
            or data.get("headSha") != commit
            or data.get("headBranch") != "agent-loop-v1"
            or data.get("workflowName") != "OpenLRR Menu Diagnostics Win32"):
        raise ValueError("Untrusted baseline workflow, branch or source commit")
    return data


def verify_bundle(folder: Path, expected: str):
    if not SHA_RE.fullmatch(expected):
        raise ValueError("Missing approved baseline SHA256")
    files = list(folder.iterdir())
    if not {"openlrr.dll", "SHA256.txt"}.issubset({p.name for p in files}):
        raise ValueError("Incomplete baseline artifact")
    if any(p.name not in PERMITTED or p.is_symlink() or not p.is_file()
           or p.stat().st_size > 10_000_000 for p in files):
        raise ValueError("Unapproved or unsafe baseline artifact entry")
    published = (folder / "SHA256.txt").read_text(encoding="utf-8").strip().lower()
    if published != expected:
        raise ValueError("Published DLL hash differs from human approval")
    file = folder / "openlrr.dll"
    # Avoid trusting the hash string without checking the file and PE header.
    h = hashlib.sha256(file.read_bytes()).hexdigest()
    if h != expected:
        raise ValueError("Baseline DLL digest mismatch")
    with file.open("rb") as handle:
        pe = handle.read(4096)
    if len(pe) < 256 or pe[:2] != b"MZ":
        raise ValueError("Missing Windows DOS header")
    offset = int.from_bytes(pe[0x3c:0x40], "little")
    if offset + 6 >= len(pe) or pe[offset:offset + 4] != b"PE\0\0":
        raise ValueError("Missing Windows PE signature")
    if int.from_bytes(pe[offset + 4:offset + 6], "little") != 0x14c:
        raise ValueError("Baseline DLL is not Windows x86")
    return file


def prepare(run_id: str, commit: str, sha: str, *, dry_run=True):
    if (CONFIG / "STOP").exists() or (CONFIG / "PAUSE").exists():
        raise RuntimeError("STOP/PAUSE active")
    approved = metadata(run_id, commit)
    final = ROOT / "openlrr.dll"
    if ROOT.is_symlink() or final.exists() or final.is_symlink() or LOCK.exists():
        raise RuntimeError("A baseline or install lock exists; refusing replacement")
    if not SHA_RE.fullmatch(sha):
        raise ValueError("Full lowercase SHA256 approval required")
    if dry_run:
        return {"cloud_run_id": run_id, "commit": approved["headSha"],
                "approved_sha256": sha, "downloaded": False, "game_launched": False}
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    LOCK.mkdir(mode=0o700)
    completed = False
    try:
        with tempfile.TemporaryDirectory(prefix="openlrr-baseline-") as work:
            dest = Path(work)
            gh("run", "download", run_id, "--repo", REPO, "--name",
               ARTIFACT, "--dir", str(dest))
            file = verify_bundle(dest, sha)
            if (CONFIG / "STOP").exists() or (CONFIG / "PAUSE").exists():
                raise RuntimeError("STOP/PAUSE before approval")
            staged = ROOT / ".baseline.pending"
            if staged.exists() or staged.is_symlink():
                raise RuntimeError("Baseline staging file already exists")
            try:
                shutil.copyfile(file, staged)
                if hashlib.sha256(staged.read_bytes()).hexdigest() != sha:
                    raise RuntimeError("Staged baseline changed")
                os.link(staged, final)  # atomic create; will NOT overwrite
            finally:
                if staged.exists():
                    staged.unlink()
            (ROOT / "provenance.json").write_text(json.dumps({
                "source_run": run_id, "head_sha": commit, "dll_sha256": sha,
                "reviewed_source_workflow": "OpenLRR Menu Diagnostics Win32",
                "approved_for_automatic_execution": False,
                "tested_in_game": False,
            }, indent=2) + "\n", encoding="utf-8")
        completed = True
    finally:
        if completed:
            LOCK.rmdir()
        else:
            print("BASELINE APPROVAL STOPPED: inspect install directory", file=sys.stderr)
    return {"stored": str(final), "approved_sha256": sha,
            "game_launched": False, "candidate_executed": False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--prepare", action="store_true")
    args = parser.parse_args(argv)
    print(json.dumps(prepare(args.run_id, args.commit, args.sha256,
                             dry_run=not args.prepare), indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, OSError, json.JSONDecodeError,
            subprocess.SubprocessError) as exc:
        print("BASELINE PREPARATION REFUSED:", exc, file=sys.stderr)
        raise SystemExit(2)
