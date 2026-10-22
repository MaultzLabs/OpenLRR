#!/usr/bin/env python3
"""Try to recover an existing interrupted local Rock Raiders MP4 safely.

Never edits, truncates, re-encodes, overwrites or uploads the source.
AVFoundation can split a fully readable/valid MP4; if the final movie
index/metadata is missing, neither size nor this tool proves recovery.
"""
from __future__ import annotations

import argparse
import json
import os
import math
import re
from zipfile import ZIP_DEFLATED, ZipFile
from pathlib import Path
import subprocess
import sys

import capture
import video_session
import index_clips
import live_clip_index


MAX_CLIP_BYTES = 150 * 1024 * 1024


def validate_exported_clips(directory: Path) -> list[dict]:
    """Refuse a false success caused by a partial or mismatched MP4 export.

    AVFoundation also inspects decoded duration, video, and audio tracks.
    Python independently checks names, bounds and actual on-disk sizes.
    """
    listing = directory / "clips.json"
    if not listing.is_file() or listing.is_symlink() or listing.stat().st_size > 1_000_000:
        raise ValueError("No complete clip manifest")
    data = json.loads(listing.read_text(encoding="utf-8"))
    clips = data.get("clips")
    if (data.get("schema") != "openlrr-window-video-clips-v1" or
            not isinstance(clips, list) or not 1 <= len(clips) <= 500 or
            data.get("clip_count") != len(clips)):
        raise ValueError("Incomplete or invalid clip manifest")
    end = 0.0
    for number, clip in enumerate(clips, 1):
        if not isinstance(clip, dict):
            raise ValueError("Invalid clip metadata")
        filename = clip.get("file")
        if filename != f"part-{number:04d}.mp4":
            raise ValueError("Unexpected clip name or sequence")
        start, duration, size = (clip.get("start_s"),
                                 clip.get("duration_s"), clip.get("bytes"))
        if (type(start) not in (int, float) or not math.isfinite(start) or
                type(duration) not in (int, float) or not math.isfinite(duration) or
                type(size) is not int or duration <= 0 or
                abs(start - end) > .05 or not 4096 < size <= MAX_CLIP_BYTES):
            raise ValueError("Missing, oversized, or discontinuous clip")
        exported = clip.get("decoded_duration_s")
        if exported is not None and (
                type(exported) not in (int, float) or not math.isfinite(exported)
                or exported <= 0):
            raise ValueError("Invalid decoded MP4 duration")
        if "video_track_present" in clip and clip["video_track_present"] is not True:
            raise ValueError("Missing MP4 video track")
        path = directory / filename
        if not path.is_file() or path.is_symlink() or path.stat().st_size != size:
            raise ValueError("MP4 missing or size differs from manifest")
        end = start + duration
    return clips


def make_upload_bundle(directory: Path, clips: list[dict]) -> Path:
    """Bundle only locally sanitized telemetry and indices, never raw logs/MP4."""
    review = directory / "upload-evidence.zip"
    if review.exists() or review.is_symlink():
        raise ValueError("Will not overwrite an earlier upload bundle")
    names = ["clips.json", "analysis-index.json"]
    names += [f"part-{n:04d}.evidence.json"
              for n in range(1, len(clips) + 1)
              if (directory / f"part-{n:04d}.evidence.json").is_file()
              and not (directory / f"part-{n:04d}.evidence.json").is_symlink()]
    with ZipFile(review, "x", compression=ZIP_DEFLATED) as archive:
        for name in names:
            archive.write(directory / name, arcname=name)
        archive.writestr("UPLOAD-ORDER.txt",
                         "Attach upload-evidence.zip first, then the part-*.mp4 "
                         "files in sequence. All times are relative to the "
                         "original video start. Metadata indexes recorded "
                         "events only; it does not analyze frames or infer "
                         "missing internal NERPs/Wine calls. The original "
                         "master is not in this ZIP.\\n")
    os.chmod(review, 0o600)
    return review


