import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch
import urllib.error

spec = importlib.util.spec_from_file_location('review', Path(__file__).parents[1] / 'review.py')
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)

class FakeClient:
    def __init__(self, error=None): self.calls = 0; self.error = error
    def open(self, request, timeout):
        self.calls += 1
        self.request = request
        if self.error: raise self.error
        return io.BytesIO(json.dumps({'id':'synthetic', 'status':'completed',
            'usage':{'input_tokens':10, 'output_tokens':5},
            'output':[{'type':'message','content':[{'type':'output_text','text':'NO_FINDINGS'}]}]}).encode())

class ReviewTests(unittest.TestCase):
    def test_authorization_is_required_before_network(self):
        client = FakeClient()
        with self.assertRaises(ValueError): review.review_once({'commit':'test'}, opener=client)
        self.assertEqual(client.calls, 0)

    @patch.dict('os.environ', {'OPENAI_API_KEY':'test-only'})
    def test_one_request_no_tools_and_bounded_output(self):
        client = FakeClient()
        result = review.review_once({'commit':'test'}, authorized=True, opener=client)
        self.assertEqual(client.calls, 1)
        body = json.loads(client.request.data)
        self.assertFalse(body['store'])
        self.assertEqual(body['tools'], [])
        self.assertEqual(body['reasoning'], {'effort': 'low'})
        self.assertEqual(body['max_output_tokens'], 6000)
        self.assertEqual(result['review'], 'NO_FINDINGS')
        self.assertFalse(result['code_applied'])
        self.assertNotIn('test-only', json.dumps(result))

    @patch.dict('os.environ', {'OPENAI_API_KEY':'test-only'})
    def test_timeout_is_never_retried(self):
        client = FakeClient(TimeoutError())
        with self.assertRaises(ValueError): review.review_once({'commit':'test'}, authorized=True, opener=client)
        self.assertEqual(client.calls, 1)

    @patch.dict('os.environ', {'OPENAI_API_KEY':'test-only'})
    def test_oversized_input_stops_before_network(self):
        client = FakeClient()
        with self.assertRaises(ValueError):
            review.review_once({'commit':'test','data':'x'*200_000}, authorized=True, opener=client)
        self.assertEqual(client.calls, 0)

    def test_packet_is_from_exact_commit_and_allowlisted_source(self):
        root = Path(__file__).resolve().parents[3]
        evidence = review.packet(root)
        self.assertEqual(len(evidence['commit']), 40)
        self.assertEqual([s['path'] for s in evidence['sources']], list(review.FILES))
        self.assertTrue(all(len(s['sha256']) == 64 for s in evidence['sources']))

if __name__ == '__main__': unittest.main()
