"""Safety-only macOS capture tests using synthetic window records and fake subprocesses."""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest import mock

MODULE = Path(__file__).resolve().parents[1] / "capture-test-window.py"
SPEC = importlib.util.spec_from_file_location("openlrr_test_capture", MODULE)
collector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(collector)


def window(window_id=301, pid=4201, width=800, height=600, layer=0):
    return {
        "kCGWindowNumber": window_id,
        "kCGWindowOwnerPID": pid,
        "kCGWindowLayer": layer,
        "kCGWindowBounds": {"Width": width, "Height": height},
        "kCGWindowOwnerName": "Isolated TEST",
        "kCGWindowName": "OpenLRR Menu TEST",
    }


class TestWindowCapture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.run_id = "autobenchmark-2026-10-18_19-02-03"
        self.run = self.root / self.run_id
        self.run.mkdir()
        self.approved = "a" * 64

    def test_reject_desktop_or_small_windows(self):
        self.assertIsNone(collector.normalize_window(window(layer=1)))
        self.assertIsNone(collector.normalize_window(window(width=100)))
        self.assertIsNone(collector.normalize_window(window(height=40)))
        self.assertIsNone(collector.normalize_window(window(pid=0)))
        self.assertIsNotNone(collector.normalize_window(window()))

    def test_explicit_window_id_required(self):
        with mock.patch.object(collector, "process_uses_test_game", return_value=True):
            with self.assertRaisesRegex(ValueError, "positive"):
                collector.eligible_window(0, [window()])
            with self.assertRaisesRegex(ValueError, "missing"):
                collector.eligible_window(99, [window()])

    def test_foreign_process_window_refused(self):
        with mock.patch.object(collector, "process_uses_test_game", return_value=False):
            with self.assertRaisesRegex(RuntimeError, "TEST game files"):
                collector.eligible_window(301, [window()])

    def test_lsof_must_show_exact_test_executable_file(self):
        expected = self.root / "OpenLRR Menu Test.app" / "drive_c"
        with mock.patch.object(collector, "GAME", expected), mock.patch.object(
                collector.subprocess, "run", return_value=subprocess.CompletedProcess(
                    [], 0, stdout="n/tmp/random/LegoRR.exe\n")):
            self.assertFalse(collector.process_uses_test_game(4201))
        with mock.patch.object(collector, "GAME", expected), mock.patch.object(
                collector.subprocess, "run", return_value=subprocess.CompletedProcess(
                    [], 0, stdout="n" + str(expected / "LegoRR.exe") + "\n")):
            self.assertTrue(collector.process_uses_test_game(4201))

    def test_requires_explicit_capture_and_macos(self):
        with self.assertRaisesRegex(ValueError, "confirm-test-only"):
            collector.capture_once(self.approved, self.run_id, 301)
        with mock.patch.object(collector.sys, "platform", "linux"):
            with self.assertRaisesRegex(RuntimeError, "macOS"):
                collector.capture_once(self.approved, self.run_id, 301,
                                       confirm_test_only=True)

    def test_preflight_checks_run_and_test_binary_sha(self):
        app = self.root / "OpenLRR Menu Test.app"
        game = app / "game"
        game.mkdir(parents=True)
        (game / "LegoRR.exe").write_bytes(b"synthetic exe")
        (game / "openlrr.dll").write_bytes(b"synthetic dll")
        good_hash = hashlib.sha256(b"synthetic dll").hexdigest()
        (self.run / "benchmark-openlrr.dll").write_bytes(b"synthetic dll")
        with mock.patch.object(collector, "APP", app), mock.patch.object(
                collector, "GAME", game), mock.patch.object(
                collector, "RUNS", self.root), mock.patch.object(
                collector, "stop_check", return_value=None):
            self.assertEqual(collector.test_install_preflight(good_hash, self.run_id), self.run)
            with self.assertRaisesRegex(RuntimeError, "approved SHA256"):
                collector.test_install_preflight("f" * 64, self.run_id)

    def test_only_window_id_capture_command_and_no_fallback(self):
        screenshot = self.run / "visual/menu.png"
        calls = []

        def fake_run(args, **kwargs):
            calls.append(args)
            self.assertEqual(args[0], "screencapture")
            self.assertIn("-l", args)
            self.assertNotIn("-D", args)
            self.assertNotIn("-R", args)
            self.assertEqual(args[-1], str(screenshot))
            # Standard 24-byte PNG header, followed by only synthetic bytes;
            # collector checks size/header, NOT game pixels.
            screenshot.write_bytes(
                collector.PNG + b"\0\0\0\x0dIHDR" + struct.pack(">II", 800, 600) + b"fake")
            return subprocess.CompletedProcess(args, 0, "", "")

        with mock.patch.object(collector.sys, "platform", "darwin"), mock.patch.object(
                collector, "test_install_preflight", return_value=self.run), mock.patch.object(
                collector, "window_info", return_value=[window()]), mock.patch.object(
                collector, "process_uses_test_game", return_value=True), mock.patch.object(
                collector, "stop_check", return_value=None), mock.patch.object(
                collector, "GAME", self.root / "test-game"), mock.patch.object(
                collector, "digest", return_value=self.approved), mock.patch.object(
                collector.subprocess, "run", side_effect=fake_run):
            result = collector.capture_once(self.approved, self.run_id, 301,
                                            confirm_test_only=True)
        self.assertEqual(result["relative_file"], "visual/menu.png")
        self.assertFalse(result["capture_origin_authenticated"])
        self.assertFalse(result["may_touch_working_game"])
        self.assertEqual(len(calls), 1)

    def test_capture_error_cleans_only_new_reserved_test_file(self):
        target = self.run / "visual/menu.png"
        with mock.patch.object(collector.sys, "platform", "darwin"), mock.patch.object(
                collector, "test_install_preflight", return_value=self.run), mock.patch.object(
                collector, "window_info", return_value=[window()]), mock.patch.object(
                collector, "process_uses_test_game", return_value=True), mock.patch.object(
                collector, "stop_check", return_value=None), mock.patch.object(
                collector.subprocess, "run", return_value=subprocess.CompletedProcess(
                    [], 1, "", "screen recording denied")):
            with self.assertRaisesRegex(RuntimeError, "no full-screen fallback"):
                collector.capture_once(self.approved, self.run_id, 301,
                                       confirm_test_only=True)
        self.assertFalse(target.exists())

    def test_existing_capture_file_is_never_overwritten(self):
        target = self.run / "visual/menu.png"
        target.parent.mkdir()
        target.write_bytes(b"preserve")
        with mock.patch.object(collector.sys, "platform", "darwin"), mock.patch.object(
                collector, "test_install_preflight", return_value=self.run), mock.patch.object(
                collector, "window_info", return_value=[window()]), mock.patch.object(
                collector, "process_uses_test_game", return_value=True):
            with self.assertRaises(FileExistsError):
                collector.capture_once(self.approved, self.run_id, 301,
                                       confirm_test_only=True)
        self.assertEqual(target.read_bytes(), b"preserve")

    def test_changed_window_owner_prevents_capture(self):
        with mock.patch.object(collector.sys, "platform", "darwin"), mock.patch.object(
                collector, "test_install_preflight", return_value=self.run), mock.patch.object(
                collector, "window_info", side_effect=[[window()], [window(pid=555)]]), mock.patch.object(
                collector, "process_uses_test_game", return_value=True), mock.patch.object(
                collector, "stop_check", return_value=None), mock.patch.object(
                collector.subprocess, "run") as capture:
            with self.assertRaisesRegex(RuntimeError, "owner changed"):
                collector.capture_once(self.approved, self.run_id, 301,
                                       confirm_test_only=True)
            capture.assert_not_called()
        self.assertFalse((self.run / "visual/menu.png").exists())


if __name__ == "__main__":
    unittest.main()
