"""Deterministic TEST run timing/boot consistency tests; no game or Mac needed."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SOURCE = Path(__file__).resolve().parents[1] / "visual_timeline.py"
spec = importlib.util.spec_from_file_location("visual_timeline", SOURCE)
vt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vt)

RUN_NAME = "autobenchmark-2026-10-18_20-09-00"
SHA = "a" * 64
BOOT = "b" * 64


def at(seconds: int, *, boot: str = BOOT, wall_shift: int = 0):
    return {"wall_ns": 1_800_000_000_000_000_000 + seconds * 1_000_000_000 + wall_shift,
            "mono_ns": 40_000_000_000 + seconds * 1_000_000_000,
            "boot_sha256": boot}


class VisualTimingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.run = Path(self.tmp.name) / RUN_NAME
        self.run.mkdir()
        (self.run / "lifecycle.verified").write_text(
            "wrapper_wait_exited=yes\ntest_game_handles=none\n", encoding="utf-8")

    def test_start_and_finish_markers_are_immutable(self):
        start = vt.begin(self.run, SHA, "baseline", clock=at(1))
        end = vt.finish(self.run, clock=at(10))
        self.assertEqual(start["start"], at(1))
        self.assertTrue(end["clean_exit_checked"])
        self.assertEqual(end["end"], at(10))
        with self.assertRaisesRegex(ValueError, "restarted"):
            vt.begin(self.run, SHA, "baseline", clock=at(11))
        with self.assertRaises(FileExistsError):
            vt.finish(self.run, clock=at(12))

    def test_missing_clean_exit_blocks_end_marker(self):
        (self.run / "lifecycle.verified").unlink()
        vt.begin(self.run, SHA, "baseline", clock=at(1))
        with self.assertRaisesRegex(ValueError, "clean lifecycle"):
            vt.finish(self.run, clock=at(10))
        self.assertFalse((self.run / "run-timing.end.json").exists())

    def test_boot_change_refused(self):
        vt.begin(self.run, SHA, "baseline", clock=at(1))
        with self.assertRaisesRegex(ValueError, "different host boots"):
            vt.finish(self.run, clock=at(10, boot="c" * 64))

    def test_clock_step_refused(self):
        vt.begin(self.run, SHA, "baseline", clock=at(1))
        with self.assertRaisesRegex(ValueError, "clock stepped"):
            vt.finish(self.run, clock=at(10, wall_shift=5_000_000_000))

    def test_out_of_bounds_elapsed_refused(self):
        vt.begin(self.run, SHA, "baseline", clock=at(1))
        with self.assertRaisesRegex(ValueError, "time range"):
            vt.finish(self.run, clock=at(1))
        with self.assertRaisesRegex(ValueError, "time range"):
            vt.finish(self.run, clock=at(2000))

    def test_bad_run_and_dll_refused(self):
        with self.assertRaisesRegex(ValueError, "Invalid TEST"):
            vt.begin(self.run, "bad", "baseline", clock=at(1))
        with self.assertRaisesRegex(ValueError, "Invalid TEST"):
            vt.begin(self.run, SHA, "unknown", clock=at(1))

    def test_symlinked_run_refused(self):
        alias = self.run.parent / "alias"
        alias.symlink_to(self.run, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlinks"):
            vt.begin(alias, SHA, "baseline", clock=at(1))

    def test_unsafe_or_missing_clock_data_refused(self):
        with self.assertRaisesRegex(ValueError, "Invalid timing clock"):
            vt.same_boot({"wall_ns": -1, "mono_ns": 1, "boot_sha256": BOOT},
                         at(5))
        with self.assertRaisesRegex(ValueError, "Malformed timing sample"):
            vt.same_boot({"mono_ns": 5}, at(5))

    def test_clock_read_bounds(self):
        with mock.patch.object(vt.time, "monotonic_ns", side_effect=[1, 1_000_000_000]), mock.patch.object(
                vt.time, "time_ns", return_value=50):
            with self.assertRaisesRegex(RuntimeError, "Unreliable"):
                vt.sample_clock()

    def test_existing_start_cannot_be_overwritten(self):
        vt.begin(self.run, SHA, "baseline", clock=at(1))
        original = (self.run / "run-timing.start.json").read_bytes()
        with self.assertRaises(FileExistsError):
            vt.begin(self.run, SHA, "baseline", clock=at(2))
        self.assertEqual((self.run / "run-timing.start.json").read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
