#!/usr/bin/env python3
"""Windows-only, window-scoped automation probe for OpenLRR.

Never records the desktop; only the identified target HWND. No game assets are shipped.
"""
from __future__ import annotations

import argparse
import ctypes
import json
from pathlib import Path
import re
import subprocess
import sys
import time

ALLOWED_KEYS = {"enter": 0x0D, "escape": 0x1B, "space": 0x20,
                "up": 0x26, "down": 0x28, "left": 0x25, "right": 0x27}
MAX_STEPS = 40
MAX_SECONDS = 180


def validate_scenario(data):
    if not isinstance(data, dict) or not isinstance(data.get("steps"), list):
        raise ValueError("Scenario must contain a steps array")
    steps = data["steps"]
    if not 1 <= len(steps) <= MAX_STEPS:
        raise ValueError("Scenario must have 1-40 steps")
    for i, step in enumerate(steps):
        if not isinstance(step, dict):
            raise ValueError(f"Step {i} must be an object")
        kind = step.get("action")
        if kind not in {"capture", "click", "key", "wait", "assert_title", "assert_alive", "assert_changed"}:
            raise ValueError(f"Step {i} has unsupported action: {kind}")
        if kind == "click":
            if not all(isinstance(step.get(k), int) and not isinstance(step[k], bool) and 0 <= step[k] <= 8192 for k in ("x", "y")):
                raise ValueError(f"Step {i}: click requires nonnegative integer client x/y <=8192")
        if kind == "key" and step.get("key") not in ALLOWED_KEYS:
            raise ValueError(f"Step {i}: unsupported key")
        if kind == "wait" and (not isinstance(step.get("seconds"), (int, float)) or isinstance(step["seconds"], bool) or not 0 <= step["seconds"] <= 10):
            raise ValueError(f"Step {i}: wait seconds must be between 0 and 10")
        if kind == "assert_title":
            if not isinstance(step.get("pattern"), str) or len(step["pattern"]) > 200:
                raise ValueError(f"Step {i}: pattern must be short regex")
            re.compile(step["pattern"])
        if kind == "assert_changed" and (not isinstance(step.get("min_difference", 0.4), (int, float)) or not 0 <= step.get("min_difference", 0.4) <= 255):
            raise ValueError(f"Step {i}: invalid difference threshold")
    return steps


class ProbeError(RuntimeError):
    pass


class Win32:
    def __init__(self):
        if sys.platform != "win32":
            raise ProbeError("Graphical playtesting requires a Windows runner")
        from ctypes import wintypes as wt
        self.wt = wt
        self.u = ctypes.WinDLL("user32", use_last_error=True)
        self.CALLBACK = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
        self.u.EnumWindows.argtypes = (self.CALLBACK, wt.LPARAM)
        self.u.GetWindowThreadProcessId.argtypes = (wt.HWND, ctypes.POINTER(wt.DWORD))
        self.u.GetWindowTextLengthW.argtypes = (wt.HWND,)
        self.u.GetWindowTextW.argtypes = (wt.HWND, wt.LPWSTR, ctypes.c_int)
        self.u.GetClientRect.argtypes = (wt.HWND, ctypes.POINTER(wt.RECT))
        self.u.ClientToScreen.argtypes = (wt.HWND, ctypes.POINTER(wt.POINT))
        self.u.IsWindowVisible.argtypes = (wt.HWND,)
        self.u.IsWindow.argtypes = (wt.HWND,)
        self.u.GetForegroundWindow.restype = wt.HWND
        self.u.SetForegroundWindow.argtypes = (wt.HWND,)
        self.u.ShowWindow.argtypes = (wt.HWND, ctypes.c_int)
        self.u.SetCursorPos.argtypes = (ctypes.c_int, ctypes.c_int)
        self.u.mouse_event.argtypes = (wt.DWORD, wt.DWORD, wt.DWORD, wt.DWORD, ctypes.c_ulonglong)
        self.u.keybd_event.argtypes = (ctypes.c_ubyte, ctypes.c_ubyte, wt.DWORD, ctypes.c_ulonglong)

    def title(self, hwnd):
        n = self.u.GetWindowTextLengthW(hwnd)
        b = ctypes.create_unicode_buffer(n + 1)
        self.u.GetWindowTextW(hwnd, b, len(b))
        return b.value

    def window_pid(self, hwnd):
        pid = self.wt.DWORD()
        self.u.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        return pid.value

    def windows(self, pid, pattern):
        found = []
        @self.CALLBACK
        def visit(hwnd, _):
            if self.u.IsWindowVisible(hwnd) and self.window_pid(hwnd) == pid:
                t = self.title(hwnd)
                if t and re.search(pattern, t, re.I):
                    found.append((hwnd, t))
            return True
        self.u.EnumWindows(visit, 0)
        return found

    def ensure_window(self, hwnd, pid):
        if not self.u.IsWindow(hwnd) or self.window_pid(hwnd) != pid:
            raise ProbeError("Target game window disappeared or changed ownership")

    def focus(self, hwnd, pid):
        self.ensure_window(hwnd, pid)
        self.u.ShowWindow(hwnd, 9)  # SW_RESTORE
        self.u.SetForegroundWindow(hwnd)
        for _ in range(10):
            if self.u.GetForegroundWindow() == hwnd:
                return
            time.sleep(0.1)
        raise ProbeError("Target window cannot receive interactive input; unlocked desktop required")

    def click(self, hwnd, pid, x, y):
        self.focus(hwnd, pid)
        rect = self.wt.RECT()
        if not self.u.GetClientRect(hwnd, ctypes.byref(rect)):
            raise ProbeError("Cannot read target client rectangle")
        if not (0 <= x < rect.right and 0 <= y < rect.bottom):
            raise ProbeError(f"Click ({x},{y}) lies outside target client {rect.right}x{rect.bottom}")
        pt = self.wt.POINT(x, y)
        if not self.u.ClientToScreen(hwnd, ctypes.byref(pt)):
            raise ProbeError("Cannot translate client coordinates")
        if not self.u.SetCursorPos(pt.x, pt.y):
            raise ProbeError("Cannot position cursor")
        self.u.mouse_event(0x0002, 0, 0, 0, 0)  # left down
        time.sleep(0.08)
        self.u.mouse_event(0x0004, 0, 0, 0, 0)  # left up

    def key(self, hwnd, pid, key):
        self.focus(hwnd, pid)
        vk = ALLOWED_KEYS[key]
        self.u.keybd_event(vk, 0, 0, 0)
        time.sleep(0.06)
        self.u.keybd_event(vk, 0, 0x0002, 0)


