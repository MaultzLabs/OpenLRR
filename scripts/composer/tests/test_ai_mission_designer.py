"""Mocked tests for bounded AI mission design -> validated native MAP drafts."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DIR))
FILE = DIR / "ai_mission_designer.py"
SPEC = importlib.util.spec_from_file_location("openlrr_ai_mission_designer", FILE)
designer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(designer)


def fixture():
    return {
        "schema_version": 1,
        "name": "CrystalFrontier",
        "title": "The Hidden Crystal Frontier",
        "synopsis": "Explore a new underground cavern and recover the crystals needed to rescue the mission.",
        "difficulty": "medium",
        "width": 24,
        "height": 20,
        "seed": 1989,
        "crystal_goal": 12,
    }


class AIGameComposerTests(unittest.TestCase):
    def test_model_design_becomes_verified_binary_maps_and_brief(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "CrystalFrontier"
            with mock.patch.object(designer.os, "system",
                                   side_effect=AssertionError("must never execute code")):
                result = designer.create_draft(root, fixture())
            self.assertTrue(result["native_map_binary_roundtrip_validated"])
            self.assertFalse(result["complete_playable_mission"])
            self.assertFalse(result["automatic_install_allowed"])
            self.assertFalse(result["game_executed"])
            self.assertTrue((root / "mission-brief.json").is_file())
            brief = json.loads((root / "mission-brief.json").read_text())
            self.assertEqual(brief["crystal_goal"], 12)
            self.assertFalse(brief["native_install_authorized"])
            sums = json.loads((root / "SHA256SUMS.json").read_text())
            self.assertIn("mission-brief.json", sums)
            self.assertEqual(result["human_level_assembly_required"], True)

    def test_model_only_controls_bounded_design_not_paths_or_commands(self):
        original = fixture()
        cases = (
            ("name", "../../Game"),
            ("name", "C:\\game.exe"),
            ("difficulty", "dangerous"),
            ("width", 9999),
            ("height", -1),
            ("crystal_goal", 999),
            ("seed", -1),
            ("title", "bad\ncommand"),
            ("synopsis", "run \x1b[33m shell"),
            ("schema_version", 2),
        )
        for key, value in cases:
            changed = dict(original)
            changed[key] = value
            with self.subTest(key=key, bad=value), self.assertRaises(ValueError):
                designer.validate_design(changed)

    def test_unrecognized_authority_fields_rejected(self):
        altered = fixture()
        altered["automatic_install_allowed"] = True
        with self.assertRaisesRegex(ValueError, "unsupported schema"):
            designer.validate_design(altered)

    def test_dry_run_without_model_key_or_network(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "CrystalFrontier"
            with mock.patch.object(designer, "propose",
                                   side_effect=AssertionError("model called")):
                self.assertEqual(designer.main([
                    "--theme", "A small underground crystal rescue mission",
                    "--out", str(target),
                ]), 0)
            self.assertFalse(target.exists())

    def test_explicit_compose_rejects_missing_key_before_model(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "CrystalFrontier"
            with mock.patch.dict(designer.os.environ, {"OPENAI_API_KEY": ""}), \
                 mock.patch.object(designer, "propose",
                                   side_effect=AssertionError("model called")):
                with self.assertRaisesRegex(RuntimeError, "requires explicit"):
                    designer.main([
                        "--theme", "A small underground crystal rescue mission",
                        "--out", str(target), "--compose",
                    ])
            self.assertFalse(target.exists())

    def test_explicit_compose_calls_model_once_and_never_launches_game(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "CrystalFrontier"
            with mock.patch.dict(designer.os.environ, {"OPENAI_API_KEY": "test"}), \
                 mock.patch.object(designer, "propose", return_value=fixture()) as model, \
                 mock.patch.object(designer.os, "system",
                                   side_effect=AssertionError("shell called")):
                self.assertEqual(designer.main([
                    "--theme", "A small underground crystal rescue mission",
                    "--out", str(target), "--compose",
                ]), 0)
            self.assertEqual(model.call_count, 1)
            self.assertTrue((target / "dugg.map").is_file())
            self.assertTrue((target / "mission-brief.json").is_file())

    def test_preflight_rejects_already_existing_output_before_api(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "CrystalFrontier"
            target.mkdir()
            with mock.patch.object(designer, "propose",
                                   side_effect=AssertionError("API must not run")):
                with self.assertRaisesRegex(ValueError, "must never be replaced"):
                    designer.main([
                        "--theme", "A small underground crystal rescue mission",
                        "--out", str(target), "--compose",
                    ])


if __name__ == "__main__":
    unittest.main()
