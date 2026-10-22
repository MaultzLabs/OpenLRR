#!/usr/bin/env python3
"""Build an offline per-MP4 code/data correlation index from original game captures.

The index is metadata: it does NOT analyze images, infer unseen NERPs
execution, upload files, read desktop content, or use any AI/API tokens.
Video-relative timestamps are approximate host-clock comparisons and may
differ from decoded frame timestamps; do not call them frame-perfect.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import re
from typing import Any

SCHEMA = "openlrr-clip-code-index-v1"
SAFE_SOURCES = frozenset({
    "video", "mac_input", "wine_api", "nerps", "openlrr_menu", "capture_control"
})
SOURCE_HINTS = {
    "openlrr_menu": "src/openlrr/OpenLRR.cpp:OpenLRR_HandleCommand",
    "nerps": "src/openlrr/game/mission/NERPsFile.cpp:NERPsRuntime_Execute",
    "wine_api": "src/openlrr/engine/drawing/DirectDraw.cpp (comparison reference only)",
    "mac_input": "native/macos-menu/Sources/NativeMenu.swift (UI comparison reference)",
}
ID_DEFINE = re.compile(r"^\s*#define\s+(IDM_[A-Z0-9_]+)\s+(0x[0-9a-fA-F]+|\d+)\s*$")


def menu_constants(source_root: Path | None) -> dict[int, str]:
    if source_root is None:
        return {}
    file = source_root / "resources" / "resource.h"
    if not file.is_file() or file.is_symlink() or file.stat().st_size > 1_000_000:
        return {}
    found: dict[int, str] = {}
    for line in file.read_text(errors="replace").splitlines():
        match = ID_DEFINE.fullmatch(line.strip())
        if match:
            ident = int(match.group(2), 0)
            if 0 <= ident <= 65535:
                found[ident] = match.group(1)
    return found


def safe_number(n: Any, *, maximum: float = 1e14) -> float | None:
    if type(n) not in (float, int) or n < 0 or n > maximum:
        return None
    return float(n)


def first_capture_time(timeline: Path) -> float | None:
    if not timeline.is_file() or timeline.is_symlink():
        return None
    with timeline.open("r", encoding="utf-8", errors="replace") as file:
        for number, line in enumerate(file):
            if number > 1_000_000:
                return None
            if len(line) > 12_000:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if (isinstance(obj, dict) and obj.get("source") == "video" and
                    obj.get("event") == "capture_started"):
                t = safe_number(obj.get("unix_s"))
                if t is not None and 946684800 < t < 4102444800:
                    return t
    return None


def build_index(session: Path, clip_directory: Path,
                *, source_root: Path | None = None,
                clip_metadata: list[dict] | None = None,
                max_events_per_clip: int = 300) -> dict:
    """Index a finished session OR one newly finalized clip during play.

    Providing clip_metadata avoids requiring a session-ending clips.json.
    The original synchronized timeline stays intact for full reconstruction.
    """
    if not 1 <= max_events_per_clip <= 50_000:
        raise ValueError("Invalid per-clip event bound")
    if clip_metadata is None:
        manifest = clip_directory / "clips.json"
        if not manifest.is_file() or manifest.is_symlink() or manifest.stat().st_size > 1_000_000:
            raise ValueError("No verified, reasonably-sized clips.json manifest")
        data = json.loads(manifest.read_text())
    else:
        data = {"schema": "openlrr-window-video-clips-v1", "clips": clip_metadata}
    if data.get("schema") != "openlrr-window-video-clips-v1":
        raise ValueError("Unrecognized clip manifest")
    raw_clips = data.get("clips", [])
    if not isinstance(raw_clips, list) or len(raw_clips) > 500:
        raise ValueError("Unbounded clip manifest")
    clips = []
    for clip in raw_clips:
        if not isinstance(clip, dict):
            raise ValueError("Invalid clip metadata")
        name = clip.get("file")
        start = safe_number(clip.get("start_s"))
        duration = safe_number(clip.get("duration_s"), maximum=14400)
        size = safe_number(clip.get("bytes"))
        if (not isinstance(name, str) or not re.fullmatch(r"part-\d{4}\.mp4", name) or
                start is None or duration is None or duration <= 0 or size is None):
            raise ValueError("Unsafe clip metadata")
        clips.append({
            "file": name, "start_s": start, "duration_s": duration,
            "bytes": int(size), "sources": {}, "events": [], "events_omitted": 0
        })
    if len({c["file"] for c in clips}) != len(clips):
        raise ValueError("Duplicate clip filename")
    labels = menu_constants(source_root)
    timeline = session / "timeline.jsonl"
    origin = first_capture_time(timeline)
    examined = 0
    attached = 0
    missed = 0
    if origin is not None:
        with timeline.open("r", encoding="utf-8", errors="replace") as file:
            for i, raw in enumerate(file):
                if i >= 1_000_000:
                    break
                if len(raw) > 12_000:
                    continue
                try:
                    event = json.loads(raw)
                except ValueError:
                    continue
                if not isinstance(event, dict) or event.get("source") not in SAFE_SOURCES:
                    continue
                t = safe_number(event.get("unix_s"))
                if t is None:
                    continue
                elapsed = t - origin
                examined += 1
                matching = next((c for c in clips if
                                 c["start_s"] <= elapsed < c["start_s"] + c["duration_s"]),
                                None)
                if matching is None:
                    missed += 1
                    continue
                attached += 1
                source = event["source"]
                matching["sources"][source] = matching["sources"].get(source, 0) + 1
                # Fixed-vocabulary metadata only. Arbitrary text from Wine,
                # windows, user input and game data is deliberately ignored.
                row: dict[str, Any] = {
                    "source": source,
                    "at_s": round(elapsed - matching["start_s"], 3)
                }
                code = SOURCE_HINTS.get(source)
                if code:
                    row["source_hint"] = code
                menu_id = event.get("menu_id")
                if source == "openlrr_menu" and type(menu_id) is int and 0 <= menu_id <= 65535:
                    row["menu_id"] = menu_id
                    if menu_id in labels:
                        row["openlrr_command"] = labels[menu_id]
                function_id = event.get("function_id")
                if source == "nerps" and type(function_id) is int and 0 <= function_id < 294:
                    row["function_id"] = function_id
                    name = event.get("function")
                    if isinstance(name, str) and re.fullmatch(r"[A-Za-z0-9_]{1,80}", name):
                        row["function"] = name
                if source == "mac_input":
                    kind = event.get("event")
                    if kind in ("left_down", "left_up", "right_down", "right_up",
                                "key_down", "key_up", "scroll", "mouse_move"):
                        row["input_event"] = kind
                if source == "wine_api":
                    channel = event.get("channel")
                    if channel in ("ddraw", "d3drm", "d3d", "dsound", "dinput", "winmm"):
                        row["wine_channel"] = channel
                if len(matching["events"]) < max_events_per_clip:
                    matching["events"].append(row)
                else:
                    matching["events_omitted"] += 1
    return {
        "schema": SCHEMA,
        "time_basis": "host_unix_clock_relative_to_capture_started_approximate",
        "capture_unix_s": origin,
        "timeline_present": timeline.is_file() and not timeline.is_symlink(),
        "events_considered": examined,
        "events_aligned": attached,
        "events_outside_clips": missed,
        "source_mapping": SOURCE_HINTS,
        "no_nerps_trace_is_not_proof_scripts_did_not_run": True,
        "no_wine_trace_is_not_proof_no_windows_calls_occurred": True,
        "indexes_all_known_sources_without_fabricating_missing_logs": True,
        "clips": clips,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("session", type=Path)
    parser.add_argument("--clips", type=Path)
    parser.add_argument("--source-root", type=Path)
    args = parser.parse_args(argv)
    directory = args.clips or args.session / "clips"
    result = build_index(args.session, directory, source_root=args.source_root)
    output = directory / "analysis-index.json"
    if output.exists() or output.is_symlink():
        raise ValueError("Will not overwrite existing index")
    # Restrict output and never publish this metadata automatically.
    import os
    with os.fdopen(os.open(output, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600),
                   "w", encoding="utf-8") as file:
        json.dump(result, file, indent=2, sort_keys=True)
        file.write("\n")
    print("Indexed", len(result["clips"]), "clips:",
          result["events_aligned"], "timeline events aligned.")
    print("Local per-clip reference:", output)
    if result["capture_unix_s"] is None:
        print("No video start timestamp: visual clips available, input synchronization unavailable.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
