"""Portable read-only HTTP spectator tests. Never capture a desktop."""
import http.client
from http.server import ThreadingHTTPServer
from pathlib import Path
import sys
import threading
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from spectator import make_handler


class FakeFrameSource:
    def __init__(self):
        self.calls = 0

    def jpeg(self):
        self.calls += 1
        return b'\xff\xd8FAKEJPG\xff\xd9'


class SpectatorTests(unittest.TestCase):
    def setUp(self):
        self.source = FakeFrameSource()
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), make_handler(self.source))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, path):
        conn = http.client.HTTPConnection('127.0.0.1', self.server.server_port)
        conn.request('GET', path)
        response = conn.getresponse()
        result = (response.status, response.getheader('Content-Type'),
                  response.getheader('Cache-Control'), response.read())
        conn.close()
        return result

    def test_viewer_is_read_only(self):
        status, _, _, body = self.request('/')
        self.assertEqual(status, 200)
        self.assertIn(b'Read-only', body)
        self.assertNotIn(b'onclick=', body)
        self.assertEqual(self.source.calls, 0)

    def test_frames_come_only_from_source(self):
        status, mime, cache, body = self.request('/frame.jpg?v=5')
        self.assertEqual((status, mime), (200, 'image/jpeg'))
        self.assertEqual(body, b'\xff\xd8FAKEJPG\xff\xd9')
        self.assertIn('no-store', cache)
        self.assertEqual(self.source.calls, 1)

    def test_no_control_endpoints(self):
        self.assertEqual(self.request('/control')[0], 404)
        self.assertEqual(self.source.calls, 0)

    def test_capture_failure_redacts_private_data(self):
        self.source.jpeg = lambda: (_ for _ in ()).throw(RuntimeError('private-machine-path'))
        status, _, _, body = self.request('/frame.jpg')
        self.assertEqual(status, 503)
        self.assertNotIn(b'private-machine-path', body)


if __name__ == '__main__':
    unittest.main()
