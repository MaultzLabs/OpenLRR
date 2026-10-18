"""Offline fake-GitHub tests for immutable supervised process-exit receipts."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/macos/publish-benchmark.sh"
HEADER = "seconds,optimization,nowait,gdi,operation,calls,total_ms,max_ms\n"
EXPECTED = "wrapper_wait_exited=yes\ntest_game_handles=none\n"


class PrivateReceiptTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        fake = self.bin / "gh"
        fake.write_text(
            '#!/bin/bash\n'
            'echo "$*" >> "$FAKE_GH_CALLS"\n'
            'if [[ "$1 $2" == "repo view" ]]; then echo PRIVATE; fi\n'
            'exit 0\n')
        fake.chmod(0o700)
        self.calls = self.root / "gh-calls.txt"
        self.run = self.root / "autobenchmark-2026-10-18_17-24-03"
        self.run.mkdir()
        (self.run / "menuperf.csv").write_text(HEADER)
        self.env = {
            **os.environ,
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "HOME": str(self.root),
            "FAKE_GH_CALLS": str(self.calls),
            "OPENLRR_SUPERVISED": "1",
            "OPENLRR_REPORT_REPO": "MaultzLabs/OpenLRR-Test-Results",
        }

    def publish(self):
        return subprocess.run(
            ["bash", str(SCRIPT), str(self.run)],
            capture_output=True, text=True,
            env=self.env, timeout=12
        )

    def put_calls(self):
        if not self.calls.exists():
            return []
        return [line for line in self.calls.read_text().splitlines()
                if "--method PUT" in line]

    def test_missing_receipt_must_not_upload(self):
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing or invalid verified lifecycle receipt", result.stderr)
        self.assertEqual(self.put_calls(), [])

    def test_extra_newline_receipt_is_rejected_byte_for_byte(self):
        (self.run / "lifecycle.verified").write_text(EXPECTED + "\n")
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.put_calls(), [])

    def test_exact_receipt_published_to_private_repo(self):
        (self.run / "lifecycle.verified").write_text(EXPECTED)
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.put_calls()
        self.assertEqual(len(calls), 2, calls)
        self.assertTrue(any("lifecycle.verified" in line for line in calls))
        self.assertTrue(any("menuperf.csv" in line for line in calls))

    def test_unsupervised_data_does_not_forge_exit_receipt(self):
        self.env["OPENLRR_SUPERVISED"] = "0"
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any("lifecycle.verified" in line for line in self.put_calls()))


if __name__ == "__main__":
    unittest.main()
