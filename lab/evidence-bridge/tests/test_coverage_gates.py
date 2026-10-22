"""Synthetic tests for Mac/Windows evidence coverage gates."""
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import audit


def mac():
    return {"schema": "openlrr-clip-code-index-v1", "capture_unix_s": 1792624765.9,
            "clips": [{"file": "part-0001.mp4", "start_s": 0, "duration_s": 30,
                       "events_omitted": 0, "sources": {"nerps": 1, "video": 1},
                       "events": [{"source": "video", "at_s": 0},
                                  {"source": "nerps", "function_id": 17, "at_s": 3}]}]}


def windows():
    return {"status": "passed", "events": [{"step": 0, "action": "capture",
            "frame": "frame-00.png", "timestamp_utc": "2026-10-21T23:19:25Z"}],
            "target": "C:/private/secret.exe"}


class CoverageTests(unittest.TestCase):
    def test_complete_index_is_not_authentic_gameplay(self):
        result = audit.audit(mac(), windows())
        self.assertEqual(result["mac"]["event_preview_coverage"], "complete")
        self.assertEqual(result["mac"]["indexed_nerps_events"], 1)
        self.assertFalse(result["mac"]["original_game_attested"])
        self.assertFalse(result["windows"]["original_game_attested"])
        self.assertFalse(result["cross_platform"]["frame_synchronized"])
        self.assertNotIn("C:/private", str(result))

    def test_omitted_events_are_incomplete(self):
        m = mac()
        m["clips"][0]["events_omitted"] = 99
        result = audit.audit(m, windows())
        self.assertEqual(result["mac"]["event_preview_coverage"], "incomplete")
        self.assertFalse(result["cross_platform"]["action_overlap_complete"])

    def test_legacy_index_is_unknown(self):
        m = mac()
        del m["clips"][0]["events_omitted"]
        self.assertEqual(audit.audit(m, windows())["mac"]["event_preview_coverage"],
                         "unknown")

    def test_contradictory_counts_rejected(self):
        m = mac()
        m["clips"][0]["sources"]["nerps"] = 0
        with self.assertRaises(ValueError):
            audit.audit(m, windows())


if __name__ == "__main__":
    unittest.main()
