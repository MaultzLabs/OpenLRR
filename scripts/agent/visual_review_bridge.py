#!/usr/bin/env python3
"""Read-only visual QA handoff to existing private human review workflow.

Builds a metadata-only packet from independently revalidated TEST benchmark
receipts, capture files, score and timing markers. Network publication requires
two explicit opt-ins and verified PRIVATE GitHub repository visibility.
No image uploads, candidate execution, game writes, or deployment permissions.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import evidence_gate
import experiment_controller
import review_queue
from visual_capture_binding import bounded_json, verify_bound_report

MAX_PACKET_BYTES = 16000
REVIEW_STATES = frozenset(("pass", "review"))
STOP_DIR = experiment_controller.STOP_DIR


def finite(value, low=0.0, high=100.0):
    if type(value) not in (float, int) or not math.isfinite(value) or not low <= value <= high:
        raise ValueError("Invalid recomputed visual metric")
    return float(value)


def evaluate(manifest: Path, runs_dir: Path, captures: Path, visual_report: Path,
             *, require_timing: bool = True, switches_dir: Path = STOP_DIR):
    if any((switches_dir / flag).exists() for flag in ("STOP", "PAUSE")):
        raise RuntimeError("STOP/PAUSE blocks private review preparation")
    experiment = bounded_json(manifest)
    registered = bounded_json(captures)
    visual = bounded_json(visual_report)
    benchmark = evidence_gate.decision(experiment, runs_dir)
    # Rehash local files, reconstruct verified run evidence, and recompute
    # screenshots/video pixels. Caller-written status and score are not trusted.
    binding = verify_bound_report(experiment, runs_dir, registered, visual)
    decision = experiment_controller.decision_for(
        benchmark, {"schema_version": 1, "events": []},
        visual_report=visual, visual_binding_verified=True)
    if (decision["may_touch_working_game"] is not False
            or decision["may_install_or_run_candidate"] is not False
            or decision["may_deploy_automatically"] is not False):
        raise ValueError("Unsafe research decision authority")
    quality = visual["status"]
    score = None if visual["score"] is None else finite(visual["score"])
    metrics = visual["metrics"]
    if type(metrics) is not dict:
        raise ValueError("Missing QA measurements")
    frames = metrics.get("frame_count")
    worst = metrics.get("worst_frame_score")
    if quality != "inconclusive":
        if type(frames) is not int or not 1 <= frames <= 24:
            raise ValueError("Invalid sampled frame count")
        worst = finite(worst)
    else:
        frames, worst = 0, None
    findings = []
    for finding in visual["findings"]:
        if type(finding) is not dict:
            raise ValueError("Malformed recomputed finding")
        code = finding.get("code")
        severity = finding.get("severity")
        if not isinstance(code, str) or len(code) > 64 or severity not in (
                "critical", "blocking", "warning", "info"):
            raise ValueError("Unsafe finding fields")
        findings.append({"code": code, "severity": severity})
    blockers = []
    if benchmark["status"] != "candidate_for_review":
        blockers.append("benchmark_not_review_candidate")
    if quality not in REVIEW_STATES:
        blockers.append("visual_regression_or_inconclusive")
    if require_timing and binding["temporal_consistency_verified"] is not True:
        blockers.append("capture_timing_not_verified")
    if decision["next_step"] != "hold_for_review" or decision["request_human_review"] is not True:
        blockers.append("controller_did_not_request_review")
    if benchmark["pairs"] < 5:
        blockers.append("insufficient_repeated_benchmarks")
    pair_index = binding["pair_index"]
    if type(pair_index) is not int or not 0 <= pair_index < benchmark["pairs"]:
        raise ValueError("Visual source is not a declared benchmark pair")
    packet = {
        "schema_version": 1,
        "kind": "openlrr-visual-review-handoff",
        "experiment_id": benchmark["experiment_id"],
        "state": "ready_for_private_review" if not blockers else "blocked",
        "blockers": blockers,
        "benchmark": {
            "status": benchmark["status"],
            "paired_trials": benchmark["pairs"],
            "median_present_change_pct": benchmark["median_present_change_pct"],
            "bootstrap_upper95_change_pct": benchmark["bootstrap_upper95_change_pct"],
            "median_logical_fps_change_pct": benchmark["median_logical_fps_change_pct"],
        },
        "visual": {
            "status": quality, "score": score,
            "worst_sampled_frame_score": worst,
            "sampled_frames": frames, "compared_pair_index": pair_index,
            "pair_coverage": "1/" + str(benchmark["pairs"]),
            "findings": findings,
            "capture_hashes": visual["capture_hashes"],
            "verified_test_run_timing": binding["temporal_consistency_verified"],
            "capture_origin_authenticated": False,
            "visible_fps_verified": False,
        },
        "policy": {
            "next_step": decision["next_step"],
            "human_approval_required": True,
            "may_install_or_run_candidate": False,
            "may_touch_working_game": False,
            "may_deploy_automatically": False,
        },
        "privacy": {
            "media_attached": False,
            "media_uploaded": False,
            "contains_media_bytes": False,
            "private_review_only": True,
        },
        "evidence_fingerprint": hashlib.sha256(json.dumps({
            "experiment": experiment, "capture_binding": binding,
            "visual_fingerprint": decision["visual_quality_fingerprint"],
        }, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest(),
    }
    if len(json.dumps(packet, sort_keys=True)) > MAX_PACKET_BYTES:
        raise ValueError("Unexpectedly large review packet")
    return packet, benchmark


def review_body(packet: dict, benchmark: dict):
    if packet.get("state") != "ready_for_private_review":
        raise ValueError("Blocked evidence cannot trigger a review")
    review_queue.validate_candidate(benchmark)
    visual = packet["visual"]
    if visual["status"] not in REVIEW_STATES or visual["verified_test_run_timing"] is not True:
        raise ValueError("Only time-correlated visuals may be published")
    lines = [
        "", "## Visual QA — VERIFIED TEST pair only",
        "- Visual classification: **" + visual["status"] + "**",
        "- Similarity agreement: **" + format(visual["score"], ".2f") +
            "/100** (NOT gameplay correctness)",
        "- Worst sampled frame: **" + format(visual["worst_sampled_frame_score"], ".2f") + "/100**",
        "- Sampled frames: **" + str(visual["sampled_frames"]) + "**",
        "- Visual trial coverage: **" + visual["pair_coverage"] + "** benchmark pairs",
        "- TEST run timing and file hashes independently verified",
        "- Capture origin is NOT cryptographically authenticated",
        "- Visible frames per second NOT measured or verified",
        "- No screenshots/videos attached or uploaded",
        "- Human review is required; no executable may be deployed automatically",
    ]
    if visual["status"] == "review":
        lines.append("- **Attention: visual differences must be inspected by the reviewer.**")
    for finding in visual["findings"][:8]:
        lines.append("- Visual finding: " + finding["code"] + " (" + finding["severity"] + ")")
    lines.extend(["", "## Evidence fingerprint",
                  "- Reference SHA256: " + visual["capture_hashes"]["reference_sha256"],
                  "- Candidate SHA256: " + visual["capture_hashes"]["candidate_sha256"],
                  "- Review evidence: " + packet["evidence_fingerprint"],
                  "",
                  "Use the normal /lab good, /lab continue or /lab reject command.",
                  "Even an explicit human 'good' review never authorizes deployment."])
    return review_queue.review_body(benchmark) + "\n" + "\n".join(lines)


def assert_private_repo():
    visibility = review_queue.gh("api", f"repos/{review_queue.REPO}",
                                 "--jq", ".private")
    if visibility.strip() != "true":
        raise RuntimeError("Review target has not been confirmed PRIVATE")


def publish(packet: dict, benchmark: dict, *, confirm_private_review: bool = False):
    if not confirm_private_review:
        raise ValueError("Explicit private review confirmation required")
    body = review_body(packet, benchmark)
    assert_private_repo()
    found = review_queue.existing_issue(packet["experiment_id"])
    if found:
        return "Existing private review issue: " + found
    url = review_queue.gh("issue", "create", "--repo", review_queue.REPO,
                          "--assignee", review_queue.REVIEWER,
                          "--title", "OpenLRR candidate for review: " + packet["experiment_id"],
                          "--body", body).strip()
    prefix = "https://github.com/" + review_queue.REPO + "/issues/"
    if not url.startswith(prefix) or not url[len(prefix):].isdigit():
        raise RuntimeError("Unexpected private review issue response")
    return "Private review issue created: " + url


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, required=True)
    p.add_argument("--runs-dir", type=Path, required=True)
    p.add_argument("--visual-captures", type=Path, required=True)
    p.add_argument("--visual-report", type=Path, required=True)
    p.add_argument("--out", type=Path)
    p.add_argument("--publish", action="store_true")
    p.add_argument("--confirm-private-review", action="store_true")
    args = p.parse_args(argv)
    try:
        if args.confirm_private_review and not args.publish:
            raise ValueError("Confirmation only allowed with --publish")
        packet, benchmark = evaluate(args.manifest, args.runs_dir,
                                     args.visual_captures, args.visual_report)
        if args.out:
            destination = args.out.absolute()
            if any(path.is_symlink() for path in (destination, *destination.parents)):
                raise ValueError("Packet output cannot pass through symlinks")
            if not destination.parent.is_dir() or destination.exists():
                raise ValueError("Packet output must be a new file in an existing folder")
            with destination.open("x", encoding="utf-8") as output:
                output.write(json.dumps(packet, indent=2, sort_keys=True) + "\n")
        if args.publish:
            print(publish(packet, benchmark,
                          confirm_private_review=args.confirm_private_review))
        else:
            print(json.dumps(packet, sort_keys=True, indent=2))
        return 0
    except (ValueError, OSError, RuntimeError, TypeError, json.JSONDecodeError) as exc:
        print("VISUAL REVIEW BRIDGE STOPPED: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
