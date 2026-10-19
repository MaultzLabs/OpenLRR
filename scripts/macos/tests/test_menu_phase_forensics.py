"""No-Mac fixtures for exact CSV grouping and post-movie phase analysis."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SOURCE = Path(__file__).resolve().parents[1] / "menu-phase-forensics.py"
SPEC = importlib.util.spec_from_file_location("menu_phase_forensics", SOURCE)
forensics = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(forensics)


def interval(*, seconds=1.27, movie=0, blits=4, slow=1, max_blt=1252.0, cpu=1270):
    values = {"movie_update": (movie, 0, 0),
              "frame_flip": (blits, 0, 0),
              "window_present_blt": (blits, 1255 if slow else 90, max_blt),
              "window_blt_over_1000ms": (slow, 0, 0),
              "window_blt_slow_thread_cpu": (slow, cpu if slow else 0, cpu if slow else 0),
              "frame_outside_flip": (blits, 4, 2),
              "window_blt_slow_low_cpu": (0, 0, 0)}
    return "".join(f"{seconds},0,0,0,{n},{c},{total},{mx}\n"
                   for n, (c, total, mx) in values.items())


class MenuPhaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name) / "autobenchmark-2026-10-19_09-14-28"
        self.dir.mkdir()
        self.file = self.dir / "menuperf.csv"
        self.header = ",".join(forensics.HEADER) + "\n"
        self.file.write_text(self.header + interval(movie=6) + interval(movie=3)
                             + interval(blits=9, slow=0) + interval(blits=9, slow=0)
                             + interval() * 5)

    def test_repeated_interval_durations_are_not_deduplicated(self):
        result = forensics.read_intervals(self.file)
        self.assertEqual(len(result), 9)
        self.assertEqual(result[-1]["interval"], 8)
        self.assertEqual(len({g["seconds"] for g in result}), 1)
        summary = forensics.summarise(result, label=self.dir.name)
        self.assertEqual(summary["movie_update_calls"], 9)
        self.assertEqual(summary["steady_post_movie_proxy_interval_count"], 5)
        self.assertEqual(summary["steady_post_movie_proxy_blt_calls_over_1000ms"], 5)
        self.assertEqual(summary["steady_post_movie_proxy_blt_calls_per_long_interval"], {"4": 5})
        self.assertAlmostEqual(summary["steady_post_movie_proxy_present_time_fraction"], 1255/1270, places=4)
        self.assertFalse(summary["phase_is_screen_verified"])

    def test_partial_data_is_refused(self):
        with self.file.open("a") as f:
            f.write("1.270,0,0,0,movie_update,0,0,0\n")
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            forensics.read_intervals(self.file)

    def test_corrupt_headers_fail(self):
        original = self.file.read_text()
        self.file.write_text(original.replace("seconds,optimization", "time,optimization", 1))
        with self.assertRaisesRegex(ValueError, "Unrecognized"):
            forensics.read_intervals(self.file)

    def test_invalid_mode_or_duplicate_measurement_fails(self):
        original = self.file.read_text()
        self.file.write_text(original.replace(",0,0,0,movie_update", ",1,0,0,movie_update", 1))
        with self.assertRaisesRegex(ValueError, "Inconsistent"):
            forensics.read_intervals(self.file)
        self.file.write_text(original.replace(",window_blt_slow_low_cpu,0", ",movie_update,0", 1))
        with self.assertRaisesRegex(ValueError, "duplicated"):
            forensics.read_intervals(self.file)

    def test_symlink_is_refused(self):
        outside = self.file.parent.parent / "other.csv"
        self.file.rename(outside)
        self.file.symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "unsafe"):
            forensics.read_intervals(self.file)

    def test_no_movie_phase_is_not_called_the_menu(self):
        self.file.write_text(self.header + interval()*6)
        with self.assertRaisesRegex(ValueError, "Movie phase"):
            forensics.summarise(forensics.read_intervals(self.file), label=self.dir.name)

    def test_no_game_or_network_side_effects(self):
        with mock.patch.object(forensics, "read_intervals", wraps=forensics.read_intervals), \
             mock.patch.object(forensics, "print", create=True) as emit:
            self.assertEqual(forensics.main([str(self.file)]), 0)
            self.assertTrue(emit.called)
        self.assertTrue(self.file.is_file())


if __name__ == "__main__":
    unittest.main()
