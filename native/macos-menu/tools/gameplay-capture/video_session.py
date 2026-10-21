#!/usr/bin/env python3
"""Continuous ScreenCaptureKit game-window video + synchronized game input.

No screenshots, no desktop capture, no unrelated sound, no automatic upload.
The original retail/Wine game is unmodified. Raw Wine logs remain private.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time
from typing import Any

import capture

ROOT = Path(__file__).resolve().parent
VIDEO_SWIFT = ROOT / "game_video.swift"
SPLIT_SWIFT = ROOT / "video_split.swift"
ALLOWED_VIDEO_EVENTS = {
    "recording_started", "capture_started", "capture_stopping",
    "recording_finalized", "recording_failed", "stream_failed",
    "target_missing", "capture_error", "finalization_unverified",
    "video_too_small", "video_complete",
}
ALLOWED_STOP_REASONS = {
    "game_window_closed", "parent_stopped", "stream_error", "time_limit"
}


def build_swift_video_tool(source: Path, label: str, *, main_struct: bool) -> Path:
    if sys.platform != "darwin":
        raise capture.CaptureError("Continuous game-window video requires macOS")
    compiler = shutil.which("xcrun")
    if not compiler:
        raise capture.CaptureError("Apple Command Line Tools/Xcode missing")
    capture.make_private_dir(capture.CACHE)
    dest = capture.CACHE / label
    marker = capture.CACHE / (label + ".sha256")
    digest = __import__("hashlib").sha256(source.read_bytes()).hexdigest()
    if dest.is_file() and not dest.is_symlink() and marker.is_file() and marker.read_text() == digest:
        return dest
    temp = capture.CACHE / (label + ".building")
    options = [compiler, "swiftc", "-O",
               "-target", "arm64-apple-macos15.0",
               "-framework", "Cocoa", "-framework", "CoreGraphics",
               "-framework", "CoreMedia", "-framework", "ScreenCaptureKit",
               "-framework", "AVFoundation"]
    if main_struct:
        options += ["-parse-as-library"]
    options += [str(source), "-o", str(temp)]
    result = subprocess.run(options, capture_output=True, text=True,
                            timeout=180, check=False)
    if result.returncode:
        raise capture.CaptureError("ScreenCaptureKit Swift tool compile failed:\n" +
                                   result.stderr[-4000:])
    os.replace(temp, dest)
    os.chmod(dest, 0o700)
    marker.write_text(digest)
    os.chmod(marker, 0o600)
    return dest


def build_video_tools() -> tuple[Path, Path]:
    return (build_swift_video_tool(VIDEO_SWIFT, "game_window_video", main_struct=False),
            build_swift_video_tool(SPLIT_SWIFT, "game_video_split", main_struct=True))


def pump_video_stdout(pipe: Any, timeline: capture.Timeline, state: dict) -> None:
    for line in pipe:
        if len(line) > 4096:
            continue
        try:
            obj = json.loads(line)
        except (ValueError, UnicodeError):
            continue
        if not isinstance(obj, dict) or obj.get("source") != "video":
            continue
        event = obj.get("event")
        if event not in ALLOWED_VIDEO_EVENTS:
            continue
        safe: dict[str, Any] = {"source": "video", "event": event}
        for field in ("unix_s", "monotonic_s", "window_id", "fps_target",
                      "bytes", "duration_s"):
            value = obj.get(field)
            if type(value) in (int, float) and abs(value) < 1e14:
                safe[field] = value
        for field in ("audio_requested", "audio_track_present", "microphone"):
            value = obj.get(field)
            if type(value) is bool:
                safe[field] = value
        if obj.get("audio_scope") == "owning_application":
            safe["audio_scope"] = "owning_application"
        for field in ("scope", "stop_reason"):
            value = obj.get(field)
            if field == "scope" and value == "single_game_window":
                safe[field] = value
            if field == "stop_reason" and value in ALLOWED_STOP_REASONS:
                safe[field] = value
        timeline.write(safe)
        if event == "capture_started":
            state["capture_started"] = True
            state["video_start_unix_s"] = safe.get("unix_s")
        if event == "video_complete":
            state["video_complete"] = True
            state["video_duration_s"] = safe.get("duration_s", 0.0)
            state["audio_track_present"] = safe.get("audio_track_present", False)
        if event in ("recording_failed", "stream_failed", "capture_error",
                     "target_missing", "finalization_unverified"):
            state["video_failed"] = True


def continuous_capture(
    probe: capture.WindowProbe,
    game: capture.GameWindow,
    session: Path,
    video_binary: Path,
    *,
    video_fps: int = 30,
    max_seconds: int = 7200,
    wine_log: Path | None = None,
    nerps_log: Path | None = None,
    input_binary: Path | None = None
) -> dict:
    if type(video_fps) is not int or not 1 <= video_fps <= 60:
        raise capture.CaptureError("Video FPS must be 1–60")
    if not 1 <= max_seconds <= capture.MAX_CAPTURE_SECONDS:
        raise capture.CaptureError("Maximum duration must be 1 second–4 hours")
    capture.make_private_dir(session)
    full_video = session / "game-window-master.mp4"
    if full_video.exists() or full_video.is_symlink():
        raise capture.CaptureError("Refusing to overwrite existing game video")
    timeline = capture.Timeline(session / "timeline.jsonl")
    raw_wine: capture.BoundedTraceFollower | None = None
    nerps: capture.NerpsFollower | None = None
    monitor: subprocess.Popen | None = None
    input_thread: threading.Thread | None = None
    recording: subprocess.Popen | None = None
    video_thread: threading.Thread | None = None
    stop = threading.Event()
    state: dict = {}
    started = time.monotonic()
    began = time.time()
    reason = "video_not_started"
    try:
        if wine_log is not None:
            raw_wine = capture.BoundedTraceFollower(
                wine_log, session / "wine_raw.local.log")
        if nerps_log is not None:
            nerps = capture.NerpsFollower(nerps_log)
        # The Swift helper has a strict same-window/PID guard independent
        # from this Python supervisor; close automatically stops both.
        recording = subprocess.Popen(
            [str(video_binary), str(game.id), str(game.pid),
             str(full_video), str(video_fps), str(max_seconds)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, bufsize=1)
        video_thread = threading.Thread(target=pump_video_stdout,
                                        args=(recording.stdout, timeline, state),
                                        daemon=True)
        video_thread.start()
        if input_binary is not None:
            monitor = subprocess.Popen(
                [str(input_binary), "events", str(game.id), str(game.pid)],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                text=True, bufsize=1)
            input_thread = threading.Thread(
                target=capture.pump_input_events,
                args=(monitor.stdout, game, timeline, stop), daemon=True)
            input_thread.start()
        timeline.write({
            "source": "capture_control", "event": "start",
            "unix_s": began, "monotonic_s": started,
            "window_id": game.id, "scope": "game_window_only",
            "mode": "continuous_h264_video",
            "input_enabled": input_binary is not None
        })
        while True:
            if not probe.inspect(game).get("exists"):
                reason = "game_window_closed"
                break
            if recording.poll() is not None:
                reason = "video_process_exited"
                break
            if time.monotonic() - started >= max_seconds:
                reason = "time_limit"
                break
            if raw_wine is not None:
                raw_wine.sample(timeline)
            if nerps is not None:
                nerps.sample(timeline)
            time.sleep(0.4)
    except KeyboardInterrupt:
        reason = "user_stopped"
    finally:
        stop.set()
        if recording is not None:
            if recording.poll() is None and recording.stdin:
                try:
                    recording.stdin.write("STOP\n")
                    recording.stdin.flush()
                except (OSError, BrokenPipeError):
                    pass
            if recording.stdin:
                recording.stdin.close()
            try:
                recording.wait(timeout=28)
            except subprocess.TimeoutExpired:
                recording.terminate()
                try:
                    recording.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    recording.kill()
                    recording.wait()
            if video_thread is not None:
                video_thread.join(timeout=2)
            if recording.stdout is not None:
                recording.stdout.close()
        if monitor is not None:
            monitor.terminate()
            try:
                monitor.wait(timeout=3)
            except subprocess.TimeoutExpired:
                monitor.kill()
                monitor.wait()
            if monitor.stdout is not None:
                monitor.stdout.close()
        if input_thread is not None:
            input_thread.join(timeout=2)
        if raw_wine is not None:
            raw_wine.close()
        timeline.write({
            "source": "capture_control", "event": "stop",
            "unix_s": time.time(), "monotonic_s": time.monotonic(),
            "window_id": game.id, "reason": reason
        })
        timeline.close()
        good = (state.get("video_complete") is True and
                not state.get("video_failed", False) and
                recording is not None and recording.returncode == 0 and
                full_video.is_file() and full_video.stat().st_size > 4096)
        if not good and full_video.exists():
            # Keep incomplete MP4 locally for debugging, but never package or
            # describe it as a valid gameplay recording.
            os.chmod(full_video, 0o600)
        result = {
            "schema_version": 2,
            "scope": "game_window_only",
            "mode": "continuous_h264_video",
            "target_window_id": game.id,
            "capture_started_utc": capture.iso_now(),
            "capture_ended_utc": capture.iso_now(),
            "stop_reason": reason,
            "video_complete": good,
            "video_filename": "game-window-master.mp4" if good else None,
            "video_duration_s": state.get("video_duration_s") if good else None,
            "video_start_unix_s": state.get("video_start_unix_s"),
            "video_fps_target": video_fps,
            "app_audio_requested": True,
            "app_audio_scope": "owning_application",
            "audio_track_present": state.get("audio_track_present", False) if good else False,
            "microphone_recorded": False,
            "input_monitor_requested": input_binary is not None,
            "wine_trace_captured_locally": raw_wine is not None,
            "wine_log_batches": raw_wine.events.batches_written if raw_wine else 0,
            "wine_log_time_basis": "host_log_read_not_game_call_time",
            "nerps_trace_source_attached": nerps is not None,
            "raw_trace_upload_allowed": False,
            "automatic_github_upload": False,
        }
        manifest = session / "manifest.json"
        with os.fdopen(os.open(manifest, os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                               0o600), "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, sort_keys=True)
            f.write("\n")
    return result


def split_private_video(binary: Path, session: Path, *, seconds: int = 300) -> Path:
    if not 30 <= seconds <= 600:
        raise capture.CaptureError("Video clip length must be 30–600 seconds")
    source = session / "game-window-master.mp4"
    if not source.is_file():
        raise capture.CaptureError("No complete master video available")
    destination = session / "clips"
    capture.make_private_dir(destination)
    proc = subprocess.run(
        [str(binary), str(source), str(destination), str(seconds)],
        stdin=subprocess.DEVNULL, capture_output=True, text=True,
        timeout=1800, check=False)
    if proc.returncode != 0 or not (destination / "clips.json").is_file():
        raise capture.CaptureError(
            "Video captured locally but automatic splitting failed. "
            "The intact master recording is still in " + str(session))
    return destination
