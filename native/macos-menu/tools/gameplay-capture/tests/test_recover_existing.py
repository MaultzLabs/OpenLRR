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
        def fake_split(cmd, **kw):
            if str(cmd[0]).endswith("mock-split"):
                dest = Path(cmd[2])
                (dest / "part-0001.mp4").write_bytes(b"finished-clip")
                (dest / "clips.json").write_text(json.dumps({
                    "schema": "openlrr-window-video-clips-v1", "clip_count": 1,
                    "clips": [{"file": "part-0001.mp4", "duration_s": 120}]
                }))
            return mock.Mock(returncode=0, stdout="", stderr="")
        with (mock.patch.object(sys, "platform", "darwin"),
              mock.patch.object(video_session, "build_swift_video_tool",
                                return_value=self.root / "mock-split"),
              mock.patch.object(recover.subprocess, "run", side_effect=fake_split)):
            self.assertEqual(recover.recover(self.source), 0)
        self.assertEqual(self.source.read_bytes(), self.original)
        self.assertTrue((self.root / "recovered-clips" / "part-0001.mp4").exists())

    def test_never_overwrite_existing_recovery_folder(self):
        (self.root / "recovered-clips").mkdir()
        with mock.patch.object(sys, "platform", "darwin"):
            with self.assertRaisesRegex(capture.CaptureError, "already exists"):
                recover.recover(self.source)
        self.assertEqual(self.source.read_bytes(), self.original)


if __name__ == "__main__":
    unittest.main()
