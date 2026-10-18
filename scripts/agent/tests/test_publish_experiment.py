"""Private experiment publication tests: fake gh; no credentials or network."""
import base64
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

AGENT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(AGENT))
import publish_experiment as publisher


class PrivatePublicationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.runs = self.root / "runs"
        self.runs.mkdir()
        self.pairs = []
        for i in range(2):
            row = {}
            for candidate in (False, True):
                n = 2 * i + 1 + int(candidate)
                name = "autobenchmark-2026-10-18_17-00-%02d" % n
                run = self.runs / name
                run.mkdir()
                (run / "lifecycle.verified").write_text(
                    "wrapper_wait_exited=yes\ntest_game_handles=none\n")
                (run / "menuperf.csv").write_text(
                    "seconds,optimization,nowait,gdi,operation,calls,total_ms,max_ms\n")
                (run / "summary.json").write_text(json.dumps({
                    "schema_version": 1, "run": name,
                    "dll_sha256": ("b" if candidate else "a") * 64,
                    "close_requested": True,
                    "metrics": {
                        "mode": {"optimization": 0, "nowait": 0, "gdi": 0},
                        "present_avg_ms": 170.0 if candidate else 200.0,
                        "frame_flips_per_s": 4.0, "logged_duration_s": 63.0,
                        "present_calls": 220, "present_accepted_percent": 100,
                        "present_busy_calls": 0, "present_error_calls": 0,
                        "present_intervals_over_1000ms": 5,
                    },
                }))
                row["candidate" if candidate else "baseline"] = name
            self.pairs.append(row)
        self.manifest = self.root / "exp_source_001.json"
        self.manifest.write_text(json.dumps({
            "schema_version": 1, "experiment_id": "exp_source_001",
            "hypothesis": "A real x86 source change reduces DirectDraw stalls.",
            "controlled_scene": "menu_boot_autotest_v1", "pairs": self.pairs,
        }))

    def test_dry_run_read_only_no_github(self):
        with mock.patch.object(publisher, "gh",
                               side_effect=AssertionError("No network allowed")):
            result = publisher.publish(self.manifest, self.runs)
        self.assertEqual(result["gate_status"], "needs_more_data")
        self.assertFalse(result["published"])
        self.assertFalse(result["game_executed"])

    def fake_private_github(self, published):
        def gh(*args, input_file=None):
            if args[:2] == ("repo", "view"):
                return "PRIVATE"
            if "--method" in args and "GET" in args:
                path = next(a for a in args if a.startswith("repos/"))
                rel = path.split("/contents/", 1)[1]
                if rel.startswith("runs/"):
                    return publisher.local_git_sha(self.root / rel)
                if rel.startswith("experiments/") and published["content"] is not None:
                    return publisher.local_git_sha(self.manifest)
                raise RuntimeError("404")
            if "--method" in args and "PUT" in args:
                assert published["content"] is None
                payload = json.loads(input_file.read_text())
                assert base64.b64decode(payload["content"]) == self.manifest.read_bytes()
                published["content"] = payload
                return "{}"
            raise AssertionError("Unknown Github call " + repr(args))
        return gh

    def test_publish_once_and_refuse_mutating_reposts(self):
        published = {"content": None}
        with mock.patch.object(publisher, "gh",
                               side_effect=self.fake_private_github(published)):
            result = publisher.publish(self.manifest, self.runs, commit=True)
            self.assertTrue(result["published"])
            self.assertFalse(result["already_published"])
            self.assertIsNotNone(published["content"])
            again = publisher.publish(self.manifest, self.runs, commit=True)
            self.assertTrue(again["already_published"])

    def test_missing_remote_receipt_prevents_manifest_publication(self):
        requested = []
        def gh(*args, input_file=None):
            requested.append(args)
            if args[:2] == ("repo", "view"):
                return "PRIVATE"
            if "--method" in args and "GET" in args:
                rel = next(a for a in args if a.startswith("repos/"))
                if rel.endswith("lifecycle.verified"):
                    raise RuntimeError("404")
                return "a" * 40
            raise AssertionError("A manifest must not be uploaded")
        with mock.patch.object(publisher, "gh", side_effect=gh):
            with self.assertRaisesRegex(RuntimeError, "missing or differs"):
                publisher.publish(self.manifest, self.runs, commit=True)
        self.assertFalse(any("PUT" in args for args in requested))

    def test_bad_local_exit_receipt_prevents_network(self):
        name = self.pairs[0]["candidate"]
        (self.runs / name / "lifecycle.verified").write_text(
            "wrapper_wait_exited=no\ntest_game_handles=unknown\n")
        with mock.patch.object(publisher, "gh",
                               side_effect=AssertionError("Must stop locally")):
            with self.assertRaisesRegex(ValueError, "Unverified"):
                publisher.publish(self.manifest, self.runs, commit=True)

    def test_public_repo_prohibited(self):
        with mock.patch.object(publisher, "gh", return_value="PUBLIC"):
            with self.assertRaisesRegex(RuntimeError, "non-private"):
                publisher.publish(self.manifest, self.runs, commit=True)


if __name__ == "__main__":
    unittest.main()
