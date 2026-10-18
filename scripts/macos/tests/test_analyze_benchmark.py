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


def make_csv(directory, *, mode=(0, 0, 0), malformed=False, outcomes=False):
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "menuperf.csv"
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(module.HEADER if not malformed else ["unknown", "header"])
        for index, (seconds, present_ms) in enumerate([(1.1, 1200), (1.3, 200)]):
            writer.writerow([seconds, *mode, "frame_flip", 1, present_ms, present_ms])
            if mode[2]:
                writer.writerow([seconds, *mode, "gdi_window_attempt", 1, present_ms, present_ms])
                writer.writerow([seconds, *mode, "gdi_present_accepted", 1, 0, 0])
                writer.writerow([seconds, *mode, "gdi_present_fallback", 0, 0, 0])
                writer.writerow([seconds, *mode, "window_present_blt", 0, 0, 0])
            else:
                writer.writerow([seconds, *mode, "window_present_blt", 1, present_ms, present_ms])
            if outcomes:
                writer.writerow([seconds, *mode, "window_present_accepted", int(index == 0), 0, 0])
                writer.writerow([seconds, *mode, "window_present_busy", int(index == 1), 0, 0])
                writer.writerow([seconds, *mode, "window_present_error", 0, 0, 0])
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

    def test_present_results_distinguish_busy_from_accepted_frames(self):
        with tempfile.TemporaryDirectory() as tmp:
            candidate = Path(tmp) / "autobenchmark-nowait"
            make_csv(candidate, mode=(0, 1, 0), outcomes=True)
            completed = subprocess.run([sys.executable, str(SCRIPT), str(candidate)],
                                       capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            metrics = json.loads((candidate / "summary.json").read_text())["metrics"]
            self.assertEqual(metrics["present_accepted_calls"], 1)
            self.assertEqual(metrics["present_busy_calls"], 1)
            self.assertEqual(metrics["present_error_calls"], 0)
            self.assertEqual(metrics["present_accepted_percent"], 50.0)

    def test_gdi_success_reports_real_present_time_not_zero_directdraw_blts(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "autobenchmark-gdi"
            make_csv(run, mode=(0, 0, 1))
            completed = subprocess.run([sys.executable, str(SCRIPT), str(run)],
                                       capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            stats = json.loads((run / "summary.json").read_text())["metrics"]
            self.assertEqual(stats["present_path"], "gdi")
            self.assertEqual(stats["present_calls"], 2)
            self.assertEqual(stats["gdi_accepted_calls"], 2)
            self.assertEqual(stats["gdi_fallback_calls"], 0)
            self.assertEqual(stats["present_accepted_percent"], 100.0)
            self.assertAlmostEqual(stats["present_avg_ms"], 700)
            self.assertAlmostEqual(stats["present_total_s"], 1.4)

    def test_gdi_fallback_includes_directdraw_time(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "autobenchmark-gdi-fallback"
            make_csv(run, mode=(0, 0, 1))
            with (run / "menuperf.csv").open("a", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerow([1.1, 0, 0, 1, "gdi_present_fallback", 1, 0, 0])
                writer.writerow([1.1, 0, 0, 1, "window_present_blt", 1, 300, 300])
                writer.writerow([1.1, 0, 0, 1, "window_present_accepted", 1, 0, 0])
            # The extra fallback does not match attempted GDI counts and
            # must fail closed rather than offering a bogus improvement.
            completed = subprocess.run([sys.executable, str(SCRIPT), str(run)],
                                       capture_output=True, text=True)
            self.assertNotEqual(completed.returncode, 0)

    def test_gdi_fallback_adds_both_phases_without_lying_about_worst(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "autobenchmark-gdi-fallback-success"
            run.mkdir()
            with (run / "menuperf.csv").open("w", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerow(module.HEADER)
                for operation, calls, total_ms, max_ms in (
                        ("frame_flip", 1, 500, 500),
                        ("gdi_window_attempt", 1, 50, 50),
                        ("gdi_present_accepted", 0, 0, 0),
                        ("gdi_present_fallback", 1, 0, 0),
                        ("window_present_blt", 1, 450, 450),
                        ("window_present_accepted", 1, 0, 0),
                        ("window_present_busy", 0, 0, 0),
                        ("window_present_error", 0, 0, 0)):
                    writer.writerow([1.1, 0, 0, 1, operation, calls, total_ms, max_ms])
            completed = subprocess.run([sys.executable, str(SCRIPT), str(run)],
                                       capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            metrics = json.loads((run / "summary.json").read_text())["metrics"]
            self.assertEqual(metrics["present_calls"], 1)
            self.assertAlmostEqual(metrics["present_avg_ms"], 500.0)
            self.assertEqual(metrics["gdi_fallback_calls"], 1)
            self.assertFalse(metrics["present_worst_is_exact"])

    def test_new_timers_split_outside_work_from_present_calls(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "autobenchmark-profiling"
            make_csv(run)
            with (run / "menuperf.csv").open("a", newline="") as handle:
                writer = csv.writer(handle)
                # 2 flip entries, with one long gap outside the flip function.
                for name, calls, total, maximum in (
                        ("frame_start_gap", 2, 1800, 1500),
                        ("frame_outside_flip", 2, 1200, 1120),
                        ("window_blt_over_100ms", 2, 0, 0),
                        ("window_blt_over_1000ms", 1, 0, 0),
                        ("frame_outside_over_100ms", 1, 0, 0),
                        ("frame_outside_over_1000ms", 1, 0, 0)):
                    writer.writerow([1.1, 0, 0, 0, name, calls, total, maximum])
            completed = subprocess.run([sys.executable, str(SCRIPT), str(run)],
                                       capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            metrics = json.loads((run / "summary.json").read_text())["metrics"]
            self.assertTrue(metrics["frame_timing_diagnostics_available"])
            self.assertEqual(metrics["frame_outside_flip_avg_ms"], 600)
            self.assertEqual(metrics["frame_start_gap_worst_ms"], 1500)
            self.assertEqual(metrics["window_blt_calls_over_1000ms"], 1)
            self.assertEqual(metrics["outside_flip_calls_over_1000ms"], 1)
            self.assertIn("Time outside Flip", (run / "report.txt").read_text())

    def test_old_benchmarks_report_missing_not_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "autobenchmark-older"
            make_csv(run)
            completed = subprocess.run([sys.executable, str(SCRIPT), str(run)],
                                       capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            metrics = json.loads((run / "summary.json").read_text())["metrics"]
            self.assertFalse(metrics["frame_timing_diagnostics_available"])
            self.assertIsNone(metrics["outside_flip_calls_over_1000ms"])

    def test_incomplete_diagnostics_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "autobenchmark-broken-profiling"
            make_csv(run)
            with (run / "menuperf.csv").open("a", newline="") as handle:
                csv.writer(handle).writerow(
                    [1.1, 0, 0, 0, "frame_outside_flip", 1, 100, 100])
            completed = subprocess.run([sys.executable, str(SCRIPT), str(run)],
                                       capture_output=True, text=True)
            self.assertNotEqual(completed.returncode, 0)
            self.assertFalse((run / "summary.json").exists())

    def test_cpu_probe_classifies_long_blt_without_claiming_wine_root_cause(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "autobenchmark-cpu-probe"
            make_csv(run)
            with (run / "menuperf.csv").open("a", newline="") as handle:
                writer = csv.writer(handle)
                for name, calls, total_ms in (
                    ("window_blt_thread_cpu", 2, 18),
                    ("window_blt_slow_thread_cpu", 1, 7),
                    ("window_blt_cpu_unavailable", 0, 0),
                    ("window_blt_slow_low_cpu", 1, 0),
                ):
                    writer.writerow([1.1, 0, 0, 0, name, calls, total_ms, total_ms])
            done = subprocess.run([sys.executable, str(SCRIPT), str(run)],
                                  capture_output=True, text=True)
            self.assertEqual(done.returncode, 0, done.stderr)
            summary = json.loads((run / "summary.json").read_text())["metrics"]
            self.assertTrue(summary["blit_cpu_probe_available"])
            self.assertEqual(summary["blit_thread_cpu_avg_ms"], 9)
            self.assertEqual(summary["blit_slow_cpu_samples"], 1)
            self.assertEqual(summary["blit_slow_low_cpu_calls"], 1)

    def test_cpu_probe_unavailable_is_not_reported_as_zero_cpu(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "autobenchmark-cpu-unavailable"
            make_csv(run)
            with (run / "menuperf.csv").open("a", newline="") as handle:
                writer = csv.writer(handle)
                for name, calls in (
                    ("window_blt_thread_cpu", 0),
                    ("window_blt_slow_thread_cpu", 0),
                    ("window_blt_cpu_unavailable", 2),
                    ("window_blt_slow_low_cpu", 0),
                ):
                    writer.writerow([1.1, 0, 0, 0, name, calls, 0, 0])
            done = subprocess.run([sys.executable, str(SCRIPT), str(run)],
                                  capture_output=True, text=True)
            self.assertEqual(done.returncode, 0, done.stderr)
            summary = json.loads((run / "summary.json").read_text())["metrics"]
            self.assertTrue(summary["blit_cpu_probe_available"])
            self.assertIsNone(summary["blit_thread_cpu_avg_ms"])
            self.assertEqual(summary["blit_thread_cpu_unavailable"], 2)

    def test_cpu_probe_rejects_inconsistent_call_count(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "autobenchmark-cpu-incomplete"
            make_csv(run)
            with (run / "menuperf.csv").open("a", newline="") as handle:
                writer = csv.writer(handle)
                for name, calls in (
                    ("window_blt_thread_cpu", 1),
                    ("window_blt_slow_thread_cpu", 1),
                    ("window_blt_cpu_unavailable", 0),
                    ("window_blt_slow_low_cpu", 1),
                ):
                    writer.writerow([1.1, 0, 0, 0, name, calls, 0, 0])
            done = subprocess.run([sys.executable, str(SCRIPT), str(run)],
                                  capture_output=True, text=True)
            self.assertNotEqual(done.returncode, 0)
            self.assertFalse((run / "summary.json").exists())

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
