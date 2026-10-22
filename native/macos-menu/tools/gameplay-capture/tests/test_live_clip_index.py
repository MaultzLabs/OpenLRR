"""Offline tests for finalized MP4 sidecars and input/source time alignment."""
import json
from io import StringIO
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import capture
import live_clip_index
import video_session

class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.session = Path(self.tmp.name)
        self.clips = self.session / "clips"
        self.clips.mkdir()
        (self.clips / "part-0001.mp4").write_bytes(b"x" * 6000)
        self.timeline = self.session / "timeline.jsonl"
        events = [
            {"source":"video","event":"capture_started","unix_s":1792620000},
            {"source":"mac_input","event":"left_down","unix_s":1792620005},
            {"source":"wine_api","channel":"ddraw","unix_s":1792620010},
            {"source":"nerps","function_id":27,"function":"GetTimer0","unix_s":1792620020},
        ]
        self.timeline.write_text("".join(json.dumps(e)+"\n" for e in events))

    def segment(self, size=6000):
        return {"part":1,"file":"part-0001.mp4","start_s":0,
                "duration_s":90,"bytes":size,"audio_track_present":True}

    def test_creates_timed_clip_reference_during_recording(self):
        writer = live_clip_index.LiveClipIndexer(self.session,self.clips)
        path = writer.write(self.segment())
        data = json.loads(path.read_text())
        self.assertTrue(data["upload_ready_size_only"])
        self.assertTrue(data["nerps_captured"])
        self.assertTrue(data["wine_captured"])
        self.assertEqual(data["events_by_source"]["mac_input"],1)
        self.assertEqual(data["events_by_source"]["nerps"],1)
        self.assertEqual(data["events_omitted"],0)
        with self.assertRaises(ValueError): writer.write(self.segment())

    def test_never_index_unfinished_clip(self):
        writer = live_clip_index.LiveClipIndexer(self.session,self.clips)
        with self.assertRaises(ValueError): writer.write(self.segment(6001))
        self.assertFalse((self.clips/"part-0001.evidence.json").exists())

    def test_mark_unusually_large_clip_for_further_processing(self):
        size = 181*1024*1024
        with (self.clips/"part-0001.mp4").open("r+b") as handle:
            handle.truncate(size)
        data = json.loads(live_clip_index.LiveClipIndexer(
            self.session,self.clips).write(self.segment(size)).read_text())
        self.assertFalse(data["upload_ready_size_only"])

    def test_video_callback_indexed_without_waiting_for_game_exit(self):
        timeline = capture.Timeline(self.session/"live-events.jsonl")
        state = {}
        lines = [
            {"source":"video","event":"capture_started","unix_s":1792620000},
            {"source":"video","event":"segment_complete","part":1,
             "start_offset_s":0,"duration_s":90,"bytes":6000},
        ]
        stream = StringIO("".join(json.dumps(x)+"\n" for x in lines))
        writer = live_clip_index.LiveClipIndexer(self.session,self.clips)
        video_session.pump_video_stdout(stream,timeline,state,
                                        on_segment=writer.write)
        timeline.close()
        self.assertEqual(state["clips_indexed_live"],1)
        self.assertTrue((self.clips/"part-0001.evidence.json").exists())

    def test_no_nerps_or_wine_claims_when_not_recorded(self):
        self.timeline.write_text(json.dumps({
            "source":"video","event":"capture_started","unix_s":1792620000
        })+"\n")
        path = live_clip_index.LiveClipIndexer(self.session,self.clips).write(
            self.segment())
        evidence = json.loads(path.read_text())
        self.assertFalse(evidence["nerps_captured"])
        self.assertFalse(evidence["wine_captured"])

    def test_existing_split_video_can_be_indexed(self):
        (self.clips/"part-0002.mp4").write_bytes(b"y"*7000)
        (self.clips/"clips.json").write_text(json.dumps({
            "schema":"openlrr-window-video-clips-v1",
            "clips":[
                {"file":"part-0001.mp4","start_s":0,"duration_s":90,"bytes":6000},
                {"file":"part-0002.mp4","start_s":90,"duration_s":30,"bytes":7000}
            ]
        }))
        paths = live_clip_index.index_existing_clips(self.session,self.clips)
        self.assertEqual(len(paths),2)

if __name__ == "__main__": unittest.main()