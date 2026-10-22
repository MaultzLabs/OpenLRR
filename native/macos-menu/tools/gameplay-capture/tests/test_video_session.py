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


    def test_rolling_segments_retained_after_late_stream_error(self):
        from io import StringIO
        timeline = capture.Timeline(self.root / "live.jsonl")
        state = {}
        lines = [
            {"source": "video", "event": "capture_started", "unix_s": 12345},
            {"source": "video", "event": "segment_complete", "part": 1,
             "start_offset_s": 0, "duration_s": 90.0, "bytes": 6000,
             "audio_track_present": True, "private_file": "/Users/alice/secrets"},
            {"source": "video", "event": "segment_complete", "part": 2,
             "start_offset_s": 90.1, "duration_s": 90.0, "bytes": 8000,
             "audio_track_present": True},
            {"source": "video", "event": "stream_failed", "error_code": -3805},
            {"source": "video", "event": "segment_finalize_failed", "part": 3,
             "stage": "remove_output", "error_code": -3805},
            {"source": "video", "event": "capture_complete",
             "finished_segments": 2, "stop_reason": "game_window_closed"}
        ]
        video_session.pump_video_stdout(
            StringIO("\n".join(json.dumps(x) for x in lines) + "\n"),
            timeline, state)
        timeline.close()
        self.assertTrue(state["partial"])
        self.assertTrue(state["capture_complete"])
        self.assertEqual([x["file"] for x in state["segments"]],
                         ["part-0001.mp4", "part-0002.mp4"])
        self.assertEqual(state["last_error"], "stream_failed")
        self.assertNotIn("/Users", (self.root / "live.jsonl").read_text())

    def test_supervisor_exports_completed_clips_even_if_wine_quit_breaks_last(self):
        from io import StringIO
        from unittest import mock

        window = capture.GameWindow(45, 321)
        session = self.root / "my-private-session"

        class TestProbe:
            def inspect(self, target):
                return {"exists": False, "id": target.id, "pid": target.pid}

        class FakeVideoProcess:
            def __init__(self, args, **kwargs):
                self.returncode = None
                self.stdin = StringIO()
                clip_dir = Path(args[3])
                (clip_dir / "part-0001.mp4").write_bytes(b"1" * 6000)
                (clip_dir / "part-0002.mp4").write_bytes(b"2" * 6000)
                events = [
                    {"source": "video", "event": "capture_started", "unix_s": 12345},
                    {"source": "video", "event": "segment_complete",
                     "part": 1, "start_offset_s": 0, "duration_s": 90,
                     "bytes": 6000, "audio_track_present": True},
                    {"source": "video", "event": "segment_complete",
                     "part": 2, "start_offset_s": 90, "duration_s": 90,
                     "bytes": 6000, "audio_track_present": False},
                    {"source": "video", "event": "stream_failed", "error_code": -3805},
                    {"source": "video", "event": "segment_finalize_failed",
                     "part": 3, "stage": "remove_output"},
                    {"source": "video", "event": "capture_complete",
                     "finished_segments": 2, "stop_reason": "game_window_closed"}
                ]
                self.stdout = StringIO(
                    "\n".join(json.dumps(item) for item in events) + "\n")

            def poll(self):
                return self.returncode

            def wait(self, timeout=None):
                self.returncode = 0
                return 0

        with mock.patch.object(video_session.subprocess, "Popen", FakeVideoProcess):
            result = video_session.continuous_capture(
                TestProbe(), window, session, self.root / "not-real-video",
                segment_seconds=90, input_binary=None)
        self.assertTrue(result["video_complete"])
        self.assertTrue(result["video_partial"])
        self.assertEqual(result["completed_segment_count"], 2)
        self.assertEqual(result["stop_reason"], "game_window_closed")
        manifest = json.loads((session / "clips" / "clips.json").read_text())
        self.assertEqual(manifest["clips"][0]["file"], "part-0001.mp4")
        self.assertEqual(manifest["clips"][1]["file"], "part-0002.mp4")
        self.assertTrue(manifest["partial"])
        self.assertEqual(
            video_session.split_private_video(self.root / "not-real-split", session),
            session / "clips")
        review = self.root / "review-live.zip"
        capture.package_review(session, review, include_frames=False)
        with zipfile.ZipFile(review) as archive:
            self.assertIn("clips.json", archive.namelist())
            self.assertNotIn("part-0001.mp4", archive.namelist())

    def test_live_clip_metadata_rejects_false_completion_and_unbounded_part(self):
        from io import StringIO
        timeline = capture.Timeline(self.root / "unsafe.jsonl")
        state = {}
        rows = [
            {"source": "video", "event": "segment_complete", "part": 0,
             "bytes": 7000, "duration_s": 3, "start_offset_s": 0},
            {"source": "video", "event": "segment_complete", "part": 900000,
             "bytes": 7000, "duration_s": 3, "start_offset_s": 0},
            {"source": "video", "event": "segment_complete", "part": 1,
             "bytes": 0, "duration_s": 3, "start_offset_s": 0}
        ]
        video_session.pump_video_stdout(
            StringIO("\n".join(json.dumps(x) for x in rows) + "\n"), timeline, state)
        timeline.close()
        self.assertEqual(state.get("segments", []), [])

    def test_live_launcher_uses_ninety_second_finalization_by_default(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "live_gameplay_launcher", ROOT / "first-level-video.py")
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        launcher = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(launcher)
        self.assertEqual(launcher.DEFAULT_SEGMENT_SECONDS, 90)
        self.assertEqual(video_session.continuous_capture.__kwdefaults__["segment_seconds"], 90)

    def test_video_event_names_are_fixed_and_no_unknown_fields(self):
        self.assertNotIn("key_text", video_session.ALLOWED_VIDEO_EVENTS)
        self.assertNotIn("desktop_capture", video_session.ALLOWED_VIDEO_EVENTS)


if __name__ == "__main__":
    unittest.main()
