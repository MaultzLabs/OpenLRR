#!/usr/bin/env python3
"""Compare OpenLRR Mac game-window evidence with Windows virtual playtest reports.

No pixel/media upload and no claim of gameplay equivalence without matching
internal state evidence. Runs offline using sanitized summaries only.

Inputs:
  Mac: gameplay-capture/recovered-clips/analysis-index.json
  Windows: lab/windows-playtest/out/<session>/report.json

Independent runs cannot be synchronized using wall-clock time. A click in one
session is NOT assumed to be the same click in the other session.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
from difflib import SequenceMatcher
import json
import math
import os
from pathlib import Path
import re
from typing import Any

SCHEMA = "openlrr-cross-platform-evidence-v1"
MAC_SCHEMA = "openlrr-clip-code-index-v1"
MAX_SOURCE_BYTES = 16 * 1024 * 1024
MAX_EVENTS = 200_000
MAX_CLIPS = 500
MAC_KEYCODES = {
    36: "enter", 53: "escape", 49: "space",
    123: "left", 124: "right", 125: "down", 126: "up",
}
WINDOWS_ACTIONS = frozenset({
    "capture", "click", "key", "wait", "assert_title",
    "assert_alive", "assert_changed",
})
WINDOWS_KEYS = frozenset({
    "enter", "escape", "space", "up", "down", "left", "right",
})
EVENT_SOURCES = frozenset({
    "video", "mac_input", "wine_api", "nerps",
    "openlrr_menu", "capture_control",
})
FRAME_NAME = re.compile(r"frame-[0-9]{2,4}\.png")


def finite_number(value: Any, *, upper: float = 1e14) -> float | None:
    if type(value) not in (int, float) or not math.isfinite(value):
        return None
    value = float(value)
    return value if 0 <= value <= upper else None


def read_json(path: Path) -> dict:
    if path.is_symlink() or not path.is_file():
        raise ValueError("Missing or symlinked evidence file")
    if path.stat().st_size > MAX_SOURCE_BYTES:
        raise ValueError("Evidence exceeds safe size limit")
    with path.open("r", encoding="utf-8") as stream:
        obj = json.load(stream)
    if not isinstance(obj, dict):
        raise ValueError("Evidence root must be an object")
    return obj


def windows_clock(raw: Any) -> datetime | None:
    if not isinstance(raw, str) or len(raw) > 48:
        return None
    # The current Win32 controller records timestamps only to a whole second.
    try:
        dt = datetime.strptime(raw, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return None
    return dt.replace(tzinfo=timezone.utc)


def normalize_mac(data: dict) -> dict:
    if data.get("schema") != MAC_SCHEMA:
        raise ValueError("Unrecognized Mac clip-index schema")
    clips = data.get("clips")
    if not isinstance(clips, list) or len(clips) > MAX_CLIPS:
        raise ValueError("Invalid Mac clip list")
    origin = finite_number(data.get("capture_unix_s"))
    source_counts: Counter[str] = Counter()
    actions: list[dict] = []
    game_events: list[dict] = []
    total = 0
    duration = 0.0
    for i, clip in enumerate(clips):
        if not isinstance(clip, dict):
            raise ValueError("Invalid Mac clip entry")
        start = finite_number(clip.get("start_s"), upper=14400)
        length = finite_number(clip.get("duration_s"), upper=14400)
        name = clip.get("file")
        events = clip.get("events")
        if (start is None or length is None or length <= 0 or
                not isinstance(name, str) or
                not re.fullmatch(r"part-[0-9]{4}\.mp4", name) or
                not isinstance(events, list)):
            raise ValueError("Unsafe Mac clip metadata")
        if i and start + .1 < duration:
            raise ValueError("Overlapping Mac clip time ranges")
        duration = max(duration, start + length)
        if total + len(events) > MAX_EVENTS:
            raise ValueError("Too many Mac timeline events")
        for event in events:
            if not isinstance(event, dict):
                continue
            source = event.get("source")
            at = finite_number(event.get("at_s"), upper=14400)
            if source not in EVENT_SOURCES or at is None or at > length + .15:
                continue
            t = round(start + at, 3)
            source_counts[source] += 1
            if source == "mac_input":
                kind = event.get("input_event")
                if kind in ("left_down", "right_down"):
                    action = {"type": "click", "time_from_video_s": t}
                    for field in ("x_normalized", "y_normalized"):
                        coordinate = finite_number(event.get(field), upper=1)
                        if coordinate is not None:
                            action[field] = coordinate
                    actions.append(action)
                elif kind == "key_down":
                    code = event.get("keycode")
                    if type(code) is int:
                        actions.append({
                            "type": "key",
                            "name": MAC_KEYCODES.get(code, "unmapped"),
                            "time_from_video_s": t,
                        })
            elif source == "openlrr_menu":
                value = event.get("menu_id")
                if type(value) is int and 0 <= value <= 65535:
                    game_events.append({"type": "menu_command", "menu_id": value,
                                        "time_from_video_s": t})
            elif source == "nerps":
                value = event.get("function_id")
                if type(value) is int and 0 <= value < 294:
                    game_events.append({"type": "nerps_function",
                                        "function_id": value,
                                        "time_from_video_s": t})
        total += len(events)
    return {
        "kind": "mac_window_capture",
        "clip_count": len(clips),
        "indexed_video_duration_s": round(duration, 3),
        "timeline_origin_recorded": origin is not None,
        "time_precision": "video_relative_host_estimate_not_frame_exact",
        "source_counts": dict(sorted(source_counts.items())),
        "game_actions": actions[:500],
        "game_actions_truncated": max(0, len(actions) - 500),
        "game_internal_events": game_events[:500],
        "game_internal_events_truncated": max(0, len(game_events) - 500),
        "has_real_game_internal_evidence": bool(game_events),
        "has_recorded_game_controls": bool(actions),
        "window_video_reference_present": bool(clips),
        "privacy_note": "No video, audio, typed text or original WAD assets were read.",
    }


def normalize_windows(data: dict) -> dict:
    if data.get("status") not in ("passed", "failed"):
        raise ValueError("Unrecognized Windows controller status")
    events = data.get("events")
    if not isinstance(events, list) or len(events) > 40:
        raise ValueError("Unsafe Windows playtest event count")
    actions: list[dict] = []
    observations: list[dict] = []
    source_counts: Counter[str] = Counter()
    initial = None
    previous_step = -1
    for event in events:
        if not isinstance(event, dict):
            raise ValueError("Malformed Windows event")
        step = event.get("step")
        kind = event.get("action")
        if type(step) is not int or not 0 <= step < 40 or step <= previous_step:
            raise ValueError("Windows step numbers must increase")
        if kind not in WINDOWS_ACTIONS:
            raise ValueError("Unsupported Windows action")
        previous_step = step
        timestamp = windows_clock(event.get("timestamp_utc"))
        if initial is None and timestamp is not None:
            initial = timestamp
        t = ((timestamp - initial).total_seconds() if initial and timestamp
             else None)
        # Do not compare these coarse Windows controller times directly
        # against an independent Mac video recording.
        source_counts[kind] += 1
        if kind == "click":
            actions.append({"type": "click", "step": step})
        elif kind == "key":
            # Current Windows report does not contain which key was sent.
            # This is intentional: never invent an absent key name.
            actions.append({"type": "key", "name": "unrecorded", "step": step})
        if kind in ("capture", "assert_changed"):
            frame = event.get("frame")
            if not isinstance(frame, str) or not FRAME_NAME.fullmatch(frame):
                # Missing/unsafe frame is not evidence of a screenshot.
                continue
            item = {"step": step, "type": "window_frame_recorded"}
            if kind == "assert_changed":
                diff = finite_number(event.get("mean_pixel_difference"),
                                     upper=255)
                if diff is not None:
                    item["mean_pixel_difference"] = round(diff, 4)
                    item["type"] = "visual_change_measured"
            observations.append(item)
    return {
        "kind": "windows_virtual_playtest",
        "controller_status": data["status"],
        "steps_observed": len(events),
        "source_counts": dict(sorted(source_counts.items())),
        "game_actions": actions,
        "visual_observations": observations,
        "time_precision": "controller_wall_clock_seconds_not_synchronized",
        # A Windows CI synthetic fixture can pass with exactly this schema.
        # 'passed' cannot establish a 1999 game or gameplay correctness.
        "original_game_execution_verified": False,
        "game_internal_events_available": False,
        "privacy_note": "Target path, PID, window title and error text are excluded.",
    }


def action_tokens(actions: list[dict]) -> list[str]:
    tokens = []
    for action in actions:
        if action["type"] == "click":
            tokens.append("click")
        elif action["type"] == "key":
            name = action.get("name")
            tokens.append("key:" + name if name in WINDOWS_KEYS
                          else "key:unknown")
    return tokens


def compare(mac: dict, windows: dict) -> dict:
    a = action_tokens(mac["game_actions"])
    b = action_tokens(windows["game_actions"])
    matcher = SequenceMatcher(a=a, b=b, autojunk=False)
    pairs = sum(block.size for block in matcher.get_matching_blocks())
    # Even 100% identical input does not imply the game handled it identically.
    return {
        "schema": SCHEMA,
        "comparison_status": "evidence_alignment_only",
        "actual_gameplay_parity": "not_established",
        "reference_windows_game_execution": "not_attested",
        "mac": mac,
        "windows": windows,
        "action_sequence": {
            "mac_count": len(a), "windows_count": len(b),
            "common_ordered_action_tokens": pairs,
            "overlap_fraction_of_shorter": (
                round(pairs / min(len(a), len(b)), 3) if a and b else None),
            "claim": "Action overlap only; different sessions and independent clocks.",
        },
        "next_evidence_gates": [
            "Attest that the Windows run actually executed the original game, not a fixture.",
            "Capture real Windows input keys, graphics frames and game-state outcomes.",
            "Instrument identical menu and NERPs events in both environments.",
            "Compare corresponding scripted scenarios, state changes and screenshots.",
        ],
    }


def write_private(result: dict, destination: Path) -> None:
    if destination.is_symlink() or destination.exists():
        raise ValueError("Will not overwrite an existing comparison")
    if destination.parent.is_symlink() or not destination.parent.is_dir():
        raise ValueError("Comparison output directory is unavailable")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    with os.fdopen(os.open(destination, flags, 0o600), "w",
                   encoding="utf-8") as output:
        json.dump(result, output, sort_keys=True, indent=2)
        output.write("\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mac-index", type=Path, required=True)
    parser.add_argument("--windows-report", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        result = compare(normalize_mac(read_json(args.mac_index)),
                         normalize_windows(read_json(args.windows_report)))
        write_private(result, args.out)
    except (ValueError, OSError, UnicodeError, json.JSONDecodeError) as error:
        parser.exit(2, f"Comparison unavailable: {type(error).__name__}.\n")
    print("Cross-platform evidence indexed; gameplay parity NOT established.")
    print("Mac internal events:", len(result["mac"]["game_internal_events"]))
    print("Windows visual observations:",
          len(result["windows"]["visual_observations"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
