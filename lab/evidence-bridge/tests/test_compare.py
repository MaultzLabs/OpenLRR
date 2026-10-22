#!/usr/bin/env python3
"""Deterministic synthetic proof for the cross-platform evidence bridge."""
import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest

SRC = Path(__file__).resolve().parents[1] / "compare.py"
spec = importlib.util.spec_from_file_location("openlrr_cross_platform_evidence", SRC)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


def mac_sample():
    return {
        "schema": "openlrr-clip-code-index-v1",
        "capture_unix_s": 1792624765.9347029,
        "clips": [
            {
                "file": "part-0001.mp4", "start_s": 0, "duration_s": 120,
                "events": [
                    {"source": "video", "at_s": 0.0},
                    {"source": "mac_input", "input_event": "left_down",
                     "at_s": 2.5, "x_normalized": .25,
                     "y_normalized": .75},
                    {"source": "mac_input", "input_event": "key_down",
                     "at_s": 3.0, "keycode": 36},
                    {"source": "openlrr_menu", "menu_id": 603,
                     "at_s": 3.2, "raw_user_path": "/Users/private"},
                    {"source": "nerps", "function_id": 17,
                     "at_s": 4.0, "function": "GetR0", "args": [8, 0, 0]},
                ],
            },
            {
                "file": "part-0002.mp4", "start_s": 120,
                "duration_s": 90, "events": [
                    {"source": "wine_api", "at_s": 5.5, "wine_channel": "ddraw"}
                ],
            },
        ],
    }


