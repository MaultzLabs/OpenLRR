#!/usr/bin/env python3
"""Offline tests for video segment/input/Wine/NERPs/source cross-references."""
from __future__ import annotations
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import index_clips


class ClipIndexTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.clips = self.root / "clips"
        self.clips.mkdir()
        self.res = self.root / "resources"
        self.res.mkdir()
        (self.res / "resource.h").write_text(
            "#define IDM_EXIT 603\n#define IDM_NONERPS 401\n")
        (self.clips / "clips.json").write_text(json.dumps({
            "schema": "openlrr-window-video-clips-v1",
            "clips": [
                {"file": "part-0001.mp4", "start_s": 0,
                 "duration_s": 90, "bytes": 50_000},
                {"file": "part-0002.mp4", "start_s": 90,
                 "duration_s": 40, "bytes": 30_000}
            ]
        }))

    def write_events(self, events):
        (self.root / "timeline.jsonl").write_text(
            "".join(json.dumps(x) + "\n" for x in events))

    def test_align_inputs_wine_functions_and_win32_menu_to_code(self):
        self.write_events([
            {"source": "video", "event": "capture_started", "unix_s": 1000},
            {"source": "mac_input", "event": "left_down", "unix_s": 1012,
             "typed_password": "DO NOT COPY", "x": 15, "y": 20},
            {"source": "wine_api", "event": "sampled_log_batch",
             "channel": "ddraw", "operation": "blt",
             "unix_s": 1014, "private_path": "/Users/secret"},
            {"source": "openlrr_menu", "event": "win32_menu_command",
             "menu_id": 603, "unix_s": 1095},
            {"source": "nerps", "event": "runtime_function",
             "function": "GetCrystals", "function_id": 55,
             "unix_s": 1100, "raw_private": "DO NOT COPY"},
            {"source": "malicious", "event": "do_not_emit", "unix_s": 1101},
            {"source": "mac_input", "event": "right_down", "unix_s": 1150}
        ])
        result = index_clips.build_index(self.root, self.clips, source_root=self.root)
        self.assertEqual(result["events_aligned"], 5)
        self.assertEqual(result["events_outside_clips"], 1)
        self.assertEqual(len(result["clips"]), 2)
        self.assertEqual(result["clips"][0]["sources"]["mac_input"], 1)
        self.assertEqual(result["clips"][0]["sources"]["wine_api"], 1)
        last = result["clips"][1]["events"]
        self.assertTrue(any(x.get("openlrr_command") == "IDM_EXIT" for x in last))
        self.assertTrue(any(x.get("function") == "GetCrystals" for x in last))
        self.assertTrue(any(x.get("source_hint", "").endswith("NERPsRuntime_Execute")
                            for x in last))
        data = json.dumps(result)
        self.assertNotIn("DO NOT COPY", data)
        self.assertNotIn("/Users/secret", data)
        self.assertNotIn("typed_password", data)

    def test_video_without_timeline_is_not_falsely_labeled_as_nerps_trace(self):
        result = index_clips.build_index(self.root, self.clips)
        self.assertIsNone(result["capture_unix_s"])
        self.assertEqual(result["events_aligned"], 0)
        self.assertFalse(result["timeline_present"])
        self.assertTrue(result["no_nerps_trace_is_not_proof_scripts_did_not_run"])

    def test_rejects_unsafe_filename_and_duplicate_clips(self):
        for names in (["../../private.mp4"],
                      ["part-0001.mp4", "part-0001.mp4"]):
            (self.clips / "clips.json").write_text(json.dumps({
                "schema": "openlrr-window-video-clips-v1",
                "clips": [
                    {"file": name, "start_s": i * 90,
                     "duration_s": 90, "bytes": 100}
                    for i, name in enumerate(names)
                ]
            }))
            with self.assertRaises(ValueError):
                index_clips.build_index(self.root, self.clips)


if __name__ == "__main__":
    unittest.main()
