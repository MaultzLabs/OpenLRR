#!/usr/bin/env python3
"""Offline tests for non-destructive repair attempts on interrupted MP4."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import capture
import video_session

spec = importlib.util.spec_from_file_location("recover_existing", ROOT / "recover-existing.py")
recover = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = recover
spec.loader.exec_module(recover)


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        self.source = self.root / "game-window-master.mp4"
        self.source.write_bytes(b"interrupted-movie-placeholder")
        self.original = self.source.read_bytes()

    def test_damaged_mp4_cannot_claim_success_or_modify_original(self):
        result = mock.Mock(returncode=3, stdout="", stderr="unreadable")
        with (mock.patch.object(sys, "platform", "darwin"),
              mock.patch.object(video_session, "build_swift_video_tool",
                                return_value=self.root / "mock-split"),
              mock.patch.object(recover.subprocess, "run", return_value=result)):
            self.assertEqual(recover.recover(self.source), 2)
        self.assertEqual(self.source.read_bytes(), self.original)
        self.assertFalse((self.root / "recovered-clips" / "clips.json").exists())

    def test_symlink_source_is_rejected_without_reading_or_writing(self):
        link = self.root / "alias.mp4"
        link.symlink_to(self.source)
        with mock.patch.object(sys, "platform", "darwin"):
            with self.assertRaisesRegex(capture.CaptureError, "non-symlinked"):
                recover.recover(link)
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_recovery_writes_separate_clips_without_replacing_master(self):
        (self.root / "timeline.jsonl").write_text(
            json.dumps({"source": "video", "event": "capture_started",
                        "unix_s": 1792620000}) + "\\n" +
            json.dumps({"source": "openlrr_menu", "event": "win32_menu_command",
                        "menu_id": 603, "unix_s": 1792620015}) + "\\n")
        def fake_split(cmd, **kw):
            if str(cmd[0]).endswith("mock-split"):
                dest = Path(cmd[2])
                (dest / "part-0001.mp4").write_bytes(b"c" * 6000)
                (dest / "clips.json").write_text(json.dumps({
                    "schema": "openlrr-window-video-clips-v1", "clip_count": 1,
                    "clips": [{"file": "part-0001.mp4", "start_s": 0, "duration_s": 120, "bytes": 6000}]
                }))
            return mock.Mock(returncode=0, stdout="", stderr="")
        with (mock.patch.object(sys, "platform", "darwin"),
              mock.patch.object(video_session, "build_swift_video_tool",
                                return_value=self.root / "mock-split"),
              mock.patch.object(recover.subprocess, "run", side_effect=fake_split)):
            self.assertEqual(recover.recover(self.source), 0)
        self.assertEqual(self.source.read_bytes(), self.original)
        self.assertTrue((self.root / "recovered-clips" / "part-0001.mp4").exists())
        self.assertTrue((self.root / "recovered-clips" / "upload-evidence.zip").exists())
        from zipfile import ZipFile
        with ZipFile(self.root / "recovered-clips" / "upload-evidence.zip") as bundle:
            self.assertIn("analysis-index.json", bundle.namelist())
            self.assertIn("part-0001.evidence.json", bundle.namelist())
            self.assertNotIn("game-window-master.mp4", bundle.namelist())
            evidence = json.loads(bundle.read("part-0001.evidence.json"))
            self.assertEqual(evidence["events"][1]["openlrr_command"], "IDM_EXIT")

    def test_validation_rejects_missing_or_size_mismatched_clips(self):
        destination = self.root / "recovered-clips"
        destination.mkdir()
        (destination / "part-0001.mp4").write_bytes(b"x" * 6000)
        manifest = {"schema": "openlrr-window-video-clips-v1",
                    "clip_count": 1,
                    "clips": [{"file": "part-0001.mp4", "start_s": 0,
                               "duration_s": 120, "bytes": 6001}]}
        (destination / "clips.json").write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "size differs"):
            recover.validate_exported_clips(destination)
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_validation_rejects_oversized_and_discontinuous_timestamps(self):
        destination = self.root / "recovered-clips"
        destination.mkdir()
        (destination / "part-0001.mp4").write_bytes(b"x" * 6000)
        (destination / "part-0002.mp4").write_bytes(b"y" * 6000)
        manifest = {"schema": "openlrr-window-video-clips-v1",
                    "clip_count": 2,
                    "clips": [{"file": "part-0001.mp4", "start_s": 0,
                               "duration_s": 120, "bytes": 6000},
                              {"file": "part-0002.mp4", "start_s": 125,
                               "duration_s": 60, "bytes": 6000}]}
        listing = destination / "clips.json"
        listing.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "discontinuous"):
            recover.validate_exported_clips(destination)
        manifest["clips"][1]["start_s"] = 120
        manifest["clips"][0]["bytes"] = 151 * 1024 * 1024
        listing.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "oversized"):
            recover.validate_exported_clips(destination)

    def test_validation_rejects_symlinked_clip(self):
        destination = self.root / "recovered-clips"
        destination.mkdir()
        (destination / "part-0001.mp4").symlink_to(self.source)
        (destination / "clips.json").write_text(json.dumps({
            "schema": "openlrr-window-video-clips-v1", "clip_count": 1,
            "clips": [{"file": "part-0001.mp4", "start_s": 0,
                       "duration_s": 120, "bytes": 6000}]}))
        with self.assertRaisesRegex(ValueError, "MP4 missing"):
            recover.validate_exported_clips(destination)

    def test_never_overwrite_existing_recovery_folder(self):
        (self.root / "recovered-clips").mkdir()
        with mock.patch.object(sys, "platform", "darwin"):
            with self.assertRaisesRegex(capture.CaptureError, "already exists"):
                recover.recover(self.source)
        self.assertEqual(self.source.read_bytes(), self.original)


if __name__ == "__main__":
    unittest.main()
