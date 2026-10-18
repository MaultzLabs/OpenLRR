#!/usr/bin/env python3
"""Synthetic, asset-free regression tests. No game or user captures required."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT.parent / "agent"))
import qa
import visual_feedback
import experiment_controller


class VisualQATests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        yy, xx = np.indices((80, 120))
        self.scene = np.stack((xx * 2 % 255, yy * 3 % 255, (xx + yy) % 255), axis=2).astype(np.uint8)

    def save(self, name, img):
        target = self.dir / name
        Image.fromarray(img).save(target)
        return target

    def analyze(self, a, b, out="report", **kwargs):
        return qa.report_for(a, b, self.dir / out, "synthetic_exp_001",
                             "menu_boot_autotest_v1", **kwargs)

    def test_identical_screenshots_pass_with_perfect_score(self):
        a = self.save("reference.png", self.scene)
        b = self.save("candidate.png", self.scene.copy())
        r = self.analyze(a, b)
        self.assertEqual(r["status"], "pass")
        self.assertEqual(r["score"], 100)
        self.assertEqual(r["frames"][0]["ssim"], 1)
        self.assertTrue((self.dir / "report" / "diff-0000.png").is_file())
        self.assertFalse(r["may_deploy_automatically"])

    def test_major_difference_triggers_regression_and_action(self):
        a = self.save("ref.png", self.scene)
        b = self.save("candidate.png", np.full_like(self.scene, 230))
        r = self.analyze(a, b)
        self.assertEqual(r["status"], "regression")
        self.assertLess(r["score"], 83)
        self.assertEqual(r["repair_feedback"]["recommended_next_step"], "isolate_regression")

    def test_blank_candidate_is_critical(self):
        a = self.save("ref.png", self.scene)
        b = self.save("black.png", np.zeros_like(self.scene))
        r = self.analyze(a, b)
        self.assertEqual(r["status"], "regression")
        self.assertIn("black_screen", [f["code"] for f in r["findings"]])

    def test_mask_excludes_known_animation(self):
        candidate = self.scene.copy()
        candidate[:50, :70] = 255
        mask = np.zeros(self.scene.shape[:2], dtype=np.uint8)
        mask[:50, :70] = 255
        a = self.save("a.png", self.scene)
        b = self.save("b.png", candidate)
        m = self.save("mask.png", mask)
        result = self.analyze(a, b, mask=m)
        self.assertEqual(result["score"], 100)
        self.assertEqual(result["status"], "pass")

    def test_invalid_and_full_mask_rejected(self):
        a = self.save("a.png", self.scene)
        b = self.save("b.png", self.scene)
        m = self.save("mask.png", np.full(self.scene.shape[:2], 255, dtype=np.uint8))
        with self.assertRaisesRegex(ValueError, "entire image"):
            self.analyze(a, b, mask=m)

    def test_mismatched_resolution_fails_closed(self):
        a = self.save("ref.png", self.scene)
        b = self.save("cand.png", self.scene[:50])
        r = self.analyze(a, b)
        self.assertEqual(r["status"], "inconclusive")
        self.assertIsNone(r["score"])
        self.assertEqual(r["findings"][0]["code"], "geometry_mismatch")

    def test_mismatched_video_frame_count_inconclusive(self):
        out = self.dir / "differences"
        out.mkdir()
        status, score, m, issues, frames = qa.compare_frames(
            [self.scene] * 4, [self.scene] * 3, None, out, 12, 94)
        self.assertEqual((status, score), ("inconclusive", None))
        self.assertEqual(issues[0]["code"], "frame_count_mismatch")
        self.assertEqual(frames, [])

    def test_frozen_video_relative_to_moving_reference(self):
        ref = [np.roll(self.scene, 17 * i, axis=1) for i in range(6)]
        candidate = [ref[0].copy() for _ in range(6)]
        out = self.dir / "diffs"
        out.mkdir()
        status, score, m, issues, frames = qa.compare_frames(
            ref, candidate, None, out, 12, 94)
        self.assertEqual(status, "regression")
        self.assertIn("possible_freeze", [i["code"] for i in issues])
        self.assertEqual(m["frame_count"], 6)

    def test_brightness_pumping_is_flagged(self):
        base = np.full((40, 60, 3), 100, dtype=np.uint8)
        ref = [base.copy() for _ in range(6)]
        cand = [np.full_like(base, x) for x in (100, 200, 100, 200, 100, 200)]
        out = self.dir / "diffs"
        out.mkdir()
        _, _, _, issues, _ = qa.compare_frames(ref, cand, None, out, 12, 94)
        self.assertIn("possible_flicker", [i["code"] for i in issues])

    def test_reject_reusing_input_or_nonempty_output(self):
        a = self.save("a.png", self.scene)
        with self.assertRaisesRegex(ValueError, "distinct"):
            self.analyze(a, a)
        b = self.save("b.png", self.scene)
        (self.dir / "report").mkdir()
        (self.dir / "report" / "do-not-overwrite.txt").write_text("preserve")
        with self.assertRaisesRegex(ValueError, "empty"):
            self.analyze(a, b)

    def test_cli_failure_on_regression(self):
        a = self.save("a.png", self.scene)
        b = self.save("b.png", np.zeros_like(self.scene))
        p = subprocess.run([sys.executable, str(ROOT / "qa.py"),
             "--reference", str(a), "--candidate", str(b),
             "--experiment-id", "synthetic_exp_001",
             "--out", str(self.dir / "cli"), "--fail-on-regression"],
             text=True, capture_output=True)
        self.assertEqual(p.returncode, 3, p.stderr)
        self.assertEqual(json.loads((self.dir / "cli/report.json").read_text())["status"], "regression")

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg unavailable")
    def test_end_to_end_video_frame_extraction(self):
        clip_dirs = []
        for suffix in ("ref", "candidate"):
            directory = self.dir / suffix
            directory.mkdir()
            for i in range(6):
                Image.fromarray(np.roll(self.scene, i * 3, axis=1)).save(directory / f"frame-{i:04d}.png")
            clip = self.dir / (suffix + ".mp4")
            p = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y",
                "-framerate", "2", "-i", str(directory / "frame-%04d.png"),
                "-c:v", "mpeg4", "-q:v", "2", str(clip)], capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stderr)
            clip_dirs.append(clip)
        report = self.analyze(clip_dirs[0], clip_dirs[1], fps=2)
        self.assertEqual(report["input_kind"], "video")
        self.assertGreater(report["metrics"]["frame_count"], 1)
        self.assertEqual(report["status"], "pass")

    def test_unmatched_durations_cannot_claim_quality_score(self):
        out = self.dir / "diffs"
        out.mkdir()
        status, score, _, findings, _ = qa.compare_frames(
            [self.scene] * 3, [self.scene] * 3, None, out, 12, 94,
            duration_pair=(3.0, 10.0))
        self.assertEqual((status, score), ("inconclusive", None))
        self.assertEqual(findings[0]["code"], "capture_duration_mismatch")

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg unavailable")
    def test_long_video_samples_late_regression(self):
        clips = []
        for suffix, broken in (("long_ref", False), ("long_candidate", True)):
            directory = self.dir / suffix
            directory.mkdir()
            for i in range(32):
                frame = np.roll(self.scene, 3 * i, axis=1)
                if broken and i >= 26:
                    frame = np.zeros_like(frame)
                Image.fromarray(frame).save(directory / f"frame-{i:04d}.png")
            clip = self.dir / (suffix + ".mp4")
            proc = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y",
                 "-framerate", "2", "-i", str(directory / "frame-%04d.png"),
                 "-c:v", "mpeg4", "-q:v", "2", str(clip)], capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            clips.append(clip)
        result = self.analyze(clips[0], clips[1], out="long-video-report", fps=2)
        self.assertLessEqual(result["metrics"]["frame_count"], qa.MAX_FRAMES)
        self.assertEqual(result["status"], "regression")
        self.assertIn("black_screen", [f["code"] for f in result["findings"]])

    def test_adapter_rejects_permission_elevation(self):
        payload = self.fake_visual()
        payload["may_deploy_automatically"] = True
        with self.assertRaisesRegex(ValueError, "authority"):
            visual_feedback.validate_visual_report(payload, "synthetic_exp_001")

    def test_adapter_rejects_wrong_experiment(self):
        with self.assertRaisesRegex(ValueError, "mismatch"):
            visual_feedback.validate_visual_report(self.fake_visual(), "another_experiment")

    def test_regression_overrides_performance_policy_without_deployment(self):
        report = {
            "schema_version": 1, "experiment_id": "synthetic_exp_001",
            "status": "candidate_for_review", "notify_human": True,
            "automatic_promotion_allowed": False, "visual_fps_verified": False
        }
        ledger = {"schema_version": 1, "events": []}
        result = experiment_controller.decision_for(
            report, ledger, visual_report=self.fake_visual())
        self.assertEqual(result["next_step"], "isolate_regression")
        self.assertEqual(result["visual_quality_status"], "regression")
        self.assertFalse(result["may_install_or_run_candidate"])
        self.assertFalse(result["may_touch_working_game"])
        self.assertFalse(result["may_deploy_automatically"])

    def test_visual_evidence_changes_dedup_fingerprint(self):
        report = {"schema_version": 1, "experiment_id": "synthetic_exp_001",
                  "status": "no_improvement", "notify_human": False,
                  "automatic_promotion_allowed": False, "visual_fps_verified": False}
        ledger = {"schema_version": 1, "events": []}
        a = experiment_controller.decision_for(report, ledger)
        b = experiment_controller.decision_for(report, ledger, visual_report=self.fake_visual())
        self.assertNotEqual(a["fingerprint"], b["fingerprint"])

    @staticmethod
    def fake_visual():
        return {
            "schema_version": 1, "tool": "openlrr-visual-qa",
            "experiment_id": "synthetic_exp_001", "status": "regression", "score": 45.3,
            "capture_hashes": {"reference_sha256": "a" * 64,
                               "candidate_sha256": "b" * 64, "mask_sha256": None},
            "findings": [{"code": "black_screen", "severity": "critical",
                          "description": "Test"}],
            "may_install_or_run_candidate": False,
            "may_touch_working_game": False,
            "may_deploy_automatically": False,
            "visual_fps_verified": False,
        }


if __name__ == "__main__":
    unittest.main()
