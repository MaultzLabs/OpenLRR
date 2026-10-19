"""Offline-only security tests for pinned baseline preparation."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SRC = Path(__file__).resolve().parents[1] / "prepare-approved-baseline.py"
SPEC = importlib.util.spec_from_file_location("openlrr_baseline_prepare", SRC)
app = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(app)


def fixture(folder: Path):
    folder.mkdir(parents=True, exist_ok=True)
    header = bytearray(512)
    header[:2] = b"MZ"
    header[0x3c:0x40] = (128).to_bytes(4, "little")
    header[128:132] = b"PE\0\0"
    header[132:134] = (0x14c).to_bytes(2, "little")
    dll = folder / "openlrr.dll"
    dll.write_bytes(header)
    sha = hashlib.sha256(header).hexdigest()
    (folder / "SHA256.txt").write_text(sha.upper() + "\n")
    return sha


class ApproveBaselineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.state = self.root / "approved-baselines"
        self.config = self.root / "config"
        self.config.mkdir()
        patcher = mock.patch.multiple(app, ROOT=self.state,
                                     LOCK=self.state / ".baseline-install.lock",
                                     CONFIG=self.config)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.commit = "a" * 40
        self.run = "39170729410"

    def response(self):
        return json.dumps({
            "status": "completed", "conclusion": "success",
            "headSha": self.commit, "headBranch": "agent-loop-v1",
            "workflowName": "OpenLRR Menu Diagnostics Win32",
        })

    def test_verified_dry_run_never_downloads_or_runs(self):
        def gh(*args):
            self.assertEqual(args[:2], ("run", "view"))
            return self.response()
        with mock.patch.object(app, "gh", side_effect=gh):
            res = app.prepare(self.run, self.commit, "b" * 64, dry_run=True)
        self.assertFalse(res["downloaded"])
        self.assertFalse(self.state.exists())

    def test_rejects_workflows_from_other_branch(self):
        wrong = json.loads(self.response())
        wrong["headBranch"] = "evil-branch"
        with mock.patch.object(app, "gh", return_value=json.dumps(wrong)):
            with self.assertRaisesRegex(ValueError, "Untrusted"):
                app.prepare(self.run, self.commit, "a" * 64)

    def test_successful_artifact_staged_once_and_no_game_execution(self):
        sha = fixture(self.root / "external")
        def gh(*args):
            if args[:2] == ("run", "view"):
                return self.response()
            self.assertEqual(args[:2], ("run", "download"))
            fixture(Path(args[-1]))
            return ""
        with mock.patch.object(app, "gh", side_effect=gh):
            result = app.prepare(self.run, self.commit, sha, dry_run=False)
        self.assertEqual(result["approved_sha256"], sha)
        self.assertFalse(result["game_launched"])
        self.assertFalse(app.LOCK.exists())
        self.assertEqual(hashlib.sha256((self.state / "openlrr.dll").read_bytes()).hexdigest(), sha)
        metadata = json.loads((self.state / "provenance.json").read_text())
        self.assertFalse(metadata["approved_for_automatic_execution"])
        with mock.patch.object(app, "gh", side_effect=AssertionError("should not download again")):
            with self.assertRaises(RuntimeError):
                app.prepare(self.run, self.commit, sha, dry_run=False)

    def test_invalid_artifact_and_stop_refuse_staging(self):
        sha = fixture(self.root / "external")
        def gh(*args):
            if args[:2] == ("run", "view"):
                return self.response()
            dest = Path(args[-1])
            fixture(dest)
            (dest / "unexpected.sh").write_text("should not accept")
            return ""
        with mock.patch.object(app, "gh", side_effect=gh):
            with self.assertRaisesRegex(ValueError, "unsafe baseline"):
                app.prepare(self.run, self.commit, sha, dry_run=False)
        self.assertTrue(app.LOCK.exists())
        self.assertFalse((self.state / "openlrr.dll").exists())
        app.LOCK.rmdir()
        (self.config / "STOP").touch()
        with mock.patch.object(app, "gh", side_effect=AssertionError("should stop")):
            with self.assertRaisesRegex(RuntimeError, "STOP/PAUSE"):
                app.prepare(self.run, self.commit, sha)

    def test_hash_tampering_or_non_x86_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            sha = fixture(folder)
            (folder / "SHA256.txt").write_text("f" * 64)
            with self.assertRaisesRegex(ValueError, "differs"):
                app.verify_bundle(folder, sha)
            (folder / "SHA256.txt").write_text(sha)
            blob = bytearray((folder / "openlrr.dll").read_bytes())
            blob[132:134] = (0x8664).to_bytes(2, "little")
            (folder / "openlrr.dll").write_bytes(blob)
            updated = hashlib.sha256(blob).hexdigest()
            (folder / "SHA256.txt").write_text(updated)
            with self.assertRaisesRegex(ValueError, "not Windows x86"):
                app.verify_bundle(folder, updated)


if __name__ == "__main__":
    unittest.main()
