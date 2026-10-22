#!/usr/bin/env python3
"""Portable safety and lifecycle tests for the Mac-only game capture lab."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import zipfile

MODULE = Path(__file__).resolve().parents[1] / "capture.py"
spec = importlib.util.spec_from_file_location("gameplay_window_capture", MODULE)
capture = importlib.util.module_from_spec(spec)
import sys
sys.modules[spec.name] = capture
spec.loader.exec_module(capture)


class FakeClock:
    t = 100.0

    def __call__(self):
        return self.t

    def sleep(self, amount):
        self.t += max(0.001, amount)


class FakeProbe:
    """Window identity becomes absent after exactly N inspect operations."""

    def __init__(self, *, close_after=4, minimized_first=False):
        self.calls = 0
        self.close_after = close_after
        self.minimized_first = minimized_first
        self.target = capture.GameWindow(id=415, pid=2941)

    def list_games(self):
        return [{"id": 415, "pid": 2941, "title": "LEGO Rock Raiders",
                 "onscreen": True, "bounds": {"width": 640, "height": 480}}]

    def inspect(self, target):
        self.calls += 1
        assert target == self.target
        visible = not (self.minimized_first and self.calls == 1)
        return {"exists": self.calls <= self.close_after,
                "id": 415, "pid": 2941, "onscreen": visible}


def good_screenshot(clock, commands):
    def screenshot(cmd):
        commands.append(cmd)
        # This is a fake screenshot; tests verify command scope, not PNG codec.
        Path(cmd[-1]).write_bytes(b"\x89PNG\r\n\x1a\n" + b"0" * 500)
        clock.t += .02
        return True
    return screenshot


class CaptureSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.target = capture.GameWindow(415, 2941)

    def test_screenshot_command_is_always_single_window_only(self):
        cmd = capture.window_only_command(415, self.root / "x.png")
        self.assertIn("-l", cmd)
        self.assertEqual(cmd[cmd.index("-l") + 1], "415")
        self.assertNotIn("-m", cmd)
        self.assertNotIn("-D", cmd)
        self.assertNotIn("-R", cmd)
        self.assertEqual(cmd[-1], str(self.root / "x.png"))
        with self.assertRaises(capture.CaptureError):
            capture.window_only_command(0, self.root / "x.png")
        with self.assertRaises(capture.CaptureError):
            capture.window_only_command(415, self.root / "x.jpg")

    def test_rejects_ambiguous_window_selection(self):
        p = FakeProbe()
        original = p.list_games
        p.list_games = lambda: original() * 2
        with self.assertRaisesRegex(capture.CaptureError, "exactly one"):
            capture.select_game_window(p, None)
        p.list_games = original
        self.assertEqual(capture.select_game_window(p, 415), self.target)

    def test_auto_stops_when_window_is_closed(self):
        probe = FakeProbe(close_after=3)
        clock = FakeClock()
        calls = []
        session = self.root / "session"
        result = capture.capture_loop(
            probe, self.target, session, fps=4, max_seconds=100,
            screenshot=good_screenshot(clock, calls),
            sleep=clock.sleep, now=clock)
        self.assertEqual(result["stop_reason"], "game_window_closed")
        self.assertEqual(result["frame_count"], 1)
        self.assertEqual(len(calls), 1)
        self.assertIn("-l", calls[0])
        self.assertEqual(len(list((session / "frames").glob("*.png"))), 1)
        lines = [json.loads(row) for row in (session / "timeline.jsonl").read_text().splitlines()]
        self.assertEqual(lines[-1]["reason"], "game_window_closed")
        self.assertEqual(lines[-1]["event"], "stop")
        self.assertEqual(lines[1]["source"], "frame")

    def test_close_during_screenshot_discards_image(self):
        probe = FakeProbe(close_after=2)
        clock = FakeClock()
        calls = []
        session = self.root / "race"
        result = capture.capture_loop(
            probe, self.target, session, fps=4, max_seconds=100,
            screenshot=good_screenshot(clock, calls),
            sleep=clock.sleep, now=clock)
        self.assertEqual(result["stop_reason"], "game_window_closed")
        self.assertEqual(result["frame_count"], 0)
        self.assertEqual(list((session / "frames").glob("*.png")), [])

    def test_minimized_game_pauses_capture(self):
        probe = FakeProbe(close_after=4, minimized_first=True)
        clock = FakeClock()
        calls = []
        result = capture.capture_loop(
            probe, self.target, self.root / "minimized", fps=4, max_seconds=100,
            screenshot=good_screenshot(clock, calls),
            sleep=clock.sleep, now=clock)
        self.assertEqual(result["stop_reason"], "game_window_closed")
        self.assertEqual(result["paused_minimized_polls"], 1)
        self.assertEqual(result["frame_count"], 1)
        self.assertEqual(len(calls), 1)

    def test_fails_safely_if_capture_permission_missing(self):
        probe = FakeProbe(close_after=100)
        clock = FakeClock()
        result = capture.capture_loop(
            probe, self.target, self.root / "denied",
            fps=4, max_seconds=100, screenshot=lambda cmd: False,
            sleep=clock.sleep, now=clock)
        self.assertEqual(result["stop_reason"],
                         "screenshot_permission_or_capture_failure")
        self.assertEqual(result["frame_count"], 0)

    def test_window_probe_rejects_identity_change(self):
        probe = capture.WindowProbe(Path("/fake/window-probe"))
        with mock.patch.object(probe, "_run",
                               return_value=[{"id": 415, "pid": 9999,
                                              "exists": True}]):
            with self.assertRaisesRegex(capture.CaptureError, "identity changed"):
                probe.inspect(self.target)

    def test_bounded_optional_nerps_only_keeps_structured_game_events(self):
        npl = self.root / "nerps.jsonl"
        npl.write_text('')  # baseline is EOF; append only new events
        follower = capture.NerpsFollower(npl)
        timeline = capture.Timeline(self.root / "events.jsonl")
        with npl.open("a") as stream:
            stream.write(json.dumps({
                "function": "AdvanceMessage", "function_id": 44, "args": [2, 3],
                "host_path": "/Users/private/secret", "frame": 72,
                "password": "dont_capture"
            }) + "\n")
            stream.write('{"function": "set token secret", "args":["password"]}\n')
        follower.sample(timeline)
        timeline.close()
        text = (self.root / "events.jsonl").read_text()
        self.assertIn("AdvanceMessage", text)
        self.assertNotIn("host_path", text)
        self.assertNotIn("password", text)
        self.assertNotIn("dont_capture", text)

    def test_export_does_not_upload_or_include_raw_wine_trace(self):
        folder = self.root / "safe"
        capture.make_private_dir(folder)
        capture.make_private_dir(folder / "frames")
        (folder / "manifest.json").write_text(json.dumps({
            "scope": "game_window_only", "stop_reason": "game_window_closed",
            "frame_count": 1
        }))
        (folder / "timeline.jsonl").write_text(
            json.dumps({"source": "frame", "file": "frames/frame-000001.png"}) + "\n"
        )
        (folder / "frames" / "frame-000001.png").write_bytes(b"image")
        (folder / "wine_raw.local.log").write_text("private path and password")
        result = self.root / "review.zip"
        self.assertEqual(capture.package_review(folder, result, include_frames=True), 1)
        with zipfile.ZipFile(result) as archive:
            self.assertEqual(set(archive.namelist()), {
                "manifest.json", "timeline.jsonl", "frames/frame-000001.png"
            })
            self.assertNotIn("password", "".join(archive.namelist()))
            self.assertNotIn("private", archive.read("timeline.jsonl").decode())
        with self.assertRaises(capture.CaptureError):
            capture.package_review(folder, result, include_frames=True)

    def test_capture_errors_not_silently_switched_to_desktop(self):
        cmd = capture.window_only_command(415, self.root / "one.png")
        self.assertEqual(cmd[0], "/usr/sbin/screencapture")
        self.assertEqual(cmd.count("-l"), 1)
        self.assertNotIn("--desktop", cmd)
        self.assertNotIn("-m", cmd)
        self.assertNotIn("-c", cmd)


    def test_privacy_filtered_wine_calls_join_same_frame_input_timeline(self):
        wine_log = self.root / "already-running-wine.log"
        wine_log.write_bytes(b"")
        follower = capture.BoundedTraceFollower(
            wine_log, self.root / "wine_raw.local.log")
        timeline = capture.Timeline(self.root / "wine-timeline.jsonl")
        with wine_log.open("ab") as writer:
            writer.write(
                b"0032:trace:ddraw:ddraw_surface7_Blt src /Users/private/secret 0x1234\n"
                b"0032:trace:ddraw:DirectDrawSurface4::Blt other private-file\n"
                b"0033:trace:d3drm:IDirect3DRM3_Update /Users/private/secret\n"
                b"0034:trace:relay:password=should-never-be-exported\n"
                b"0035:fixme:dsound:PlaySound save tokens=private\n"
                b"0036:trace:ddraw:directdraw_surface7_Fl"
            )
        follower.sample(timeline)
        with wine_log.open("ab") as writer:
            writer.write(b"ip\n")
        follower.sample(timeline)
        timeline.close()
        follower.close()
        records = [json.loads(row) for row in
                   (self.root / "wine-timeline.jsonl").read_text().splitlines()]
        self.assertEqual(sum(row["count"] for row in records), 5)
        self.assertEqual(follower.events.matched_calls, 5)
        self.assertEqual(follower.events.batches_written, 2)
        self.assertEqual(
            sum(row["count"] for row in records if
                row["channel"] == "ddraw" and row["operation"] == "blt"), 2)
        self.assertEqual(
            sum(row["count"] for row in records if row["operation"] == "flip"), 1)
        self.assertTrue(all(row["time_basis"] == "host_log_read" for row in records))
        safe = json.dumps(records)
        for secret in ("private", "/Users", "password", "0x1234", "tokens="):
            self.assertNotIn(secret, safe)
        self.assertIn(b"/Users/private/secret",
                      (self.root / "wine_raw.local.log").read_bytes())

    def test_wine_parser_ignores_oversize_and_unknown_channel(self):
        log = self.root / "wine-extra.log"
        log.write_bytes(b"")
        follower = capture.BoundedTraceFollower(log, self.root / "raw.local.log")
        timeline = capture.Timeline(self.root / "summary.jsonl")
        with log.open("ab") as stream:
            stream.write(
                b"trace:ddraw:" + b"x" * 6000 + b"BlT\n"
                b"trace:custom:password Blt\n"
                b"garbage-line\n"
                b"0030:trace:dinput:GetDeviceState()\n"
            )
        follower.sample(timeline)
        timeline.close()
        follower.close()
        rows = (self.root / "summary.jsonl").read_text().splitlines()
        self.assertEqual(len(rows), 1)
        self.assertEqual(json.loads(rows[0])["operation"], "getdevicestate")


if __name__ == "__main__":
    unittest.main()
