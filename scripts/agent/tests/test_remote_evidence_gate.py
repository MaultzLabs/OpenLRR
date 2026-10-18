"""Synthetic private evidence: no GitHub network, Mac execution, or model calls."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

AGENT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(AGENT_DIR))
SPEC = importlib.util.spec_from_file_location(
    "openlrr_remote_evidence_gate", AGENT_DIR / "remote_evidence_gate.py"
)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class PrivateRemoteEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.runs = self.root / "runs"
        self.runs.mkdir()
        self.manifest = self.root / "exp.json"
        self.pairs = []

    def record(self, number, is_candidate=False, *, with_receipt=True, sha=None):
        name = "autobenchmark-2026-10-18_17-00-%02d" % number
        folder = self.runs / name
        folder.mkdir()
        if with_receipt:
            (folder / "lifecycle.verified").write_text(
                "wrapper_wait_exited=yes\ntest_game_handles=none\n")
        (folder / "summary.json").write_text(json.dumps({
            "schema_version": 1, "run": name,
            "dll_sha256": sha or (("b" if is_candidate else "a") * 64),
            "close_requested": True,
            "metrics": {
                "mode": {"optimization": 0, "nowait": 0, "gdi": 0},
                "present_avg_ms": 160.0 if is_candidate else 200.0,
                "frame_flips_per_s": 4.0,
                "logged_duration_s": 63.0, "present_calls": 220,
                "present_accepted_percent": 100.0,
                "present_busy_calls": 0, "present_error_calls": 0,
                "present_intervals_over_1000ms": 5,
            },
        }))
        return name

    def experiment(self, count=5):
        for i in range(count):
            baseline = self.record(2 * i + 1)
            candidate = self.record(2 * i + 2, is_candidate=True)
            self.pairs.append({"baseline": baseline, "candidate": candidate})
        self.manifest.write_text(json.dumps({
            "schema_version": 1, "experiment_id": "source_fix_20261018",
            "hypothesis": "Review a measured source change against an unchanged DLL.",
            "controlled_scene": "menu_boot_autotest_v1",
            "pairs": self.pairs,
        }))

    def test_five_verified_pairs_held_for_visual_review(self):
        self.experiment()
        result = gate.evaluate(self.manifest, self.runs)
        self.assertEqual(result["evidence_gate"]["status"], "candidate_for_review")
        self.assertEqual(result["research_policy"]["next_step"], "hold_for_review")
        self.assertFalse(result["may_deploy_automatically"])
        self.assertFalse(result["may_execute_candidate"])
        self.assertFalse(result["evidence_gate"]["visual_fps_verified"])

    def test_two_pairs_not_automatic_approval(self):
        self.experiment(count=2)
        result = gate.evaluate(self.manifest, self.runs)
        self.assertEqual(result["evidence_gate"]["status"], "needs_more_data")
        self.assertNotEqual(result["next_owner_action"], "human_visual_review")

    def test_missing_or_tampered_remote_exit_receipt_fails_closed(self):
        self.experiment(count=2)
        path = self.runs / self.pairs[0]["candidate"] / "lifecycle.verified"
        path.unlink()
        with self.assertRaisesRegex(ValueError, "Unverified"):
            gate.evaluate(self.manifest, self.runs)
        path.write_text("wrapper_wait_exited=yes\ntest_game_handles=unknown\n")
        with self.assertRaisesRegex(ValueError, "Unverified"):
            gate.evaluate(self.manifest, self.runs)

    def test_equal_hashes_cannot_claim_source_change(self):
        self.experiment(count=2)
        for pair in self.pairs:
            path = self.runs / pair["candidate"] / "summary.json"
            data = json.loads(path.read_text())
            data["dll_sha256"] = "a" * 64
            path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "No experimental intervention"):
            gate.evaluate(self.manifest, self.runs)

    def test_prohibited_manifest_symlink(self):
        self.experiment(count=2)
        link = self.root / "linked.json"
        link.symlink_to(self.manifest)
        with self.assertRaisesRegex(ValueError, "symlinked"):
            gate.evaluate(link, self.runs)

    def test_output_never_overwrites_previous_evidence(self):
        self.experiment(count=2)
        result_file = self.root / "report.json"
        self.assertEqual(gate.main([
            "--manifest", str(self.manifest),
            "--runs-dir", str(self.runs),
            "--out", str(result_file)]), 0)
        with self.assertRaisesRegex(RuntimeError, "already exists"):
            gate.main([
                "--manifest", str(self.manifest),
                "--runs-dir", str(self.runs),
                "--out", str(result_file)])


if __name__ == "__main__":
    unittest.main()
