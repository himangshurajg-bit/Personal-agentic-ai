"""Explicit loopback transport checks; no real providers, keys or internet.

Run: python -m unittest discover -s tests/integration -v
Not part of the default offline unit discovery (directory intentionally not a package).
"""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import threading
import unittest
from contextlib import closing, contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

from agent.providers import post_json


@contextmanager
def fixture(status=200, body=b'{"steps":[]}', headers=None, raw_status=False):
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            data = self.rfile.read(int(self.headers.get('Content-Length', '0')))
            requests.append((self.path, dict(self.headers), data))
            if raw_status:
                self.connection.sendall(b'private-fixture-marker\r\n\r\n')
                self.close_connection = True
                return
            self.send_response(status)
            for name, value in (headers or {}).items():
                self.send_header(name, value)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': 0.01}, daemon=True)
    thread.start()
    try:
        yield 'http://127.0.0.1:' + str(server.server_port), requests
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        if thread.is_alive():
            raise RuntimeError('Loopback fixture did not stop')


class TransportTests(unittest.TestCase):
    def test_post_json_uses_real_loopback_and_ignores_proxy(self):
        with fixture() as (url, requests), patch.dict('os.environ', {
            'http_proxy': 'http://127.0.0.1:1', 'HTTP_PROXY': 'http://127.0.0.1:1',
            'https_proxy': 'http://127.0.0.1:1', 'HTTPS_PROXY': 'http://127.0.0.1:1',
            'no_proxy': '', 'NO_PROXY': '',
        }):
            result = post_json(url + '/api/chat', {'request': 'fictional café'}, {'X-Fixture': 'example'})
        self.assertEqual(result, {'steps': []})
        self.assertEqual(len(requests), 1)
        path, headers, body = requests[0]
        self.assertEqual(path, '/api/chat')
        self.assertEqual(headers['Content-Type'], 'application/json')
        self.assertEqual(headers['X-Fixture'], 'example')
        self.assertEqual(json.loads(body), {'request': 'fictional café'})

    def test_invalid_json_is_sanitized(self):
        with fixture(body=b'private-fixture-marker') as (url, _):
            with self.assertRaisesRegex(ValueError, '^Provider returned invalid JSON$'):
                post_json(url, {}, {})

    def test_invalid_encoding_is_sanitized(self):
        with fixture(body=b'\xff') as (url, _):
            with self.assertRaisesRegex(ValueError, '^Provider returned invalid JSON$'):
                post_json(url, {}, {})

    def test_oversized_reply_is_rejected(self):
        with fixture(body=b' ' * 65537) as (url, _):
            with self.assertRaisesRegex(ValueError, '^Provider response too large$'):
                post_json(url, {}, {})

    def test_redirect_does_not_contact_destination(self):
        with fixture() as (destination, target_requests):
            with fixture(status=307, body=b'', headers={'Location': destination}) as (source, source_requests):
                with self.assertRaisesRegex(ValueError, '^Provider redirects are disabled$'):
                    post_json(source, {'example': True}, {})
        self.assertEqual(len(source_requests), 1)
        self.assertEqual(target_requests, [])

    def test_http_failure_hides_body_and_does_not_retry(self):
        with fixture(status=429, body=b'private-fixture-marker') as (url, requests):
            with self.assertRaisesRegex(ValueError, '^Provider request failed; check model, credentials and endpoint$'):
                post_json(url, {}, {})
        self.assertEqual(len(requests), 1)

    def test_deep_json_cli_fails_cleanly_without_local_effects(self):
        # Python 3.11's decoder raises RecursionError; newer decoders may parse it.
        # Either path must fail safely before any tool or review is performed.
        nested = '[' * 2000 + '0' + ']' * 2000
        cases = {
            'outer_response': nested.encode(),
            'planner_content': json.dumps({'message': {'content': nested}}).encode(),
        }
        for boundary, body in cases.items():
            with self.subTest(boundary=boundary), tempfile.TemporaryDirectory() as tmp:
                database = Path(tmp) / 'memory.sqlite3'
                with fixture(body=body) as (url, requests):
                    result = subprocess.run(
                        [sys.executable, '-m', 'agent', '--db', str(database), 'run',
                         'remember Must not be saved', '--provider', 'local'],
                        env={**os.environ, 'LOCAL_AGENT_URL': url, 'LOCAL_AGENT_MODEL': 'fixture'},
                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(result.stdout, '')
                error = json.loads(result.stderr)
                self.assertEqual(set(error), {'error'})
                self.assertNotIn('Traceback', result.stderr)
                self.assertNotIn('Must not be saved', result.stderr)
                self.assertEqual(len(requests), 1)
                with closing(sqlite3.connect(database)) as db:
                    for table in ('notes', 'proposals', 'audit'):
                        self.assertEqual(db.execute('SELECT count(*) FROM ' + table).fetchone()[0], 0)

    def test_duplicate_json_cli_rejected_before_effects(self):
        plan = '{"steps":[{"tool":"notes.add","args":{"text":"first","text":"private-fixture-marker"}}]}'
        valid_response = json.dumps({'message': {'content': json.dumps({
            'steps': [{'tool': 'notes.add', 'args': {'text': 'private-fixture-marker'}}]})}})
        cases = {
            'outer_response': (b'{"message":{},' + valid_response[1:].encode(),
                               'Provider returned invalid JSON'),
            'planner_content': (json.dumps({'message': {'content': plan}}).encode(),
                                'Planner content must be strict JSON'),
        }
        for boundary, (body, expected_error) in cases.items():
            with self.subTest(boundary=boundary), tempfile.TemporaryDirectory() as tmp:
                database = Path(tmp) / 'memory.sqlite3'
                with fixture(body=body) as (url, requests):
                    result = subprocess.run(
                        [sys.executable, '-m', 'agent', '--db', str(database), 'run',
                         'prepare a note', '--provider', 'local'],
                        env={**os.environ, 'LOCAL_AGENT_URL': url, 'LOCAL_AGENT_MODEL': 'fixture'},
                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(result.stdout, '')
                self.assertEqual(json.loads(result.stderr), {'error': expected_error})
                self.assertNotIn('private-fixture-marker', result.stderr)
                self.assertEqual(len(requests), 1)
                with closing(sqlite3.connect(database)) as db:
                    for table in ('notes', 'proposals', 'audit'):
                        self.assertEqual(db.execute('SELECT count(*) FROM ' + table).fetchone()[0], 0)

    def test_malformed_http_status_is_sanitized(self):
        with fixture(raw_status=True) as (url, requests):
            with self.assertRaisesRegex(ValueError, '^Provider request failed; check model, credentials and endpoint$'):
                post_json(url, {}, {})
        self.assertEqual(len(requests), 1)


if __name__ == '__main__':
    unittest.main()