def windows_sample():
    return {
        "status": "passed",
        "pid": 31912,
        "target": "C:/private/secret/game.exe",
        "evidence": "window-only",
        "events": [
            {"step": 0, "action": "capture",
             "timestamp_utc": "2026-10-21T23:19:25Z", "title": "private",
             "frame": "frame-00.png"},
            {"step": 1, "action": "click",
             "timestamp_utc": "2026-10-21T23:19:25Z",
             "title": "not for export"},
            {"step": 2, "action": "key",
             "timestamp_utc": "2026-10-21T23:19:27Z"},
            {"step": 3, "action": "assert_changed",
             "timestamp_utc": "2026-10-21T23:19:29Z",
             "frame": "frame-03.png", "mean_pixel_difference": 3.19},
        ],
    }


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_cross_platform_actions_and_game_events_without_fabrication(self):
        m = bridge.normalize_mac(mac_sample())
        w = bridge.normalize_windows(windows_sample())
        result = bridge.compare(m, w)
        self.assertEqual(result["schema"], bridge.SCHEMA)
        self.assertEqual(m["clip_count"], 2)
        self.assertEqual(m["indexed_video_duration_s"], 210)
        self.assertEqual(m["game_actions"], [
            {"type": "click", "time_from_video_s": 2.5,
             "x_normalized": .25, "y_normalized": .75},
            {"type": "key", "name": "enter", "time_from_video_s": 3.0}
        ])
        self.assertEqual([e["type"] for e in m["game_internal_events"]],
                         ["menu_command", "nerps_function"])
        self.assertEqual(m["game_internal_events"][1]["function_id"], 17)
        self.assertEqual(w["visual_observations"][1]["mean_pixel_difference"], 3.19)
        self.assertEqual(result["action_sequence"]["common_ordered_action_tokens"], 1)
        self.assertEqual(w["game_actions"][1]["name"], "unrecorded")
        self.assertEqual(result["actual_gameplay_parity"], "not_established")
        self.assertFalse(w["original_game_execution_verified"])

    def test_private_path_pid_and_raw_titles_do_not_leak(self):
        report = json.dumps(
            bridge.compare(bridge.normalize_mac(mac_sample()),
                           bridge.normalize_windows(windows_sample())),
            sort_keys=True)
        for forbidden in ("C:/private", "/Users/private", "31912",
                          "not for export", "raw_user_path"):
            self.assertNotIn(forbidden, report)

    def test_empty_real_mac_session_does_not_become_gameplay_evidence(self):
        data = mac_sample()
        for clip in data["clips"]:
            clip["events"] = [{"source": "video", "at_s": 0}]
        m = bridge.normalize_mac(data)
        self.assertEqual(m["game_internal_events"], [])
        self.assertFalse(m["has_recorded_game_controls"])
        result = bridge.compare(m, bridge.normalize_windows(windows_sample()))
        self.assertIsNone(result["action_sequence"]["overlap_fraction_of_shorter"])

    def test_different_clocks_are_never_synchronized_or_called_parity(self):
        m = bridge.normalize_mac(mac_sample())
        w = bridge.normalize_windows(windows_sample())
        self.assertIn("not_synchronized", w["time_precision"])
        self.assertEqual(bridge.compare(m, w)["reference_windows_game_execution"],
                         "not_attested")

    def test_rejects_unsafe_or_invalid_records(self):
        bad = mac_sample()
        bad["clips"][0]["file"] = "../../retail.wad"
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            bridge.normalize_mac(bad)
        bad = mac_sample()
        bad["clips"][0]["events"] = "not a list"
        with self.assertRaises(ValueError):
            bridge.normalize_mac(bad)
        bad = windows_sample()
        bad["events"][1]["step"] = 0
        with self.assertRaises(ValueError):
            bridge.normalize_windows(bad)
        bad = windows_sample()
        bad["events"].append({"step": 99, "action": "execute",
                              "timestamp_utc": "2026-10-21T23:19:29Z"})
        with self.assertRaises(ValueError):
            bridge.normalize_windows(bad)

    def test_missing_video_frame_not_assumed_observed(self):
        w = windows_sample()
        w["events"][0]["frame"] = "../../outside.png"
        result = bridge.normalize_windows(w)
        self.assertEqual(len(result["visual_observations"]), 1)

    def test_private_file_creation_rejects_overwrites_and_symlinks(self):
        target = self.root / "evidence.json"
        bridge.write_private({"schema": bridge.SCHEMA}, target)
        self.assertEqual(json.loads(target.read_text())["schema"], bridge.SCHEMA)
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
        with self.assertRaisesRegex(ValueError, "overwrite"):
            bridge.write_private({}, target)
        source = self.root / "old.json"
        source.write_text('{"safe": true}')
        alias = self.root / "alias.json"
        alias.symlink_to(source)
        with self.assertRaisesRegex(ValueError, "symlink"):
            bridge.read_json(alias)
        with self.assertRaises(ValueError):
            bridge.write_private({}, alias)

    def test_actual_previous_mac_capture_index_is_accepted(self):
        # 10m29s evidence from the real user-recovered recording:
        # video-only events do not create fictional game controls.
        m = {"schema": bridge.MAC_SCHEMA, "capture_unix_s": 1792624765.9347029,
             "clips": [
                 {"file": f"part-{i:04d}.mp4", "start_s": start,
                  "duration_s": seconds,
                  "events": [{"source": "video", "at_s": 0}]
                            if i == 1 else []}
                 for i, start, seconds in
                 [(1, 0, 120), (2, 120, 120), (3, 240, 60),
                  (4, 300, 60), (5, 360, 60), (6, 420, 60),
                  (7, 480, 60), (8, 540, 60), (9, 600, 29.57)]
             ]}
        out = bridge.normalize_mac(m)
        self.assertAlmostEqual(out["indexed_video_duration_s"], 629.57)
        self.assertFalse(out["has_real_game_internal_evidence"])
        self.assertEqual(out["clip_count"], 9)

    def test_cli_end_to_end_produces_private_json_without_binary_frames(self):
        src_mac = self.root / "mac.json"
        src_win = self.root / "windows.json"
        destination = self.root / "comparison.json"
        src_mac.write_text(json.dumps(mac_sample()))
        src_win.write_text(json.dumps(windows_sample()))
        self.assertEqual(bridge.main(["--mac-index", str(src_mac),
                                      "--windows-report", str(src_win),
                                      "--out", str(destination)]), 0)
        self.assertEqual(bridge.read_json(destination)["actual_gameplay_parity"],
                         "not_established")


if __name__ == "__main__":
    unittest.main()
