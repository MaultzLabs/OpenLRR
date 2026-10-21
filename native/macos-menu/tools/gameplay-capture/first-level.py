#!/usr/bin/env python3
"""One-paste, one-session Rock Raiders capture coordinator for macOS.

Starts ONLY a confidently identified normal Rock Raiders Wine app (never a
test/native app). Waits for exactly one verified game window, follows gameplay
until that exact window closes, and packages its *sanitized* local observations.
No GitHub upload, original game modification, system-wide video, or injected DLL.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import time

import capture

APP_TERMS = ("rock raiders", "openlrr", "legorr")
FORBIDDEN_TERMS = ("test", "native", "prototype", "benchmark", "diagnostic")
WAIT_SECONDS_DEFAULT = 360


def is_normal_game_app(path: Path) -> bool:
    """Only a real, local macOS bundle whose own name identifies the game."""
    if path.is_symlink() or not path.is_dir() or path.suffix.lower() != ".app":
        return False
    name = path.stem.lower()
    if not any(term in name for term in APP_TERMS):
        return False
    if any(term in name for term in FORBIDDEN_TERMS):
        return False
    # Don't follow symlinks or assume a random folder called "Game.app".
    return (path / "Contents" / "Info.plist").is_file()


def find_normal_game_apps(home: Path | None = None) -> list[Path]:
    home = home or Path.home()
    roots = [home / "Applications" / "Sikarugir", home / "Applications",
             Path("/Applications")]
    # Deliberately search limited known application locations, not personal
    # documents, external disks, or arbitrary executable files.
    matches: dict[str, Path] = {}
    for root in roots:
        if not root.is_dir() or root.is_symlink():
            continue
        for pattern in ("*.app", "*/*.app", "*/*/*.app"):
            for path in root.glob(pattern):
                if is_normal_game_app(path):
                    matches[str(path)] = path
    return sorted(matches.values(), key=lambda x: str(x).lower())


def wait_for_game(probe: capture.WindowProbe, timeout: float,
                  *, interval: float = 0.75,
                  clock=time.monotonic,
                  sleep=time.sleep) -> capture.GameWindow:
    """Only accept one window; never guess between multiple candidates."""
    deadline = clock() + timeout
    last_notice = clock()
    while clock() < deadline:
        windows = probe.list_games()
        if len(windows) == 1:
            try:
                return capture.select_game_window(probe, None)
            except capture.CaptureError:
                # A game can close between enumeration and identification.
                pass
        elif len(windows) > 1:
            ids = ", ".join(str(row.get("id", "?")) for row in windows[:8])
            raise capture.CaptureError(
                "Multiple Rock Raiders windows visible (" + ids +
                "). Close the extra game windows, then run this command again.")
        if clock() - last_notice >= 20:
            print("Waiting for the original Rock Raiders main menu…", flush=True)
            last_notice = clock()
        sleep(interval)
    raise capture.CaptureError(
        "Timed out waiting for an original Rock Raiders window. "
        "The game might use a different window title. "
        "Nothing was recorded or uploaded.")


def choose_application(explicit: Path | None, discovered: list[Path]) -> Path | None:
    if explicit is not None:
        if not is_normal_game_app(explicit):
            raise capture.CaptureError(
                "The selected app is not a recognized normal game bundle. "
                "Menu Test and native prototype apps are refused.")
        return explicit
    if len(discovered) == 1:
        return discovered[0]
    if len(discovered) > 1:
        # When both retail and OpenLRR wrappers exist, prefer the one the
        # user requested. Never select an app whose name says TEST/native.
        openlrr = [app for app in discovered if app.stem.lower() == "openlrr"]
        if len(openlrr) == 1:
            return openlrr[0]
        print("More than one normal game app found; not guessing which to start:")
        for app in discovered:
            print("  " + str(app))
        print("Open your preferred ORIGINAL Wine Rock Raiders app manually.")
    else:
        print("No known normal game app found under ~/Applications or /Applications.")
        print("Open your ORIGINAL Rock Raiders Wine app manually.")
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path,
                        help="optional original Rock Raiders Wine .app to open")
    parser.add_argument("--fps", type=int, default=4,
                        help="window screenshots per second, 1–10 (default 4)")
    parser.add_argument("--wait-seconds", type=int, default=WAIT_SECONDS_DEFAULT)
    parser.add_argument("--max-minutes", type=float, default=120)
    parser.add_argument("--wine-log", type=Path,
                        help="optional existing Wine debug log, captured locally")
    parser.add_argument("--nerps-log", type=Path,
                        help="optional existing instrumented NERPs JSONL log")
    parser.add_argument("--no-input", action="store_true",
                        help="disable input event listener")
    args = parser.parse_args(argv)
    if sys.platform != "darwin":
        raise capture.CaptureError("This capture launcher requires macOS")
    if not (1 <= args.fps <= 10):
        raise capture.CaptureError("Select 1–10 captures per second")
    if not (10 <= args.wait_seconds <= 900):
        raise capture.CaptureError("Window wait must be 10–900 seconds")
    if not (1 <= args.max_minutes <= 240):
        raise capture.CaptureError("Capture duration must be 1–240 minutes")

    # Compile the existing trusted, window-scoped probe *before* opening game.
    probe_bin = capture.build_probe()
    probe = capture.WindowProbe(probe_bin)
    print("Rock Raiders game-window-only capture is ready.", flush=True)
    print("No desktop recording, no automatic upload, no game-file edits.",
          flush=True)

    current = probe.list_games()
    if len(current) > 1:
        raise capture.CaptureError(
            "Multiple game windows already visible; close extra windows first.")
    if not current:
        application = choose_application(args.app, find_normal_game_apps())
        if application is not None:
            print("Opening original Wine app: " + str(application), flush=True)
            launched = subprocess.run(["/usr/bin/open", str(application)],
                                      capture_output=True, text=True,
                                      timeout=20, check=False)
            if launched.returncode != 0:
                print("Automatic app launch was unsuccessful. "
                      "Open Rock Raiders normally.", flush=True)
    else:
        print("Existing game detected; not launching another copy.", flush=True)

    print("Please play the first mission normally, then QUIT the game.",
          flush=True)
    print("Closing the game window will automatically stop the recorder.",
          flush=True)
    target = wait_for_game(probe, args.wait_seconds)
    session = capture.next_session_path(capture.DEFAULT_OUTPUT)
    print("Recording game window #" + str(target.id) + ".")
    print("Private session: " + str(session), flush=True)

    result = capture.capture_loop(
        probe, target, session, fps=args.fps,
        max_seconds=args.max_minutes * 60,
        wine_log=args.wine_log, nerps_log=args.nerps_log,
        event_exe=None if args.no_input else probe_bin)
    if result["frame_count"] == 0:
        print("No screenshot frames were obtained. "
              "Check Terminal Screen Recording permission before retrying.",
              flush=True)
        print("Session diagnostics: " + str(session), flush=True)
        return 2

    archive = session.with_name(session.name + "-review.zip")
    records = capture.package_review(session, archive, include_frames=True)
    print("\nCapture finished: " + result["stop_reason"])
    print("Frames: " + str(result["frame_count"]) +
          "; timestamped timeline entries: " + str(records))
    print("PRIVATE REVIEW ZIP: " + str(archive), flush=True)
    print("Raw Wine log stays local and is NOT included in the ZIP.",
          flush=True)
    print("Share the review ZIP in ChatGPT after checking its contents.")
    # Finder only selects the already-created local ZIP; it never uploads.
    try:
        subprocess.run(["/usr/bin/open", "-R", str(archive)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       timeout=12, check=False)
    except (OSError, subprocess.TimeoutExpired):
        pass  # The location above is still printed for manual selection.
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (capture.CaptureError, OSError, subprocess.TimeoutExpired) as exc:
        print("Capture could not start safely: " + str(exc), file=sys.stderr)
        raise SystemExit(1)
