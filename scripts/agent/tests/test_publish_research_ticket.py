"""No-network tests for gated private research-ticket publication."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import publish_research_ticket as outbox


class ResearchOutboxTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.runs = self.root / "runs"
        self.runs.mkdir()
        self.manifest = self.root / "example_001.json"
        self.manifest.write_text(json.dumps({"experiment_id": "example_001"}))
        self.decision = self.root / "decision.json"
        self.ledger = self.root / "ledger.json"
        self.ticket = self.root / "ticket.json"
        self.request = {
            "schema_version": 1, "ticket_id": "research_" + "a" * 24,
            "experiment_id": "example_001",
            "next_step": "improve_instrumentation",
            "approved_to_invoke_model": False,
            "approved_to_execute_game": False,
        }
        self.ticket.write_text(json.dumps(self.request))
        self.decision.write_text("{}")
        self.ledger.write_text("{}")

    def patched_gate(self):
        return mock.patch.object(outbox.publish_experiment.remote_evidence_gate, "evaluate",
                                 return_value={
                                     "may_execute_candidate": False,
                                     "may_deploy_automatically": False,
                                 })

    def test_dry_run_never_networks(self):
        with mock.patch.object(outbox.research_ticket, "ticket_from_decision",
                               return_value=self.request), self.patched_gate(), \
             mock.patch.object(outbox.publish_experiment, "gh",
                               side_effect=AssertionError("network called")):
            r = outbox.publish(self.ticket, self.decision, self.ledger,
                               self.manifest, self.runs)
        self.assertFalse(r["private_ticket_published"])
        self.assertFalse(r["model_invoked"])
        self.assertFalse(r["new_game_executed"])

    def test_ticket_mismatch_rejected_before_network(self):
        with mock.patch.object(outbox.research_ticket, "ticket_from_decision",
                               return_value=self.request), self.patched_gate(), \
             mock.patch.object(outbox.publish_experiment, "gh",
                               side_effect=AssertionError("network called")):
            self.ticket.write_text('{"ticket_id": "fabricated"}')
            with self.assertRaisesRegex(ValueError, "disagrees"):
                outbox.publish(self.ticket, self.decision, self.ledger,
                               self.manifest, self.runs, commit=True)

    def test_verification_failure_never_uploads_ticket(self):
        with mock.patch.object(outbox.research_ticket, "ticket_from_decision",
                               return_value=self.request), self.patched_gate(), \
             mock.patch.object(outbox.publish_experiment, "publish",
                               side_effect=RuntimeError("private A/B receipts absent")), \
             mock.patch.object(outbox.publish_experiment, "gh",
                               side_effect=AssertionError("unverified upload")):
            with self.assertRaisesRegex(RuntimeError, "receipts absent"):
                outbox.publish(self.ticket, self.decision, self.ledger,
                               self.manifest, self.runs, commit=True)

    def test_private_publication_is_immutable_and_idempotent(self):
        previous = {"blob": None}
        def sha_of_ticket(_):
            return hashlib.sha1(
                b"blob " + str(self.ticket.stat().st_size).encode() +
                b"\0" + self.ticket.read_bytes()).hexdigest()
        def check_remote(path):
            self.assertTrue(path.startswith("research-tickets/"))
            return previous["blob"]
        def gh(*args, input_file=None):
            self.assertIn("PUT", args)
            self.assertIsNotNone(input_file)
            previous["blob"] = sha_of_ticket(self.ticket)
            return "{}"
        with mock.patch.object(outbox.research_ticket, "ticket_from_decision",
                               return_value=self.request), self.patched_gate(), \
             mock.patch.object(outbox.publish_experiment, "publish",
                               return_value={"published": True, "experiment_id": "example_001"}), \
             mock.patch.object(outbox.publish_experiment, "ensure_private_repo"), \
             mock.patch.object(outbox.publish_experiment, "remote_sha",
                               side_effect=check_remote), \
             mock.patch.object(outbox.publish_experiment, "gh",
                               side_effect=gh):
            first = outbox.publish(self.ticket, self.decision, self.ledger,
                                   self.manifest, self.runs, commit=True)
            self.assertTrue(first["private_ticket_published"])
            again = outbox.publish(self.ticket, self.decision, self.ledger,
                                   self.manifest, self.runs, commit=True)
            self.assertTrue(again["already_published"])
            previous["blob"] = "f" * 40
            with self.assertRaisesRegex(RuntimeError, "refuse overwrite"):
                outbox.publish(self.ticket, self.decision, self.ledger,
                               self.manifest, self.runs, commit=True)


if __name__ == "__main__":
    unittest.main()
