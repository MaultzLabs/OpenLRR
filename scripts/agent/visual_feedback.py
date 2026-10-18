"""Validate offline visual QA evidence before routing it into research policy.

Visual captures are advisory and are never authenticated by this module.
They may reprioritize a hypothesis, but may not approve code or execution.
"""
from __future__ import annotations

import hashlib
import json
import math
import re

HASH = re.compile(r"^[0-9a-f]{64}$")
CODE = re.compile(r"^[a-z][a-z0-9_]{1,63}$")
STATUS = {"pass", "review", "regression", "inconclusive"}
SEVERITY = {"critical", "blocking", "warning", "info"}


def validate_visual_report(raw: dict | None, experiment_id: str) -> dict | None:
    if raw is None:
        return None
    if type(raw) is not dict or raw.get("schema_version") != 1:
        raise ValueError("Unrecognized visual QA report")
    if raw.get("tool") != "openlrr-visual-qa" or raw.get("experiment_id") != experiment_id:
        raise ValueError("Visual report provenance/experiment mismatch")
    if raw.get("status") not in STATUS:
        raise ValueError("Invalid visual QA status")
    if any(raw.get(key) is not False for key in (
            "may_install_or_run_candidate", "may_touch_working_game",
            "may_deploy_automatically", "visual_fps_verified")):
        raise ValueError("Visual report attempts to elevate authority")
    score = raw.get("score")
    if raw["status"] == "inconclusive":
        if score is not None:
            raise ValueError("Inconclusive visual report cannot assert a score")
    elif type(score) not in (int, float) or not math.isfinite(score) or not 0 <= score <= 100:
        raise ValueError("Invalid visual score")
    hashes = raw.get("capture_hashes")
    if type(hashes) is not dict or any(
            not isinstance(hashes.get(name), str) or not HASH.fullmatch(hashes[name])
            for name in ("reference_sha256", "candidate_sha256")):
        raise ValueError("Capture hashes missing")
    if hashes["reference_sha256"] == hashes["candidate_sha256"] and raw["status"] == "regression":
        raise ValueError("Identical capture hashes cannot support a regression claim")
    findings = raw.get("findings")
    if type(findings) is not list or len(findings) > 32:
        raise ValueError("Visual findings absent or excessive")
    codes = []
    for finding in findings:
        if type(finding) is not dict or not CODE.fullmatch(str(finding.get("code", ""))):
            raise ValueError("Invalid finding code")
        if finding.get("severity") not in SEVERITY:
            raise ValueError("Invalid finding severity")
        codes.append(finding["code"])
    # Stable compact fingerprint covers exact report, not just the rounded score.
    if len(json.dumps(raw, sort_keys=True)) > 250_000:
        raise ValueError("Oversize visual QA report")
    fingerprint = hashlib.sha256(
        json.dumps(raw, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    ).hexdigest()
    return {"status": raw["status"], "score": score,
            "reason_codes": codes, "fingerprint": fingerprint}


def adapt_policy(policy: dict, visual: dict | None, benchmark_status: str) -> dict:
    if visual is None or visual["status"] == "pass":
        return policy
    result = dict(policy)
    status = visual["status"]
    if status == "regression":
        result.update(
            next_step="isolate_regression",
            why="Captured visual regression blocks the experiment; examine differences: " +
                (", ".join(visual["reason_codes"][:6]) or "score below threshold"),
            request_human_review=False,
        )
    elif status == "inconclusive":
        result.update(
            next_step="improve_instrumentation",
            why="Visual media cannot be compared reliably; fix capture alignment before research.",
            request_human_review=False,
        )
    elif status == "review" and benchmark_status == "candidate_for_review":
        result.update(
            next_step="hold_for_review",
            why="Performance candidate has visible differences requiring human review: " +
                (", ".join(visual["reason_codes"][:6]) or "difference above tolerance"),
            request_human_review=True,
        )
    # For insufficient/rejected performance evidence, do not grant a review
    # status merely because screenshots had a moderate difference.
    return result
