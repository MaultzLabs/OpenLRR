#!/usr/bin/env python3
"""Private human review queue and feedback protocol for OpenLRR evidence reports.

A candidate is eligible for human review only after offline evidence_gate has
returned candidate_for_review. No approval here authorizes binary execution,
merging, deployment or modification of the user's working game.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

REPO = "MaultzLabs/OpenLRR-Test-Results"  # intentionally private
REVIEWER = "MaultzLabs"
ID_RE = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_-]{2,63}$")


def feedback_from_comments(comments: list[dict]) -> dict:
    """Accept only explicit commands from the approved GitHub account."""
    latest = {"decision": "awaiting_human", "reason": "",
              "automatic_deploy_allowed": False}
    for comment in comments:
        if not isinstance(comment, dict):
            continue
        actor = comment.get("user")
        if not isinstance(actor, dict) or actor.get("login", "").lower() != REVIEWER.lower():
            continue
        msg = comment.get("body")
        if not isinstance(msg, str) or len(msg) > 1200:
            continue
        matched = re.fullmatch(r"/lab (good|continue|reject)(?:: ([^\r\n]{1,1000}))?", msg.strip())
        if not matched:
            continue
        command, reason = matched.groups()
        if command in ("continue", "reject") and not reason:
            continue
        latest = {"decision": command, "reason": reason or "",
                  "automatic_deploy_allowed": False,
                  "review_comment_id": comment.get("id"),
                  "review_author": REVIEWER}
    return latest


def gh(*args: str) -> str:
    process = subprocess.run(["gh", *args], capture_output=True,
                             text=True, timeout=40, check=False)
    if process.returncode:
        raise RuntimeError("GitHub private review operation failed; check gh auth and repo access")
    if len(process.stdout) > 2_000_000:
        raise RuntimeError("Oversize GitHub response")
    return process.stdout


def validate_candidate(report: dict):
    if not isinstance(report, dict) or report.get("schema_version") != 1:
        raise ValueError("Invalid review evidence")
    exp = report.get("experiment_id")
    if not isinstance(exp, str) or not ID_RE.fullmatch(exp):
        raise ValueError("Unsafe experiment id")
    if report.get("status") != "candidate_for_review" or report.get("notify_human") is not True:
        raise ValueError("Evidence gate did not authorize review notification")
    if report.get("automatic_promotion_allowed") is not False:
        raise ValueError("Unsafe automatic promotion request")
    if report.get("visual_fps_verified") is not False:
        raise ValueError("Evidence gate cannot attest to real visible FPS")
    if type(report.get("pairs")) is not int or report["pairs"] < 5:
        raise ValueError("Insufficient replicated trials")
    for field in ("hypothesis", "reason", "next_action"):
        value = report.get(field)
        if not isinstance(value, str) or not 10 <= len(value) <= 1500:
            raise ValueError("Missing bounded review detail " + field)
    for field in ("median_present_change_pct", "bootstrap_upper95_change_pct",
                  "median_logical_fps_change_pct"):
        value = report.get(field)
        if type(value) not in (int, float) or not -1000 <= value <= 1000:
            raise ValueError("Missing/invalid measured effect " + field)
    return exp


def review_body(report: dict):
    exp = validate_candidate(report)
    return "\n".join([
        "<!-- openlrr-lab-review:" + exp + " -->",
        "@MaultzLabs — OpenLRR has a candidate worth your review.",
        "",
        "## Hypothesis",
        report["hypothesis"],
        "",
        "## Why it was flagged",
        report["reason"],
        "",
        f"Paired verified runs: **{report['pairs']}**",
        f"Median presentation change: **{report['median_present_change_pct']}%** (negative is faster)",
        f"Bootstrap upper 95th percentile of estimated change: **{report['bootstrap_upper95_change_pct']}%**",
        f"Median logical-flips change: **{report['median_logical_fps_change_pct']}%** (NOT visible FPS)",
        "",
        "## What to check in the game",
        "Check actual menu and in-game visuals, stutter, flicker, tearing, responsiveness and regressions. "
        "This is a promising benchmark, **not a proven gameplay fix**.",
        "",
        "## Your review commands (comment exactly one)",
        "- Good job: /lab good: describe what looked correct",
        "- Keep working: /lab continue: explain what's wrong or what you want improved",
        "- Reject direction: /lab reject: explain why this approach should stop",
        "",
        "The human reason is recorded as research feedback for future planning, "
        "not as a shell command. No response approves execution or deployment automatically.",
        "",
        "## Proposed next action",
        report["next_action"],
        "",
        "Private benchmark data remain in this repository. Review the separate candidate "
        "build and source patch before running any unreviewed executable.",
    ])


def existing_issue(exp: str):
    data = json.loads(gh("issue", "list", "--repo", REPO, "--state", "all",
                         "--limit", "1000", "--json", "number,body,url"))
    matches = [i for i in data if "<!-- openlrr-lab-review:" + exp + " -->" in i.get("body", "")]
    if matches:
        return matches[0]["url"]
    return None


def publish(report: dict, *, dry_run: bool = True) -> str:
    exp = validate_candidate(report)
    body = review_body(report)
    if dry_run:
        print(body)
        return "DRY RUN: no notification sent"
    found = existing_issue(exp)
    if found:
        return "Existing review issue: " + found
    url = gh("issue", "create", "--repo", REPO, "--assignee", REVIEWER,
             "--title", "OpenLRR candidate for review: " + exp,
             "--body", body).strip()
    # Toast is supplemental. Email delivery depends on GitHub preferences.
    if sys.platform == "darwin":
        subprocess.run(["osascript", "-e",
                        'display notification "Experiment ready for review in private GitHub Issues" '
                        'with title "OpenLRR AI Laboratory"'],
                       timeout=8, check=False, capture_output=True)
    return "Private review issue created: " + url


def fetch_feedback(issue_number: int) -> dict:
    if not 1 <= issue_number <= 1_000_000:
        raise ValueError("Invalid review issue number")
    issue = json.loads(gh("api", f"repos/{REPO}/issues/{issue_number}"))
    if "<!-- openlrr-lab-review:" not in issue.get("body", ""):
        raise ValueError("Not an OpenLRR lab review issue")
    comments = json.loads(gh("api", f"repos/{REPO}/issues/{issue_number}/comments?per_page=100"))
    if not isinstance(comments, list):
        raise RuntimeError("Unexpected GitHub feedback data")
    return {"issue": issue_number, **feedback_from_comments(comments)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument("--report", type=Path)
    actions.add_argument("--feedback-issue", type=int)
    parser.add_argument("--publish", action="store_true", help="Create private issue only if eligible")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)
    if args.report:
        report = json.loads(args.report.read_text(encoding="utf-8"))
        print(publish(report, dry_run=not args.publish))
    else:
        reply = fetch_feedback(args.feedback_issue)
        output = json.dumps(reply, indent=2, sort_keys=True) + "\n"
        if args.out:
            args.out.write_text(output, encoding="utf-8")
        print(output, end="")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError,
            subprocess.SubprocessError) as exc:
        print("REVIEW QUEUE STOPPED:", exc, file=sys.stderr)
        raise SystemExit(2)
