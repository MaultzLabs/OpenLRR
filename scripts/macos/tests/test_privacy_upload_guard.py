#!/usr/bin/env python3
"""Uploader whitelist regressions run without network or user files."""
import csv
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "privacy-validate-benchmark.py"
SPEC = importlib.util.spec_from_file_location("privacy_guard", SOURCE)
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class PrivacyUploadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.run = Path(self.tmp.name) / "autobenchmark-2026-10-19_22-51-41"
        self.run.mkdir()
        self.rows = [
            ["1.250", "0", "0", "0", "frame_flip", "4", "0.0000", "0.0000"],
            ["1.250", "0", "0", "0", "window_present_blt", "4", "100.0000", "25.0000"],
        ]
        self.summary = {
            "schema_version": 1, "run": self.run.name,
            "close_requested": True,
            "metrics": {"mode": {"optimization": 0, "nowait": 0, "gdi": 0},
                        "frame_flips": 4, "present_calls": 4,
                        "present_path": "directdraw", "logged_duration_s": 1.25,
                        "present_avg_ms": 25},
        }
        self.write()

    def write(self):
        with (self.run / "menuperf.csv").open("w", newline="") as out:
            writer = csv.writer(out)
            writer.writerow(guard.HEADER)
            writer.writerows(self.rows)
        (self.run / "summary.json").write_text(json.dumps(self.summary))
        (self.run / "lifecycle.verified").write_text(guard.RECEIPT)

    def test_valid_bounded_payload_and_verified_receipt(self):
        guard.validate(self.run, True)

    def test_unexpected_csv_operation_rejected(self):
        self.rows[0][4] = "/Users/owner/private.txt"
        self.write()
        with self.assertRaisesRegex(ValueError, "operation"):
            guard.validate(self.run, True)

    def test_formula_and_extra_csv_columns_rejected(self):
        self.rows[0][5] = "=HYPERLINK"
        self.write()
        with self.assertRaises(ValueError):
            guard.validate(self.run, True)
        self.rows[0][5] = "4"
        self.rows[0].append("password")
        self.write()
        with self.assertRaises(ValueError):
            guard.validate(self.run, True)

    def test_unapproved_json_metadata_rejected(self):
        self.summary["mac_home_directory"] = "/Users/owner/private"
        self.write()
        with self.assertRaisesRegex(ValueError, "fields"):
            guard.validate(self.run, True)

    def test_nested_text_and_nan_rejected(self):
        self.summary["metrics"]["present_avg_ms"] = "admin@example.com"
        self.write()
        with self.assertRaisesRegex(ValueError, "numeric"):
            guard.validate(self.run, True)
        self.summary["metrics"]["present_avg_ms"] = float("nan")
        self.write()
        with self.assertRaisesRegex(ValueError, "numeric"):
            guard.validate(self.run, True)

    def test_unapproved_boolean_or_freeform_string_rejected(self):
        self.summary["metrics"]["frame_flips"] = True
        self.write()
        with self.assertRaisesRegex(ValueError, "numeric"):
            guard.validate(self.run, True)
        self.summary["metrics"]["present_path"] = "http://malicious.example"
        self.write()
        with self.assertRaisesRegex(ValueError, "text"):
            guard.validate(self.run, True)

    def test_symlinked_files_and_run_names_rejected(self):
        (self.run / "summary.json").unlink()
        (self.run / "summary.json").symlink_to(self.run / "menuperf.csv")
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            guard.validate(self.run, True)
        (self.run / "summary.json").unlink()
        self.write()
        bad = self.run.parent / "autobenchmark-not-a-timestamp"
        bad.symlink_to(self.run, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "Invalid"):
            guard.validate(bad, True)

    def test_invalid_receipt_and_missing_summary_fail_closed(self):
        (self.run / "lifecycle.verified").write_text(guard.RECEIPT + "\n")
        with self.assertRaisesRegex(ValueError, "exit evidence"):
            guard.validate(self.run, True)
        (self.run / "summary.json").unlink()
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            guard.validate(self.run, True)

    def test_summary_comparison_contains_only_derived_numeric_fields(self):
        self.summary["comparison"] = {
            "baseline_mode": dict(self.summary["metrics"]["mode"]),
            "graphics_modes_match": False,
            "baseline_metrics": dict(self.summary["metrics"]),
            "percentage_change": {
                "frame_flips_per_s": -33.8, "present_avg_ms": 62.2,
                "present_worst_ms": 0.2,
                "present_intervals_over_1000ms": 40.0,
            },
        }
        self.summary["baseline_run"] = "autobenchmark-2026-10-19_21-50-40"
        self.write()
        guard.validate(self.run, True)
        self.summary["comparison"]["source_mac_path"] = "/Users/owner"
        self.write()
        with self.assertRaisesRegex(ValueError, "comparison"):
            guard.validate(self.run, True)

if __name__ == "__main__":
    unittest.main()
