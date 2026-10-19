#!/usr/bin/env python3
"""Stage a cloud-compiled OpenLRR candidate into QUARANTINE; never run it.

Mac worker precursor: verifies GitHub run, known artifact name, x86 PE,
patch scope and SHA256. It never touches the game, Downloads, or Wine.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

REPO = "MaultzLabs/OpenLRR"
CONFIG = Path.home() / ".config/openlrr-benchmark"
INBOX = Path.home() / ".local/share/openlrr-agent/candidate-inbox"
ARTIFACTS = (
    "OpenLRR-Evidence-Candidate-REVIEW-REQUIRED",
    "OpenLRR-AI-Compiled-Draft-REVIEW-REQUIRED",
)
WORKFLOWS = (
    "OpenLRR Evidence-Grounded AI Smoke Test",
    "OpenLRR AI Graphics Proposal (review only)",
)
ALLOWED = {"openlrr.dll", "SHA256.txt", "proposal.patch",
           "proposal.json", "REVIEW-REQUIRED.txt"}
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
RUN_RE = re.compile(r"^[0-9]{8,14}$")


def gh(*args: str) -> str:
    proc = subprocess.run(["gh", *args], capture_output=True,
                          text=True, timeout=90, check=False)
    if proc.returncode:
        raise RuntimeError("GitHub read/download failed; no candidate was installed")
    return proc.stdout


def run_metadata(run_id: str) -> dict:
    if not RUN_RE.fullmatch(run_id):
        raise ValueError("Invalid cloud run ID")
    data = json.loads(gh("run", "view", run_id, "--repo", REPO,
                         "--json", "conclusion,status,headBranch,headSha,workflowName"))
    if data.get("conclusion") != "success" or data.get("status") != "completed":
        raise ValueError("Cloud workflow not successful")
    if data.get("workflowName") not in WORKFLOWS:
        raise ValueError("Unexpected workflow")
    if data.get("headBranch") not in ("main", "agent-loop-v1", "lab-evidence-planner-v1"):
        raise ValueError("Unapproved build branch")
    if not re.fullmatch(r"[a-f0-9]{40}", str(data.get("headSha", ""))):
        raise ValueError("Missing source revision")
    return data


def validate_bundle(root: Path) -> dict:
    root = root.resolve()
    files = list(root.iterdir())
    names = {p.name for p in files}
    # Raw GitHub artifact has exactly ALLOWED files. Once quarantined, our
    # staging process adds only a provenance.json sidecar; accept that single
    # trusted layout too, but never ignore arbitrary extra files.
    if names != ALLOWED and names != ALLOWED | {"provenance.json"}:
        raise ValueError("Artifact is missing required files or contains unexpected files")
    if any(p.is_symlink() or not p.is_file() or p.parent.resolve() != root
           or p.stat().st_size > 10_000_000 for p in files):
        raise ValueError("Unsafe candidate artifact")
    manifest = json.loads((root / "proposal.json").read_text(encoding="utf-8"))
    if manifest.get("status") != "patch_ready" or manifest.get("review_required") is not True:
        raise ValueError("Candidate not classified as review-required")
    if manifest.get("host_execution_authorized") is not False:
        raise ValueError("Unexpected authority to execute candidate")
    if manifest.get("source_file") != "src/openlrr/engine/drawing/DirectDraw.cpp":
        raise ValueError("Candidate exceeded source scope")
    patch = (root / "proposal.patch").read_text(encoding="utf-8")
    if not patch.startswith("--- a/src/openlrr/engine/drawing/DirectDraw.cpp\n"
                            "+++ b/src/openlrr/engine/drawing/DirectDraw.cpp\n"):
        raise ValueError("Unexpected patch scope")
    # One newline-prefixed +++ header is expected (the second line of a
    # unified diff). Any newline-prefixed --- or extra +++ signals another file.
    if patch.count("\n--- ") or patch.count("\n+++ ") != 1:
        raise ValueError("Multiple patch files disallowed")
    expected = (root / "SHA256.txt").read_text(encoding="utf-8").strip().lower()
    if not SHA_RE.fullmatch(expected):
        raise ValueError("Malformed artifact SHA256")
    path = root / "openlrr.dll"
    h = hashlib.sha256(path.read_bytes()).hexdigest()
    if h != expected:
        raise ValueError("Compiled candidate SHA256 mismatch")
    with path.open("rb") as handle:
        header = handle.read(4096)
    if len(header) < 256 or header[:2] != b"MZ":
        raise ValueError("Missing Windows PE header")
    offset = int.from_bytes(header[0x3c:0x40], "little")
    if offset + 6 > len(header) or header[offset:offset + 4] != b"PE\0\0":
        raise ValueError("Corrupted Windows PE header")
    if int.from_bytes(header[offset + 4:offset + 6], "little") != 0x14c:
        raise ValueError("Expected x86, not x64 or ARM")
    return {"candidate_sha256": h, "source_file": manifest["source_file"],
            "review_required": True, "automatic_execution": False}


def stage(run_id: str) -> dict:
    if (CONFIG / "STOP").exists() or (CONFIG / "PAUSE").exists():
        raise RuntimeError("STOP/PAUSE active; candidate not retrieved")
    run = run_metadata(run_id)
    INBOX.mkdir(parents=True, exist_ok=True, mode=0o700)
    target = INBOX / ("run-" + run_id)
    if target.exists():
        raise ValueError("Already quarantined; refusing replacement")
    with tempfile.TemporaryDirectory(prefix="openlrr-quarantine-") as tmp:
        temp = Path(tmp)
        success = False
        for artifact in ARTIFACTS:
            try:
                gh("run", "download", run_id, "--repo", REPO, "--name",
                   artifact, "--dir", str(temp))
                success = True
                break
            except RuntimeError:
                if list(temp.iterdir()):
                    raise ValueError("Partial download; refusing fallback")
        if not success:
            raise ValueError("No compiled candidate artifact; AI may have abstained")
        verified = validate_bundle(temp)
        if (CONFIG / "STOP").exists() or (CONFIG / "PAUSE").exists():
            raise RuntimeError("STOP/PAUSE active before quarantine write")
        staging = INBOX / (".run-" + run_id + "-pending")
        if staging.exists():
            raise ValueError("Stale staging directory; fail closed")
        try:
            staging.mkdir(mode=0o700)
            for file in temp.iterdir():
                shutil.copyfile(file, staging / file.name)
            (staging / "provenance.json").write_text(
                json.dumps({"run_id": run_id, "cloud_revision": run["headSha"],
                            "workflow": run["workflowName"], **verified},
                           indent=2) + "\n", encoding="utf-8")
            for path in staging.iterdir():
                path.chmod(0o600)
            staging.rename(target)
        finally:
            if staging.exists():
                shutil.rmtree(staging)
    return {"quarantined": str(target), **verified}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_id")
    args = parser.parse_args()
    print(json.dumps(stage(args.run_id), sort_keys=True, indent=2))
    print("REVIEW REQUIRED: no candidate has been installed or executed")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError,
            json.JSONDecodeError) as exc:
        print("QUARANTINE STOP:", exc, file=sys.stderr)
        raise SystemExit(2)
