"""No-Wine, no-GitHub tests for bounded unattended known-DLL Mac worker."""
from datetime import datetime, timedelta, timezone
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

FILE = Path(__file__).resolve().parents[1] / "approved-diagnostic-worker.py"
SPEC = importlib.util.spec_from_file_location("openlrr_known_diagnostic_worker", FILE)
worker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(worker)
NOW = datetime(2026, 10, 19, 3, tzinfo=timezone.utc)


class KnownDiagnosticWorkerTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.config = self.root / "config"
        self.state = self.root / "state"
        self.config.mkdir()
        self.state.mkdir()
        self.checkout = self.root / "OpenLRR-Agent"
        self.checkout.mkdir()
        self.app = self.root / "OpenLRR Menu Test.app"
        self.app.mkdir()
        self.script = self.root / "diagnostic-one-shot.sh"
        self.script.write_text("#!/bin/bash\n")
        patches = [
            mock.patch.object(worker, "CONFIG", self.config),
            mock.patch.object(worker, "STATE", self.state),
            mock.patch.object(worker, "ENROLLMENT", self.config / "approved-diagnostic-worker.json"),
            mock.patch.object(worker, "HISTORY", self.state / "approved-diagnostic-worker-history.json"),
            mock.patch.object(worker, "RUN_LOCK", self.state / "approved-diagnostic-worker.lock"),
            mock.patch.object(worker, "ROOT", self.checkout),
            mock.patch.object(worker, "APP", self.app),
            mock.patch.object(worker, "SCRIPT", self.script),
            mock.patch.object(worker, "preflight", return_value={
                "checkout_sha": "a" * 40,
                "file_sha256": {"scripts/macos/diagnostic-one-shot.sh": "b" * 64},
            }),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def test_enrollment_does_not_launch_game_and_is_finite(self):
        with mock.patch.object(worker.subprocess, "run",
                               side_effect=AssertionError("unexpected external process")):
            enrolled = worker.enroll(now=NOW)
        self.assertFalse(enrolled["game_launched"])
        self.assertEqual(enrolled["max_unattended_diagnostic_attempts"], 2)
        self.assertFalse(enrolled["automatic_ai_candidate_execution"])
        rec = worker.read_json(worker.ENROLLMENT)
        self.assertFalse(rec["automatic_dll_replacement_allowed"])
        self.assertEqual(rec["approved_dll_sha256"], worker.APPROVED_DLL_SHA)
        self.assertEqual(worker.validate_enrollment(now=NOW)["approved_run_id"],
                         worker.APPROVED_RUN)
        with self.assertRaisesRegex(RuntimeError, "cannot be overwritten"):
            worker.enroll(now=NOW)

    def test_dry_run_fully_inert(self):
        worker.enroll(now=NOW)
        with mock.patch.object(worker.subprocess, "run",
                               side_effect=AssertionError("unexpected command")):
            check = worker.work(now=NOW)
        self.assertEqual(check["decision"], "approved_diagnostic_available")
        self.assertFalse(worker.HISTORY.exists())
        self.assertFalse(worker.RUN_LOCK.exists())

    def test_one_per_day_and_at_most_two_total(self):
        worker.enroll(now=NOW)
        calls = []
        def complete(argv, **kwargs):
            calls.append(argv)
            self.assertEqual(argv, [
                "/bin/bash", str(self.script),
                worker.APPROVED_RUN, worker.APPROVED_REVISION
            ])
            self.assertNotIn("OPENAI_API_KEY", kwargs["env"])
            self.assertNotIn("GH_TOKEN", kwargs["env"])
            self.assertLessEqual(kwargs["timeout"], worker.MAX_SECONDS)
            return mock.Mock(returncode=0)
        with mock.patch.dict(worker.os.environ, {
            "OPENAI_API_KEY": "private-api-key",
            "GH_TOKEN": "private-gh-token",
        }), mock.patch.object(worker.subprocess, "run", side_effect=complete):
            one = worker.work(execute=True, now=NOW)
            same = worker.work(execute=True, now=NOW)
            two = worker.work(execute=True, now=NOW + timedelta(days=1))
            third = worker.work(execute=True, now=NOW + timedelta(days=2))
        self.assertEqual(one["decision"], "completed_verified_diagnostic")
        self.assertEqual(same["decision"], "already_attempted_today")
        self.assertEqual(two["decision"], "completed_verified_diagnostic")
        self.assertEqual(third["decision"], "maximum_attempts_reached")
        self.assertEqual(len(calls), 2)
        self.assertFalse(worker.RUN_LOCK.exists())
        self.assertEqual([x["status"] for x in worker.history()["attempts"]],
                         ["success", "success"])

    def test_unfinished_run_consumes_slot_and_retains_lock(self):
        worker.enroll(now=NOW)
        with mock.patch.object(worker.subprocess, "run",
                               return_value=mock.Mock(returncode=2)):
            with self.assertRaisesRegex(RuntimeError, "did not finish cleanly"):
                worker.work(execute=True, now=NOW)
        self.assertTrue(worker.RUN_LOCK.exists())
        self.assertEqual(worker.history()["attempts"][0]["status"], "claimed")
        with mock.patch.object(worker.subprocess, "run",
                               side_effect=AssertionError("retry blocked")):
            with self.assertRaisesRegex(RuntimeError, "lock"):
                worker.work(execute=True, now=NOW + timedelta(days=1))

    def test_stop_and_pause_prevent_any_authorized_run(self):
        worker.enroll(now=NOW)
        for name in ("STOP", "PAUSE"):
            flag = self.config / name
            flag.touch()
            with mock.patch.object(worker.subprocess, "run",
                                   side_effect=AssertionError("must not run")):
                with self.assertRaisesRegex(RuntimeError, "STOP/PAUSE"):
                    worker.work(execute=True, now=NOW)
            flag.unlink()

    def test_expiry_and_future_authorization_stop_even_without_io(self):
        worker.enroll(now=NOW)
        with mock.patch.object(worker.subprocess, "run",
                               side_effect=AssertionError("must not run")):
            with self.assertRaisesRegex(ValueError, "expired"):
                worker.work(execute=True, now=NOW + timedelta(days=8))
            with self.assertRaisesRegex(ValueError, "not yet valid"):
                worker.work(execute=True, now=NOW - timedelta(minutes=1))

    def test_changed_checkout_revokes_enrollment(self):
        worker.enroll(now=NOW)
        with mock.patch.object(worker, "preflight", return_value={
            "checkout_sha": "f" * 40,
            "file_sha256": {"scripts/macos/diagnostic-one-shot.sh": "b" * 64},
        }), mock.patch.object(worker.subprocess, "run",
                             side_effect=AssertionError("unexpected")):
            with self.assertRaisesRegex(RuntimeError, "code changed"):
                worker.work(execute=True, now=NOW)

    def test_provenance_and_authority_tampering_fails_closed(self):
        worker.enroll(now=NOW)
        origin = worker.read_json(worker.ENROLLMENT)
        for key, bad in (
            ("approved_run_id", "12345678999"),
            ("allowed_max_attempts", 99),
            ("ai_generated_candidate_execution_allowed", True),
            ("automatic_dll_replacement_allowed", True),
        ):
            mutated = dict(origin)
            mutated[key] = bad
            worker.ENROLLMENT.write_text(json.dumps(mutated))
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "authority"):
                worker.work(execute=True, now=NOW)
        worker.ENROLLMENT.write_text(json.dumps(origin))

    def test_repeated_enrollment_never_overwrites(self):
        worker.enroll(now=NOW)
        data = worker.ENROLLMENT.read_text()
        with self.assertRaises(RuntimeError):
            worker.enroll(now=NOW + timedelta(days=1))
        self.assertEqual(worker.ENROLLMENT.read_text(), data)


if __name__ == "__main__":
    unittest.main()