def recover(source: Path, *, chunk_seconds: int = 120) -> int:
    if sys.platform != "darwin":
        raise capture.CaptureError("This tool requires macOS")
    if not source.is_file() or source.is_symlink() or source.suffix.lower() != ".mp4":
        raise capture.CaptureError("Expected an existing, non-symlinked MP4 file")
    if not 30 <= chunk_seconds <= 300:
        raise capture.CaptureError("Recovery clips must be 30–300 seconds")

    # Distinct destination. Never modify the input 557-MB file.
    destination = source.parent / "recovered-clips"
    if destination.exists() or destination.is_symlink():
        raise capture.CaptureError(
            "Recovery folder already exists. Inspect it before another attempt.")
    splitter = video_session.build_swift_video_tool(
        video_session.SPLIT_SWIFT, "game_video_split", main_struct=True)
    capture.make_private_dir(destination)
    print("Checking the original MP4 container. Its bytes will not be changed.")
    proc = subprocess.run(
        [str(splitter), str(source), str(destination), str(chunk_seconds)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        timeout=1800, check=False)
    manifest = destination / "clips.json"
    if proc.returncode != 0 or not manifest.is_file():
        print("The MP4 could not be split with Apple's built-in AVFoundation.",
              file=sys.stderr)
        print("Likely causes include an unfinalized MP4 index or a damaged file.",
              file=sys.stderr)
        print("KEEP THE ORIGINAL for future forensic recovery: " + str(source),
              file=sys.stderr)
        return 2
    try:
        clips = validate_exported_clips(destination)
    except (ValueError, OSError, json.JSONDecodeError) as error:
        print("Split output failed MP4 size/timestamp verification: " +
              str(error), file=sys.stderr)
        print("Original preserved: " + str(source), file=sys.stderr)
        return 2
    count = len(clips)
    # Align the safely recovered video with any earlier input/Wine records.
    # Missing telemetry remains explicit rather than being inferred.
    repo_root = Path(__file__).resolve().parents[4]
    correlation = index_clips.build_index(source.parent, destination,
                                          source_root=repo_root)
    (destination / "analysis-index.json").write_text(
        json.dumps(correlation, sort_keys=True, indent=2) + "\n",
        encoding="utf-8")
    os.chmod(destination / "analysis-index.json", 0o600)
    try:
        details = live_clip_index.index_existing_clips(source.parent, destination,
                                                       source_root=repo_root)
        print("Generated " + str(len(details)) +
              " private per-clip input/code evidence files.")
    except (ValueError, OSError) as error:
        # Never throw away playable video because old input telemetry is
        # unavailable, malformed, or a sidecar already exists.
        print("Recovered MP4s are safe, but per-clip evidence could not "
              "be indexed: " + type(error).__name__, file=sys.stderr)
    try:
        bundle = make_upload_bundle(destination, clips)
        print("Upload evidence ZIP: " + str(bundle))
    except (ValueError, OSError) as error:
        print("Clips are safe; optional upload bundle failed: " +
              str(error), file=sys.stderr)
    print("Recovery succeeded. Verified " + str(count) +
          " separate MP4 files at or below 150 MiB.")
    print("Recovery folder: " + str(destination))
    print("Original remains unchanged: " + str(source))
    try:
        subprocess.run(["/usr/bin/open", str(destination)],
                       stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, check=False, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        pass
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", type=Path,
                        help="existing interrupted game-window-master.mp4")
    parser.add_argument("--clip-seconds", type=int, default=120)
    args = parser.parse_args(argv)
    return recover(args.video, chunk_seconds=args.clip_seconds)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (capture.CaptureError, OSError, subprocess.TimeoutExpired) as exc:
        print("Recovery stopped without changing the source: " + str(exc),
              file=sys.stderr)
        raise SystemExit(1)
