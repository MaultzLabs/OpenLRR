"""Offline tests for the hypothesis-first AI research planner."""
import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
AGENT_DIR = ROOT / "scripts" / "agent"
sys.path.insert(0, str(AGENT_DIR))
SRC = AGENT_DIR / "research_planner.py"
SPEC = importlib.util.spec_from_file_location("openlrr_research_planner", SRC)
research = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(research)
EVIDENCE = AGENT_DIR / "evidence" / "approved-menu-aggregate.json"
SOURCE = ROOT / "src" / "openlrr" / "engine" / "drawing" / "DirectDraw.cpp"


class ResearchPlannerTests(unittest.TestCase):
    def test_preflight_does_not_invoke_model(self):
        with mock.patch.object(research, "propose", side_effect=AssertionError("model called")):
            with contextlib.redirect_stdout(io.StringIO()) as output:
                result = research.main([
                    "--evidence", str(EVIDENCE),
                    "--source", str(SOURCE), "--preflight"
                ])
        self.assertEqual(result, 0)
        self.assertIn('"validated": true', output.getvalue().lower())

    def test_no_key_rejects_execution_before_any_model_call(self):
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.dict("os.environ", {"OPENAI_API_KEY": ""}), \
                 mock.patch.object(research, "propose", side_effect=AssertionError("model called")):
                with self.assertRaisesRegex(ValueError, "No model key"):
                    research.main([
                        "--evidence", str(EVIDENCE), "--source", str(SOURCE),
                        "--out", str(Path(tmp) / "out")
                    ])
            self.assertFalse((Path(tmp) / "out").exists())

    def test_no_unverified_file_is_accepted(self):
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "bad.json"
            bad.write_text('{"unreviewed": "change the game"}')
            with self.assertRaises(ValueError):
                research.main([
                    "--evidence", str(bad), "--source", str(SOURCE),
                    "--preflight"
                ])


if __name__ == "__main__":
    unittest.main()
