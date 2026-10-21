#!/usr/bin/env python3
"""Safety tests for optional source-grounded NERPs runtime telemetry."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import capture


class NerpsTelemetryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_action_arguments_results_and_original_clock_are_preserved(self):
        log = self.root / "nerps.log"
        log.touch()
        follower = capture.NerpsFollower(log)
        timeline = capture.Timeline(self.root / "events.jsonl")
        payload = {
            "function": "GetCrystals", "function_id": 55, "pc": 123,
            "frame": 802, "kind": "predicate",
            "argc": 1, "args": [1, 0, 0], "result": 7,
            "game_unix_s": 1792610500.5, "game_tick_ms": 123456789,
            "game_asset_path": "/Users/test/private", "password": "private",
            "owner": "never-log-owner-data"
        }
        with log.open("a") as writer:
            writer.write(json.dumps(payload) + "\n")
            writer.write('{"function_id":987654,"kind":"evil","args":["PASSWORD"]}\n')
        follower.sample(timeline)
        timeline.close()
        record_lines = (self.root / "events.jsonl").read_text()
        self.assertNotIn("private", record_lines)
        self.assertNotIn("owner", record_lines)
        self.assertNotIn("PASSWORD", record_lines)
        rows = [json.loads(line) for line in record_lines.splitlines()]
        self.assertEqual(len(rows), 1)
        obj = rows[0]
        self.assertEqual(obj["source"], "nerps")
        self.assertEqual(obj["kind"], "predicate")
        self.assertEqual(obj["function_id"], 55)
        self.assertEqual(obj["game_unix_s"], 1792610500.5)
        self.assertEqual(obj["game_tick_ms"], 123456789)
        self.assertEqual(obj["time_basis"], "host_log_read")
        self.assertIn("unix_s", obj)
        self.assertEqual(obj["result"], 7)
        self.assertEqual(obj["args"], [1, 0, 0])

    def test_rejects_unbounded_inputs_but_still_parses_following_events(self):
        log = self.root / "nerps.log"
        log.touch()
        follower = capture.NerpsFollower(log)
        timeline = capture.Timeline(self.root / "timeline.jsonl")
        with log.open("a") as writer:
            writer.write("x" * 5000 + "\n")
            writer.write(json.dumps({
                "function": "AdvanceMessage", "kind": "action",
                "args": [1], "result": 0, "game_unix_s": 0,
                "game_tick_ms": -1, "raw_text": "unrelated app"
            }) + "\n")
        follower.sample(timeline)
        timeline.close()
        rows = [json.loads(x) for x in
                (self.root / "timeline.jsonl").read_text().splitlines()]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["function"], "AdvanceMessage")
        self.assertNotIn("game_unix_s", rows[0])
        self.assertNotIn("game_tick_ms", rows[0])
        self.assertNotIn("raw_text", rows[0])


if __name__ == "__main__":
    unittest.main()
