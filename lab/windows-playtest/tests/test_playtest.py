import importlib.util
import json
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('playtest', BASE / 'playtest.py')
playtest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(playtest)

class ScenarioTests(unittest.TestCase):
    def test_fixture(self):
        scenario = json.loads((BASE / 'tests/fixture-scenario.json').read_text())
        self.assertEqual(len(playtest.validate_scenario(scenario)), 6)

    def test_game_smoke(self):
        scenario = json.loads((BASE / 'game-smoke.json').read_text())
        self.assertEqual(len(playtest.validate_scenario(scenario)), 5)

    def test_source_grounded_menu_scenario(self):
        scenario = json.loads((BASE / 'tests/menu-scenario.json').read_text())
        actions = [step['action'] for step in playtest.validate_scenario(scenario)]
        self.assertEqual(actions.count('ensure_no_nerps'), 2)
        self.assertNotIn('shell', actions)

    def test_first_mission_uses_existing_cheat(self):
        scenario = json.loads((BASE / 'first-mission-sandbox.json').read_text())
        steps = playtest.validate_scenario(scenario)
        self.assertEqual(steps[0]['action'], 'capture')
        self.assertEqual([x['action'] for x in steps].count('ensure_no_nerps'), 1)
        self.assertNotIn('shell', [x['action'] for x in steps])

    def test_injection_not_supported(self):
        with self.assertRaisesRegex(ValueError, 'unsupported action'):
            playtest.validate_scenario({'steps': [{'action': 'shell', 'command': 'del /s'}]})

    def test_negative_click(self):
        with self.assertRaisesRegex(ValueError, 'click requires'):
            playtest.validate_scenario({'steps': [{'action': 'click', 'x': -1, 'y': 2}]})

    def test_click_bool_rejected(self):
        with self.assertRaises(ValueError):
            playtest.validate_scenario({'steps': [{'action': 'click', 'x': True, 'y': 2}]})

    def test_wait_duration_bound(self):
        with self.assertRaises(ValueError):
            playtest.validate_scenario({'steps': [{'action': 'wait', 'seconds': 60}]})

    def test_empty_rejected(self):
        with self.assertRaises(ValueError):
            playtest.validate_scenario({'steps': []})

    def test_key_whitelist(self):
        with self.assertRaises(ValueError):
            playtest.validate_scenario({'steps': [{'action': 'key', 'key': 'ctrl-alt-del'}]})

    def test_title_regex(self):
        with self.assertRaises(Exception):
            playtest.validate_scenario({'steps': [{'action': 'assert_title', 'pattern': '['}]})

    def test_difference_threshold(self):
        with self.assertRaises(ValueError):
            playtest.validate_scenario({'steps': [{'action': 'assert_changed', 'min_difference': 300}]})

if __name__ == '__main__':
    unittest.main()
