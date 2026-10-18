"""Offline tests for evidence-based human escalation (no GitHub or OpenAI)."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "evidence_gate.py"
spec = importlib.util.spec_from_file_location("openlrr_evidence_gate", SOURCE)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class EvidenceGateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.serial = 0

    def run_record(self, present, fps=4.0, slow=10, errors=0, mode=None,
                   sha="a" * 64, verified=True, duration=63):
        self.serial += 1
        name = "autobenchmark-2026-10-18_17-{:02d}-{:02d}".format(
            self.serial // 60, self.serial % 60)
        run = self.root / name
        run.mkdir()
        if verified:
            (run / "lifecycle.verified").write_text(gate.LIFECYCLE_RECEIPT)
        summary = {
            "schema_version": 1, "run": name, "dll_sha256": sha,
            "close_requested": True, "metrics": {
                "mode": mode or {"optimization": 0, "nowait": 0, "gdi": 0},
                "present_avg_ms": present, "frame_flips_per_s": fps,
                "logged_duration_s": duration, "present_calls": 261,
                "present_accepted_percent": 100.0,
                "present_busy_calls": 0, "present_error_calls": errors,
                "present_intervals_over_1000ms": slow
            }}
        (run / "summary.json").write_text(json.dumps(summary))
        return name

    def manifest(self, number=5, candidate_ratio=0.82, fps=4.0, errors=0,
                 verified=True, changes=None):
        pairs = []
        for i in range(number):
            baseline = self.run_record(200 + i, fps=4.0)
            candidate = self.run_record((200 + i) * (candidate_ratio if changes is None else changes[i]),
                                        fps=fps, sha="b" * 64, errors=errors, verified=verified)
            pairs.append({"baseline": baseline, "candidate": candidate})
        return {"schema_version": 1, "experiment_id": "fast_present_test1",
                "hypothesis": "Test if a limited windowed presentation change reduces stalls.",
                "controlled_scene": "menu_boot_autotest_v1", "pairs": pairs}

    def test_good_repeatable_gain_requests_human_review_not_deployment(self):
        res = gate.decision(self.manifest(), self.root)
        self.assertEqual(res["status"], "candidate_for_review")
        self.assertTrue(res["notify_human"])
        self.assertFalse(res["automatic_promotion_allowed"])
        self.assertFalse(res["visual_fps_verified"])
        self.assertLess(res["bootstrap_upper95_change_pct"], -5)

    def test_two_runs_are_never_promoted(self):
        res = gate.decision(self.manifest(number=2), self.root)
        self.assertEqual(res["status"], "needs_more_data")
        self.assertFalse(res["notify_human"])

    def test_small_or_worse_results_not_promoted(self):
        for ratio, expected in ((0.99, "no_improvement"), (1.12, "no_improvement")):
            with self.subTest(ratio=ratio):
                self.setUp()
                res = gate.decision(self.manifest(candidate_ratio=ratio), self.root)
                self.assertEqual(res["status"], expected)
                self.assertFalse(res["notify_human"])

    def test_noisy_results_trigger_instrumentation_not_spam(self):
        res = gate.decision(self.manifest(changes=[0.75, 1.02, 0.80, 1.01, 0.77]), self.root)
        self.assertEqual(res["status"], "inconclusive")
        self.assertFalse(res["notify_human"])

    def test_false_gain_with_lost_throughput_is_regression(self):
        res = gate.decision(self.manifest(fps=3.7), self.root)
        self.assertEqual(res["status"], "regression")
        self.assertFalse(res["notify_human"])

    def test_incomplete_exit_is_hard_error(self):
        with self.assertRaisesRegex(ValueError, "Unverified Mac test lifecycle"):
            gate.decision(self.manifest(number=1, verified=False), self.root)

    def test_invalid_mode_and_scene_rejected(self):
        doc = self.manifest(number=1)
        doc["controlled_scene"] = "another_scene"
        with self.assertRaisesRegex(ValueError, "Scene"):
            gate.decision(doc, self.root)

    def test_no_unearned_significance(self):
        self.assertEqual(gate.quantile([10], .95), 10)
        self.assertAlmostEqual(gate.quantile([0, 10], .5), 5)


if __name__ == "__main__":
    unittest.main()
