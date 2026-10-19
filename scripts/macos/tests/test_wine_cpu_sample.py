"""Offline test that Mac CPU sampling never targets unrelated processes."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

FILE = Path(__file__).resolve().parents[1] / "wine-cpu-sample.py"
SPEC = importlib.util.spec_from_file_location("openlrr_wine_cpu_sample", FILE)
profiler = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(profiler)


class ProfilerSafetyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        app = root / "OpenLRR Menu Test.app"
        game = app / "Contents/SharedSupport/prefix/drive_c/Program Files/Rock Raiders OpenLRR"
        game.mkdir(parents=True)
        (game / "LegoRR.exe").write_bytes(b"fixture")
        (game / "menuperf.csv").write_text(
            "seconds,optimization,nowait,gdi,operation,calls,total_ms,max_ms\n"
            "1.0,0,0,0,frame_flip,5,10.0000,5.0000\n"
        )
        config = root / "config"
        config.mkdir()
        for prop, replacement in [
            ("APP", app), ("GAME", game), ("CONFIG", config),
            ("STATE", root / "profiles"),
            ("SAMPLE_BINARY", root / "sample"),
        ]:
            patch = mock.patch.object(profiler, prop, replacement)
            patch.start()
            self.addCleanup(patch.stop)
        profiler.SAMPLE_BINARY.write_bytes(b"mac sample fixture")

    def test_dry_run_never_touches_processes_or_network(self):
        with mock.patch.object(profiler.subprocess, "run",
                               side_effect=AssertionError("process attempted")):
            self.assertEqual(profiler.main([]), 0)
        self.assertFalse(profiler.STATE.exists())

    def test_requires_pid_owned_by_test_directory_and_wine(self):
        def commands(argv, *, timeout):
            if argv[0] == "/usr/sbin/lsof":
                self.assertEqual(argv[-1], str(profiler.GAME / "menuperf.csv"))
                return "107\n205\n"
            if argv[0] == "/bin/ps":
                return "wine64-preloader\n" if argv[2] == "205" else "/usr/bin/python\n"
            raise AssertionError("unexpected process lookup")
        with mock.patch.object(profiler, "checked_run", side_effect=commands):
            self.assertEqual(profiler.find_test_wine_pid(), "205")

    def test_multiple_test_wine_pids_blocked(self):
        def commands(argv, *, timeout):
            return "107\n205\n" if argv[0] == "/usr/sbin/lsof" else "wine64-preloader\n"
        with mock.patch.object(profiler, "checked_run", side_effect=commands):
            with self.assertRaisesRegex(RuntimeError, "exactly one"):
                profiler.find_test_wine_pid()

    def test_untrusted_pid_or_no_test_handles_refused(self):
        for candidate in ("abc\n", "", "-11\n"):
            with self.subTest(candidate=candidate), \
                 mock.patch.object(profiler, "checked_run", return_value=candidate):
                with self.assertRaises(RuntimeError):
                    profiler.find_test_wine_pid()

    def test_live_writer_file_is_required_before_process_inspection(self):
        target = profiler.GAME / "menuperf.csv"
        target.unlink()
        with mock.patch.object(profiler, "checked_run",
                               side_effect=AssertionError("process lookup should not run")):
            with self.assertRaisesRegex(RuntimeError, "telemetry file"):
                profiler.find_test_wine_pid()
        target.write_text("not real TEST telemetry\n")
        with mock.patch.object(profiler, "checked_run",
                               side_effect=AssertionError("process lookup should not run")):
            with self.assertRaisesRegex(RuntimeError, "header"):
                profiler.find_test_wine_pid()

    def test_test_telemetry_symlink_is_never_followed(self):
        live = profiler.GAME / "menuperf.csv"
        live.unlink()
        foreign = profiler.GAME.parent / "untrusted.csv"
        foreign.write_text("seconds,optimization,nowait,gdi,operation,calls,total_ms,max_ms\n")
        live.symlink_to(foreign)
        with mock.patch.object(profiler, "checked_run",
                               side_effect=AssertionError("must not inspect symlink")):
            with self.assertRaisesRegex(RuntimeError, "telemetry file"):
                profiler.find_test_wine_pid()

    def test_no_live_writer_never_falls_back_to_name_only(self):
        with mock.patch.object(profiler, "checked_run", return_value="") as lookup:
            with self.assertRaisesRegex(RuntimeError, "No live TEST"):
                profiler.find_test_wine_pid()
        self.assertEqual(lookup.call_count, 1)
        self.assertEqual(lookup.call_args.args[0][-1],
                         str(profiler.GAME / "menuperf.csv"))

    def test_lsof_empty_exit_one_is_a_no_writer_result(self):
        with mock.patch.object(profiler.subprocess, "run",
                               return_value=mock.Mock(returncode=1, stdout="", stderr="")):
            self.assertEqual(profiler.checked_run(
                ["/usr/sbin/lsof", "-nP", "-t", str(profiler.GAME / "menuperf.csv")],
                timeout=5), "")

    def test_lsof_error_cannot_be_misread_as_no_writer(self):
        with mock.patch.object(profiler.subprocess, "run",
                               return_value=mock.Mock(returncode=1, stdout="",
                                                      stderr="permission denied")):
            with self.assertRaisesRegex(RuntimeError, "lookup"):
                profiler.checked_run(
                    ["/usr/sbin/lsof", "-nP", "-t",
                     str(profiler.GAME / "menuperf.csv")], timeout=5)

    def test_other_process_holding_live_file_does_not_grant_capture(self):
        def fake(argv, *, timeout):
            if argv[0] == "/usr/sbin/lsof":
                return "205\n"
            return "/usr/bin/python3\n"
        with mock.patch.object(profiler, "checked_run", side_effect=fake):
            with self.assertRaisesRegex(RuntimeError, "exactly one Wine writer"):
                profiler.find_test_wine_pid()

    def test_stop_and_pause_prevent_preflight(self):
        for flag in ("STOP", "PAUSE"):
            marker = profiler.CONFIG / flag
            marker.touch()
            with mock.patch.object(profiler, "checked_run",
                                   side_effect=AssertionError("must not discover")):
                with self.assertRaisesRegex(RuntimeError, "STOP/PAUSE"):
                    profiler.find_test_wine_pid()
            marker.unlink()

    def test_sanitized_report_never_contains_raw_paths(self):
        raw = (
            "Call graph: 3205 Thread_111\n"
            "ddraw wined3d Metal CoreAnimation\n"
            "/Users/private/Documents/secret-project.dmg\n"
            "wine wine libsystem_kernel ddraw"
        )
        report = profiler.sanitized_summary(raw, "205")
        self.assertEqual(report["symbol_mention_counts"]["ddraw"], 2)
        self.assertEqual(report["symbol_mention_counts"]["wine"], 2)
        self.assertFalse(report["safe_to_upload_raw_trace"])
        self.assertFalse(report["has_driver_attribution"])
        self.assertNotIn("secret-project", str(report))
        self.assertNotIn("/Users", str(report))

    def test_capture_requires_same_test_pid_twice(self):
        with mock.patch.object(profiler, "find_test_wine_pid",
                               side_effect=["205", "206"]), \
             mock.patch.object(profiler.subprocess, "run",
                               side_effect=AssertionError("must not sample")):
            with self.assertRaisesRegex(RuntimeError, "identity changed"):
                profiler.capture()
        self.assertFalse(profiler.STATE.exists())

    def test_capture_writes_local_0600_report_no_upload(self):
        def simulate(argv, **kw):
            self.assertEqual(argv[0], str(profiler.SAMPLE_BINARY))
            self.assertEqual(argv[1], "205")
            self.assertEqual(argv[-2], "-file")
            raw = Path(argv[-1])
            raw.write_text("ddraw ddraw wine wined3d Metal")
            return mock.Mock(returncode=0)
        with mock.patch.object(profiler, "find_test_wine_pid",
                               return_value="205") as lookup, \
             mock.patch.object(profiler.subprocess, "run", side_effect=simulate):
            result = profiler.capture()
        self.assertEqual(lookup.call_count, 2)
        self.assertFalse(result["raw_trace_uploaded"])
        self.assertFalse(result["started_game"])
        self.assertEqual(result["symbol_mention_counts"]["ddraw"], 2)
        self.assertTrue(Path(result["summary_path"]).is_file())
        self.assertTrue(Path(result["raw_trace_path"]).is_file())
        self.assertEqual(Path(result["raw_trace_path"]).stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
