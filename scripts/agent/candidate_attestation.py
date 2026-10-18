#!/usr/bin/env python3
"""Produce an immutable-source-scope provenance claim for a cloud-built DLL.

The CI workflow supplies its actual checkout SHA and its triggering run SHA.
No executable is ever launched. Claims are corroborating metadata, not a
cryptographic signature or permission to run AI-authored native code.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

SHA40 = re.compile(r"^[0-9a-f]{40}$")
RUN_ID = re.compile(r"^[0-9]{8,14}$")
SOURCE = "src/openlrr/engine/drawing/DirectDraw.cpp"


def fingerprint(path: Path, max_bytes: int) -> str:
    if path.is_symlink() or not path.is_file() or not 1 <= path.stat().st_size <= max_bytes:
        raise ValueError("Invalid or oversized build input")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(proposal: Path, patch: Path, dll: Path, source: Path,
          source_revision: str, workflow_head: str, run_id: str) -> dict:
    if not SHA40.fullmatch(source_revision) or not SHA40.fullmatch(workflow_head):
        raise ValueError("Build requires two complete GitHub source identities")
    if not RUN_ID.fullmatch(run_id):
        raise ValueError("Invalid GitHub workflow run identity")
    manifest = json.loads(proposal.read_text(encoding="utf-8"))
    if (manifest.get("status") != "patch_ready" or
        manifest.get("review_required") is not True or
        manifest.get("host_execution_authorized") is not False or
        manifest.get("source_file") != SOURCE):
        raise ValueError("Cannot attest an unreviewed or out-of-scope proposal")
    patch_bytes = patch.read_text(encoding="utf-8")
    if not patch_bytes.startswith("--- a/" + SOURCE + "\n+++ b/" + SOURCE + "\n"):
        raise ValueError("Patch escaped approved graphics source")
    if patch_bytes.count("\n--- ") or patch_bytes.count("\n+++ ") != 1:
        raise ValueError("Patch modifies multiple files")
    return {
        "schema_version": 1,
        "workflow": "OpenLRR AI Graphics Proposal (review only)",
        "workflow_head_sha": workflow_head,
        "workflow_run_id": run_id,
        "compiled_source_revision": source_revision,
        "source_file": SOURCE,
        "patched_source_file_sha256": fingerprint(source, 2_000_000),
        "proposal_patch_sha256": fingerprint(patch, 200_000),
        "compiled_dll_sha256": fingerprint(dll, 10_000_000),
        "is_windows_x86": True,
        "human_source_review_required": True,
        "automatic_host_execution": False,
        "automatic_deployment": False,
    }


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--proposal", type=Path, required=True)
    p.add_argument("--patch", type=Path, required=True)
    p.add_argument("--dll", type=Path, required=True)
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--source-revision", required=True)
    p.add_argument("--workflow-head", required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--out", type=Path, required=True)
    args = p.parse_args(argv)
    data = build(args.proposal, args.patch, args.dll, args.source,
                 args.source_revision, args.workflow_head, args.run_id)
    if args.out.exists():
        raise ValueError("Attestation cannot overwrite an existing file")
    args.out.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n",
                        encoding="utf-8")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print("BUILD ATTESTATION REFUSED:", exc, file=sys.stderr)
        raise SystemExit(2)