def capture(hwnd, windows, pid, outfile):
    # Pillow 11.2+ Windows window= uses PrintWindow. No screen/desktop fallback.
    from PIL import ImageGrab
    windows.ensure_window(hwnd, pid)
    img = ImageGrab.grab(window=int(hwnd))
    windows.ensure_window(hwnd, pid)
    if img.width < 16 or img.height < 16:
        raise ProbeError("Window capture returned an invalid frame")
    img.convert("RGB").save(outfile)
    return img.convert("RGB")


def changed(a, b):
    from PIL import ImageChops, ImageStat
    if a.size != b.size:
        return 255.0
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3


def execute(win, pid, steps, dest, title_pattern, start_timeout=25, launched_process=None):
    deadline = time.monotonic() + start_timeout
    matches = []
    while time.monotonic() < deadline:
        if launched_process is not None and launched_process.poll() is not None:
            raise ProbeError(
                f"Target Windows executable exited before game window appeared "
                f"(process exit code {launched_process.returncode})"
            )
        matches = win.windows(pid, title_pattern)
        if len(matches) == 1:
            break
        if len(matches) > 1:
            raise ProbeError("Multiple matching windows: refusing ambiguous inputs")
        time.sleep(0.25)
    if len(matches) != 1:
        raise ProbeError("No matching game window appeared before deadline")
    hwnd, _ = matches[0]
    events = []
    last_frame = None
    start = time.monotonic()
    for i, step in enumerate(steps):
        if time.monotonic() - start > MAX_SECONDS:
            raise ProbeError("Playtest exceeded time limit")
        win.ensure_window(hwnd, pid)
        kind = step["action"]
        event = {"step": i, "action": kind, "timestamp_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "title": win.title(hwnd)}
        if kind == "wait":
            time.sleep(step["seconds"])
        elif kind == "click":
            win.click(hwnd, pid, step["x"], step["y"])
        elif kind == "key":
            win.key(hwnd, pid, step["key"])
        elif kind == "assert_title":
            if not re.search(step["pattern"], win.title(hwnd), re.I):
                raise ProbeError(f"Step {i}: title assertion failed: {win.title(hwnd)!r}")
        elif kind == "capture" or kind == "assert_changed":
            img = capture(hwnd, win, pid, dest / f"frame-{i:02d}.png")
            event["frame"] = f"frame-{i:02d}.png"
            if kind == "assert_changed":
                if last_frame is None:
                    raise ProbeError("assert_changed requires an earlier capture")
                diff = changed(last_frame, img)
                event["mean_pixel_difference"] = round(diff, 4)
                if diff < step.get("min_difference", 0.4):
                    raise ProbeError(f"Step {i}: frame did not change enough ({diff:.3f})")
            last_frame = img
        elif kind == "assert_alive":
            win.ensure_window(hwnd, pid)
        events.append(event)
        (dest / "timeline.json").write_text(json.dumps(events, indent=2), encoding="utf-8")
    return events


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, help="Local executable to launch (private assets stay private)")
    parser.add_argument("--pid", type=int, help="Attach to an existing process instead")
    parser.add_argument("--scenario", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--title", default="Rock Raiders|OpenLRR", help="Regex for target window title")
    parser.add_argument("--startup-timeout", type=float, default=25)
    opts = parser.parse_args(argv)
    if (opts.exe is None) == (opts.pid is None):
        parser.error("Use exactly one of --exe or --pid")
    steps = validate_scenario(json.loads(opts.scenario.read_text(encoding="utf-8")))
    if not 0 < opts.startup_timeout <= 90:
        parser.error("startup timeout must be 0-90 seconds")
    opts.out.mkdir(parents=True, exist_ok=True)
    report = {"status": "failed", "target": str(opts.exe) if opts.exe else "attached-process", "steps_requested": len(steps), "evidence": "window-only", "events": []}
    proc = None
    try:
        win = Win32()
        if opts.exe:
            exe = opts.exe.resolve(strict=True)
            proc = subprocess.Popen([str(exe)], cwd=str(exe.parent))
            pid = proc.pid
        else:
            pid = opts.pid
        report["pid"] = pid
        report["events"] = execute(win, pid, steps, opts.out, opts.title, opts.startup_timeout, proc)
        report["status"] = "passed"
    except Exception as exc:
        report["error"] = str(exc)
        report["exception_type"] = type(exc).__name__
        print(f"PLAYTEST FAILED: {exc}", file=sys.stderr)
    finally:
        (opts.out / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=4)
            except subprocess.TimeoutExpired:
                proc.kill()
    print(json.dumps({"status": report["status"], "report": str(opts.out / 'report.json'), "steps": len(report["events"])}))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
