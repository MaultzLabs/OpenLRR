#!/usr/bin/env python3
"""No-Mac/offline tests for paste-and-play Rock Raiders recorder coordinator."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import capture

spec = importlib.util.spec_from_file_location("gameplay_first_level", ROOT / "first-level.py")
first = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = first
spec.loader.exec_module(first)


class FakeClock:
    def __init__(self):
        self.t = 100.0
    def __call__(self):
        return self.t
    def sleep(self, seconds):
        self.t += seconds


class FakeProbe:
    def __init__(self, rows):
        self.rows = rows
    def list_games(self):
        return self.rows
    def inspect(self, target):
        return {"exists": True, "id": target.id, "pid": target.pid, "onscreen": True}


class FirstLevelTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def app(self, name):
        path = self.root / "Applications" / name
        (path / "Contents").mkdir(parents=True)
        (path / "Contents" / "Info.plist").write_text("test-only")
        return path

    def test_launches_only_identified_normal_game_bundle(self):
        normal = self.app("LEGO Rock Raiders OpenLRR.app")
        self.assertTrue(first.is_normal_game_app(normal))
        for name in ("OpenLRR Menu Test.app", "OpenLRR Native.app",
                     "Rock Raiders Benchmark.app", "OpenLRR Prototype.app"):
            self.assertFalse(first.is_normal_game_app(self.app(name)))
        self.assertFalse(first.is_normal_game_app(self.app("Safari.app")))
        self.assertFalse(first.is_normal_game_app(self.root / "not-a-game.app"))
        alias = self.root / "OpenLRR.app"
        alias.symlink_to(normal)
        self.assertFalse(first.is_normal_game_app(alias))

    def test_finds_no_test_or_native_apps(self):
        apps = self.root / "Applications" / "Sikarugir"
        apps.mkdir(parents=True)
        for name in ("OpenLRR Menu Test.app", "OpenLRR Native.app", "OpenLRR.app"):
            p = apps / name
            (p / "Contents").mkdir(parents=True)
            (p / "Contents" / "Info.plist").write_text("test-only")
        result = first.find_normal_game_apps(home=self.root)
        self.assertEqual([x.name for x in result], ["OpenLRR.app"])

    def test_prefer_openlrr_over_separate_original_retail_wrapper(self):
        a = self.app("OpenLRR.app")
        b = self.app("Lego Rock Raiders.app")
        self.assertEqual(first.choose_application(None, [b, a]), a)
        with self.assertRaisesRegex(capture.CaptureError, "not a recognized"):
            first.choose_application(self.app("OpenLRR Menu Test.app"), [a])

    def test_multiple_unclear_original_apps_are_not_guessed(self):
        a = self.app("Lego Rock Raiders.app")
        b = self.app("Rock Raiders Retail.app")
        self.assertIsNone(first.choose_application(None, [a, b]))

    def test_wait_returns_exact_single_window(self):
        clock = FakeClock()
        probe = FakeProbe([{"id": 45, "pid": 321, "title": "Rock Raiders"}])
        result = first.wait_for_game(probe, 20, clock=clock, sleep=clock.sleep)
        self.assertEqual(result, capture.GameWindow(45, 321))

    def test_wait_does_not_guess_ambiguous_window(self):
        clock = FakeClock()
        rows = [{"id": 45, "pid": 321}, {"id": 46, "pid": 322}]
        with self.assertRaisesRegex(capture.CaptureError, "Multiple"):
            first.wait_for_game(FakeProbe(rows), 20, clock=clock, sleep=clock.sleep)

    def test_wait_reports_missing_screen_permission_without_waiting_six_minutes(self):
        class DeniedProbe(FakeProbe):
            def diagnose(self):
                return {"counts_only": True,
                        "screen_recording_permission": False,
                        "eligible_game_windows": 0,
                        "wine_like_windows": 1,
                        "wine_like_untitled_windows": 1}
        clock = FakeClock()
        with self.assertRaisesRegex(capture.CaptureError, "Screen Recording permission"):
            first.wait_for_game(DeniedProbe([]), 90, clock=clock,
                                sleep=clock.sleep)
        self.assertLess(clock.t - 100.0, 30)

    def test_wait_exits_on_deadline_when_wine_game_window_untitled(self):
        class UntitledProbe(FakeProbe):
            def diagnose(self):
                return {"counts_only": True,
                        "screen_recording_permission": True,
                        "eligible_game_windows": 0,
                        "wine_like_windows": 1,
                        "wine_like_untitled_windows": 1}
        clock = FakeClock()
        with self.assertRaisesRegex(capture.CaptureError, "No verified"):
            first.wait_for_game(UntitledProbe([]), 45, clock=clock,
                                sleep=clock.sleep)
        self.assertGreaterEqual(clock.t - 100.0, 45)
        self.assertLess(clock.t - 100.0, 48)

    def test_timeout_does_not_capture_other_windows(self):
        clock = FakeClock()
        with self.assertRaisesRegex(capture.CaptureError, "Timed out"):
            first.wait_for_game(FakeProbe([]), 10, clock=clock, sleep=clock.sleep)

    def test_one_paste_pipeline_records_then_packages_locally(self):
        probe = FakeProbe([{"id": 45, "pid": 321}])
        session = self.root / "private-session"
        params = ["--fps", "4", "--max-minutes", "30"]
        with (mock.patch.object(first.sys, "platform", "darwin"),
              mock.patch.object(first.capture, "build_probe", return_value=self.root / "probe"),
              mock.patch.object(first.capture, "WindowProbe", return_value=probe),
              mock.patch.object(first.capture, "next_session_path", return_value=session),
              mock.patch.object(first.capture, "capture_loop",
                                return_value={"frame_count": 8, "stop_reason": "game_window_closed"}) as run,
              mock.patch.object(first.capture, "package_review", return_value=24) as package,
              mock.patch.object(first, "wait_for_game",
                                return_value=capture.GameWindow(45, 321))):
            code = first.main(params)
        self.assertEqual(code, 0)
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.kwargs["fps"], 4)
        self.assertEqual(run.call_args.kwargs["max_seconds"], 1800)
        self.assertEqual(run.call_args.kwargs["wine_log"], None)
        self.assertEqual(run.call_args.kwargs["nerps_log"], None)
        self.assertEqual(package.call_count, 1)
        self.assertTrue(package.call_args.kwargs["include_frames"])
        self.assertEqual(package.call_args.args[0], session)
        self.assertEqual(package.call_args.args[1],
                         self.root / "private-session-review.zip")

    def test_zero_frame_does_not_claim_successful_package(self):
        probe = FakeProbe([{"id": 45, "pid": 321}])
        with (mock.patch.object(first.sys, "platform", "darwin"),
              mock.patch.object(first.capture, "build_probe", return_value=self.root / "probe"),
              mock.patch.object(first.capture, "WindowProbe", return_value=probe),
              mock.patch.object(first.capture, "next_session_path", return_value=self.root / "session"),
              mock.patch.object(first.capture, "capture_loop",
                                return_value={"frame_count": 0, "stop_reason": "screenshot_permission_or_capture_failure"}),
              mock.patch.object(first.capture, "package_review") as package,
              mock.patch.object(first, "wait_for_game",
                                return_value=capture.GameWindow(45, 321))):
            self.assertEqual(first.main([]), 2)
        package.assert_not_called()


if __name__ == "__main__":
    unittest.main()
