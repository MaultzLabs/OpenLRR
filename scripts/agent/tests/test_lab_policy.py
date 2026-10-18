"""Research transitions cannot turn statistical screening or feedback into deployment."""
import importlib.util
from pathlib import Path
import unittest

SRC = Path(__file__).resolve().parents[1] / "lab_policy.py"
spec = importlib.util.spec_from_file_location("openlrr_research_policy", SRC)
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


def report(status):
    return {"experiment_id": "test123", "status": status}


def review(choice="awaiting_human", reason=""):
    return {"decision": choice, "reason": reason, "automatic_deploy_allowed": False}


class PolicyTests(unittest.TestCase):
    def test_no_feedback_defaults_to_safe_pending_review(self):
        data = policy.decide(report("candidate_for_review"))
        self.assertEqual(data["next_step"], "hold_for_review")
        self.assertEqual(data["review_decision"], "awaiting_human")
        self.assertFalse(data["may_deploy_automatically"])

    def test_no_feedback_allows_research_without_human_approval(self):
        data = policy.decide(report("no_improvement"))
        self.assertEqual(data["next_step"], "new_hypothesis")
        self.assertFalse(data["request_human_review"])

    def test_candidate_waits_without_approval(self):
        data = policy.decide(report("candidate_for_review"), review())
        self.assertEqual(data["next_step"], "hold_for_review")
        self.assertTrue(data["request_human_review"])
        self.assertFalse(data["may_run_unreviewed_binary"])

    def test_good_job_does_not_deploy(self):
        data = policy.decide(report("candidate_for_review"), review("good", "looks smooth"))
        self.assertEqual(data["next_step"], "prepare_manual_acceptance_check")
        self.assertFalse(data["may_touch_working_game"])
        self.assertFalse(data["may_deploy_automatically"])

    def test_reviewer_continue_reason_is_preserved(self):
        data = policy.decide(report("candidate_for_review"),
                             review("continue", "Still drops frames when scrolling"))
        self.assertEqual(data["next_step"], "revise_hypothesis_from_feedback")
        self.assertIn("drops frames", data["reviewer_reason"])

    def test_reviewer_can_reject_approach(self):
        data = policy.decide(report("candidate_for_review"),
                             review("reject", "Rendering is broken"))
        self.assertEqual(data["next_step"], "abandon_experiment_family")

    def test_feedback_reason_required_for_continue(self):
        with self.assertRaises(ValueError):
            policy.decide(report("candidate_for_review"), review("continue"))

    def test_research_decisions_are_not_a_fixed_blind_repeat(self):
        expected = {
            "needs_more_data": "complete_paired_measurement",
            "inconclusive": "improve_instrumentation",
            "no_improvement": "new_hypothesis",
            "regression": "isolate_regression",
        }
        for status, next_step in expected.items():
            with self.subTest(status=status):
                data = policy.decide(report(status), review())
                self.assertEqual(data["next_step"], next_step)
                self.assertFalse(data["request_human_review"])

    def test_unreviewed_human_feedback_rejected(self):
        with self.assertRaises(ValueError):
            policy.decide(report("no_improvement"), review("good", "looks good"))

    def test_fake_deploy_authorization_rejected(self):
        bad = review("good", "works")
        bad["automatic_deploy_allowed"] = True
        with self.assertRaises(ValueError):
            policy.decide(report("candidate_for_review"), bad)


if __name__ == "__main__":
    unittest.main()
