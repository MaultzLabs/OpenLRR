#!/usr/bin/env python3
"""Portable tests for continuous video capture protocol and private packaging."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import capture
import video_session


class VideoSessionTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)

    def test_video_helper_protocol_drops_arbitrary_and_private_strings(self):
        from io import StringIO
        timeline = capture.Timeline(self.root / "video.jsonl")
        state = {}
        lines = [
            {"source": "video", "event": "capture_started",
             "unix_s": 12345, "monotonic_s": 100, "scope": "single_game_window",
             "window_id": 51, "audio_requested": True, "microphone": False,
             "audio_scope": "owning_application",
             "secret": "private tokens", "filename": "/Users/name"},
            {"source": "video", "event": "video_complete",
             "bytes": 98000, "duration_s": 23.1,
             "audio_track_present": True, "audio_scope": "owning_application",
             "stop_reason": "game_window_closed", "raw_path": "/Users/name"},
            {"source": "video", "event": "hacked",
             "message": "password", "filename": "/Users/name"}
        ]
        video_session.pump_video_stdout(
            StringIO("\n".join(json.dumps(x) for x in lines) + "\n"),
            timeline, state)
        timeline.close()
        payload = (self.root / "video.jsonl").read_text()
        self.assertNotIn("private", payload)
        self.assertNotIn("password", payload)
        self.assertNotIn("/Users", payload)
        recs = [json.loads(x) for x in payload.splitlines()]
        self.assertEqual(len(recs), 2)
        self.assertTrue(state["capture_started"])
        self.assertTrue(state["video_complete"])
        self.assertEqual(state["video_duration_s"], 23.1)
        self.assertTrue(state["audio_track_present"])
        self.assertTrue(recs[0]["audio_requested"])
        self.assertFalse(recs[0]["microphone"])
        self.assertEqual(recs[1]["audio_scope"], "owning_application")
        self.assertEqual(recs[-1]["stop_reason"], "game_window_closed")

    def test_private_review_export_includes_safe_segment_metadata_not_video(self):
        s = self.root / "session"
        capture.make_private_dir(s)
        capture.make_private_dir(s / "clips")
        (s / "manifest.json").write_text(json.dumps({
            "scope": "game_window_only", "mode": "continuous_h264_video",
            "video_complete": True
        }))
        (s / "timeline.jsonl").write_text(
            json.dumps({"source": "video", "event": "capture_started", "unix_s": 4}) + "\n" +
            json.dumps({"source": "mac_input", "event": "left_down", "unix_s": 5}) + "\n")
        (s / "wine_raw.local.log").write_text("private path /Users/secret")
        (s / "game-window-master.mp4").write_bytes(b"private video")
        (s / "clips" / "part-0001.mp4").write_bytes(b"private video")
        (s / "clips" / "clips.json").write_text(json.dumps({
            "schema": "openlrr-window-video-clips-v1",
            "private": "must not leak",
            "clips": [
                {"file": "part-0001.mp4", "start_s": 0, "duration_s": 300,
                 "bytes": 125000, "private": "injection"},
                {"file": "../../secrets", "start_s": 0, "duration_s": 2,
                 "bytes": 2}
            ]
        }))
        archive_path = self.root / "review.zip"
        capture.package_review(s, archive_path, include_frames=False)
        with zipfile.ZipFile(archive_path) as archive:
            self.assertEqual(set(archive.namelist()),
                             {"manifest.json", "timeline.jsonl", "clips.json"})
            self.assertNotIn("private", archive.read("clips.json").decode())
            clips = json.loads(archive.read("clips.json"))["clips"]
            self.assertEqual(clips, [{
                "file": "part-0001.mp4", "start_s": 0,
                "duration_s": 300, "bytes": 125000
            }])
            self.assertNotIn("secret", archive.read("timeline.jsonl").decode())

    def test_video_event_names_are_fixed_and_no_unknown_fields(self):
        self.assertNotIn("key_text", video_session.ALLOWED_VIDEO_EVENTS)
        self.assertNotIn("desktop_capture", video_session.ALLOWED_VIDEO_EVENTS)


if __name__ == "__main__":
    unittest.main()
