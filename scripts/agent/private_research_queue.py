#!/usr/bin/env python3
"""Discover a single pending private OpenLRR research ticket, READ ONLY.

No model calls, game execution, GitHub writes or promises of budget approval.
The actual dispatcher independently revalidates the selected ticket and
atomically reserves the daily and per-ticket slots BEFORE any model call.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import sys

import private_research_inbox as inbox

TICKET_FILE = re.compile(r"^research_[a-f0-9]{24}\.json$")
DAY_FILE = re.compile(r"^daily_[0-9]{8}\.json$")
CLAIM_FILE = re.compile(r"^ticket_research_[a-f0-9]{24}\.json$")
MAX_DIRECTORY_FILES = 1000


def remote_directory(name: str) -> list[dict]:
    if name not in ("research-tickets", "research-dispatches"):
        raise ValueError("Unexpected remote directory")
    rows = json.loads(inbox.gh(
        "api", "repos/" + inbox.REPO + "/contents/" + name + "?ref=" + inbox.REF
    ))
    if type(rows) is not list or len(rows) > MAX_DIRECTORY_FILES:
        raise ValueError("Malformed/oversized GitHub research directory")
    for row in rows:
        if type(row) is not dict or row.get("type") != "file":
            raise ValueError("Private research directory contains unexpected object")
        filename = row.get("name")
        if type(filename) is not str or row.get("path") != name + "/" + filename:
            raise ValueError("Unexpected private GitHub result path")
        if filename != ".gitkeep" and not (
            TICKET_FILE.fullmatch(filename) if name == "research-tickets"
            else (DAY_FILE.fullmatch(filename) or CLAIM_FILE.fullmatch(filename))
        ):
            raise ValueError("Private research directory contains unsupported entry")
    return rows


def select_one(*, now: datetime | None = None) -> dict:
    inbox.private_repo_only()
    utc = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    day = utc.strftime("%Y%m%d")
    tickets = remote_directory("research-tickets")
    claims = remote_directory("research-dispatches")
    names = {e["name"] for e in claims}
    if "daily_" + day + ".json" in names:
        return {"pending_ticket_id": None, "day_already_reserved": True,
                "unclaimed_ticket_count": 0, "model_invoked": False,
                "game_executed": False}
    pending = []
    for entry in tickets:
        filename = entry["name"]
        if filename == ".gitkeep":
            continue
        identifier = filename[:-5]
        if "ticket_" + identifier + ".json" not in names:
            pending.append(identifier)
    pending.sort()
    return {
        "pending_ticket_id": pending[0] if pending else None,
        "day_already_reserved": False,
        "unclaimed_ticket_count": len(pending),
        "model_invoked": False,
        "game_executed": False,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--discover-private", action="store_true",
                        help="Read private directory listings; never start a model")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)
    if args.out is not None and not args.discover_private:
        parser.error("--out requires --discover-private")
    if not args.discover_private:
        print(json.dumps({"mode": "offline_dry_run", "github_queried": False,
                          "model_invoked": False}, sort_keys=True))
        return 0
    result = select_one()
    if args.out is not None:
        args.out.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with args.out.open("x", encoding="utf-8") as writer:
            writer.write(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, TypeError,
            json.JSONDecodeError) as exc:
        print("PRIVATE QUEUE DISCOVERY STOPPED:", exc, file=sys.stderr)
        raise SystemExit(2)
