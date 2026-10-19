"""Offline proof of fail-closed paid OpenLRR research dispatch."""
import base64
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import budgeted_research_dispatch as dispatch

NOW = datetime(2026, 10, 18, 22, tzinfo=timezone.utc)
LATER = datetime(2026, 10, 19, 22, tzinfo=timezone.utc)


def verified_ticket(identity="research_" + "a" * 24):
    return {
        "ticket_id": identity,
        "experiment_id": "example_source_ab_001",
        "evidence_fingerprint": "a" * 64,
        "verification_only": True,
        "verified_evidence_status": "no_improvement",
        "verified_research_next_step": "new_hypothesis",
        "verified_matched_pairs": 5,
        "automatic_model_execution_allowed": False,
        "automatic_game_execution_allowed": False,
    }


class BudgetedDispatchTests(unittest.TestCase):
    def test_offline_default_does_not_access_private_github_or_paid_model(self):
        with mock.patch.object(dispatch.inbox, "gh", side_effect=AssertionError("network")), \
             mock.patch.object(dispatch, "produce_research_plan",
                               side_effect=AssertionError("model called")):
            self.assertEqual(dispatch.main(["--ticket-id", verified_ticket()["ticket_id"]]), 0)

    def test_disabled_flag_blocks_reservation_without_network(self):
        with mock.patch.dict(dispatch.os.environ, {
            "OPENLRR_RESEARCH_EXECUTION_ENABLED": "false",
            "GH_TOKEN": "private",
            "OPENAI_API_KEY": "key",
        }), mock.patch.object(dispatch.inbox, "private_repo_only",
                             side_effect=AssertionError("must not call GH")):
            with self.assertRaisesRegex(RuntimeError, "not enabled"):
                dispatch.reserve_one_model_call(verified_ticket(), now=NOW)

    def test_no_model_key_disallows_reservation(self):
        with mock.patch.dict(dispatch.os.environ, {
            "OPENLRR_RESEARCH_EXECUTION_ENABLED": "true",
            "GH_TOKEN": "", "OPENAI_API_KEY": "",
        }), mock.patch.object(dispatch.inbox, "private_repo_only",
                             side_effect=AssertionError("must not call GH")):
            with self.assertRaisesRegex(RuntimeError, "Missing"):
                dispatch.reserve_one_model_call(verified_ticket(), now=NOW)

    def test_atomic_day_and_ticket_claim_before_any_model(self):
        records = {}
        def response(command, **kw):
            assert command[:4] == ["gh", "api", "--method", "PUT"]
            path = command[4].split("/contents/", 1)[1]
            body = json.loads(Path(command[6]).read_text())
            raw = base64.b64decode(body["content"])
            if path in records:
                return mock.Mock(returncode=1, stdout="", stderr="422 already exists")
            records[path] = raw
            return mock.Mock(returncode=0, stdout=json.dumps({
                "content": {"path": path, "sha": dispatch.git_blob(raw)},
            }), stderr="")
        with mock.patch.dict(dispatch.os.environ, {
            "OPENLRR_RESEARCH_EXECUTION_ENABLED": "true",
            "GH_TOKEN": "private", "OPENAI_API_KEY": "key",
        }), mock.patch.object(dispatch.inbox, "private_repo_only"), \
             mock.patch.object(dispatch.subprocess, "run", side_effect=response), \
             mock.patch.object(dispatch, "produce_research_plan",
                               side_effect=AssertionError("do not invoke model inside reservation")):
            issued = dispatch.reserve_one_model_call(verified_ticket(), now=NOW)
            self.assertEqual(issued["reservation_day"], "20261018")
            self.assertEqual(len(records), 2)
            with self.assertRaisesRegex(RuntimeError, "slot already consumed"):
                dispatch.reserve_one_model_call(
                    verified_ticket("research_" + "b" * 24), now=NOW)
            self.assertEqual(len(records), 2)
            with self.assertRaisesRegex(RuntimeError, "slot already consumed"):
                dispatch.reserve_one_model_call(verified_ticket(), now=LATER)
            # The next day is consumed despite ticket already existing:
            # fail-closed means no second model expense.
            self.assertEqual(len(records), 3)

    def test_rejects_unverified_or_overprivileged_ticket(self):
        item = verified_ticket()
        item["verification_only"] = False
        with self.assertRaisesRegex(ValueError, "unverified"):
            dispatch.reserve_one_model_call(item, now=NOW)
        item = verified_ticket()
        item["automatic_game_execution_allowed"] = True
        with self.assertRaisesRegex(ValueError, "overprivileged"):
            dispatch.reserve_one_model_call(item, now=NOW)

    def test_forged_private_write_ack_never_authorizes_model(self):
        item = verified_ticket()
        def malformed(*args, **kwargs):
            return mock.Mock(returncode=0, stdout=json.dumps({
                "content": {"path": "wrong", "sha": "a" * 40}
            }), stderr="")
        with mock.patch.dict(dispatch.os.environ, {
            "OPENLRR_RESEARCH_EXECUTION_ENABLED": "true",
            "GH_TOKEN": "private", "OPENAI_API_KEY": "key",
        }), mock.patch.object(dispatch.inbox, "private_repo_only"), \
             mock.patch.object(dispatch.subprocess, "run", side_effect=malformed), \
             mock.patch.object(dispatch, "produce_research_plan",
                               side_effect=AssertionError("model called")):
            with self.assertRaisesRegex(RuntimeError, "acknowledgement invalid"):
                dispatch.reserve_one_model_call(item, now=NOW)

    def test_cli_model_path_revalidates_and_reserves_before_one_call(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "one-research-plan.json"
            trace = []
            verified = verified_ticket()
            fake_plan = {
                "schema_version": 1, "source_ticket": verified["ticket_id"],
                "model_calls_requested": 1, "game_executed": False,
                "deployment_authorized": False,
            }
            def fake_verify(*args):
                trace.append("verified")
                return verified
            def fake_reserve(*args):
                trace.append("reserved")
                return {"reservation_day": "20261018"}
            def fake_model(*args):
                trace.append("model")
                return fake_plan
            with mock.patch.dict(dispatch.os.environ, {
                "OPENLRR_RESEARCH_EXECUTION_ENABLED": "true",
                "GH_TOKEN": "private", "OPENAI_API_KEY": "key",
            }), mock.patch.object(dispatch.inbox, "get_verified_ticket",
                                 side_effect=fake_verify), \
                 mock.patch.object(dispatch, "reserve_one_model_call",
                                   side_effect=fake_reserve), \
                 mock.patch.object(dispatch, "produce_research_plan",
                                   side_effect=fake_model):
                self.assertEqual(dispatch.main([
                    "--ticket-id", verified["ticket_id"],
                    "--run-model", "--out", str(output),
                ]), 0)
                self.assertEqual(trace, ["verified", "reserved", "model"])
                self.assertTrue(output.exists())
                with self.assertRaisesRegex(ValueError, "Unique"):
                    dispatch.main([
                        "--ticket-id", verified["ticket_id"],
                        "--run-model", "--out", str(output),
                    ])


if __name__ == "__main__":
    unittest.main()
