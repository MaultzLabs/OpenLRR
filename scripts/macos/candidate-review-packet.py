#!/usr/bin/env python3
"""Generate an inert, independently validated DLL review packet from quarantine.

No AI calls, no GitHub access, no game launch, no executable approval.
The packet binds the immutable cloud revision, candidate DLL digest and
source patch digest, reports approved baseline readiness and Wine host risks.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys

HOME = Path.home()
INBOX = HOME / ".local/share/openlrr-agent/candidate-inbox"
BASELINE = HOME / ".local/share/openlrr-agent/approved-baselines/openlrr.dll"
CONFIG = HOME / ".config/openlrr-benchmark"
TEST_APP = HOME / "Applications/Sikarugir/OpenLRR Menu Test.app"
SOURCE_DIR = Path(__file__).resolve().parent
COMMIT_RE = re.compile(r"^[a-f0-9]{40}$")
RUN_RE = re.compile(r"^[0-9]{8,14}$")
SHA_RE = re.compile(r"^[a-f0-9]{64}$")


def load_module(name: str, filename: str):
    source = SOURCE_DIR / filename
    spec = importlib.util.spec_from_file_location(name, source)
    if spec is None or spec.loader is None:
        raise RuntimeError("Trusted local lab helper missing: " + filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_small_json(path: Path) -> dict:
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= 8192:
        raise ValueError("Missing or unsafe reviewed candidate metadata")
    result = json.loads(path.read_text(encoding="utf-8"))
    if type(result) is not dict:
        raise ValueError("Unexpected review metadata type")
    return result


def sha256(path: Path) -> str:
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= 10_000_000:
        raise ValueError("Unsafe candidate evidence file")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def baseline_status() -> tuple[str, str | None]:
    provenance = BASELINE.parent / "provenance.json"
    if not BASELINE.exists() and not provenance.exists():
        return ("not_prepared", None)
    if BASELINE.is_symlink() or not BASELINE.is_file() or not provenance.is_file():
        raise ValueError("Incomplete or unsafe approved baseline")
    data = read_small_json(provenance)
    identity = data.get("dll_sha256")
    if (type(identity) is not str or not SHA_RE.fullmatch(identity)
            or data.get("reviewed_source_workflow") != "OpenLRR Menu Diagnostics Win32"
            or data.get("approved_for_automatic_execution") is not False
            or data.get("tested_in_game") is not False):
        raise ValueError("Baseline provenance is not from approved lab workflow")
    if sha256(BASELINE) != identity:
        raise ValueError("Approved baseline DLL digest changed")
    return ("prepared_review_required", identity)


def review(run_id: str) -> dict:
    if type(run_id) is not str or not RUN_RE.fullmatch(run_id):
        raise ValueError("Invalid compiled candidate run identifier")
    if (CONFIG / "STOP").exists() or (CONFIG / "PAUSE").exists():
        raise RuntimeError("STOP/PAUSE active; review queue frozen")
    root = INBOX / ("run-" + run_id)
    if root.is_symlink() or not root.is_dir() or root.resolve().parent != INBOX.resolve():
        raise ValueError("Candidate not in fixed private quarantine")
    quarantine = load_module("openlrr_candidate_review_inbox", "candidate-inbox.py")
    verified = quarantine.validate_bundle(root)
    provenance = read_small_json(root / "provenance.json")
    commit = provenance.get("cloud_revision")
    if (provenance.get("run_id") != run_id
            or provenance.get("candidate_sha256") != verified["candidate_sha256"]
            or provenance.get("automatic_execution") is not False
            or provenance.get("review_required") is not True
            or provenance.get("workflow") not in quarantine.WORKFLOWS
            or type(commit) is not str or not COMMIT_RE.fullmatch(commit)):
        raise ValueError("Candidate's immutable cloud provenance disagrees")
    patch_sha = sha256(root / "proposal.patch")
    base_state, baseline_sha = baseline_status()
    if baseline_sha == verified["candidate_sha256"]:
        raise ValueError("Candidate is identical to baseline; no source intervention")

    mapping_status = "unavailable"
    mapping_risks = []
    if TEST_APP.exists():
        safety = load_module("openlrr_candidate_review_wine_audit", "wine-isolation-audit.py")
        try:
            mapping = safety.inspect(TEST_APP)
        except (OSError, ValueError, RuntimeError):
            mapping_status = "unverifiable"
            mapping_risks = ["Wine TEST prefix cannot be independently audited"]
        else:
            mapping_status = (
                "no_external_symlinks_observed"
                if mapping["wine_drive_link_audit_complete"]
                else "unsafe_or_incomplete"
            )
            mapping_risks = mapping["issues"]
    packet_id = hashlib.sha256(
        (run_id + ":" + commit + ":" + verified["candidate_sha256"]
         + ":" + patch_sha).encode("ascii")
    ).hexdigest()
    return {
        "schema_version": 1,
        "review_packet_id": "dll_review_" + packet_id[:24],
        "cloud_run_id": run_id,
        "source_revision": commit,
        "source_workflow": provenance["workflow"],
        "candidate_sha256": verified["candidate_sha256"],
        "source_patch_sha256": patch_sha,
        "baseline_state": base_state,
        "baseline_sha256": baseline_sha,
        "wine_mapping_status": mapping_status,
        "wine_mapping_risks": mapping_risks[:32],
        "test_environment": "OpenLRR Menu Test.app only",
        "human_review_required": True,
        "strong_host_sandbox_attestation_available": False,
        "automatic_candidate_execution_allowed": False,
        "may_modify_working_game": False,
        "game_launched": False,
        "external_requests_made": False,
    }


def write_once(path: Path, packet: dict) -> None:
    if path.exists() or path.is_symlink():
        raise ValueError("Existing review packet cannot be replaced")
    if any(p.is_symlink() for p in (path.absolute(), *path.absolute().parents)):
        raise ValueError("Review packet path traverses a symlink")
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_EXCL | os.O_CREAT, 0o600),
                   "w", encoding="utf-8") as handle:
        handle.write(json.dumps(packet, indent=2, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--out", type=Path,
                        help="Optional new local JSON file for human review; no network")
    args = parser.parse_args(argv)
    data = review(args.run_id)
    if args.out:
        write_once(args.out, data)
    print(json.dumps(data, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, TypeError, json.JSONDecodeError) as exc:
        print("CANDIDATE REVIEW PACKET STOPPED:", exc, file=sys.stderr)
        raise SystemExit(2)
