"""Synthetic-only safety tests: actual OpenLRR or Wine are never executed."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "paired-dll-eval.py"
SPEC = importlib.util.spec_from_file_location("openlrr_paired_dll_eval", SCRIPT)
lab = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lab)


def pe_stub(path: Path, character: int):
    header = bytearray(512)
    header[:2] = b"MZ"
    header[0x3c:0x40] = (128).to_bytes(4, "little")
    header[128:132] = b"PE\0\0"
    header[132:134] = (0x14c).to_bytes(2, "little")
    header[200] = character
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header)
    return hashlib.sha256(header).hexdigest()


class PairedDllTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.state = self.root / "state"
        self.state.mkdir()
        self.config = self.root / "config"
        self.config.mkdir()
        self.results = self.root / "results"
        self.results.mkdir()
        self.download = self.root / "Downloads/openlrr.dll"
        self.download.parent.mkdir()
        self.baseline = self.state / "approved-baselines/openlrr.dll"
        self.candidate = self.root / "quarantine/run-39169390987/openlrr.dll"
        self.base_sha = pe_stub(self.baseline, 42)
        self.cand_sha = pe_stub(self.candidate, 43)
        (self.candidate.parent / "SHA256.txt").write_text(self.cand_sha + "\n")
        (self.candidate.parent / "proposal.patch").write_text(
            "--- a/src/openlrr/engine/drawing/DirectDraw.cpp\n"
            "+++ b/src/openlrr/engine/drawing/DirectDraw.cpp\n"
            "@@ -1 +1 @@\n-old\n+new\n")
        (self.candidate.parent / "proposal.json").write_text(json.dumps({
            "source_file": "src/openlrr/engine/drawing/DirectDraw.cpp",
            "status": "patch_ready", "review_required": True,
            "host_execution_authorized": False,
        }))
        (self.candidate.parent / "REVIEW-REQUIRED.txt").write_text(
            "Manual execution approval required")
        (self.candidate.parent / "provenance.json").write_text(json.dumps({
            "run_id": "39169390987", "candidate_sha256": self.cand_sha,
            "automatic_execution": False,
        }))
        self.supervisor = self.root / "OpenLRR-Agent/scripts/macos/lab-supervisor.py"
        self.controller = self.root / "OpenLRR-Agent/scripts/agent/experiment_controller.py"
        self.python = self.state / "venv/bin/python"
        for p in (self.supervisor, self.controller, self.python):
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("fixture")
        for key, value in {
            "STATE": self.state, "CONFIG": self.config, "RESULTS": self.results,
            "DOWNLOAD_DLL": self.download,
            "BACKUP": self.download.parent / ".openlrr-paired-eval-original.dll",
            "TEMP": self.download.parent / ".openlrr-paired-eval-pending.dll",
            "BASELINE": self.baseline,
            "INBOX": self.root / "quarantine",
            "LOCK": self.state / "paired-eval.lock",
            "SUPERVISOR": self.supervisor,
            "CONTROLLER": self.controller,
            "PYTHON": self.python,
        }.items():
            patcher = mock.patch.object(lab, key, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_dry_run_does_not_modify_a_file_or_invoke_game(self):
        with mock.patch.object(lab, "candidate_source", return_value=self.candidate), \
             mock.patch.object(lab.subprocess, "run",
                               side_effect=AssertionError("No game or API permitted")), \
             mock.patch.object(lab, "stage_source",
                               side_effect=AssertionError("Cannot stage DLL")):
            self.assertEqual(lab.main([
                "--baseline-sha", self.base_sha,
                "--candidate-sha", self.cand_sha,
                "--candidate-run-id", "39169390987",
            ]), 0)
        self.assertFalse(self.download.exists())
        self.assertFalse(lab.LOCK.exists())

    def test_mismatched_or_identical_hashes_and_stop_rejected(self):
        with mock.patch.object(lab, "candidate_source", return_value=self.candidate):
            with self.assertRaisesRegex(ValueError, "two distinct"):
                lab.preflight(self.base_sha, self.base_sha, "39169390987", 1, 60)
            with self.assertRaisesRegex(ValueError, "hash disagrees"):
                lab.preflight(self.base_sha, "a" * 64, "39169390987", 1, 60)
            with self.assertRaisesRegex(ValueError, "Limited"):
                lab.preflight(self.base_sha, self.cand_sha, "39169390987", 6, 60)
            (self.config / "STOP").touch()
            with self.assertRaisesRegex(RuntimeError, "STOP or PAUSE"):
                lab.preflight(self.base_sha, self.cand_sha, "39169390987", 1, 60)

    def test_unrecovered_original_backup_blocks_new_trial(self):
        lab.BACKUP.write_bytes(b"original")
        with mock.patch.object(lab, "candidate_source", return_value=self.candidate):
            with self.assertRaisesRegex(RuntimeError, "backup"):
                lab.preflight(self.base_sha, self.cand_sha, "39169390987", 1, 60)
        self.assertEqual(lab.BACKUP.read_bytes(), b"original")

    def test_requires_candidate_manifest_and_distinct_source(self):
        self.assertEqual(
            lab.candidate_source("39169390987", self.cand_sha), self.candidate)
        valid = lab.preflight(self.base_sha, self.cand_sha, "39169390987", 1, 60)
        self.assertEqual(valid["max_game_runs"], 2)
        self.assertFalse(valid["working_game_modified"])
        metadata = self.candidate.parent / "provenance.json"
        metadata.write_text(json.dumps({
            "run_id": "39169390987", "candidate_sha256": "a" * 64,
            "automatic_execution": False,
        }))
        with self.assertRaisesRegex(ValueError, "provenance"):
            lab.candidate_source("39169390987", self.cand_sha)

    def test_supervisor_must_confirm_exit_and_correct_hash(self):
        name = "autobenchmark-2026-10-18_17-25-28"
        run = self.results / name
        run.mkdir()
        (run / "lifecycle.verified").write_text(
            "wrapper_wait_exited=yes\ntest_game_handles=none\n")
        (run / "summary.json").write_text(json.dumps({
            "dll_sha256": self.base_sha, "run": name, "close_requested": True,
            "metrics": {"mode": {"optimization": 0, "nowait": 0, "gdi": 0}},
        }))
        def fake_run(*args, **kwargs):
            self.assertNotIn("GITHUB_TOKEN", kwargs["env"])
            self.assertNotIn("OPENAI_API_KEY", kwargs["env"])
            return mock.Mock(returncode=0)
        with mock.patch.object(lab, "names", side_effect=[set(), {name}]), \
             mock.patch.dict(lab.os.environ, {
                 "GITHUB_TOKEN": "secret", "OPENAI_API_KEY": "secret",
             }):
            self.assertEqual(lab.invoke_supervisor(
                self.base_sha, 60, run=fake_run), name)
        (run / "lifecycle.verified").unlink()
        with mock.patch.object(lab, "names", side_effect=[set(), {name}]), \
             self.assertRaisesRegex(RuntimeError, "exit receipt"):
            lab.invoke_supervisor(self.base_sha, 60, run=fake_run)

    def test_two_approved_binaries_restore_original_downloads_and_hold_for_review(self):
        original = b"MY EXISTING DOWNLOADS DLL"
        self.download.write_bytes(original)
        order = []
        def fake_supervisor(sha, seconds, *, run):
            self.assertEqual(lab.digest(self.download), sha)
            order.append(sha)
            return f"autobenchmark-2026-10-18_17-00-{len(order):02d}"
        def fake_controller(argv, **kwargs):
            self.assertNotIn("GITHUB_TOKEN", kwargs["env"])
            self.assertNotIn("OPENAI_API_KEY", kwargs["env"])
            doc = json.loads(Path(argv[argv.index("--manifest") + 1]).read_text())
            self.assertEqual(doc["pairs"][0], {
                "baseline": "autobenchmark-2026-10-18_17-00-01",
                "candidate": "autobenchmark-2026-10-18_17-00-02",
            })
            outfile = Path(argv[argv.index("--output") + 1])
            outfile.write_text(json.dumps({
                "manifest_verified": True, "may_install_or_run_candidate": False,
                "disposition": "requires_safe_worker_or_human",
                "next_step": "complete_paired_measurement",
            }))
            return mock.Mock(returncode=0)

        with mock.patch.object(lab, "candidate_source", return_value=self.candidate), \
             mock.patch.object(lab, "invoke_supervisor", side_effect=fake_supervisor), \
             mock.patch.dict(lab.os.environ, {
                 "GITHUB_TOKEN": "private", "OPENAI_API_KEY": "private",
             }):
            info = lab.execute(self.base_sha, self.cand_sha, "39169390987",
                               1, 60, run=fake_controller)
        self.assertEqual(order, [self.base_sha, self.cand_sha])
        self.assertEqual(info["pairs"], 1)
        self.assertEqual(self.download.read_bytes(), original)
        self.assertFalse(lab.BACKUP.exists())
        self.assertFalse(lab.LOCK.exists())

    def test_failed_supervisor_holds_lock_but_restores_downloads(self):
        original = b"ORIGINAL FILE"
        self.download.write_bytes(original)
        with mock.patch.object(lab, "candidate_source", return_value=self.candidate), \
             mock.patch.object(lab, "invoke_supervisor",
                               side_effect=RuntimeError("wine failed")):
            with self.assertRaisesRegex(RuntimeError, "wine failed"):
                lab.execute(self.base_sha, self.cand_sha, "39169390987",
                            1, 60)
        self.assertTrue(lab.LOCK.exists())
        self.assertEqual(self.download.read_bytes(), original)
        self.assertFalse(lab.BACKUP.exists())


if __name__ == "__main__":
    unittest.main()
