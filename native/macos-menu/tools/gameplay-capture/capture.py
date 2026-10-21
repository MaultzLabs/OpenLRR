#!/usr/bin/env python3
"""Window-only Rock Raiders research capture. No desktop capture, no auto-upload.

Run on macOS with the ORIGINAL Windows game already open in Wine/Wineskin.
The parent process never launches/replaces/modifies LegoRR.exe, any DLL, or Wine.
When the precise window ID disappears, every capture and input helper stops.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time
from typing import Any, Callable
import zipfile

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "window_probe.swift"
CACHE = Path.home() / "Library/Caches/OpenLRR-GameplayCapture"
DEFAULT_OUTPUT = Path.home() / "Movies/OpenLRR Gameplay Captures"
MAX_CAPTURE_SECONDS = 4 * 60 * 60
MAX_LOCAL_TRACE_BYTES = 20_000_000
ALLOWED_EVENT_NAMES = {
    "left_down", "left_up", "right_down", "right_up", "mouse_move",
    "scroll", "key_down", "key_up", "game_window_closed"
}
ALLOWED_NERPS_FIELDS = {"function", "opcode", "instruction", "args", "pc", "frame"}
MAX_INPUT_LINE = 4096


class CaptureError(RuntimeError):
    pass


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def make_private_dir(directory: Path) -> None:
    if directory.is_symlink():
        raise CaptureError("Refusing a symlinked output directory")
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    if directory.is_symlink():
        raise CaptureError("Output directory changed to a symlink")
    os.chmod(directory, 0o700)


def json_line(obj: dict[str, Any]) -> str:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n"


@dataclass(frozen=True)
class GameWindow:
    id: int
    pid: int

    @classmethod
    def from_record(cls, item: dict) -> "GameWindow":
        wid, pid = item.get("id"), item.get("pid")
        if type(wid) is not int or type(pid) is not int or wid <= 0 or pid <= 0:
            raise CaptureError("Invalid game window identity")
        return cls(wid, pid)


class WindowProbe:
    def __init__(self, executable: Path):
        self.executable = executable

    def _run(self, *args: str) -> list[dict]:
        result = subprocess.run([str(self.executable), *args],
                                capture_output=True, text=True, timeout=8,
                                check=False)
        if result.returncode:
            raise CaptureError("Window probe failed (screen/window access or identity)")
        rows = []
        for line in result.stdout.splitlines():
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                raise CaptureError("Window probe returned invalid JSON") from exc
            if not isinstance(row, dict):
                raise CaptureError("Window probe returned invalid record")
            rows.append(row)
        return rows

    def list_games(self) -> list[dict]:
        return self._run("list")

    def inspect(self, target: GameWindow) -> dict:
        rows = self._run("inspect", str(target.id), str(target.pid))
        if len(rows) != 1:
            raise CaptureError("Game window probe did not return one identity")
        row = rows[0]
        if row.get("id") != target.id or row.get("pid") != target.pid:
            raise CaptureError("Game window identity changed")
        return row


def select_game_window(probe: WindowProbe, window_id: int | None) -> GameWindow:
    games = probe.list_games()
    if window_id is not None:
        games = [game for game in games if game.get("id") == window_id]
    if len(games) != 1:
        raise CaptureError(
            "Expected exactly one visible Rock Raiders game window. "
            "Open the game first and use 'list' to select its --window-id."
        )
    target = GameWindow.from_record(games[0])
    if probe.inspect(target).get("exists") is not True:
        raise CaptureError("Game window closed before recording started")
    return target


def build_probe() -> Path:
    if sys.platform != "darwin":
        raise CaptureError("Game window capture only runs on macOS")
    if not SOURCE.is_file():
        raise CaptureError("Native game-window probe source missing")
    compiler = shutil.which("xcrun")
    if not compiler:
        raise CaptureError("Apple Xcode Command Line Tools required (xcrun missing)")
    make_private_dir(CACHE)
    exe = CACHE / "game_window_probe"
    digest = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    marker = CACHE / "probe_sha256"
    if exe.is_file() and marker.is_file() and marker.read_text() == digest:
        return exe
    temporary = CACHE / "probe.building"
    command = [compiler, "swiftc", "-O", "-framework", "Cocoa",
               "-framework", "CoreGraphics", str(SOURCE), "-o", str(temporary)]
    result = subprocess.run(command, capture_output=True, text=True, timeout=180,
                            check=False)
    if result.returncode:
        raise CaptureError("Swift window probe compilation failed:\n" +
                           result.stderr[-6000:])
    os.replace(temporary, exe)
    os.chmod(exe, 0o700)
    marker.write_text(digest)
    return exe


class Timeline:
    """Thread-safe, local-only newline JSON. Raw logs never go here."""

    def __init__(self, path: Path):
        self._file = os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                                      0o600), "w", encoding="utf-8")
        self._lock = threading.Lock()

    def write(self, event: dict) -> None:
        with self._lock:
            self._file.write(json_line(event))
            self._file.flush()

    def close(self) -> None:
        with self._lock:
            self._file.close()



# This is a deliberately low-resolution *observation* of Wine log output,
# not a timestamp supplied by the game, not a native call trace, and not a
# substitute for instrumenting NERPs inside a reviewed Windows build.
_WINE_TAG = re.compile(
    r"(?<![A-Za-z])(trace|fixme|warn|err):(ddraw|d3drm|d3d|dsound|dinput|winmm):",
    flags=re.IGNORECASE,
)
_WINE_OPERATIONS = (
    ("bltfast", re.compile(r"(?<![a-z])bltfast(?![a-z])", re.I)),
    ("blt", re.compile(r"(?<![a-z])blt(?![a-z])", re.I)),
    ("flip", re.compile(r"(?<![a-z])flip(?![a-z])", re.I)),
    ("unlock", re.compile(r"(?<![a-z])unlock(?![a-z])", re.I)),
    ("lock", re.compile(r"(?<![a-z])lock(?![a-z])", re.I)),
    ("releasedc", re.compile(r"(?<![a-z])releasedc(?![a-z])", re.I)),
    ("getdc", re.compile(r"(?<![a-z])getdc(?![a-z])", re.I)),
    ("createsurface", re.compile(r"(?<![a-z])createsurface(?![a-z])", re.I)),
    ("directdrawcreate", re.compile(r"(?<![a-z])directdrawcreate(?:ex)?(?![a-z])", re.I)),
    ("setdisplaymode", re.compile(r"(?<![a-z])setdisplaymode(?![a-z])", re.I)),
    ("setcooperativelevel", re.compile(r"(?<![a-z])setcooperativelevel(?![a-z])", re.I)),
    ("waitforverticalblank", re.compile(r"(?<![a-z])waitforverticalblank(?![a-z])", re.I)),
    ("getdevicestate", re.compile(r"(?<![a-z])getdevicestate(?![a-z])", re.I)),
    ("getdevicedata", re.compile(r"(?<![a-z])getdevicedata(?![a-z])", re.I)),
    ("waveoutwrite", re.compile(r"(?<![a-z])waveoutwrite(?![a-z])", re.I)),
    ("playsound", re.compile(r"(?<![a-z])playsound(?![a-z])", re.I)),
    ("render", re.compile(r"(?<![a-z])render(?![a-z])", re.I)),
    ("update", re.compile(r"(?<![a-z])update(?![a-z])", re.I)),
)
_WINE_LEVELS = frozenset({"trace", "fixme", "warn", "err"})
_WINE_CHANNELS = frozenset({"ddraw", "d3drm", "d3d", "dsound", "dinput", "winmm"})


class SanitizedWineEvents:
    """Tail complete lines and produce only bounded, fixed-vocabulary counters.

    Batch timestamps are the *host observation time* of log bytes being read.
    They are not the time each Wine function executed. Raw lines, arguments,
    paths, addresses, user text and unknown symbols are never emitted.
    """

    MAX_LINE = 4096
    MAX_GROUPS = 50

    def __init__(self) -> None:
        self._partial = b""
        self._discarding = False
        self.matched_calls = 0
        self.batches_written = 0

    def reset_partial(self) -> None:
        self._partial = b""
        self._discarding = False

    def observe(self, chunk: bytes, timeline: "Timeline") -> None:
        data = self._partial + chunk
        pieces = data.split(b"\n")
        self._partial = pieces.pop()
        if len(self._partial) > self.MAX_LINE:
            self._partial = b""
            self._discarding = True

        counts: dict[tuple[str, str, str], int] = {}
        for index, line in enumerate(pieces):
            # Finish ignoring an oversized line from the previous sample.
            if self._discarding and index == 0:
                self._discarding = False
                continue
            if len(line) > self.MAX_LINE:
                continue
            # Only the fixed Wine severity/channel marker can enter the data.
            raw = line.decode("ascii", errors="ignore")
            tag = _WINE_TAG.search(raw)
            if tag is None:
                continue
            severity, channel = tag.group(1).lower(), tag.group(2).lower()
            if severity not in _WINE_LEVELS or channel not in _WINE_CHANNELS:
                continue
            # Use a bounded message prefix and known labels only, never an
            # arbitrary symbol, DLL name, address, path or Win32 argument.
            message = raw[tag.end():tag.end() + 180]
            operation = "other"
            for label, pattern in _WINE_OPERATIONS:
                if pattern.search(message):
                    operation = label
                    break
            key = (channel, operation, severity)
            if key not in counts and len(counts) >= self.MAX_GROUPS:
                key = (channel, "other", severity)
            counts[key] = counts.get(key, 0) + 1

        if not counts:
            return
        observation_monotonic = time.monotonic()
        observation_unix = time.time()
        for (channel, operation, severity), count in sorted(counts.items()):
            timeline.write({
                "source": "wine_api", "event": "sampled_log_batch",
                "channel": channel, "operation": operation,
                "severity": severity, "count": count,
                "monotonic_s": observation_monotonic,
                "unix_s": observation_unix,
                "time_basis": "host_log_read",
            })
            self.matched_calls += count
        self.batches_written += 1


class BoundedTraceFollower:
    """Read only new bytes from a user-specified existing log, locally.

    Wine relay can contain file paths and other sensitive information; never
    copy those raw lines into a GitHub research package.
    """
    def __init__(self, source: Path, destination: Path, limit: int = MAX_LOCAL_TRACE_BYTES):
        if not source.is_file() or source.is_symlink():
            raise CaptureError("Requested trace file not found or is a symlink")
        self.source = source
        self._cursor = source.stat().st_size  # no historic unrelated data
        self._count = 0
        self._limit = limit
        self.events = SanitizedWineEvents()
        self._out = os.fdopen(os.open(destination, os.O_WRONLY | os.O_CREAT |
                                     os.O_EXCL, 0o600), "wb")

    def sample(self, timeline: Timeline | None = None) -> None:
        if self._count >= self._limit:
            return
        size = self.source.stat().st_size
        if size < self._cursor:  # log rotation or reset
            self._cursor = size
            self.events.reset_partial()
        amount = min(size - self._cursor, self._limit - self._count, 65536)
        if amount <= 0:
            return
        with self.source.open("rb") as src:
            src.seek(self._cursor)
            chunk = src.read(amount)
        self._cursor += len(chunk)
        self._count += len(chunk)
        self._out.write(chunk)
        self._out.flush()
        if timeline is not None:
            self.events.observe(chunk, timeline)

    def close(self) -> None:
        self._out.close()


class NerpsFollower:
    """Optional structured NERPs trace produced by future opt-in DLL hooks.

    Only small numeric arguments + declared function identifiers are copied.
    It is not a claim that a vanilla LegoRR.exe emits NERPs telemetry.
    """

    def __init__(self, source: Path):
        if not source.is_file() or source.is_symlink():
            raise CaptureError("Optional NERPs trace file not found")
        self.source = source
        self._cursor = source.stat().st_size

    def sample(self, timeline: Timeline) -> None:
        with self.source.open("rb") as stream:
            stream.seek(self._cursor)
            data = stream.read(32768)
            if not data:
                return
            # Only parse complete newline records. Incomplete trailing bytes
            # are revisited, not dropped.
            ending = data.rfind(b"\n")
            if ending == -1:
                return
            self._cursor += ending + 1
            data = data[:ending + 1]
        for line in data.splitlines():
            if len(line) > MAX_INPUT_LINE:
                continue
            try:
                payload = json.loads(line)
            except (ValueError, UnicodeError):
                continue
            if not isinstance(payload, dict):
                continue
            cleaned = {}
            for key in ALLOWED_NERPS_FIELDS:
                value = payload.get(key)
                if key == "function":
                    if isinstance(value, str) and len(value) <= 80 and value.replace("_", "").isalnum():
                        cleaned[key] = value
                elif key == "args":
                    if isinstance(value, list) and len(value) <= 8 and all(
                        type(v) in (int, float) and abs(v) < 1e9 for v in value
                    ):
                        cleaned[key] = value
                elif type(value) is int and abs(value) < 1e9:
                    cleaned[key] = value
            if not cleaned:
                continue
            timeline.write({"source": "nerps", "event": "runtime_function",
                            "unix_s": time.time(), "monotonic_s": time.monotonic(),
                            **cleaned})


def pump_input_events(pipe: Any, target: GameWindow, timeline: Timeline,
                      stop: threading.Event) -> None:
    for line in pipe:
        if stop.is_set():
            break
        if len(line) > MAX_INPUT_LINE:
            continue
        try:
            record = json.loads(line)
        except (ValueError, UnicodeError):
            continue
        if not isinstance(record, dict):
            continue
        event = record.get("event")
        if record.get("window_id") not in (None, target.id) or event not in ALLOWED_EVENT_NAMES:
            continue
        if record.get("source") not in ("mac_input", "capture_control"):
            continue
        # Rebuild the safe record instead of storing arbitrary helper output.
        safe = {key: record[key] for key in (
            "source", "event", "unix_s", "monotonic_s", "window_id",
            "x", "y", "x_normalized", "y_normalized", "scroll_y", "keycode"
        ) if key in record and (
            key in ("source", "event") or type(record[key]) in (int, float)
        )}
        timeline.write(safe)


def window_only_command(window_id: int, output: Path,
                        screencapture: str = "/usr/sbin/screencapture") -> list[str]:
    if type(window_id) is not int or window_id <= 0:
        raise CaptureError("Missing exact game window ID")
    if output.suffix.lower() != ".png":
        raise CaptureError("Screen captures must be PNG files")
    # -l is mandatory: never fall back to full desktop (-m, -D, -R, etc).
    return [screencapture, "-x", "-o", "-t", "png", "-l",
            str(window_id), str(output)]


def take_window_frame(target: GameWindow, image: Path, *,
                      screenshot: Callable[[list[str]], bool],
                      probe: WindowProbe) -> bool:
    before = probe.inspect(target)
    if not before.get("exists") or not before.get("onscreen"):
        return False
    if not screenshot(window_only_command(target.id, image)):
        image.unlink(missing_ok=True)
        return False
    # Window IDs can be recycled: delete the capture unless the same game's
    # exact window identity still exists after the screenshot completes.
    after = probe.inspect(target)
    if not after.get("exists") or after.get("pid") != target.pid:
        image.unlink(missing_ok=True)
        return False
    if not image.is_file() or image.stat().st_size < 200:
        image.unlink(missing_ok=True)
        return False
    os.chmod(image, 0o600)
    return True


def system_capture(command: list[str]) -> bool:
    try:
        result = subprocess.run(command, capture_output=True, timeout=12,
                                check=False)
        return result.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def next_session_path(root: Path) -> Path:
    make_private_dir(root)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    for index in range(100):
        result = root / f"rock-raiders-{stamp}-{index:02d}"
        if not result.exists() and not result.is_symlink():
            return result
    raise CaptureError("Unable to allocate a unique private capture directory")


def capture_loop(probe: WindowProbe, target: GameWindow, destination: Path,
                 fps: int = 4, max_seconds: float = 7200,
                 screenshot: Callable[[list[str]], bool] = system_capture,
                 wine_log: Path | None = None,
                 nerps_log: Path | None = None,
                 event_exe: Path | None = None,
                 sleep: Callable[[float], None] = time.sleep,
                 now: Callable[[], float] = time.monotonic) -> dict:
    if type(fps) is not int or not (1 <= fps <= 10):
        raise CaptureError("Frame rate must be 1-10 window screenshots per second")
    if not (1 <= max_seconds <= MAX_CAPTURE_SECONDS):
        raise CaptureError("Session duration must be between 1 second and 4 hours")
    make_private_dir(destination)
    make_private_dir(destination / "frames")
    timeline = Timeline(destination / "timeline.jsonl")
    raw_wine: BoundedTraceFollower | None = None
    nerps: NerpsFollower | None = None
    monitor: subprocess.Popen | None = None
    monitor_thread: threading.Thread | None = None
    stop = threading.Event()
    count, missed, inactive = 0, 0, 0
    reason = "unexpected_error"
    started = now()
    began = time.time()

    try:
        if wine_log is not None:
            raw_wine = BoundedTraceFollower(wine_log, destination / "wine_raw.local.log")
        if nerps_log is not None:
            nerps = NerpsFollower(nerps_log)
        if event_exe is not None:
            monitor = subprocess.Popen(
                [str(event_exe), "events", str(target.id), str(target.pid)],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                text=True, bufsize=1)
            monitor_thread = threading.Thread(
                target=pump_input_events, args=(monitor.stdout, target, timeline, stop),
                daemon=True)
            monitor_thread.start()
        timeline.write({
            "source": "capture_control", "event": "start",
            "unix_s": began, "monotonic_s": started,
            "window_id": target.id, "scope": "game_window_only",
            "input_enabled": event_exe is not None
        })
        period = 1.0 / fps
        next_frame = started
        frame_number = 0
        while True:
            inspection = probe.inspect(target)
            if not inspection.get("exists"):
                reason = "game_window_closed"
                break
            if now() - started >= max_seconds:
                reason = "time_limit"
                break
            if raw_wine is not None:
                raw_wine.sample(timeline)
            if nerps is not None:
                nerps.sample(timeline)
            if not inspection.get("onscreen"):
                inactive += 1
                sleep(min(period, 0.3))
                next_frame = now()
                continue
            delay = next_frame - now()
            if delay > 0:
                sleep(min(delay, 0.3))
                continue
            frame_number += 1
            file = destination / "frames" / f"frame-{count + 1:06d}.png"
            start_frame = now()
            worked = take_window_frame(target, file, screenshot=screenshot,
                                       probe=probe)
            if worked:
                count += 1
                missed = 0
                timeline.write({
                    "source": "frame", "event": "game_window_screenshot",
                    "window_id": target.id, "frame": count,
                    "file": f"frames/frame-{count:06d}.png",
                    "monotonic_s": start_frame,
                    "unix_s": time.time(),
                    "capture_duration_ms": round((now() - start_frame) * 1000, 2)
                })
            else:
                missed += 1
                if not probe.inspect(target).get("exists"):
                    reason = "game_window_closed"
                    break
                if missed >= 3:
                    reason = "screenshot_permission_or_capture_failure"
                    break
            next_frame = max(next_frame + period, now())
    except KeyboardInterrupt:
        reason = "user_stopped"
    finally:
        stop.set()
        if monitor is not None:
            monitor.terminate()
            try:
                monitor.wait(timeout=2)
            except subprocess.TimeoutExpired:
                monitor.kill()
                monitor.wait(timeout=2)
            if monitor.stdout:
                monitor.stdout.close()
        if monitor_thread is not None:
            monitor_thread.join(timeout=2)
        if raw_wine is not None:
            raw_wine.close()
        timeline.write({
            "source": "capture_control", "event": "stop",
            "reason": reason, "unix_s": time.time(),
            "monotonic_s": now(), "window_id": target.id
        })
        timeline.close()
        result = {
            "schema_version": 1,
            "scope": "game_window_only",
            "target_window_id": target.id,
            "frame_count": count,
            "paused_minimized_polls": inactive,
            "stop_reason": reason,
            "capture_started_utc": datetime.fromtimestamp(began, tz=timezone.utc).isoformat(),
            "capture_ended_utc": iso_now(),
            "wine_trace_captured_locally": raw_wine is not None,
            "wine_api_observations": raw_wine.events.matched_calls if raw_wine else 0,
            "wine_log_batches": raw_wine.events.batches_written if raw_wine else 0,
            "wine_time_basis": "host_log_read_not_game_call_time",
            "nerps_runtime_trace_source_attached": nerps is not None,
            "input_monitor_requested": event_exe is not None,
            "raw_trace_upload_allowed": False,
            "automatic_github_upload": False
        }
        manifest = destination / "manifest.json"
        with os.fdopen(os.open(manifest, os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                              0o600), "w", encoding="utf-8") as stream:
            json.dump(result, stream, indent=2, sort_keys=True)
            stream.write("\n")
    return result


def package_review(session: Path, output: Path, *, include_frames: bool) -> int:
    """Manual, reviewed export only. Never includes raw Wine trace or OS data."""
    summary = json.loads((session / "manifest.json").read_text())
    if summary.get("scope") != "game_window_only":
        raise CaptureError("Export requires a verified window-only session")
    safe_records = []
    for line in (session / "timeline.jsonl").read_text().splitlines():
        record = json.loads(line)
        if record.get("source") not in (
            "frame", "mac_input", "capture_control", "nerps", "wine_api", "video"
        ):
            continue
        if record.get("source") == "mac_input" and record.get("event") not in ALLOWED_EVENT_NAMES:
            continue
        safe_records.append(record)
    if output.exists() or output.is_symlink():
        raise CaptureError("Export file already exists")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED,
                         compresslevel=6) as archive:
        archive.writestr("manifest.json", json.dumps(summary, indent=2))
        archive.writestr("timeline.jsonl", "".join(json_line(row) for row in safe_records))
        # Only small, numeric/safe clip metadata goes into review ZIP.
        # The actual MP4s remain separate files for upload size limits.
        clip_manifest = session / "clips" / "clips.json"
        if clip_manifest.is_file() and not clip_manifest.is_symlink():
            raw = json.loads(clip_manifest.read_text())
            if raw.get("schema") == "openlrr-window-video-clips-v1":
                clips = raw.get("clips", [])
                cleaned_clips = []
                if isinstance(clips, list) and len(clips) <= 500:
                    for item in clips:
                        if not isinstance(item, dict):
                            continue
                        name = item.get("file")
                        if not isinstance(name, str) or not __import__("re").fullmatch(r"part-[0-9]{4}\\.mp4", name):
                            continue
                        numbers = [item.get(key) for key in ("start_s", "duration_s", "bytes")]
                        if not all(type(x) in (int, float) and 0 <= x < 1e12 for x in numbers):
                            continue
                        cleaned_clips.append({
                            "file": name, "start_s": numbers[0],
                            "duration_s": numbers[1], "bytes": numbers[2]
                        })
                    archive.writestr("clips.json", json.dumps({
                        "schema": "openlrr-window-video-clips-v1",
                        "time_basis": "relative_to_video_start",
                        "clips": cleaned_clips
                    }, sort_keys=True))
        if include_frames:
            for frame in sorted((session / "frames").glob("frame-*.png")):
                if frame.is_symlink():
                    raise CaptureError("Refusing symlinked frame in export")
                archive.write(frame, arcname="frames/" + frame.name)
    os.chmod(output, 0o600)
    return len(safe_records)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list", help="list only eligible Rock Raiders windows")
    rec = commands.add_parser("record", help="record only one verified game window")
    rec.add_argument("--window-id", type=int, help="select from list if ambiguous")
    rec.add_argument("--fps", type=int, default=4)
    rec.add_argument("--max-minutes", type=float, default=120)
    rec.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT)
    rec.add_argument("--wine-log", type=Path,
                     help="optional already-running Wine log; kept local, never uploaded")
    rec.add_argument("--nerps-log", type=Path,
                     help="optional structured instrumented NERPs JSONL log")
    rec.add_argument("--no-input", action="store_true",
                     help="do not request Input Monitoring permission")
    pack = commands.add_parser("package", help="manual sanitized ZIP, no upload")
    pack.add_argument("session", type=Path)
    pack.add_argument("output", type=Path)
    pack.add_argument("--include-frames", action="store_true")
    args = parser.parse_args()

    if args.command == "package":
        count = package_review(args.session, args.output,
                               include_frames=args.include_frames)
        print(f"Created local review ZIP ({count} timeline events): {args.output}")
        return 0

    exe = build_probe()
    probe = WindowProbe(exe)
    if args.command == "list":
        for entry in probe.list_games():
            print(f"Game window #{entry['id']} (pid {entry['pid']}): "
                  f"{entry['title']} ({entry['bounds']['width']:.0f}×"
                  f"{entry['bounds']['height']:.0f})")
        return 0

    target = select_game_window(probe, args.window_id)
    folder = next_session_path(args.output_root)
    print(f"Recording ONLY Rock Raiders window #{target.id}. "
          f"Closing the window stops capture automatically.")
    print(f"Local session: {folder}", flush=True)
    result = capture_loop(
        probe, target, folder, fps=args.fps,
        max_seconds=args.max_minutes * 60,
        wine_log=args.wine_log, nerps_log=args.nerps_log,
        event_exe=None if args.no_input else exe)
    print(f"Stopped: {result['stop_reason']} — {result['frame_count']} "
          f"window-only frames. No files were uploaded.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (CaptureError, OSError, ValueError) as exc:
        print(f"Capture not started or stopped safely: {exc}", file=sys.stderr)
        sys.exit(1)
