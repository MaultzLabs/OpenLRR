"""End-to-end, synthetic-only evidence binding and tamper-rejection tests."""
from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT.parent / "agent"))

import bound_pair
import pipeline
import experiment_controller
import visual_capture_binding as gate
import visual_timeline as vt

LIFECYCLE = "wrapper_wait_exited=yes\ntest_game_handles=none\n"


class VerifiedPairTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.runs = self.home / "runs"
        self.runs.mkdir()
        self.manifest = self.home / "experiment.json"
        self.capture_manifest = self.home / "registered.json"
        self.output = self.home / "visual-report"
        self.ledger = self.home / "ledger.json"
        self.switches = self.home / "switches"
        self.switches.mkdir()
        yy, xx = np.indices((90, 140))
        self.scene = np.stack((xx * 2 % 255, yy * 2 % 255,
                               (xx + yy) % 255), axis=2).astype(np.uint8)
        self.runs_by_arm = {}
        for idx, arm in enumerate(("baseline", "candidate")):
            run = f"autobenchmark-2026-10-18_19-01-0{idx}"
            root = self.runs / run
            (root / "visual").mkdir(parents=True)
            (root / "lifecycle.verified").write_text(LIFECYCLE)
            summary = {
                "schema_version": 1,
                "run": run,
                "close_requested": True,
                "dll_sha256": ("a" if arm == "baseline" else "b") * 64,
                "metrics": {
                    "mode": {"optimization": 0, "nowait": 0, "gdi": 0},
                    "present_avg_ms": 200.0 if arm == "baseline" else 160.0,
                    "frame_flips_per_s": 4.0,
                    "logged_duration_s": 63.0, "present_calls": 250,
                    "present_accepted_percent": 100.0,
                    "present_error_calls": 0, "present_busy_calls": 0,
                    "present_intervals_over_1000ms": 5,
                },
            }
            (root / "summary.json").write_text(json.dumps(summary))
            candidate = self.scene.copy() if arm == "baseline" else np.zeros_like(self.scene)
            Image.fromarray(candidate).save(root / "visual" / "menu.png")
            self.runs_by_arm[arm] = run
        self.experiment = {
            "schema_version": 1, "experiment_id": "synthetic_verified_pair",
            "hypothesis": "Check whether candidate render is visible as expected.",
            "controlled_scene": "menu_boot_autotest_v1",
            "pairs": [self.runs_by_arm],
        }
        self.manifest.write_text(json.dumps(self.experiment))

    def make_timed_receipts(self, *, arm: str | None = None) -> None:
        targets = (arm,) if arm is not None else ("baseline", "candidate")
        for name in targets:
            run_name = self.runs_by_arm[name]
            folder = self.runs / run_name
            dll_sha = ("a" if name == "baseline" else "b") * 64
            mode = "baseline"
            base_wall = 1_800_000_000_000_000_000
            base_mono = 20_000_000_000
            boot = "c" * 64
            def at(seconds):
                ns = seconds * 1_000_000_000
                return {"wall_ns": base_wall + ns, "mono_ns": base_mono + ns,
                        "boot_sha256": boot}
            vt.begin(folder, dll_sha, mode, clock=at(1))
            vt.finish(folder, clock=at(15))
            capture_path = folder / "visual/menu.png"
            receipt = {
                "schema_version": 1, "run": run_name,
                "window_id": 301, "owner_pid": 4501,
                "size": {"width": 140, "height": 90},
                "sha256": gate.sha256_file(capture_path),
                "relative_file": "visual/menu.png",
                "window_owner_checked": True,
                "capture_origin_authenticated": False,
                "may_touch_working_game": False,
                "may_deploy_automatically": False,
                "approved_dll_sha256": dll_sha,
                "capture_started": at(4), "capture_finished": at(5),
            }
            vt.write_exclusive(folder / "visual/menu.capture.json", receipt)

    def register(self):
        return bound_pair.register(self.manifest, self.runs, 0,
                                   "visual/menu.png", "visual/menu.png",
                                   self.capture_manifest)

    def analyze(self):
        return bound_pair.analyze(self.manifest, self.runs,
                                  self.capture_manifest, self.output)

    def coordinate(self, report, captures):
        return experiment_controller.coordinate(
            self.manifest, self.runs, self.ledger,
            visual_report=report, visual_captures=captures,
            switches_dir=self.switches)

    def test_one_command_pipeline_produces_verified_research_decision(self):
        result = pipeline.run_once(self.manifest, self.runs, self.home / 'pipeline-result')
        self.assertEqual(result['visual_status'], 'regression')
        self.assertEqual(result['research_next_step'], 'isolate_regression')
        self.assertFalse(result['capture_origin_authenticated'])
        self.assertFalse(result['automatic_execution'])
        self.assertTrue((self.home / 'pipeline-result/research-decision.json').is_file())
        self.assertFalse((self.home / 'pipeline-result/read-only-ledger.json').exists())

    def test_one_command_pipeline_wont_overwrite_existing_evidence(self):
        destination = self.home / 'pipeline-result'
        destination.mkdir()
        marker = destination / 'keep.txt'
        marker.write_text('protected')
        with self.assertRaisesRegex(ValueError, 'overwrite'):
            pipeline.run_once(self.manifest, self.runs, destination)
        self.assertEqual(marker.read_text(), 'protected')

    def test_one_command_pipeline_wont_write_into_run_folder(self):
        with self.assertRaisesRegex(ValueError, 'outside'):
            pipeline.run_once(self.manifest, self.runs, self.runs / 'injected')

    def test_one_command_pipeline_refuses_missing_capture(self):
        missing = self.runs / self.runs_by_arm['candidate'] / 'visual/menu.png'
        missing.unlink()
        with self.assertRaisesRegex(ValueError, 'absent'):
            pipeline.run_once(self.manifest, self.runs, self.home / 'pipeline-result')

    def test_opted_in_timing_is_independently_verified(self):
        self.make_timed_receipts()
        captures = self.register()
        report = self.analyze()
        self.assertTrue(report['capture_binding']['temporal_consistency_verified'])
        decision = experiment_controller.coordinate(
            self.manifest, self.runs, self.ledger,
            visual_report=report, visual_captures=captures,
            require_timing=True, switches_dir=self.switches)
        self.assertTrue(decision['visual_temporal_consistency_verified'])
        self.assertFalse(decision['visual_capture_origin_authenticated'])
        self.assertEqual(decision['next_step'], 'isolate_regression')

    def test_strict_timing_blocks_untimed_legacy_captures(self):
        with self.assertRaisesRegex(ValueError, 'require timestamped'):
            bound_pair.register(self.manifest, self.runs, 0, 'visual/menu.png',
                                'visual/menu.png', self.capture_manifest,
                                require_timing=True)

    def test_strict_pipeline_end_to_end(self):
        self.make_timed_receipts()
        result = pipeline.run_once(self.manifest, self.runs,
                                   self.home / 'strict-output', require_timing=True)
        self.assertTrue(result['temporal_consistency_verified'])
        self.assertFalse(result['automatic_execution'])

    def test_only_one_run_timed_refuses_pair(self):
        self.make_timed_receipts(arm='baseline')
        with self.assertRaisesRegex(ValueError, 'Only one arm'):
            self.register()

    def test_incomplete_timestamp_group_fails_closed(self):
        run = self.runs / self.runs_by_arm['baseline']
        vt.begin(run, 'a' * 64, 'baseline', clock={
            'wall_ns': 1_800_000_001_000_000_000,
            'mono_ns': 21_000_000_000, 'boot_sha256': 'c' * 64})
        with self.assertRaisesRegex(ValueError, 'Incomplete TEST'):
            self.register()

    def test_capture_outside_run_window_rejected(self):
        self.make_timed_receipts()
        file = self.runs / self.runs_by_arm['candidate'] / 'visual/menu.capture.json'
        rec = json.loads(file.read_text())
        rec['capture_started']['mono_ns'] += 30_000_000_000
        rec['capture_finished']['mono_ns'] += 30_000_000_000
        rec['capture_started']['wall_ns'] += 30_000_000_000
        rec['capture_finished']['wall_ns'] += 30_000_000_000
        file.write_text(json.dumps(rec))
        with self.assertRaisesRegex(ValueError, 'outside supervised TEST'):
            self.register()

    def test_forged_capture_sha_rejected(self):
        self.make_timed_receipts()
        file = self.runs / self.runs_by_arm['candidate'] / 'visual/menu.capture.json'
        rec = json.loads(file.read_text())
        rec['sha256'] = 'd' * 64
        file.write_text(json.dumps(rec))
        with self.assertRaisesRegex(ValueError, 'does not match'):
            self.register()

    def test_changed_host_boot_rejected(self):
        self.make_timed_receipts()
        file = self.runs / self.runs_by_arm['candidate'] / 'visual/menu.capture.json'
        rec = json.loads(file.read_text())
        rec['capture_started']['boot_sha256'] = 'd' * 64
        rec['capture_finished']['boot_sha256'] = 'd' * 64
        file.write_text(json.dumps(rec))
        with self.assertRaisesRegex(ValueError, 'different host boots'):
            self.register()

    def test_clock_step_rejected(self):
        self.make_timed_receipts()
        file = self.runs / self.runs_by_arm['baseline'] / 'visual/menu.capture.json'
        rec = json.loads(file.read_text())
        rec['capture_started']['wall_ns'] += 20_000_000_000
        rec['capture_finished']['wall_ns'] += 20_000_000_000
        file.write_text(json.dumps(rec))
        with self.assertRaisesRegex(ValueError, 'clock stepped'):
            self.register()

    def test_timing_end_hash_tamper_rejected(self):
        self.make_timed_receipts()
        file = self.runs / self.runs_by_arm['candidate'] / 'run-timing.end.json'
        rec = json.loads(file.read_text())
        rec['start_sha256'] = 'f' * 64
        file.write_text(json.dumps(rec))
        with self.assertRaisesRegex(ValueError, 'has changed'):
            self.register()

    def test_cannot_add_timing_after_report_without_reverification(self):
        captures = self.register()
        report = self.analyze()
        self.make_timed_receipts()
        with self.assertRaisesRegex(ValueError, 'not bound'):
            self.coordinate(report, captures)
    def test_valid_pair_flags_visual_regression_for_research(self):
        captures = self.register()
        result = self.analyze()
        self.assertEqual(result["status"], "regression")
        self.assertFalse(result["capture_binding"]["capture_origin_authenticated"])
        self.assertTrue(result["capture_binding"]["verified_local_receipts"])
        decision = self.coordinate(result, captures)
        self.assertEqual(decision["next_step"], "isolate_regression")
        self.assertTrue(decision["visual_capture_binding_verified"])
        self.assertFalse(decision["visual_capture_origin_authenticated"])
        self.assertFalse(decision["may_touch_working_game"])
        self.assertFalse(decision["may_deploy_automatically"])
        self.assertFalse(self.ledger.exists())

    def test_cli_registration_and_analysis_end_to_end(self):
        cmd = [sys.executable, str(ROOT / "bound_pair.py")]
        import subprocess
        first = subprocess.run(cmd + ["register", "--experiment", str(self.manifest),
            "--runs-dir", str(self.runs), "--out", str(self.capture_manifest),
            "--baseline-file", "visual/menu.png",
            "--candidate-file", "visual/menu.png"], capture_output=True, text=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        second = subprocess.run(cmd + ["analyze", "--experiment", str(self.manifest),
            "--runs-dir", str(self.runs), "--captures", str(self.capture_manifest),
            "--out", str(self.output)], capture_output=True, text=True)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(json.loads((self.output / "report.json").read_text())["status"], "regression")

    def test_modified_capture_rejected_before_analysis(self):
        self.register()
        path = self.runs / self.runs_by_arm["candidate"] / "visual/menu.png"
        path.write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "Capture bytes changed"):
            self.analyze()

    def test_modified_summary_rejected(self):
        self.register()
        path = self.runs / self.runs_by_arm["baseline"] / "summary.json"
        path.write_text(path.read_text() + " ")
        with self.assertRaisesRegex(ValueError, "Run summary changed"):
            self.analyze()

    def test_changed_run_receipt_rejected(self):
        self.register()
        path = self.runs / self.runs_by_arm["candidate"] / "lifecycle.verified"
        path.write_text("no trusted exit")
        with self.assertRaisesRegex(ValueError, "Unverified Mac test lifecycle"):
            self.analyze()

    def test_swapped_run_arm_rejected(self):
        manifest = self.register()
        manifest["captures"]["baseline"]["run"] = self.runs_by_arm["candidate"]
        with self.assertRaisesRegex(ValueError, "run does not match experiment arm"):
            gate.verified_capture_binding(self.experiment, self.runs, manifest)

    def test_path_traversal_rejected(self):
        manifest = self.register()
        manifest["captures"]["baseline"]["file"] = "../../other.png"
        with self.assertRaisesRegex(ValueError, "visual"):
            gate.verified_capture_binding(self.experiment, self.runs, manifest)

    def test_symlink_media_rejected(self):
        manifest = self.register()
        run = self.runs / self.runs_by_arm["baseline"] / "visual"
        (run / "fake.png").symlink_to(run / "menu.png")
        manifest["captures"]["baseline"]["file"] = "visual/fake.png"
        with self.assertRaisesRegex(ValueError, "Symlink"):
            gate.verified_capture_binding(self.experiment, self.runs, manifest)

    def test_tampered_score_rejected_even_with_valid_hashes(self):
        captures = self.register()
        report = self.analyze()
        report["score"] = 99.98
        with self.assertRaisesRegex(ValueError, "independently computed evidence"):
            self.coordinate(report, captures)
        self.assertFalse(self.ledger.exists())

    def test_tampered_findings_rejected(self):
        captures = self.register()
        report = self.analyze()
        report["findings"] = []
        with self.assertRaisesRegex(ValueError, "independently computed evidence"):
            self.coordinate(report, captures)

    def test_tampered_binding_rejected(self):
        captures = self.register()
        report = self.analyze()
        report["capture_binding"]["baseline"]["summary_sha256"] = "f" * 64
        with self.assertRaisesRegex(ValueError, "not bound"):
            self.coordinate(report, captures)

    def test_visual_report_without_capture_manifest_refused(self):
        self.register()
        report = self.analyze()
        with self.assertRaisesRegex(ValueError, "requires the paired"):
            experiment_controller.coordinate(
                self.manifest, self.runs, self.ledger,
                visual_report=report, switches_dir=self.switches)

    def test_manifest_without_report_refused(self):
        captures = self.register()
        with self.assertRaisesRegex(ValueError, "requires the paired"):
            experiment_controller.coordinate(
                self.manifest, self.runs, self.ledger,
                visual_captures=captures, switches_dir=self.switches)

    def test_registration_never_overwrites_manifest(self):
        self.register()
        before = self.capture_manifest.read_bytes()
        with self.assertRaises(FileExistsError):
            self.register()
        self.assertEqual(self.capture_manifest.read_bytes(), before)

    def test_stop_and_pause_block_offline_pipeline(self):
        for name in ("STOP", "PAUSE"):
            with self.subTest(name=name):
                # The standalone registrar shares the supervisor's global STOP
                # location. Patch its module constant, never the real home.
                original = bound_pair.SWITCHES
                bound_pair.SWITCHES = self.switches
                try:
                    flag = self.switches / name
                    flag.touch()
                    with self.assertRaisesRegex(ValueError, "STOP or PAUSE"):
                        self.register()
                    flag.unlink()
                finally:
                    bound_pair.SWITCHES = original
        self.assertFalse(self.capture_manifest.exists())

    def test_matching_image_must_not_imply_execution_authority(self):
        self.register()
        report = self.analyze()
        report["may_install_or_run_candidate"] = True
        with self.assertRaisesRegex(ValueError, "authorize execution"):
            self.coordinate(report, json.loads(self.capture_manifest.read_text()))

    def test_report_checks_capture_files_again_after_registration(self):
        captures = self.register()
        report = self.analyze()
        path = self.runs / self.runs_by_arm["baseline"] / "visual/menu.png"
        path.write_bytes(b"tampered after analysis")
        with self.assertRaisesRegex(ValueError, "Capture bytes changed"):
            self.coordinate(report, captures)


if __name__ == "__main__":
    unittest.main()
