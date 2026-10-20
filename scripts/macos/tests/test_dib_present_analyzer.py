"""Read-only regression proof for the TEST-only CPU DIB presenting candidate."""
import csv
import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "analyze-benchmark.py"
spec = importlib.util.spec_from_file_location("dib_analyzer", SCRIPT)
analyze = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyze)

DIB = ("dib_window_attempt", "dib_backbuffer_lock", "dib_stretchdibits",
       "dib_backbuffer_unlock", "dib_present_accepted", "dib_present_fallback")


def write_run(path: Path, *, fallback=False, corrupt=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    metrics = [
        ("frame_flip", 1, 500),
        ("window_present_blt", int(fallback), 450 if fallback else 0),
        ("window_present_accepted", int(fallback), 0),
        ("window_present_busy", 0, 0),
        ("window_present_error", 0, 0),
        ("dib_window_attempt", 1, 50 if fallback else 85),
        ("dib_backbuffer_lock", 1, 5 if fallback else 10),
        ("dib_stretchdibits", 0 if fallback else 1, 0 if fallback else 70),
        ("dib_backbuffer_unlock", 0 if fallback else 1, 0 if fallback else 2),
        ("dib_present_accepted", 0 if fallback else 1, 0),
        ("dib_present_fallback", int(fallback), 0),
    ]
    if corrupt:
        metrics = [(n, (int(v) if n != corrupt else int(v) + 1), ms)
                   for n, v, ms in metrics]
    with path.open("w", newline="") as output:
        writer = csv.writer(output)
        writer.writerow(analyze.HEADER)
        for name, calls, ms in metrics:
            writer.writerow([1.25, 0, 0, 0, name, calls, ms, ms])
    return path


class DibAnalysisTests(unittest.TestCase):
    def test_success_is_real_cpu_side_present_without_directdraw_blt(self):
        with tempfile.TemporaryDirectory() as t:
            run = write_run(Path(t) / "menuperf.csv")
            stats = analyze.analyze_csv(run)
            self.assertEqual(stats["present_path"], "dib_cpu")
            self.assertEqual(stats["present_calls"], 1)
            self.assertEqual(stats["present_accepted_calls"], 1)
            self.assertEqual(stats["present_accepted_percent"], 100)
            self.assertEqual(stats["dib_accepted_calls"], 1)
            self.assertEqual(stats["dib_fallback_calls"], 0)
            self.assertEqual(stats["mode"]["dib"], True)
            self.assertAlmostEqual(stats["present_avg_ms"], 85)
            self.assertEqual(stats["dib_lock_max_ms"], 10)
            self.assertEqual(stats["dib_copy_max_ms"], 70)
            self.assertFalse(stats["gdi_accepted_calls"])

    def test_fallback_time_included_without_claiming_exact_worst(self):
        with tempfile.TemporaryDirectory() as t:
            run = write_run(Path(t) / "menuperf.csv", fallback=True)
            stats = analyze.analyze_csv(run)
            self.assertEqual(stats["present_path"], "dib_cpu")
            self.assertEqual(stats["dib_fallback_calls"], 1)
            self.assertEqual(stats["present_calls"], 1)
            self.assertAlmostEqual(stats["present_avg_ms"], 500)
            self.assertFalse(stats["present_worst_is_exact"])
            self.assertEqual(stats["present_accepted_calls"], 1)

    def test_inconsistent_dib_outcomes_fail_closed(self):
        with tempfile.TemporaryDirectory() as t:
            run = write_run(Path(t) / "menuperf.csv", corrupt="dib_present_fallback")
            with self.assertRaisesRegex(ValueError, "DIB accepted/fallback"):
                analyze.analyze_csv(run)

    def test_no_double_count_blt_with_success(self):
        with tempfile.TemporaryDirectory() as t:
            run = write_run(Path(t) / "menuperf.csv", corrupt="window_present_blt")
            with self.assertRaisesRegex(ValueError, "DIB fallback count"):
                analyze.analyze_csv(run)

    def test_incomplete_dib_metrics_fail_closed(self):
        with tempfile.TemporaryDirectory() as t:
            run = write_run(Path(t) / "menuperf.csv")
            raw = run.read_text()
            run.write_text("\n".join(line for line in raw.splitlines()
                                     if ",dib_backbuffer_unlock," not in line) + "\n")
            with self.assertRaisesRegex(ValueError, "Partial DIB"):
                analyze.analyze_csv(run)

    def test_candidate_dib_mode_is_not_baseline(self):
        with tempfile.TemporaryDirectory() as t:
            folder = Path(t)
            run = write_run(folder / "candidate.csv")
            original = folder / "baseline.csv"
            with original.open("w", newline="") as output:
                w = csv.writer(output)
                w.writerow(analyze.HEADER)
                for operation, calls, total in (
                    ("frame_flip", 1, 500),
                    ("window_present_blt", 1, 450),
                    ("window_present_accepted", 1, 0),
                ):
                    w.writerow([1.25, 0, 0, 0, operation, calls, total, total])
            compared = analyze.make_comparison(
                analyze.analyze_csv(run), analyze.analyze_csv(original))
            self.assertFalse(compared["graphics_modes_match"])

if __name__ == "__main__":
    unittest.main()
