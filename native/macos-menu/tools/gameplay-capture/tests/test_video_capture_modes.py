#!/usr/bin/env python3
"""Runbook regression: menu-only video includes the initial slow/black window."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import capture
import video_session

spec = importlib.util.spec_from_file_location("gameplay_first_level_video", ROOT / "first-level-video.py")
video_app = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = video_app
spec.loader.exec_module(video_app)


class FakeWindowProbe:
    def list_games(self):
        return [{"id": 900, "pid": 999,
                 "title": "OpenLRR", "onscreen": True}]


class SessionModeTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)

    def invoke(self, argv):
        probe = FakeWindowProbe()
        with (mock.patch.object(sys, "platform", "darwin"),
              mock.patch.object(video_app.video_session, "build_video_tools",
                                return_value=(self.root / "video", self.root / "split")),
              mock.patch.object(video_app.capture, "build_probe",
                                return_value=self.root / "window"),
              mock.patch.object(video_app.capture, "WindowProbe", return_value=probe),
              mock.patch.object(video_app.first, "wait_for_game",
                                return_value=capture.GameWindow(900, 999)),
              mock.patch.object(video_app.capture, "next_session_path",
                                return_value=self.root / "private-capture"),
              mock.patch.object(video_app.video_session, "continuous_capture",
                                return_value={"video_complete": False}) as session):
            code = video_app.main(argv)
        self.assertEqual(code, 2)  # mock video not finalized; never fake success
        self.assertEqual(session.call_count, 1)
        return session.call_args.kwargs

    def test_menu_only_mode_has_short_ceiling_and_same_game_window(self):
        called = self.invoke(["--session", "menu"])
        self.assertEqual(called["max_seconds"], 15 * 60)
        self.assertEqual(called["video_fps"], 30)

    def test_full_mode_includes_menu_then_tutorial(self):
        called = self.invoke(["--session", "full"])
        self.assertEqual(called["max_seconds"], 120 * 60)

    def test_explicit_ceiling_is_honored(self):
        called = self.invoke(["--session", "menu", "--max-minutes", "8"])
        self.assertEqual(called["max_seconds"], 8 * 60)

    def test_invalid_mode_rejected_before_game(self):
        with (mock.patch.object(sys, "platform", "darwin"),
              mock.patch.object(video_app.video_session, "build_video_tools") as compile):
            with self.assertRaises(SystemExit):
                video_app.main(["--session", "unknown"])
            compile.assert_not_called()


if __name__ == "__main__":
    unittest.main()
