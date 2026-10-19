"""No-network tests for independent private research intake."""
import base64
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import evidence_gate
import experiment_controller
import lab_policy
import private_research_inbox as inbox


class PrivateIntakeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.runs = self.root / "runs"
        self.runs.mkdir()
        self.remote = {}
        pairs = []
        for i in range(5):
            pair = {}
            for is_candidate in (False, True):
                n = 2 * i + 1 + int(is_candidate)
                name = "autobenchmark-2026-10-18_17-00-%02d" % n
                folder = self.runs / name
                folder.mkdir()
                data = {
                    "schema_version": 1, "run": name,
                    "dll_sha256": ("b" if is_candidate else "a") * 64,
                    "close_requested": True,
                    "metrics": {
                        "mode": {"optimization": 0, "nowait": 0, "gdi": 0},
                        "present_avg_ms": 220.0 if is_candidate else 200.0,
                        "frame_flips_per_s": 4.0,
                        "logged_duration_s": 62.0,
                        "present_calls": 200,
                        "present_accepted_percent": 100.0,
                        "present_busy_calls": 0,
                        "present_error_calls": 0,
                        "present_intervals_over_1000ms": 4,
                    },
                }
                self.remote["runs/" + name + "/summary.json"] = json.dumps(data).encode()
                self.remote["runs/" + name + "/lifecycle.verified"] = (
                    b"wrapper_wait_exited=yes\ntest_game_handles=none\n"
                )
                self.remote["runs/" + name + "/menuperf.csv"] = (
                    b"seconds,optimization,nowait,gdi,operation,calls,total_ms,max_ms\n"
                )
                for f in ("summary.json", "lifecycle.verified", "menuperf.csv"):
                    (folder / f).write_bytes(self.remote["runs/" + name + "/" + f])
                pair["candidate" if is_candidate else "baseline"] = name
            pairs.append(pair)
        self.doc = {
            "schema_version": 1,
            "experiment_id": "remote_diagnostics_001",
            "hypothesis": "The candidate presentation path reduces long DirectDraw stalls.",
            "controlled_scene": "menu_boot_autotest_v1",
            "pairs": pairs,
        }
        self.manifest = self.root / "remote_diagnostics_001.json"
        self.manifest.write_text(json.dumps(self.doc))
        self.remote["experiments/remote_diagnostics_001.json"] = self.manifest.read_bytes()
        gate = evidence_gate.decision(self.doc, self.runs)
        self.assertEqual(gate["status"], "no_improvement")
        policy = lab_policy.decide(gate)
        fingerprint = hashlib.sha256(
            experiment_controller.canonical({"report": gate, "feedback": None}).encode("ascii")
        ).hexdigest()
        self.id = "research_" + fingerprint[:24]
        self.ticket = {
            "schema_version": 1,
            "ticket_id": self.id,
            "experiment_id": self.doc["experiment_id"],
            "evidence_fingerprint": fingerprint,
            "next_step": "new_hypothesis",
            "reason": policy["why"],
            "requested_utc_day": "2026-10-18",
            "request_kind": "research_only",
            "approved_to_invoke_model": False,
            "approved_to_dispatch_cloud_workflow": False,
            "approved_to_compile": False,
            "approved_to_execute_game": False,
            "approved_to_deploy": False,
            "requires_separate_budget_and_dispatch_review": True,
        }
        self.remote["research-tickets/" + self.id + ".json"] = json.dumps(self.ticket).encode()

    def fake_gh(self, *args):
        if args[0:2] == ("repo", "view"):
            return "PRIVATE"
        if args[0] == "api":
            endpoint = args[1]
            path = endpoint.split("/contents/", 1)[1]
            if not path.endswith("?ref=main"):
                raise AssertionError("Unpinned private ref")
            path = path[:-9]
            if path not in self.remote:
                raise RuntimeError("missing private file")
            payload = self.remote[path]
            return json.dumps({
                "type": "file", "path": path, "size": len(payload),
                "sha": inbox.git_blob_sha(payload),
                "encoding": "base64", "content": base64.b64encode(payload).decode(),
            })
        raise AssertionError("unexpected network call")

    def test_valid_remote_ticket_is_verified_but_not_executable(self):
        with mock.patch.object(inbox, "gh", side_effect=self.fake_gh) as network:
            result = inbox.get_verified_ticket(self.id)
        self.assertGreaterEqual(network.call_count, 32)
        self.assertEqual(result["verified_evidence_status"], "no_improvement")
        self.assertEqual(result["verified_research_next_step"], "new_hypothesis")
        self.assertEqual(result["verified_matched_pairs"], 5)
        self.assertFalse(result["automatic_model_execution_allowed"])
        self.assertFalse(result["automatic_game_execution_allowed"])
        self.assertFalse(result["automatic_deployment_allowed"])

    def test_dry_run_never_calls_github(self):
        with mock.patch.object(inbox, "gh", side_effect=AssertionError("network")):
            self.assertEqual(inbox.main(["--ticket-id", self.id]), 0)

    def test_blob_checksum_tampering_detected(self):
        with mock.patch.object(inbox, "gh", side_effect=self.fake_gh):
            self.assertEqual(inbox.remote_blob(
                "research-tickets/" + self.id + ".json", max_size=20000),
                self.remote["research-tickets/" + self.id + ".json"])
        good = self.fake_gh("api", "repos/" + inbox.REPO
                            + "/contents/research-tickets/" + self.id + ".json?ref=main")
        corrupt = json.loads(good)
        corrupt["sha"] = "b" * 40
        with mock.patch.object(inbox, "gh", return_value=json.dumps(corrupt)):
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                inbox.remote_blob("research-tickets/" + self.id + ".json", max_size=20000)

    def test_ticket_cannot_be_escalated_to_execution(self):
        bad = dict(self.ticket)
        bad["approved_to_invoke_model"] = True
        with self.assertRaisesRegex(ValueError, "privilege escalation"):
            inbox.checked_ticket(bad, self.id)
        bad = dict(self.ticket)
        bad["approved_to_execute_game"] = True
        with self.assertRaisesRegex(ValueError, "privilege escalation"):
            inbox.checked_ticket(bad, self.id)

    def test_forged_research_justification_is_rejected(self):
        self.ticket["reason"] = "Run the unreviewed binary now"
        self.remote["research-tickets/" + self.id + ".json"] = json.dumps(self.ticket).encode()
        with mock.patch.object(inbox, "gh", side_effect=self.fake_gh):
            with self.assertRaisesRegex(ValueError, "reason differs"):
                inbox.get_verified_ticket(self.id)

    def test_forged_benchmark_metrics_are_detected(self):
        # The evidence gate compares the median of five paired runs, so
        # tampering with just one value can leave its summary unchanged.
        # Change all five candidate runs to ensure the recomputed evidence
        # fingerprint differs while retaining the no_improvement category.
        for pair in self.doc["pairs"]:
            candidate = pair["candidate"]
            key = "runs/" + candidate + "/summary.json"
            changed = json.loads(self.remote[key])
            changed["metrics"]["present_avg_ms"] = 240.0
            self.remote[key] = json.dumps(changed).encode()
        with mock.patch.object(inbox, "gh", side_effect=self.fake_gh):
            with self.assertRaisesRegex(ValueError, "fingerprint disagrees"):
                inbox.get_verified_ticket(self.id)

    def test_missing_exit_receipt_fails_closed(self):
        first = self.doc["pairs"][0]["candidate"]
        self.remote["runs/" + first + "/lifecycle.verified"] = b"not_verified"
        with mock.patch.object(inbox, "gh", side_effect=self.fake_gh):
            with self.assertRaisesRegex(ValueError, "Unverified Mac test lifecycle"):
                inbox.get_verified_ticket(self.id)

    def test_public_repository_never_accepted(self):
        with mock.patch.object(inbox, "gh", return_value="PUBLIC"):
            with self.assertRaisesRegex(RuntimeError, "private"):
                inbox.get_verified_ticket(self.id)

    def test_reviewer_feedback_ticket_requires_authenticated_review(self):
        bad = dict(self.ticket)
        bad["next_step"] = "revise_hypothesis_from_feedback"
        bad["reason"] = "Specific user said to keep going"
        self.remote["research-tickets/" + self.id + ".json"] = json.dumps(bad).encode()
        with mock.patch.object(inbox, "gh", side_effect=self.fake_gh):
            with self.assertRaisesRegex(ValueError, "not authenticated"):
                inbox.get_verified_ticket(self.id)


if __name__ == "__main__":
    unittest.main()
