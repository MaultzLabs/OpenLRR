#!/usr/bin/env python3
"""Bind an existing visual QA report to independently revalidated TEST run files.

This proves file/run *consistency*, NOT who captured the screen nor that media
came from a game window. It has no execution, network, deployment or AI access.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

import evidence_gate

SHA = re.compile(r"^[a-f0-9]{64}$")
CAPTURE_FILE = re.compile(r"^visual/[A-Za-z0-9][A-Za-z0-9_.-]{0,63}\.(?:png|jpg|jpeg|bmp|webp|mp4|mov|mkv|webm|avi)$")
MAX_CAPTURE_BYTES = 1_000_000_000
MAX_JSON_BYTES = 250_000
RECEIPT_NAME = "lifecycle.verified"
SUMMARY_NAME = "summary.json"


def canonical_digest(value: dict) -> str:
    return hashlib.sha256(json.dumps(
        value, ensure_ascii=True, sort_keys=True,
        separators=(",", ":")).encode("ascii")).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def regular_unlinked(path: Path) -> Path:
    absolute = path.absolute()
    # A symlink in ANY ancestor can redirect a supposedly isolated capture
    # path into a different location. Reject rather than following it.
    if any(p.is_symlink() for p in (absolute, *absolute.parents)):
        raise ValueError("Symlink in verified capture path")
    if not path.is_file():
        raise ValueError("Required verified capture file absent")
    return absolute


def bounded_json(path: Path) -> dict:
    file = regular_unlinked(path)
    if not 0 < file.stat().st_size <= MAX_JSON_BYTES:
        raise ValueError("Manifest/report exceeds allowed size")
    obj = json.loads(file.read_text(encoding="utf-8"))
    if type(obj) is not dict:
        raise ValueError("Expected JSON object")
    return obj


def verified_capture_binding(experiment: dict, runs_dir: Path,
                             manifest: dict) -> tuple[dict, Path, Path]:
    if type(experiment) is not dict or experiment.get("schema_version") != 1:
        raise ValueError("Invalid existing benchmark manifest")
    if type(manifest) is not dict or set(manifest) != {
            "schema_version", "experiment_id", "pair_index",
            "scene", "captures"}:
        raise ValueError("Unexpected capture manifest structure")
    if type(manifest["schema_version"]) is not int or manifest["schema_version"] != 1:
        raise ValueError("Unknown capture manifest version")
    if manifest["experiment_id"] != experiment.get("experiment_id") or (
            not isinstance(manifest["experiment_id"], str)
            or not evidence_gate.ID_RE.fullmatch(manifest["experiment_id"])):
        raise ValueError("Capture belongs to a different experiment")
    if (manifest["scene"] != experiment.get("controlled_scene")
            or manifest["scene"] != "menu_boot_autotest_v1"):
        raise ValueError("Capture scene does not match certified benchmark scene")
    pair_index = manifest["pair_index"]
    pairs = experiment.get("pairs")
    if type(pair_index) is not int or type(pairs) is not list or not 0 <= pair_index < len(pairs):
        raise ValueError("Capture pair index outside experiment")
    expected_pair = pairs[pair_index]
    if type(expected_pair) is not dict or set(expected_pair) != {"baseline", "candidate"}:
        raise ValueError("Bad benchmark pair")
    captures = manifest["captures"]
    if type(captures) is not dict or set(captures) != {"baseline", "candidate"}:
        raise ValueError("Capture manifest requires baseline and candidate")
    paths = {}
    identities = {}
    root = runs_dir.resolve(strict=True)
    for arm in ("baseline", "candidate"):
        rec = captures[arm]
        if type(rec) is not dict or set(rec) != {
                "run", "file", "sha256", "summary_sha256"}:
            raise ValueError("Unexpected capture record fields")
        run_name = expected_pair[arm]
        if rec["run"] != run_name or not isinstance(run_name, str) or not evidence_gate.RUN_RE.fullmatch(run_name):
            raise ValueError("Capture run does not match experiment arm")
        filename = rec["file"]
        if not isinstance(filename, str) or not CAPTURE_FILE.fullmatch(filename):
            raise ValueError("Capture must reside under its run's visual/ folder")
        for key in ("sha256", "summary_sha256"):
            if not isinstance(rec[key], str) or not SHA.fullmatch(rec[key]):
                raise ValueError("Invalid capture or summary SHA256")
        run_path = root / run_name
        summary = regular_unlinked(run_path / SUMMARY_NAME)
        receipt = regular_unlinked(run_path / RECEIPT_NAME)
        # The existing evidence gate must independently accept both run
        # receipts, exact DLL identity, graphics mode and presentation metrics.
        verified = evidence_gate.load_verified_run(root, run_name)
        if sha256_file(summary) != rec["summary_sha256"]:
            raise ValueError("Run summary changed since capture registration")
        capture = regular_unlinked(run_path / filename)
        if not 0 < capture.stat().st_size <= MAX_CAPTURE_BYTES:
            raise ValueError("Capture size outside limits")
        if sha256_file(capture) != rec["sha256"]:
            raise ValueError("Capture bytes changed since registration")
        paths[arm] = capture
        identities[arm] = {
            "run": run_name,
            "file": filename,
            "capture_sha256": rec["sha256"],
            "summary_sha256": rec["summary_sha256"],
            "lifecycle_sha256": sha256_file(receipt),
            "dll_sha256": verified["sha"],
            "graphics_mode": verified["mode"],
        }
    if paths["baseline"] == paths["candidate"]:
        raise ValueError("Capture files cannot be identical paths")
    binding = {
        "schema_version": 1,
        "experiment_id": experiment["experiment_id"],
        "scene": manifest["scene"],
        "pair_index": pair_index,
        "experiment_manifest_digest": canonical_digest(experiment),
        "capture_manifest_digest": canonical_digest(manifest),
        "baseline": identities["baseline"],
        "candidate": identities["candidate"],
        "verified_local_receipts": True,
        "capture_origin_authenticated": False,
        "may_touch_working_game": False,
        "may_deploy_automatically": False,
    }
    return binding, paths["baseline"], paths["candidate"]


def verify_bound_report(experiment: dict, runs_dir: Path,
                        capture_manifest: dict, report: dict) -> dict:
    if type(report) is not dict or report.get("tool") != "openlrr-visual-qa":
        raise ValueError("Not a recognized visual QA report")
    binding, baseline, candidate = verified_capture_binding(
        experiment, runs_dir, capture_manifest)
    if report.get("capture_binding") != binding:
        raise ValueError("Visual report is not bound to these verified TEST runs")
    if report.get("experiment_id") != binding["experiment_id"] or report.get("scene") != binding["scene"]:
        raise ValueError("Visual report references different experiment or scene")
    hashes = report.get("capture_hashes")
    if type(hashes) is not dict or hashes.get("reference_sha256") != sha256_file(baseline) or (
            hashes.get("candidate_sha256") != sha256_file(candidate)):
        raise ValueError("Visual report content hashes no longer match captures")
    if (report.get("may_touch_working_game") is not False
            or report.get("may_deploy_automatically") is not False
            or report.get("may_install_or_run_candidate") is not False):
        raise ValueError("Visual report attempts to authorize execution")
    return binding
