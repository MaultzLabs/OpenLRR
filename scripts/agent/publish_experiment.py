#!/usr/bin/env python3
"""Publish a fully verified paired experiment to the PRIVATE results repository.

Default is dry-run. Requires every individual run summary, CSV, and Mac
process-exit receipt to ALREADY exist remotely and match local Git blob hashes.
No generated code, credentials, DLLs, game assets, or screenshots are uploaded.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

import remote_evidence_gate

REPO = "MaultzLabs/OpenLRR-Test-Results"
EXP_ID = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_-]{2,63}$")
RUN_NAME = re.compile(r"^autobenchmark-\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d$")
SHA = re.compile(r"^[0-9a-f]{40}$")


def gh(*args: str, input_file: Path | None = None) -> str:
    argv = ["gh", *args]
    if input_file is not None:
        argv.extend(["--input", str(input_file)])
    proc = subprocess.run(argv, capture_output=True, text=True,
                          timeout=65, check=False)
    if proc.returncode:
        raise RuntimeError("Private GitHub operation failed; local evidence preserved")
    if len(proc.stdout) > 2_000_000:
        raise RuntimeError("Private GitHub response unexpectedly large")
    return proc.stdout.strip()


def ensure_private_repo():
    if gh("repo", "view", REPO, "--json", "visibility", "--jq", ".visibility") != "PRIVATE":
        raise RuntimeError("Refusing to publish to a non-private repository")


def local_git_sha(path: Path) -> str:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 2_000_000:
        raise ValueError("Invalid run evidence file")
    return hashlib.sha1(b"blob " + str(path.stat().st_size).encode() + b"\x00" +
                        path.read_bytes()).hexdigest()


def remote_sha(path: str):
    if not re.fullmatch(r"[a-zA-Z0-9._/-]{1,180}", path):
        raise ValueError("Unexpected GitHub content path")
    try:
        value = gh("api", "--method", "GET",
                   "repos/" + REPO + "/contents/" + path, "--jq", ".sha")
    except RuntimeError:
        return None
    if not SHA.fullmatch(value):
        raise ValueError("Private GitHub returned invalid content SHA")
    return value


def verify_uploaded_runs(manifest: dict, runs: Path):
    seen = set()
    for pair in manifest["pairs"]:
        for arm in ("baseline", "candidate"):
            name = pair[arm]
            if name in seen:
                raise ValueError("Reused benchmark identity")
            seen.add(name)
            if not RUN_NAME.fullmatch(name):
                raise ValueError("Invalid benchmark identity")
            for filename in ("menuperf.csv", "summary.json", "lifecycle.verified"):
                local = runs / name / filename
                expected = local_git_sha(local)
                published = remote_sha("runs/" + name + "/" + filename)
                if expected != published:
                    raise RuntimeError("A required private benchmark upload is missing or differs")


def publish(manifest: Path, runs: Path, *, commit=False) -> dict:
    if manifest.is_symlink() or not manifest.is_file() or manifest.stat().st_size > 100_000:
        raise ValueError("Unreviewed experiment manifest")
    source = manifest.read_bytes()
    data = json.loads(source.decode("utf-8"))
    exp = data.get("experiment_id") if type(data) is dict else None
    if not isinstance(exp, str) or not EXP_ID.fullmatch(exp):
        raise ValueError("Invalid experiment identity")
    if manifest.name != exp + ".json":
        raise ValueError("Manifest filename disagrees with experiment identity")
    # Reconstruct every run-level inference; never trust a copied model report.
    outcome = remote_evidence_gate.evaluate(manifest, runs)
    if outcome["may_execute_candidate"] is not False or outcome["may_deploy_automatically"] is not False:
        raise RuntimeError("Unsafe remote policy")
    target = "experiments/" + exp + ".json"
    result = {
        "experiment_id": exp, "remote_path": target,
        "manifest_sha256": hashlib.sha256(source).hexdigest(),
        "gate_status": outcome["evidence_gate"]["status"],
        "published": False, "game_executed": False,
        "automatic_deployment_allowed": False,
    }
    if not commit:
        return result
    ensure_private_repo()
    verify_uploaded_runs(data, runs)
    existing = remote_sha(target)
    expected_blob = local_git_sha(manifest)
    if existing is not None:
        if existing != expected_blob:
            raise RuntimeError("Remote experiment differs; refusing overwrite")
        return {**result, "published": True, "already_published": True}
    payload = {
        "message": "Record verified supervised OpenLRR source-DLL experiment " + exp,
        "content": base64.b64encode(source).decode("ascii"),
    }
    with tempfile.TemporaryDirectory(prefix="openlrr-exp-publish-") as tmp:
        path = Path(tmp) / "github-upload.json"
        path.write_text(json.dumps(payload))
        gh("api", "--method", "PUT", "repos/" + REPO + "/contents/" + target,
           input_file=path)
    if remote_sha(target) != expected_blob:
        raise RuntimeError("Remote experiment upload was not verified")
    return {**result, "published": True, "already_published": False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--runs-dir", type=Path, required=True)
    parser.add_argument("--publish", action="store_true",
                        help="Explicitly publish verified manifest, never executable")
    args = parser.parse_args(argv)
    result = publish(args.manifest, args.runs_dir, commit=args.publish)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, TypeError, json.JSONDecodeError,
            subprocess.SubprocessError) as exc:
        print("EXPERIMENT PUBLISH REFUSED:", exc, file=sys.stderr)
        raise SystemExit(2)
