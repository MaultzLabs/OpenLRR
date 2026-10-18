"""Offline checks: reviewer commands, private notification boundaries and no auto-deploy."""
import importlib.util
import json
from pathlib import Path
import unittest
from unittest import mock

SOURCE = Path(__file__).resolve().parents[1] / "review_queue.py"
spec = importlib.util.spec_from_file_location("openlrr_review_queue", SOURCE)
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)


def candidate():
    return {
        "schema_version": 1, "experiment_id": "experiment_001",
        "status": "candidate_for_review", "notify_human": True,
        "automatic_promotion_allowed": False, "visual_fps_verified": False,
        "hypothesis": "Reduce presentation stalls by changing one directdraw behavior",
        "reason": "Consistent measured gains in five independently verified pairs.",
        "next_action": "Ask for a human visual review before promoting anything.",
        "pairs": 5, "median_present_change_pct": -18.0,
        "bootstrap_upper95_change_pct": -14.0,
        "median_logical_fps_change_pct": 20.0,
    }


class ReviewQueueTests(unittest.TestCase):
    def test_no_notification_for_inconclusive_or_regression(self):
        for status in ("inconclusive", "regression", "no_improvement", "needs_more_data"):
            data = candidate()
            data["status"] = status
            data["notify_human"] = False
            with mock.patch.object(review, "gh", side_effect=AssertionError("network called")):
                with self.assertRaisesRegex(ValueError, "authorize"):
                    review.publish(data, dry_run=False)

    def test_dry_run_never_creates_issue(self):
        with mock.patch.object(review, "gh", side_effect=AssertionError("network called")):
            result = review.publish(candidate(), dry_run=True)
        self.assertIn("DRY RUN", result)

    def test_private_issue_has_review_commands_but_not_deployment(self):
        with mock.patch.object(review, "existing_issue", return_value=None), \
             mock.patch.object(review, "gh", return_value="https://github.com/MaultzLabs/OpenLRR-Test-Results/issues/3") as github, \
             mock.patch.object(review.sys, "platform", "linux"):
            value = review.publish(candidate(), dry_run=False)
        self.assertIn("issues/3", value)
        arguments = github.call_args.args
        self.assertIn("MaultzLabs/OpenLRR-Test-Results", arguments)
        self.assertIn("--assignee", arguments)
        self.assertIn("/lab continue:", arguments[-1])
        self.assertIn("/lab good:", arguments[-1])
        self.assertIn("not a proven gameplay fix", arguments[-1])

    def test_dedup_skips_repeating_alert(self):
        with mock.patch.object(review, "existing_issue",
                               return_value="https://github.com/private/issues/1"), \
             mock.patch.object(review, "gh", side_effect=AssertionError("created duplicate")):
            result = review.publish(candidate(), dry_run=False)
            self.assertIn("Existing review issue", result)

    def test_only_authorized_reviewer_comments_can_change_plan(self):
        comments = [
            {"id": 1, "user": {"login": "attacker"}, "body": "/lab good"},
            {"id": 2, "user": {"login": "MaultzLabs"},
             "body": "/lab continue: menu still visibly freezes on hover"},
            {"id": 3, "user": {"login": "attacker"},
             "body": "/lab reject: try an unrelated patch"},
        ]
        result = review.feedback_from_comments(comments)
        self.assertEqual(result["decision"], "continue")
        self.assertEqual(result["reason"], "menu still visibly freezes on hover")
        self.assertFalse(result["automatic_deploy_allowed"])

    def test_reason_required_for_continue_or_reject(self):
        comments = [
            {"id": 1, "user": {"login": "MaultzLabs"}, "body": "/lab continue"},
            {"id": 2, "user": {"login": "MaultzLabs"}, "body": "/lab reject"},
            {"id": 3, "user": {"login": "MaultzLabs"},
             "body": "/lab good: no flicker and visibly smooth now"},
        ]
        result = review.feedback_from_comments(comments)
        self.assertEqual(result["decision"], "good")
        self.assertFalse(result["automatic_deploy_allowed"])

    def test_feedback_read_is_from_private_issue_only(self):
        calls = []
        def gh_stub(*args):
            calls.append(args)
            if "/comments?" in args[-1]:
                return json.dumps([{"user": {"login": "MaultzLabs"}, "id": 12,
                                    "body": "/lab reject: visual artifacts"}])
            return json.dumps({"body": "<!-- openlrr-lab-review:experiment_001 -->"})
        with mock.patch.object(review, "gh", side_effect=gh_stub):
            result = review.fetch_feedback(3)
        self.assertEqual(result["decision"], "reject")
        self.assertTrue(all("OpenLRR-Test-Results" in args[-1] for args in calls))


if __name__ == "__main__":
    unittest.main()
