"""Offline tests of passive phase data; no game or Wine executed."""
import csv
import importlib.util
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("openlrr_phase_probe", HERE / "analyze-benchmark.py")
analyzer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(analyzer)


def make_run(path, *, phases=True, partial=False):
    data = [
        ("frame_flip", 2, 2600, 1300),
        ("window_present_blt", 2, 2200, 1250),
        ("window_present_accepted", 2, 0, 0),
        ("window_present_busy", 0, 0, 0),
        ("window_present_error", 0, 0, 0),
    ]
    if phases:
        data.append(("game_mainloop", 2, 110, 90))
        if not partial:
            data.append(("d3drm_device_update", 2, 40, 29))
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(analyzer.HEADER)
        for op, calls, total, maximum in data:
            writer.writerow([2.7, 0, 0, 0, op, calls, total, maximum])


class PhaseProbeTests(unittest.TestCase):
    def test_passive_mainloop_and_update_timing(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "menuperf.csv"
            make_run(run)
            metrics = analyzer.analyze_csv(run)
            self.assertEqual(metrics["present_path"], "directdraw")
            self.assertTrue(metrics["game_phase_diagnostics_available"])
            self.assertEqual(metrics["game_mainloop_calls"], 2)
            self.assertEqual(metrics["game_mainloop_avg_ms"], 55)
            self.assertEqual(metrics["d3drm_update_avg_ms"], 20)
            self.assertEqual(metrics["d3drm_update_worst_ms"], 29)
            self.assertEqual(metrics["frame_flips"], 2)
            self.assertEqual(metrics["present_accepted_calls"], 2)

    def test_zero_state_mainloop_with_live_frames_is_valid(self):
        # A real menu may use Main_LoopUpdate2 (nested UI path) and never
        # execute currState.MainLoop. Preserve the observed zero, do not
        # synthesize a main-loop average, and keep D3DRM measurements.
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "menuperf.csv"
            make_run(run)
            csvtext = run.read_text()
            csvtext = csvtext.replace(
                ",game_mainloop,2,110,90", ",game_mainloop,0,0,0")
            run.write_text(csvtext)
            metrics = analyzer.analyze_csv(run)
            self.assertEqual(metrics["frame_flips"], 2)
            self.assertTrue(metrics["game_phase_diagnostics_available"])
            self.assertEqual(metrics["game_mainloop_calls"], 0)
            self.assertIsNone(metrics["game_mainloop_avg_ms"])
            self.assertEqual(
                metrics["game_mainloop_observation"], "state_mainloop_not_observed")
            self.assertEqual(metrics["d3drm_update_calls"], 2)

    def test_zero_update_and_zero_mainloop_do_not_invent_update_times(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "menuperf.csv"
            make_run(run)
            csvtext = run.read_text().replace(
                ",game_mainloop,2,110,90", ",game_mainloop,0,0,0").replace(
                ",d3drm_device_update,2,40,29", ",d3drm_device_update,0,0,0")
            run.write_text(csvtext)
            metrics = analyzer.analyze_csv(run)
            self.assertEqual(metrics["game_mainloop_calls"], 0)
            self.assertEqual(metrics["d3drm_update_calls"], 0)
            self.assertIsNone(metrics["d3drm_update_avg_ms"])
            self.assertEqual(metrics["present_path"], "directdraw")

    def test_missing_phase_means_unavailable_not_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "menuperf.csv"
            make_run(run, phases=False)
            metrics = analyzer.analyze_csv(run)
            self.assertFalse(metrics["game_phase_diagnostics_available"])
            self.assertIsNone(metrics["d3drm_update_worst_ms"])

    def test_partial_phase_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp) / "menuperf.csv"
            make_run(run, partial=True)
            with self.assertRaisesRegex(ValueError, "Incomplete main-loop"):
                analyzer.analyze_csv(run)

    def test_no_rendering_logic_swapped_in_passive_branch(self):
        direct = (HERE.parents[1] / "src/openlrr/engine/drawing/DirectDraw.cpp").read_text()
        assert "MenuPerf::DibWindowPresent()" not in direct
        assert "TryDibWindowPresent" not in direct
        assert "DirectDraw_fSurf()->Blt(&dest, DirectDraw_bSurf(), &src, flags, nullptr)" in direct

if __name__ == "__main__":
    unittest.main()
