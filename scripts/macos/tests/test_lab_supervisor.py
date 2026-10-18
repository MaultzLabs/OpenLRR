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

    def test_verified_pair_is_handed_to_controller_without_new_game(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            script = home / "OpenLRR-Agent/scripts/agent/experiment_controller.py"
            script.parent.mkdir(parents=True)
            script.write_text("# trusted local controller")
            python = home / ".local/share/openlrr-agent/venv/bin/python"
            python.parent.mkdir(parents=True)
            python.write_text("# python")
            results = home / "results"
            results.mkdir()
            state = home / "agent-state"
            runs = ["autobenchmark-2026-10-18_16-10-47",
                    "autobenchmark-2026-10-18_16-12-12"]
            observed = {}

            def simulate_controller(command, **kwargs):
                self.assertNotIn("OPENAI_API_KEY", kwargs["env"])
                self.assertNotIn("GH_TOKEN", kwargs["env"])
                self.assertNotIn("GITHUB_TOKEN", kwargs["env"])
                manifest_path = Path(command[command.index("--manifest") + 1])
                manifest = json.loads(manifest_path.read_text())
                observed["manifest"] = manifest
                output = Path(command[command.index("--output") + 1])
                output.write_text(json.dumps({
                    "experiment_id": manifest["experiment_id"],
                    "manifest_verified": True,
                    "may_install_or_run_candidate": False,
                    "next_step": "complete_paired_measurement",
                }))
                return mock.Mock(returncode=0)

            with mock.patch.object(lab, "HOME", home), \
                 mock.patch.object(lab, "STATE", state), \
                 mock.patch.object(lab, "RESULTS", results), \
                 mock.patch.object(lab, "switches", return_value="ready"), \
                 mock.patch.object(lab, "verify_result", return_value=results / "a.csv") as verified, \
                 mock.patch.object(lab, "audit") as audit, \
                 mock.patch.object(lab.subprocess, "run", side_effect=simulate_controller), \
                 mock.patch.object(lab.subprocess, "Popen",
                                   side_effect=AssertionError("Unexpected Mac game launch")), \
                 mock.patch.dict(lab.os.environ, {
                     "OPENAI_API_KEY": "secret",
                     "GH_TOKEN": "github secret",
                     "GITHUB_TOKEN": "secret"
                 }):
                output = lab.handoff_verified_pair(
                    runs, ["baseline", "nowait"], "a" * 64)
            self.assertTrue(output.is_file())
            self.assertEqual(verified.call_count, 2)
            self.assertEqual(observed["manifest"]["pairs"][0]["baseline"], runs[0])
            self.assertEqual(observed["manifest"]["pairs"][0]["candidate"], runs[1])
            self.assertEqual(observed["manifest"]["controlled_scene"],
                             "menu_boot_autotest_v1")
            self.assertEqual(audit.call_args.args[0], "policy_handoff_completed")

    def test_policy_handoff_rejects_unpaired_or_unverified_runs(self):
        with mock.patch.object(lab, "verify_result",
                               side_effect=AssertionError("Should refuse early")), \
             mock.patch.object(lab.subprocess, "run",
                               side_effect=AssertionError("No policy execution")):
            with self.assertRaisesRegex(ValueError, "exactly"):
                lab.handoff_verified_pair(
                    ["autobenchmark-2026-10-18_16-10-47"],
                    ["baseline"], "a" * 64)
            with self.assertRaisesRegex(ValueError, "exactly"):
                lab.handoff_verified_pair(
                    ["autobenchmark-2026-10-18_16-10-47",
                     "autobenchmark-2026-10-18_16-12-12"],
                    ["baseline", "baseline"], "a" * 64)

    def test_coordinate_requires_explicit_run_and_true_ab_modes(self):
        for args in (
            ["--approved-sha", "a" * 64, "--coordinate"],
            ["--approved-sha", "a" * 64, "--run",
             "--plan", "baseline,baseline", "--coordinate"],
        ):
            with self.subTest(args=args), self.assertRaises(SystemExit):
                lab.main(args)

    def test_pause_never_initiates_runner(self):
        with mock.patch.object(lab, "switches", side_effect=["pause", "stop"]), \
             mock.patch.object(lab.subprocess, "Popen",
                               side_effect=AssertionError("launched on pause")):
            self.assertFalse(lab.wait_unpaused(1))

    def test_game_runner_does_not_inherit_model_credentials(self):
        with tempfile.TemporaryDirectory() as tmp:
            dll = Path(tmp) / "openlrr.dll"
            dll.write_bytes(b"MZapproved")
            sha = lab.fingerprint(dll)
            name = "autobenchmark-2026-10-18_15-20-00"
            child = mock.Mock()
            child.poll.return_value = 0
            child.returncode = 0
            with mock.patch.object(lab, "DLL", dll), \
                 mock.patch.object(lab, "switches", return_value="ready"), \
                 mock.patch.object(lab, "known_runs", side_effect=[set(), {name}]), \
                 mock.patch.object(lab, "verify_result", return_value=Path(tmp) / "menuperf.csv"), \
                 mock.patch.object(lab, "audit"), \
                 mock.patch.object(lab.subprocess, "Popen", return_value=child) as launch, \
                 mock.patch.dict(lab.os.environ, {
                     "OPENAI_API_KEY": "should-not-reach-game",
                     "GH_TOKEN": "should-not-reach-game",
                     "GITHUB_TOKEN": "should-not-reach-game",
                 }):
                lab.run_one("baseline", sha, 30, None)
                passed_env = launch.call_args.kwargs["env"]
                self.assertNotIn("OPENAI_API_KEY", passed_env)
                self.assertNotIn("GH_TOKEN", passed_env)
                self.assertNotIn("GITHUB_TOKEN", passed_env)
                self.assertEqual(passed_env["OPENLRR_SUPERVISED"], "1")

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
