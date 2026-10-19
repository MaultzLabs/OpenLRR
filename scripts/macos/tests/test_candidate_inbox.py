"""Offline tests for the AI candidate quarantine; no GitHub or Mac processes."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "candidate-inbox.py"
SPEC = importlib.util.spec_from_file_location("openlrr_candidate_inbox", SCRIPT)
inbox = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inbox)


def fixture(root: Path):
    root.mkdir(parents=True, exist_ok=True)
    header = bytearray(512)
    header[:2] = b"MZ"
    header[0x3c:0x40] = (128).to_bytes(4, "little")
    header[128:132] = b"PE\0\0"
    header[132:134] = (0x14c).to_bytes(2, "little")
    binary = root / "openlrr.dll"
    binary.write_bytes(bytes(header))
    digest = hashlib.sha256(binary.read_bytes()).hexdigest()
    (root / "SHA256.txt").write_text(digest + "\n")
    (root / "proposal.patch").write_text(
        "--- a/src/openlrr/engine/drawing/DirectDraw.cpp\n"
        "+++ b/src/openlrr/engine/drawing/DirectDraw.cpp\n"
        "@@ -1 +1 @@\n-old\n+new\n")
    (root / "proposal.json").write_text(json.dumps({
        "source_file": "src/openlrr/engine/drawing/DirectDraw.cpp",
        "status": "patch_ready", "review_required": True,
        "host_execution_authorized": False,
    }))
    (root / "REVIEW-REQUIRED.txt").write_text("not approved for execution")


class InboxTests(unittest.TestCase):
    def test_valid_patch_and_x86_dll_can_be_quarantined(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "files"
            fixture(folder)
            result = inbox.validate_bundle(folder)
            self.assertTrue(result["review_required"])
            self.assertFalse(result["automatic_execution"])

    def test_mismatched_sha_and_extra_file_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root)
            (root / "SHA256.txt").write_text("a" * 64)
            with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
                inbox.validate_bundle(root)
            (root / "SHA256.txt").write_text(
                hashlib.sha256((root / "openlrr.dll").read_bytes()).hexdigest())
            (root / "extra.sh").write_text("never run")
            with self.assertRaisesRegex(ValueError, "unexpected files"):
                inbox.validate_bundle(root)

    def test_invalid_source_scope_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture(root)
            (root / "proposal.patch").write_text(
                "--- a/src/openlrr/engine/drawing/DirectDraw.cpp\n"
                "+++ b/src/openlrr/engine/drawing/DirectDraw.cpp\n"
                "--- a/.github/workflows/unsafe.yml\n"
                "+++ b/.github/workflows/unsafe.yml\n")
            with self.assertRaisesRegex(ValueError, "Multiple patch files"):
                inbox.validate_bundle(root)

    def test_rejects_failed_or_untrusted_workflow(self):
        expected = {"status": "completed", "conclusion": "success",
                    "headBranch": "agent-loop-v1",
                    "headSha": "a" * 40,
                    "workflowName": "OpenLRR Evidence-Grounded AI Smoke Test"}
        with mock.patch.object(inbox, "gh", return_value=json.dumps(expected)):
            self.assertEqual(inbox.run_metadata("39169390987"), expected)
        expected["conclusion"] = "failure"
        with mock.patch.object(inbox, "gh", return_value=json.dumps(expected)):
            with self.assertRaises(ValueError):
                inbox.run_metadata("39169390987")

    def test_staging_only_writes_to_quarantine(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config = root / "config"
            config.mkdir()
            destination = root / "inbox"
            expected = {"status": "completed", "conclusion": "success",
                        "headBranch": "agent-loop-v1",
                        "headSha": "a" * 40,
                        "workflowName": "OpenLRR Evidence-Grounded AI Smoke Test"}

            def fake_gh(*args):
                if args[0:2] == ("run", "view"):
                    return json.dumps(expected)
                if args[0:2] == ("run", "download"):
                    fixture(Path(args[-1]))
                    return ""
                raise AssertionError("Unexpected external operation")

            with mock.patch.object(inbox, "CONFIG", config), \
                 mock.patch.object(inbox, "INBOX", destination), \
                 mock.patch.object(inbox, "gh", side_effect=fake_gh):
                result = inbox.stage("39169390987")
                self.assertFalse(result["automatic_execution"])
                self.assertTrue((destination / "run-39169390987" / "provenance.json").exists())
                with self.assertRaisesRegex(ValueError, "Already quarantined"):
                    inbox.stage("39169390987")


if __name__ == "__main__":
    unittest.main()
