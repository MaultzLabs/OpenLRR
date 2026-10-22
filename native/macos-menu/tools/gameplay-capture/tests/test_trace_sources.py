#!/usr/bin/env python3
"""Mandatory default trace discovery and authentic instrumented runtime events."""
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import capture
import trace_sources
import video_session
import index_clips


class AllStreamTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.trace_dir = self.root / "active-traces"
        self.trace_dir.mkdir(mode=0o700)

    def _stream(self, name, text=""):
        file = self.trace_dir / name
        file.write_text(text)
        file.chmod(0o600)
        return file

    def test_required_sources_default_to_fail_closed(self):
        found, checks = trace_sources.discover(root=self.trace_dir)
        self.assertIsNone(found)
        self.assertEqual(checks, {"wine": "missing", "nerps": "missing"})
        with self.assertRaisesRegex(capture.CaptureError, "No game was launched"):
            trace_sources.require(root=self.trace_dir)

    def test_both_sources_discovered_without_user_path_options(self):
        self._stream("wine-debug.log")
        self._stream("nerps-events.jsonl")
        found, checks = trace_sources.discover(root=self.trace_dir)
        self.assertIsNotNone(found)
        self.assertEqual(found.wine, self.trace_dir / "wine-debug.log")
        self.assertEqual(found.nerps, self.trace_dir / "nerps-events.jsonl")
        self.assertEqual(set(checks.values()), {"ready_to_follow"})

    def test_symlink_and_stale_and_unsafe_files_refused(self):
        wine = self._stream("wine-debug.log")
        nerps = self.trace_dir / "nerps-events.jsonl"
        nerps.symlink_to(wine)
        found, checks = trace_sources.discover(root=self.trace_dir)
        self.assertIsNone(found)
        self.assertEqual(checks["nerps"], "missing")
        nerps.unlink()
        nerps = self._stream("nerps-events.jsonl")
        nerps.chmod(0o644)
        self.assertEqual(trace_sources.discover(root=self.trace_dir)[1]["nerps"],
                         "not_private")
        nerps.chmod(0o600)
        old = time.time() - trace_sources.MAX_SOURCE_AGE_SECONDS - 5
        os.utime(wine, (old, old))
        self.assertEqual(trace_sources.discover(root=self.trace_dir)[1]["wine"],
                         "stale")

    def test_instrumented_menu_and_nerps_ids_preserved_with_game_time(self):
        records = [
            {"event": "menu_command", "menu_id": 603,
             "game_unix_s": 1792624767.123, "game_tick_ms": 1234},
            {"function": "GetR0", "function_id": 17, "pc": 4,
             "frame": 23, "kind": "predicate",
             "args": [0, 0, 0], "argc": 0, "result": 5,
             "game_unix_s": 1792624768.456, "game_tick_ms": 2234},
            {"event": "menu_command", "menu_id": 70000,
             "game_unix_s": 1792624769.1},
            {"function_id": "not numeric", "args": ["secret"]},
        ]
        path = self.trace_dir / "nerps-events.jsonl"
        path.write_text("\n".join(json.dumps(row) for row in records) + "\n")
        path.chmod(0o600)
        timeline = capture.Timeline(self.root / "timeline.jsonl")
        follower = capture.NerpsFollower(path)
        follower.sample(timeline)
        follower.sample(timeline)
        timeline.close()
        got = [json.loads(x) for x in
               (self.root / "timeline.jsonl").read_text().splitlines()]
        self.assertEqual(len(got), 2)
        self.assertEqual(got[0]["source"], "openlrr_menu")
        self.assertEqual(got[0]["menu_id"], 603)
        self.assertEqual(got[1]["function_id"], 17)
        self.assertEqual(got[1]["result"], 5)
        self.assertEqual(got[1]["pc"], 4)
        self.assertEqual(got[1]["time_basis"], "game_unix_clock")
        self.assertAlmostEqual(got[1]["unix_s"], 1792624768.456)
        self.assertNotIn("secret", str(got))
        self.assertEqual(follower._cursor, path.stat().st_size)

    def test_readiness_never_conflates_live_game_tracing_with_source_presence(self):
        p = self.root / "timeline.jsonl"
        p.write_text(json.dumps({"source": "video", "event": "capture_started"}) + "\n")
        coverage = video_session.diagnostic_coverage(
            p, video_verified=True, input_requested=True,
            wine_attached=True, nerps_attached=True)
        self.assertFalse(coverage["all_streams_observed"])
        self.assertEqual(coverage["streams"]["wine"], "attached_no_matching_calls")
        self.assertEqual(coverage["streams"]["nerps"], "attached_no_events")


if __name__ == "__main__":
    unittest.main()
