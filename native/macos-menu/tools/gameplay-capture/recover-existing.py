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
from pathlib import Path
import subprocess
import sys

import capture
import video_session


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
    data = json.loads(manifest.read_text())
    count = data.get("clip_count")
    print("Recovery succeeded. Created " + str(count) + " separate MP4 clips.")
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
