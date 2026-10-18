"""Offline tests for automatic candidate discovery; never launch binaries."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SRC = Path(__file__).resolve().parents[1] / "candidate-inbox-scan.py"
SPEC = importlib.util.spec_from_file_location("openlrr_quarantine_scan", SRC)
scan = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(scan)


class ScanTests(unittest.TestCase):
    def test_successful_runs_are_selected_once(self):
        items = [
            {"databaseId": 39169390987, "status": "completed", "conclusion": "success"},
            {"databaseId": 39169390988, "status": "completed", "conclusion": "failure"},
            {"databaseId": 39169390989, "status": "in_progress", "conclusion": None},
        ]
        with mock.patch.object(scan.inbox, "gh", return_value=json.dumps(items)):
            self.assertEqual(list(scan.list_recent()), ["39169390987"])

    def test_dry_run_does_not_download(self):
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(scan.inbox, "INBOX", Path(tmp) / "inbox"), \
                 mock.patch.object(scan.inbox, "CONFIG", Path(tmp)), \
                 mock.patch.object(scan, "list_recent", return_value=iter(["39169390987"])), \
                 mock.patch.object(scan.inbox, "stage",
                                   side_effect=AssertionError("executed stage")):
                result = scan.scan(dry_run=True)
                self.assertEqual(result["inspected"], ["39169390987"])
                self.assertEqual(result["quarantined"], [])
                self.assertFalse(result["executed_anything"])

    def test_staged_candidate_and_research_abstention(self):
        with tempfile.TemporaryDirectory() as tmp:
            def fake_stage(run_id):
                if run_id == "39169390987":
                    raise ValueError("No compiled candidate artifact; AI may have abstained")
                return {"candidate_sha256": "a" * 64, "automatic_execution": False}
            with mock.patch.object(scan.inbox, "INBOX", Path(tmp) / "inbox"), \
                 mock.patch.object(scan.inbox, "CONFIG", Path(tmp)), \
                 mock.patch.object(scan, "list_recent",
                                   return_value=iter(["39169390987", "39169390990"])), \
                 mock.patch.object(scan.inbox, "stage", side_effect=fake_stage):
                result = scan.scan(dry_run=False)
                self.assertEqual(len(result["quarantined"]), 1)
                self.assertEqual(result["quarantined"][0]["run_id"], "39169390990")
                self.assertFalse(result["modified_game"])

    def test_stop_prevents_network_and_quarantine(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp)
            (config / "STOP").touch()
            with mock.patch.object(scan.inbox, "CONFIG", config), \
                 mock.patch.object(scan, "list_recent",
                                   side_effect=AssertionError("network requested")):
                with self.assertRaisesRegex(RuntimeError, "STOP/PAUSE"):
                    scan.scan(dry_run=False)


if __name__ == "__main__":
    unittest.main()
