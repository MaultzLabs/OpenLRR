"""Offline safety tests for the bounded Mac OpenLRR supervisor."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SOURCE = Path(__file__).resolve().parents[1] / "lab-supervisor.py"
spec = importlib.util.spec_from_file_location("openlrr_lab_supervisor", SOURCE)
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)


class SupervisorSafetyTests(unittest.TestCase):
    def test_fixed_modes_only_with_bounded_plan(self):
        self.assertEqual(lab.parse_plan("baseline,gdi"), ["baseline", "gdi"])
        for bad in ("gdi", "baseline,evil", "baseline;rm -rf /",
                    "baseline,baseline,baseline,baseline,gdi",
                    "baseline,,nowait", ""):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                lab.parse_plan(bad)

    def test_dry_run_has_no_process_or_network_or_ai(self):
        sha = "f" * 64
        with mock.patch.object(lab, "parse_plan", wraps=lab.parse_plan), \
             mock.patch.object(lab, "preflight", return_value={"will_run": False}), \
             mock.patch.object(lab.subprocess, "Popen",
                               side_effect=AssertionError("executed app")), \
             mock.patch.object(lab.subprocess, "run",
                               side_effect=AssertionError("executed request")), \
             mock.patch.object(lab, "audit",
                               side_effect=AssertionError("wrote an audit log")):
            self.assertEqual(lab.main(["--approved-sha", sha]), 0)

    def test_stop_prevents_launcher(self):
        with mock.patch.object(lab, "switches", return_value="stop"), \
             mock.patch.object(lab.subprocess, "Popen",
                               side_effect=AssertionError("STOP bypassed")):
            with self.assertRaisesRegex(RuntimeError, "PAUSE or STOP"):
                lab.run_one("baseline", "a" * 64, 210, None)

    def test_preflight_rejects_changed_binary_and_stale_lock(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            dll = tmp / "openlrr.dll"
            dll.write_bytes(b"MZtest-dll")
            game = tmp / "game"
            game.mkdir()
            (game / "LegoRR.exe").write_bytes(b"MZfake")
            runner = tmp / "run-autobenchmark.sh"
            analyzer = tmp / "analyze-benchmark.py"
            runner.touch()
            analyzer.touch()
            sha = lab.fingerprint(dll)
            with mock.patch.object(lab, "DLL", dll), \
                 mock.patch.object(lab, "GAME", game), \
                 mock.patch.object(lab, "RUNNER", runner), \
                 mock.patch.object(lab, "ANALYZER", analyzer), \
                 mock.patch.object(lab, "STOP", tmp / "STOP"), \
                 mock.patch.object(lab, "LOCK", tmp / "lock"):
                info = lab.preflight(sha, ["baseline"], 60, False)
                self.assertFalse(info["will_run"])
                with self.assertRaisesRegex(RuntimeError, "SHA256"):
                    lab.preflight("a" * 64, ["baseline"], 60, False)
                (tmp / "lock").mkdir()
                with self.assertRaisesRegex(RuntimeError, "lock"):
                    lab.preflight(sha, ["baseline"], 60, True)

    def test_lifecycle_verification_required_even_with_valid_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            name = "autobenchmark-2026-10-18_15-11-13"
            run = tmp / name
            run.mkdir()
            sha = "a" * 64
            summary = {
                "schema_version": 1, "run": name, "dll_sha256": sha,
                "close_requested": True,
                "metrics": {
                    "mode": {"optimization": 0, "nowait": 0, "gdi": 0},
                    "present_calls": 500, "logged_duration_s": 212.0
                }
            }
            (run / "summary.json").write_text(json.dumps(summary))
            (run / "menuperf.csv").write_text("fake local counters")
            with mock.patch.object(lab, "RESULTS", tmp), \
                 mock.patch.object(lab, "verify_upload") as check:
                with self.assertRaisesRegex(RuntimeError, "exit receipt"):
                    lab.verify_result(name, "baseline", sha)
                check.assert_not_called()
                (run / "lifecycle.verified").write_text(
                    "wrapper_wait_exited=yes\ntest_game_handles=none\n")
                csv = lab.verify_result(name, "baseline", sha)
                self.assertEqual(csv, run / "menuperf.csv")
                self.assertEqual(check.call_count, 2)
                with self.assertRaisesRegex(RuntimeError, "approved binary"):
                    lab.verify_result(name, "baseline", "b" * 64)
                with self.assertRaisesRegex(RuntimeError, "graphics mode"):
                    lab.verify_result(name, "gdi", sha)

    def test_pause_never_initiates_runner(self):
        with mock.patch.object(lab, "switches", side_effect=["pause", "stop"]), \
             mock.patch.object(lab.subprocess, "Popen",
                               side_effect=AssertionError("launched on pause")):
            self.assertFalse(lab.wait_unpaused(1))

    def test_launch_refuses_checksum_change(self):
        with tempfile.TemporaryDirectory() as tmp:
            file = Path(tmp) / "openlrr.dll"
            file.write_bytes(b"MZincorrect")
            with mock.patch.object(lab, "switches", return_value="ready"), \
                 mock.patch.object(lab, "DLL", file), \
                 mock.patch.object(lab.subprocess, "Popen",
                                   side_effect=AssertionError("wrong DLL launched")):
                with self.assertRaisesRegex(RuntimeError, "changed"):
                    lab.run_one("baseline", "a" * 64, 210, None)


if __name__ == "__main__":
    unittest.main()
