"""No-Mac fixture tests for the fixed OpenLRR menu diagnostic session package.

These exercise boundaries and comparisons, NOT actual Wine launch/display FPS.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parents[1] / "menu-diagnostic-session.py"
SPEC = importlib.util.spec_from_file_location("openlrr_menu_diagnostic_session", HERE)
session = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(session)

BASE = "autobenchmark-2026-10-18_22-47-08"
SECOND = "autobenchmark-2026-10-18_22-48-35"
THIRD = "autobenchmark-2026-10-18_22-50-09"
FOURTH = "autobenchmark-2026-10-18_22-52-19"


class MenuSessionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.root = root
        self.app = root / "OpenLRR Menu Test.app"
        self.game = (self.app / "Contents/SharedSupport/prefix/drive_c"
                     / "Program Files/Rock Raiders OpenLRR")
        self.game.mkdir(parents=True)
        self.checkouts = root / "OpenLRR-Agent/scripts/macos"
        self.checkouts.mkdir(parents=True)
        self.runs = root / "Downloads/OpenLRR Benchmark Runs"
        self.runs.mkdir(parents=True)
        self.config = root / "flags"
        self.config.mkdir()
        self.output = root / "sessions"
        (self.game / "LegoRR.exe").write_bytes(b"the TEST executable")
        (self.game / "openlrr.dll").write_bytes(b"old test DLL")
        for name in ("diagnostic-one-shot.sh", "lab-supervisor.py",
                     "wine-cpu-sample.py"):
            (self.checkouts / name).write_text("#!/bin/bash\n")
        venv = root / ".local/share/openlrr-agent/venv/bin/python"
        venv.parent.mkdir(parents=True)
        venv.write_text("python fixture")
        self.patches = [
            mock.patch.object(session, "HOME", root),
            mock.patch.object(session, "APP", self.app),
            mock.patch.object(session, "GAME", self.game),
            mock.patch.object(session, "CONFIG", self.config),
            mock.patch.object(session, "OUTPUT", self.output),
            mock.patch.object(session, "RUNS", self.runs),
            mock.patch.object(session, "ROOT", root / "OpenLRR-Agent"),
            mock.patch.object(session, "ONE_SHOT",
                              self.checkouts / "diagnostic-one-shot.sh"),
            mock.patch.object(session, "SUPERVISOR",
                              self.checkouts / "lab-supervisor.py"),
            mock.patch.object(session, "PROFILE",
                              self.checkouts / "wine-cpu-sample.py"),
            mock.patch.object(session, "safe_process",
                              return_value="PRIVATE"),
            mock.patch.object(session.shutil, "which", return_value="/usr/bin/gh"),
        ]
        for p in self.patches:
            p.start()
            self.addCleanup(p.stop)
        self.assertEqual(session.DLL_SHA,
                         "1179323074e03caf22f89ecbf05b9234f8ef5e18f2c1d6b8d797c2cf31c5b4ff")

    def fixture(self, run: str, mode="baseline", *, latency=200.0,
                seconds=62.0, valid_receipt=True, binary_sha=True):
        folder = self.runs / run
        folder.mkdir()
        payload = b"MZlocal benchmark DLL fixture"
        (folder / "benchmark-openlrr.dll").write_bytes(payload)
        summary = {
            "schema_version": 1, "run": run,
            "dll_sha256": session.DLL_SHA if binary_sha else "a" * 64,
            "close_requested": True,
            "metrics": {
                "mode": {"optimization": 0, "nowait": int(mode == "nowait"),
                         "gdi": int(mode == "gdi")},
                "logged_duration_s": seconds,
                "frame_flips_per_s": 4.0,
                "present_avg_ms": latency, "present_calls": 200,
                "window_blt_calls_over_1000ms": 31,
                "blit_thread_cpu_samples": 185,
                "blit_slow_low_cpu_calls": 1,
            },
        }
        (folder / "summary.json").write_text(json.dumps(summary))
        (folder / "menuperf.csv").write_text(
            "seconds,optimization,nowait,gdi,operation,calls,total_ms,max_ms\n"
        )
        (folder / "lifecycle.verified").write_text(
            "wrapper_wait_exited=yes\ntest_game_handles=none\n"
            if valid_receipt else "unverified\n"
        )
        return folder, payload

    def test_default_preflight_is_inert(self):
        with mock.patch.object(session.subprocess, "Popen",
                               side_effect=AssertionError("game must not launch")):
            detail = session.check_environment(1, os_check=False)
        self.assertEqual(detail["plan"], ["baseline", "baseline"])
        self.assertFalse(detail["visible_fps_verified"])
        self.assertEqual(detail["screenshots_available"], "unverified")
        self.assertFalse(self.output.exists())

    def test_macos_lsof_one_without_handles_is_clean_preflight(self):
        def no_handles(argv, **kwargs):
            self.assertEqual(argv[0], "/usr/sbin/lsof")
            return mock.Mock(returncode=1, stdout="", stderr="")
        with mock.patch.object(session, "sys") as fake_sys, \
             mock.patch.object(session.subprocess, "run", side_effect=no_handles):
            fake_sys.platform = "darwin"
            data = session.check_environment(1, os_check=True)
        self.assertEqual(data["plan"], ["baseline", "baseline"])

    def test_macos_lsof_still_running_process_blocks_preflight(self):
        with mock.patch.object(session, "sys") as fake_sys, \
             mock.patch.object(session.subprocess, "run",
                               return_value=mock.Mock(
                                   returncode=0, stdout="12345\\n", stderr="")):
            fake_sys.platform = "darwin"
            with self.assertRaisesRegex(RuntimeError, "open file handles"):
                session.check_environment(1, os_check=True)

    def test_macos_lsof_unreliable_output_blocks_preflight(self):
        with mock.patch.object(session, "sys") as fake_sys, \
             mock.patch.object(session.subprocess, "run",
                               return_value=mock.Mock(
                                   returncode=1, stdout="", stderr="unknown error")):
            fake_sys.platform = "darwin"
            with self.assertRaisesRegex(RuntimeError, "unreliable"):
                session.check_environment(1, os_check=True)

    def test_unreviewed_sessions_are_never_eligible(self):
        for value in (0, 3, 4, 5, 6, 99):
            with self.subTest(session=value), self.assertRaises(ValueError):
                session.check_environment(value, os_check=False)

    def test_STOP_PAUSE_and_lock_gate_even_preflight(self):
        for marker in (self.config / "STOP", self.config / "PAUSE",
                       self.config / "supervisor.lock"):
            marker.touch()
            with self.subTest(marker=marker), self.assertRaises(RuntimeError):
                session.check_environment(1, os_check=False)
            marker.unlink()

    def test_installed_test_dll_symlink_to_working_game_refused(self):
        original = self.game / "openlrr.dll"
        original.unlink()
        original.symlink_to(self.root / "WorkingGame/openlrr.dll")
        with self.assertRaisesRegex(RuntimeError, "symlinks"):
            session.check_environment(1, os_check=False)

    def test_wrong_or_missing_run_count_not_a_pass(self):
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            session.verify_completed([BASE], session.MODES[1])

    def test_bad_receipt_or_binary_prevents_report(self):
        folder, _ = self.fixture(BASE, valid_receipt=False)
        with self.assertRaisesRegex(ValueError, "process exit"):
            session.verify_completed([BASE], ("baseline",))
        (folder / "lifecycle.verified").write_text(
            "wrapper_wait_exited=yes\ntest_game_handles=none\n")
        with self.assertRaisesRegex(ValueError, "reviewed"):
            session.verify_completed([BASE], ("baseline",))

    def test_wrong_mode_bad_duration_rejected(self):
        folder, payload = self.fixture(BASE, mode="nowait", seconds=30.0)
        with mock.patch.object(session, "sha256_file", return_value=session.DLL_SHA):
            with self.assertRaisesRegex(ValueError, "graphics mode"):
                session.verify_completed([BASE], ("baseline",))
            doc = json.loads((folder / "summary.json").read_text())
            doc["metrics"]["mode"]["nowait"] = 0
            (folder / "summary.json").write_text(json.dumps(doc))
            with self.assertRaisesRegex(ValueError, "comparable"):
                session.verify_completed([BASE], ("baseline",))

    def test_two_baselines_are_repeatability_not_a_b_or_visible_fps(self):
        for name in (BASE, SECOND):
            self.fixture(name)
        with mock.patch.object(session, "sha256_file", return_value=session.DLL_SHA):
            report = session.verify_completed([BASE, SECOND], session.MODES[1])
        self.assertEqual(report["pairs"], [])
        self.assertEqual(report["evidence_completeness"]["verified_visible_fps"],
                         "missing")
        self.assertEqual(report["evidence_completeness"]["audio_test_result"],
                         "missing")
        self.assertFalse(report["claims"]["60_visible_fps_achieved"])

    def test_two_config_a_b_pairs_are_preliminary_not_proven(self):
        for name, mode, latency in zip(
            (BASE, SECOND, THIRD, FOURTH),
            session.MODES[2], (200.0, 190.0, 210.0, 205.0),
        ):
            self.fixture(name, mode, latency=latency)
        with mock.patch.object(session, "sha256_file", return_value=session.DLL_SHA):
            report = session.verify_completed(
                [BASE, SECOND, THIRD, FOURTH], session.MODES[2]
            )
        self.assertEqual(len(report["pairs"]), 2)
        self.assertEqual(report["pairs"][0]["candidate_mode"], "nowait")
        self.assertFalse(report["claims"]["session_2_proves_performance_gain"])
        self.assertEqual(report["pairs"][0]["average_present_change_pct"], -5.0)

    def test_interrupted_session_never_reports_success_or_restarts(self):
        state = []
        p = mock.Mock()
        p.poll.return_value = 3
        p.returncode = 3
        def write_preflight(*args, **kwargs):
            return {"schema_version": 1}
        with mock.patch.object(session, "check_environment",
                               return_value={"session": 1}), \
             mock.patch.object(session, "mac_snapshot",
                               return_value={"test": True}), \
             mock.patch.object(session.subprocess, "Popen",
                               return_value=p) as launched:
            with self.assertRaisesRegex(RuntimeError, "failed"):
                session.run_session(1, profile_cpu=False)
        launched.assert_called_once()
        generated = list(self.output.glob("*/session-state.json"))
        self.assertEqual(len(generated), 1)
        report = json.loads(generated[0].read_text())
        self.assertEqual(report["state"], "failed_or_incomplete")
        self.assertTrue(report["stop_or_crash_requires_human_inspection"])
        self.assertEqual(list(self.output.glob("*/report.json")), [])

    def test_output_idempotent_and_no_overwrites(self):
        dest = self.root / "record.json"
        session.store_new(dest, {"result": "missing_visual"})
        data = dest.read_text()
        with self.assertRaisesRegex(RuntimeError, "Existing"):
            session.store_new(dest, {"result": "passed"})
        self.assertEqual(dest.read_text(), data)


if __name__ == "__main__":
    unittest.main()
