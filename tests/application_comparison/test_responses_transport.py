"""Local HTTP fixtures only: no API key or external model invocation."""
import http.server
import json
import subprocess
import threading
import unittest
from experiments.application_comparison.responses_transport import ResponsesTransport


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        self.server.requests.append(json.loads(self.rfile.read(int(self.headers['Content-Length']))))
        if self.server.mode == 'slow':
            self.server.release.wait(2)
            return
        self.send_response(302 if self.server.mode == 'redirect' else 200)
        if self.server.mode == 'redirect':
            self.send_header('Location', 'http://127.0.0.1:1/credentials-must-not-follow')
        self.end_headers()
        if self.server.mode == 'success':
            self.wfile.write(b'{"model":"fixture","status":"completed","output":[]}')
        elif self.server.mode == 'malformed':
            self.wfile.write(b'{"value":1,"value":2}')


class ResponsesTransportTests(unittest.TestCase):
    def setUp(self):
        self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.server.requests = []
        self.server.release = threading.Event()
        self.server.mode = 'success'
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.cleanup_server)
        self.endpoint = f'http://127.0.0.1:{self.server.server_port}/v1/responses'
        self.transport = ResponsesTransport('fixture', endpoint=self.endpoint)

    def cleanup_server(self):
        self.server.release.set()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def test_bounded_worker_round_trip_and_frozen_configuration(self):
        response = self.transport({'model': 'fixture', 'input': []}, timeout=5)
        self.assertEqual(response['model'], 'fixture')
        self.assertEqual(self.server.requests, [{'model': 'fixture', 'input': []}])
        self.transport.endpoint += '/changed'
        with self.assertRaisesRegex(ValueError, 'configuration changed'):
            self.transport({}, timeout=5)

    def test_redirects_do_not_forward_credentials(self):
        self.server.mode = 'redirect'
        with self.assertRaisesRegex(RuntimeError, 'HTTP status 302'):
            self.transport({}, timeout=5)
        self.assertEqual(len(self.server.requests), 1)

    def test_timeout_stops_network_worker(self):
        self.server.mode = 'slow'
        with self.assertRaises(subprocess.TimeoutExpired):
            self.transport({}, timeout=0.25)

    def test_duplicate_response_keys_are_rejected(self):
        self.server.mode = 'malformed'
        with self.assertRaises(ValueError):
            self.transport({}, timeout=5)

    def test_nonfixture_credentials_cannot_go_to_plain_http(self):
        transport = ResponsesTransport('not-a-real-key', endpoint=self.endpoint)
        with self.assertRaises(RuntimeError):
            transport({}, timeout=5)
        self.assertEqual(self.server.requests, [])


if __name__ == '__main__':
    unittest.main()
