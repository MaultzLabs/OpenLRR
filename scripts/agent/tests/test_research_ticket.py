"""Research handoff tickets are inert and must match recorded controller output."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SRC = Path(__file__).resolve().parents[1] / "research_ticket.py"
spec = importlib.util.spec_from_file_location("openlrr_research_ticket", SRC)
ticket = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ticket)


def sources():
    fingerprint = "a" * 64
    decision = {
        "schema_version": 1,
        "disposition": "ready_for_new_research",
        "manifest_verified": True,
        "ledger_committed": True,
        "may_install_or_run_candidate": False,
        "may_touch_working_game": False,
        "may_deploy_automatically": False,
        "model_invoked": False,
        "candidate_compiled": False,
        "request_human_review": False,
        "experiment_id": "real_pair_001",
        "fingerprint": fingerprint,
        "next_step": "improve_instrumentation",
        "utc_day": "2026-10-18",
        "why": "The repeated timing data needs more targeted instrumentation."
    }
    ledger = {"schema_version": 1, "events": [{
        "fingerprint": fingerprint,
        "experiment_id": "real_pair_001",
        "next_step": "improve_instrumentation",
        "utc_day": "2026-10-18"
    }]}
    return decision, ledger


class ResearchTicketTests(unittest.TestCase):
    def test_eligible_decision_yields_data_only_ticket(self):
        decision, ledger = sources()
        result = ticket.ticket_from_decision(decision, ledger)
        self.assertEqual(result["request_kind"], "research_only")
        self.assertEqual(result["next_step"], "improve_instrumentation")
        self.assertFalse(result["approved_to_invoke_model"])
        self.assertFalse(result["approved_to_dispatch_cloud_workflow"])
        self.assertFalse(result["approved_to_execute_game"])
        self.assertTrue(result["requires_separate_budget_and_dispatch_review"])

    def test_no_ticket_for_promising_candidate_or_human_review_hold(self):
        decision, ledger = sources()
        for field, value in (
            ("disposition", "ready_to_notify_privately"),
            ("disposition", "already_processed"),
            ("request_human_review", True),
            ("next_step", "hold_for_review"),
        ):
            changed = dict(decision)
            changed[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                ticket.ticket_from_decision(changed, ledger)

    def test_rejects_fake_ledger_entries_or_fingerprint_mismatch(self):
        decision, ledger = sources()
        changed = {"schema_version": 1, "events": []}
        with self.assertRaisesRegex(ValueError, "No unique"):
            ticket.ticket_from_decision(decision, changed)
        bad = dict(ledger)
        bad["events"] = [dict(ledger["events"][0]),
                         dict(ledger["events"][0])]
        with self.assertRaisesRegex(ValueError, "No unique"):
            ticket.ticket_from_decision(decision, bad)
        bad = dict(decision)
        bad["fingerprint"] = "b" * 64
        with self.assertRaisesRegex(ValueError, "No unique"):
            ticket.ticket_from_decision(bad, ledger)

    def test_no_escalation_from_metadata(self):
        decision, ledger = sources()
        for field in ("may_install_or_run_candidate", "may_touch_working_game",
                      "may_deploy_automatically", "model_invoked", "candidate_compiled"):
            changed = dict(decision)
            changed[field] = True
            with self.subTest(field=field), self.assertRaises(ValueError):
                ticket.ticket_from_decision(changed, ledger)

    def test_never_overwrite_existing_ticket(self):
        decision, ledger = sources()
        result = ticket.ticket_from_decision(decision, ledger)
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            dest = folder / "ticket.json"
            ticket.write_ticket(dest, result)
            saved = dest.read_text()
            with self.assertRaisesRegex(ValueError, "never be replaced"):
                ticket.write_ticket(dest, result)
            self.assertEqual(dest.read_text(), saved)
            self.assertFalse(json.loads(saved)["approved_to_compile"])

    def test_cli_builds_ticket_from_reviewed_local_files(self):
        decision, ledger = sources()
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            (folder / "decision.json").write_text(json.dumps(decision))
            (folder / "ledger.json").write_text(json.dumps(ledger))
            result = folder / "ticket.json"
            ticket.main([
                "--decision", str(folder / "decision.json"),
                "--ledger", str(folder / "ledger.json"),
                "--out", str(result),
            ])
            self.assertEqual(json.loads(result.read_text())["experiment_id"], "real_pair_001")


if __name__ == "__main__":
    unittest.main()
