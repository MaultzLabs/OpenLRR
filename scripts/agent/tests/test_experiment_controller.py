"""End-to-end offline tests for the verified research coordinator."""
import importlib.util
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

DIRECTORY = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DIRECTORY))
SPEC = importlib.util.spec_from_file_location(
    "openlrr_experiment_controller", DIRECTORY / "experiment_controller.py"
)
controller = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(controller)
RECEIPT = "wrapper_wait_exited=yes\ntest_game_handles=none\n"
TODAY = datetime(2026, 10, 18, 12, tzinfo=timezone.utc)


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.runs = self.home / "runs"
        self.runs.mkdir()
        self.manifest_path = self.home / "manifest.json"
        self.ledger = self.home / "decisions.json"
        self.switches = self.home / "switches"
        self.switches.mkdir()

    def record(self, idx: int, *, candidate: bool, good: bool = False,
               receipt: bool = True):
        run_id = f"autobenchmark-2026-10-18_17-{idx // 60:02d}-{idx % 60:02d}"
        directory = self.runs / run_id
        directory.mkdir()
        if receipt:
            (directory / "lifecycle.verified").write_text(RECEIPT)
        duration = 63.0
        present = 160.0 if (candidate and good) else 200.0
        payload = {
            "schema_version": 1, "run": run_id,
            "dll_sha256": ("b" if candidate else "a") * 64,
            "close_requested": True,
            "metrics": {
                "mode": {"optimization": 0, "nowait": 0, "gdi": 0},
                "present_avg_ms": present,
                "frame_flips_per_s": 4.0,
                "logged_duration_s": duration,
                "present_calls": 250,
                "present_accepted_percent": 100.0,
                "present_error_calls": 0,
                "present_busy_calls": 0,
                "present_intervals_over_1000ms": 5,
            },
        }
        (directory / "summary.json").write_text(json.dumps(payload))
        return run_id

    def write_manifest(self, *, count=2, good=False, receipt=True):
        pairs = []
        for i in range(count):
            left = self.record(i * 2 + 1, candidate=False)
            right = self.record(i * 2 + 2, candidate=True, good=good,
                                receipt=receipt)
            pairs.append({"baseline": left, "candidate": right})
        doc = {
            "schema_version": 1, "experiment_id": "controlled_ab_20261018",
            "hypothesis": "The source change reduces the slow windowed present calls.",
            "controlled_scene": "menu_boot_autotest_v1",
            "pairs": pairs,
        }
        self.manifest_path.write_text(json.dumps(doc))
        return doc

    def run_controller(self, *, commit=False, feedback=None):
        return controller.coordinate(
            self.manifest_path, self.runs, self.ledger,
            feedback=feedback, switches_dir=self.switches,
            commit=commit, now=TODAY
        )

    def test_research_action_writes_once_and_never_executes(self):
        self.write_manifest(count=5, good=False)
        first = self.run_controller(commit=True)
        self.assertEqual(first["next_step"], "new_hypothesis")
        self.assertEqual(first["disposition"], "ready_for_new_research")
        self.assertTrue(first["manifest_verified"])
        self.assertTrue(first["ledger_committed"])
        self.assertFalse(first["model_invoked"])
        self.assertFalse(first["may_install_or_run_candidate"])
        self.assertFalse(first["may_touch_working_game"])
        again = self.run_controller(commit=True)
        self.assertEqual(again["disposition"], "already_processed")
        self.assertFalse(again["ledger_committed"])
        self.assertEqual(len(json.loads(self.ledger.read_text())["events"]), 1)

    def test_proven_candidate_requires_human_not_auto_deploy(self):
        self.write_manifest(count=5, good=True)
        first = self.run_controller(commit=True)
        self.assertEqual(first["disposition"], "ready_to_notify_privately")
        self.assertEqual(first["next_step"], "hold_for_review")
        self.assertTrue(first["request_human_review"])
        self.assertFalse(first["may_deploy_automatically"])

    def test_two_pairs_are_insufficient_not_an_automatic_repeat(self):
        self.write_manifest(count=2, good=True)
        result = self.run_controller()
        self.assertEqual(result["next_step"], "complete_paired_measurement")
        self.assertEqual(result["disposition"], "requires_safe_worker_or_human")
        self.assertFalse(self.ledger.exists())

    def test_forged_benchmark_exit_receipt_prevents_decision(self):
        self.write_manifest(count=1, receipt=False)
        with self.assertRaisesRegex(ValueError, "Unverified Mac test lifecycle"):
            self.run_controller(commit=True)
        self.assertFalse(self.ledger.exists())

    def test_stop_and_pause_prevent_processing(self):
        self.write_manifest(count=1)
        for name in ("STOP", "PAUSE"):
            flag = self.switches / name
            flag.touch()
            with self.assertRaisesRegex(RuntimeError, "STOP or PAUSE"):
                self.run_controller(commit=True)
            flag.unlink()
        self.assertFalse(self.ledger.exists())

    def test_feedback_must_match_experiment_and_cannot_authorize_deploy(self):
        self.write_manifest(count=5, good=True)
        bad = {"experiment_id": "different", "decision": "good",
               "reason": "looks fine", "automatic_deploy_allowed": False}
        with self.assertRaisesRegex(ValueError, "another experiment"):
            self.run_controller(feedback=bad)
        bad["experiment_id"] = "controlled_ab_20261018"
        bad["automatic_deploy_allowed"] = True
        with self.assertRaisesRegex(ValueError, "prohibit"):
            self.run_controller(feedback=bad)
        bad["automatic_deploy_allowed"] = False
        success = self.run_controller(feedback=bad)
        self.assertEqual(success["next_step"], "prepare_manual_acceptance_check")
        self.assertFalse(success["may_deploy_automatically"])

    def test_per_day_budget_stops_more_model_research_requests(self):
        self.write_manifest(count=5)
        report = controller.evidence_gate.decision(
            json.loads(self.manifest_path.read_text()), self.runs)
        previous = []
        for i in range(3):
            previous.append({
                "fingerprint": f"{i + 1:064x}",
                "experiment_id": f"prior_{i}",
                "next_step": "new_hypothesis", "utc_day": "2026-10-18"
            })
        ledger = {"schema_version": 1, "events": previous}
        got = controller.decision_for(report, ledger, now=TODAY)
        self.assertEqual(got["disposition"], "daily_research_budget_exhausted")
        self.assertFalse(got["model_invoked"])
        previous[0]["utc_day"] = "2026-10-17"
        ready = controller.decision_for(report, ledger, now=TODAY)
        self.assertEqual(ready["disposition"], "ready_for_new_research")

    def test_lock_prevents_uncoordinated_writes(self):
        self.write_manifest(count=2)
        lock = self.ledger.with_name(self.ledger.name + ".lock")
        lock.touch()
        with self.assertRaisesRegex(RuntimeError, "already locked"):
            self.run_controller(commit=True)
        self.assertFalse(self.ledger.exists())
        self.assertTrue(lock.exists())

    def test_tampered_ledger_rejected(self):
        self.write_manifest(count=2)
        self.ledger.write_text(json.dumps({
            "schema_version": 1, "events": [{
                "fingerprint": "not-a-hash", "experiment_id": "prior",
                "next_step": "new_hypothesis", "utc_day": "2026-10-18"
            }]
        }))
        with self.assertRaisesRegex(ValueError, "fingerprint"):
            self.run_controller()

    def test_no_model_call_or_git_shell_reachable_from_controller(self):
        self.write_manifest(count=2)
        with mock.patch.object(controller.os, "system",
                               side_effect=AssertionError("unexpected shell")):
            result = self.run_controller(commit=True)
        self.assertFalse(result["candidate_compiled"])
        self.assertTrue(self.ledger.exists())


if __name__ == "__main__":
    unittest.main()
