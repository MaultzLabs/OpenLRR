"""Proof that cloud artifact provenance records real SHA identities without running code."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "candidate_attestation.py"
SPEC = importlib.util.spec_from_file_location("openlrr_artifact_attestation", SCRIPT)
attest = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(attest)


class CandidateAttestationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.proposal = root / "proposal.json"
        self.patch = root / "proposal.patch"
        self.source = root / "DirectDraw.cpp"
        self.dll = root / "openlrr.dll"
        self.proposal.write_text(json.dumps({
            "status": "patch_ready",
            "source_file": attest.SOURCE,
            "host_execution_authorized": False,
            "review_required": True,
        }))
        self.patch.write_text("--- a/" + attest.SOURCE + "\n"
                              "+++ b/" + attest.SOURCE + "\n"
                              "@@ -1 +1 @@\n-old\n+new\n")
        self.source.write_text("new")
        pe = bytearray(512)
        pe[:2] = b"MZ"
        pe[0x3c:0x40] = (128).to_bytes(4, "little")
        pe[128:132] = b"PE\0\0"
        pe[132:134] = (0x14c).to_bytes(2, "little")
        self.dll.write_bytes(pe)

    def attest(self):
        return attest.build(self.proposal, self.patch, self.dll, self.source,
                            "a" * 40, "b" * 40, "39169390987")

    def test_two_distinct_source_identities_and_patch_hash(self):
        item = self.attest()
        self.assertEqual(item["workflow_head_sha"], "b" * 40)
        self.assertEqual(item["compiled_source_revision"], "a" * 40)
        self.assertEqual(item["proposal_patch_sha256"],
                         hashlib.sha256(self.patch.read_bytes()).hexdigest())
        self.assertEqual(item["compiled_dll_sha256"],
                         hashlib.sha256(self.dll.read_bytes()).hexdigest())
        self.assertFalse(item["automatic_host_execution"])
        self.assertFalse(item["automatic_deployment"])

    def test_fails_on_unsafe_model_proposal(self):
        data = json.loads(self.proposal.read_text())
        data["host_execution_authorized"] = True
        self.proposal.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "unreviewed"):
            self.attest()

    def test_fails_on_non_x86_and_patch_scope_escape(self):
        b = bytearray(self.dll.read_bytes())
        b[132:134] = (0x8664).to_bytes(2, "little")
        self.dll.write_bytes(b)
        with self.assertRaisesRegex(ValueError, "not x86"):
            self.attest()
        b[132:134] = (0x14c).to_bytes(2, "little")
        self.dll.write_bytes(b)
        self.patch.write_text("--- a/a.cpp\n+++ b/a.cpp\n")
        with self.assertRaisesRegex(ValueError, "Patch escaped"):
            self.attest()


if __name__ == "__main__":
    unittest.main()
