#!/usr/bin/env python3
"""Offline fixture tests. No game installation, GitHub token or network needed."""
import csv
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "analyze-benchmark.py"
spec = importlib.util.spec_from_file_location("benchmark_analyzer", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def make_csv(directory, *, mode=(0, 0, 0), malformed=False):
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "menuperf.csv"
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(module.HEADER if not malformed else ["unknown", "header"])
        for seconds, present_ms in [(1.1, 1200), (1.3, 200)]:
            writer.writerow([seconds, *mode, "frame_flip", 1, present_ms, present_ms])
            writer.writerow([seconds, *mode, "window_present_blt", 1, present_ms, present_ms])
    return path


class AnalyzerTests(unittest.TestCase):
    def test_correct_totals_and_safe_report(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "autobenchmark-2026-10-18_22-01-01"
            make_csv(run)
            (run / "menuperf.finished").write_text("close requested")
            (run / "benchmark-openlrr.dll").write_bytes(b"MZtest-pe-payload")
            completed = subprocess.run([sys.executable, str(SCRIPT), str(run)],
                                       capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            summary = json.loads((run / "summary.json").read_text())
            stats = summary["metrics"]
            self.assertEqual(stats["present_calls"], 2)
            self.assertEqual(stats["frame_flips"], 2)
            self.assertAlmostEqual(stats["present_total_s"], 1.4)
            self.assertAlmostEqual(stats["present_avg_ms"], 700)
            self.assertEqual(stats["present_intervals_over_1000ms"], 1)
            self.assertTrue(summary["close_requested"])
            self.assertEqual(summary["dll_sha256"], hashlib.sha256(b"MZtest-pe-payload").hexdigest())
            self.assertNotIn(tmp, (run / "report.txt").read_text())
            self.assertNotIn(tmp, (run / "summary.json").read_text())

    def test_comparison_warns_when_renderer_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            baseline = make_csv(root / "autobenchmark-baseline")
            candidate = root / "autobenchmark-candidate"
            make_csv(candidate, mode=(0, 0, 1))
            done = subprocess.run([sys.executable, str(SCRIPT), str(candidate),
                                   "--baseline", str(baseline)],
                                  capture_output=True, text=True)
            self.assertEqual(done.returncode, 0, done.stderr)
            summary = json.loads((candidate / "summary.json").read_text())
            self.assertFalse(summary["comparison"]["graphics_modes_match"])
            self.assertEqual(summary["comparison"]["percentage_change"]["present_avg_ms"], 0)

    def test_malformed_header_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "autobenchmark-malformed"
            make_csv(run, malformed=True)
            completed = subprocess.run([sys.executable, str(SCRIPT), str(run)],
                                       capture_output=True, text=True)
            self.assertNotEqual(completed.returncode, 0)
            self.assertFalse((run / "summary.json").exists())


if __name__ == "__main__":
    unittest.main()
