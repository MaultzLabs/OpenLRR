#!/usr/bin/env python3
"""Emit safe code-and-input evidence as each Rock Raiders MP4 closes.

Called from ScreenCaptureKit segment_complete; entirely local. No paid API,
upload, screenshots or new Wine/game instrumentation. Only finalized clips
are indexed. The original timeline remains available for full inspection.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

import index_clips

MAX_UPLOAD_BYTES = 180 * 1024 * 1024
MAX_EVENT_PREVIEW = 20_000


class LiveClipIndexer:
    def __init__(self, session: Path, clips: Path,
                 *, source_root: Path | None = None) -> None:
        self.session = session
        self.clips = clips
        self.source_root = source_root
        self.indexed_parts: set[int] = set()

    @staticmethod
    def _validate_finished_segment(segment: dict[str, Any]) -> dict[str, Any]:
        part = segment.get("part")
        name = segment.get("file")
        start = segment.get("start_s")
        duration = segment.get("duration_s")
        size = segment.get("bytes")
        if (type(part) is not int or not 1 <= part <= 9999 or
                name != f"part-{part:04d}.mp4" or
                type(start) not in (int, float) or not 0 <= start < 14400 or
                type(duration) not in (int, float) or not 0 < duration <= 600 or
                type(size) is not int or not 4096 < size < 10**10):
            raise ValueError("Unsafe or incomplete finalized clip metadata")
        return {
            "part": part, "file": name, "start_s": start,
            "duration_s": duration, "bytes": size,
            "audio_track_present": segment.get("audio_track_present") is True
        }

    def write(self, segment: dict[str, Any]) -> Path:
        """Write once upon finalization, while the next MP4 records."""
        clip = self._validate_finished_segment(segment)
        if clip["part"] in self.indexed_parts:
            raise ValueError("Duplicate finalized clip event")
        source_video = self.clips / clip["file"]
        if (not source_video.is_file() or source_video.is_symlink() or
                source_video.stat().st_size != clip["bytes"]):
            raise ValueError("Cannot index a missing or unfinished MP4")
        data = index_clips.build_index(
            self.session, self.clips, source_root=self.source_root,
            clip_metadata=[{key: clip[key] for key in
                            ("file", "start_s", "duration_s", "bytes")}],
            max_events_per_clip=MAX_EVENT_PREVIEW)
        matches = data["clips"][0]
        under_budget = clip["bytes"] <= MAX_UPLOAD_BYTES
        sidecar: dict[str, Any] = {
            "schema": "openlrr-live-clip-evidence-v1",
            "video": clip["file"],
            "start_s": clip["start_s"],
            "duration_s": clip["duration_s"],
            "bytes": clip["bytes"],
            "audio_track_present": clip["audio_track_present"],
            "under_180_mib_target": under_budget,
            "upload_ready_size_only": under_budget,
            "events_by_source": matches["sources"],
            "events_indexed": len(matches["events"]),
            "events_omitted": matches["events_omitted"],
            "events": matches["events"],
            "capture_unix_s": data["capture_unix_s"],
            "time_basis": data["time_basis"],
            "source_mapping": data["source_mapping"],
            "nerps_captured": matches["sources"].get("nerps", 0) > 0,
            "wine_captured": matches["sources"].get("wine_api", 0) > 0,
            "warning": (
                "Approximate host time correlation; no claims of pixel-level "
                "video analysis or undocumented game-code execution."
            ),
        }
        filename = self.clips / f"part-{clip['part']:04d}.evidence.json"
        with os.fdopen(os.open(filename, os.O_CREAT | os.O_EXCL | os.O_WRONLY,
                               0o600), "w", encoding="utf-8") as output:
            json.dump(sidecar, output, sort_keys=True, indent=2)
            output.write("\n")
        self.indexed_parts.add(clip["part"])
        return filename


def index_existing_clips(session: Path, clips: Path,
                         *, source_root: Path | None = None) -> list[Path]:
    """Make the same private evidence sidecars for older split recordings."""
    manifest = clips / "clips.json"
    if not manifest.is_file() or manifest.is_symlink():
        raise ValueError("Original local video clips manifest is missing")
    data = json.loads(manifest.read_text())
    if data.get("schema") != "openlrr-window-video-clips-v1":
        raise ValueError("Unrecognized clip format")
    writer = LiveClipIndexer(session, clips, source_root=source_root)
    outputs = []
    entries = data.get("clips", [])
    if not isinstance(entries, list) or len(entries) > 500:
        raise ValueError("Unbounded clip manifest")
    for clip in entries:
        if not isinstance(clip, dict):
            raise ValueError("Unsafe clip manifest entry")
        name = clip.get("file")
        if not isinstance(name, str) or not name.startswith("part-") or not name.endswith(".mp4"):
            raise ValueError("Unsafe clip name")
        part = int(name[5:9]) if len(name) == 13 and name[5:9].isdigit() else 0
        outputs.append(writer.write({
            "part": part,
            "file": name,
            "start_s": clip.get("start_s"),
            "duration_s": clip.get("duration_s"),
            "bytes": clip.get("bytes"),
            "audio_track_present": clip.get("audio_track_present") is True
            # Unknown legacy audio track stays explicitly unattested.
        }))
    return outputs
