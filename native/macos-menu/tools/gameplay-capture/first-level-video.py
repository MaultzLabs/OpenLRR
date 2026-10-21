#!/usr/bin/env python3
"""One paste: launch original OpenLRR, record real WINDOW VIDEO + game controls.

Keeps complete master MP4 private, automatically splits it into <=180MiB
5-minute clips, and creates a sanitized timeline ZIP, all local. No upload.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

import capture
import video_session

LAUNCHER = Path(__file__).resolve().parent / "first-level.py"
spec = importlib.util.spec_from_file_location("original_game_launcher", LAUNCHER)
if spec is None or spec.loader is None:
    raise RuntimeError("Original-game launcher not found")
first = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = first
spec.loader.exec_module(first)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--app", type=Path, help="explicit original Wine OpenLRR .app")
    ap.add_argument("--diagnose", action="store_true",
                    help="report only safe window counts and permission; do not launch or record")
    ap.add_argument("--fps", type=int, default=30,
                    help="continuous MP4 requested FPS (default 30)")
    ap.add_argument("--clip-minutes", type=int, default=5,
                    help="target segment length (1–10 min; default 5)")
    ap.add_argument("--session", choices=("menu", "full"), default="full",
                    help="menu: 15-minute diagnostic recording; full: menu through tutorial (default)")
    ap.add_argument("--max-minutes", type=int,
                    help="optional safety limit; defaults to 15 min menu / 120 min full")
    ap.add_argument("--wait-seconds", type=int, default=360)
    ap.add_argument("--wine-log", type=Path,
                    help="optional existing Wine debug log, raw text stays local")
    ap.add_argument("--nerps-log", type=Path,
                    help="optional existing instrumented NERPs JSONL stream")
    ap.add_argument("--no-input", action="store_true",
                    help="disable game-key and mouse-event capture")
    args = ap.parse_args(argv)
    if sys.platform != "darwin":
        raise capture.CaptureError("Continuous window video requires macOS")
    if not 1 <= args.fps <= 60:
        raise capture.CaptureError("Video FPS must be 1–60")
    if not 1 <= args.clip_minutes <= 10:
        raise capture.CaptureError("Clips must be 1–10 minutes")
    if args.max_minutes is None:
        args.max_minutes = 15 if args.session == "menu" else 120
    if not 1 <= args.max_minutes <= 240:
        raise capture.CaptureError("Session duration must be 1–240 minutes")
    if not 10 <= args.wait_seconds <= 900:
        raise capture.CaptureError("Game window wait must be 10–900 seconds")

    if args.diagnose:
        # No video tool compilation, no game launch and no capture.
        finder = capture.WindowProbe(capture.build_probe())
        info = finder.diagnose()
        print(json.dumps(info, sort_keys=True))
        if info.get("screen_recording_permission") is False:
            print("Terminal needs Screen Recording permission. "
                  "See System Settings > Privacy & Security > "
                  "Screen & System Audio Recording. Then restart Terminal.")
        elif info.get("wine_like_windows", 0) > 0 and not info.get("eligible_game_windows", 0):
            print("Wine windows exist, but they have no verified Rock Raiders "
                  "title. No unrelated window will be recorded.")
        return 0

    # Compile all helpers before launching, avoiding a long compiler pause
    # after the game appears. None modifies the Wine prefix or game files.
    video_binary, split_binary = video_session.build_video_tools()
    input_binary = None if args.no_input else capture.build_probe()
    finder_probe = capture.WindowProbe(input_binary or capture.build_probe())
    print("Continuous 30-FPS-style game-window recording prepared.", flush=True)
    print("Recording ONLY your Rock Raiders window, no desktop, no upload.",
          flush=True)

    game_windows = finder_probe.list_games()
    if len(game_windows) > 1:
        raise capture.CaptureError("More than one Rock Raiders window open")
    if not game_windows:
        application = first.choose_application(
            args.app, first.find_normal_game_apps())
        if application is not None:
            print("Opening original Wine game: " + str(application), flush=True)
            result = subprocess.run(["/usr/bin/open", str(application)],
                                    capture_output=True, text=True,
                                    timeout=20, check=False)
            if result.returncode != 0:
                print("Could not start automatically. Open your original "
                      "Rock Raiders Wine app manually.", flush=True)

    if args.session == "menu":
        print("MENU DIAGNOSTIC: interact with the slow or black main menu.", flush=True)
        print("No need to reach a mission. Quit normally when finished.", flush=True)
    else:
        print("FULL SESSION: menu first, then attempt tutorial/gameplay.", flush=True)
        print("The slow menu is valuable and is INCLUDED, not skipped.", flush=True)
    print("Video and inputs stop at game-window closure or the safety limit.",
          flush=True)
    game = first.wait_for_game(finder_probe, args.wait_seconds)
    session = capture.next_session_path(capture.DEFAULT_OUTPUT)
    print("Recording original game window #" + str(game.id) +
          " to a private local MP4.", flush=True)
    result = video_session.continuous_capture(
        finder_probe, game, session, video_binary,
        video_fps=args.fps, max_seconds=args.max_minutes * 60,
        wine_log=args.wine_log, nerps_log=args.nerps_log,
        input_binary=input_binary)
    if not result["video_complete"]:
        print("Video did not finalize successfully. Review the local"
              " diagnostic timeline: " + str(session), file=sys.stderr)
        return 2

    print("Full-resolution video saved locally. Splitting into shareable clips…",
          flush=True)
    clips = video_session.split_private_video(
        split_binary, session, seconds=args.clip_minutes * 60)
    info = json.loads((clips / "clips.json").read_text())
    archive = session.with_name(session.name + "-timeline-review.zip")
    count = capture.package_review(session, archive, include_frames=False)
    print("Recorded " + args.session + " video + synchronized inputs.")
    print("Ready-to-share video clips: " + str(clips))
    print("Clip count: " + str(info["clip_count"]))
    print("Timeline review ZIP: " + str(archive))
    print("Original master video remains at: " + str(session))
    print("Share the clips and timeline ZIP after reviewing them.")
    # Finder only REVEALS the local clips, never sends any files.
    try:
        subprocess.run(["/usr/bin/open", str(clips)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       timeout=12, check=False)
    except (OSError, subprocess.TimeoutExpired):
        pass
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (capture.CaptureError, OSError, subprocess.TimeoutExpired) as error:
        print("Capture stopped safely: " + str(error), file=sys.stderr)
        raise SystemExit(1)
