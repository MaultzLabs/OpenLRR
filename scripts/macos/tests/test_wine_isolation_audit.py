"""Offline Wine filesystem isolation audit tests; no game/Wine process launched."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest import mock

SOURCE = Path(__file__).resolve().parents[1] / "wine-isolation-audit.py"
SPEC = importlib.util.spec_from_file_location("openlrr_wine_isolation_audit", SOURCE)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


class PrefixIsolationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.app = self.root / "OpenLRR Menu Test.app"
        self.prefix = self.app / "Contents/SharedSupport/prefix"
        self.drive = self.prefix / "drive_c"
        self.game = self.drive / "Program Files/Rock Raiders OpenLRR"
        self.dos = self.prefix / "dosdevices"
        self.game.mkdir(parents=True)
        self.dos.mkdir(parents=True)
        (self.game / "LegoRR.exe").write_bytes(b"MZfixture")
        (self.game / "openlrr.dll").write_bytes(b"MZfixture")
        (self.dos / "c:").symlink_to("../drive_c")

    def test_c_only_with_no_external_symlinks_is_not_full_sandbox(self):
        with mock.patch.object(audit.os, "system",
                               side_effect=AssertionError("shell must never be used")):
            result = audit.inspect(self.app)
        self.assertTrue(result["wine_drive_link_audit_complete"])
        self.assertFalse(result["observed_host_mapping_risk"])
        self.assertFalse(result["host_filesystem_isolation_verified"])
        self.assertFalse(result["unreviewed_candidate_autorun_allowed"])
        self.assertFalse(result["game_executed"])

    def test_root_mapped_z_drive_is_host_exposure(self):
        (self.dos / "z:").symlink_to("/")
        report = audit.inspect(self.app)
        self.assertTrue(report["observed_host_mapping_risk"])
        self.assertIn("External Wine drive mapping detected: z:", report["issues"])
        with self.assertRaisesRegex(RuntimeError, "exposes host"):
            audit.main(["--test-app", str(self.app), "--require-safe-mappings"])

    def test_home_document_symlink_under_drive_c_is_host_exposure(self):
        home = self.root / "private-mac-documents"
        home.mkdir()
        (self.drive / "My Documents").symlink_to(home)
        report = audit.inspect(self.app)
        self.assertTrue(report["observed_host_mapping_risk"])
        self.assertIn("Host-exposing symlink within Wine C drive", report["issues"])

    def test_game_directory_replacement_is_refused(self):
        victim = self.root / "external-game"
        victim.mkdir()
        (self.game / "openlrr.dll").unlink()
        (self.game / "openlrr.dll").symlink_to(victim / "openlrr.dll")
        with self.assertRaisesRegex(ValueError, "symlinked"):
            audit.inspect(self.app)

    def test_sandbox_claim_never_granted_just_from_drive_mapping_audit(self):
        with self.assertRaisesRegex(RuntimeError, "requires stronger"):
            audit.main([
                "--test-app", str(self.app),
                "--require-automatic-execution-isolation",
            ])

    def test_missing_drive_mapping_fails_safe_mapping_check(self):
        (self.dos / "c:").unlink()
        report = audit.inspect(self.app)
        self.assertTrue(report["observed_host_mapping_risk"])
        self.assertIn("Wine c: mapping does not point exactly", report["issues"])

    def test_scan_cap_never_returns_clean_audit(self):
        with mock.patch.object(audit, "MAX_SCANNED_ENTRIES", 1):
            result = audit.inspect(self.app)
        self.assertTrue(result["observed_host_mapping_risk"])
        self.assertIn("Prefix filesystem scan cap exceeded", result["issues"])

    def test_nonexistent_test_app_fails_without_creating_files(self):
        other = self.root / "other"
        with self.assertRaisesRegex(ValueError, "absent"):
            audit.inspect(other)
        self.assertFalse(other.exists())


if __name__ == "__main__":
    unittest.main()
