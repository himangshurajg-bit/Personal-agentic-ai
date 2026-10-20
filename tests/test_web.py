import http.client
import io
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
from agent.web import make_server
from agent.memory import Memory


class WebTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.db = str(Path(self.temp.name) / 'memory.sqlite3')
        self.server = make_server(self.db, 0)
        self.host = '127.0.0.1:' + str(self.server.server_port)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def request(self, path, body=None, origin=True, host=None, raw=None, content_type='application/json'):
        c = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=3)
        headers = {'Host': host or self.host, 'Content-Type': content_type}
        if origin:
            headers['Origin'] = 'http://' + self.host if origin is True else origin
        try:
            c.request('POST' if body is not None or raw is not None else 'GET', path,
                      body=raw if raw is not None else json.dumps(body) if body is not None else None,
                      headers=headers)
            r = c.getresponse()
            data = r.read()
            return r.status, dict(r.getheaders()), data
        finally:
            c.close()

    def api(self, path, body):
        status, _, raw = self.request('/api/' + path, body)
        return status, json.loads(raw)

    def test_bound_only_to_loopback(self):
        self.assertEqual(self.server.server_address[0], '127.0.0.1')

    def test_static_assets_and_security_headers(self):
        for path in ['/', '/style.css', '/app.js']:
            status, headers, raw = self.request(path)
            self.assertEqual(status, 200)
            self.assertGreater(len(raw), 500)
            self.assertIn("frame-ancestors 'none'", headers['Content-Security-Policy'])
            self.assertEqual(headers['Cache-Control'], 'no-store')
        self.assertEqual(self.request('/../../agent/memory.py')[0], 404)
        self.assertEqual(self.request('/api/pending')[0], 404)

    def test_rejects_foreign_host_origin_missing_origin_and_non_json(self):
        for options in [dict(host='evil.test'), dict(origin=False), dict(origin='https://evil.test'),
                        dict(content_type='text/plain')]:
            self.assertEqual(self.request('/api/run', {'request': 'remember forbidden'}, **options)[0], 403)
        self.assertFalse(Path(self.db).exists())

    def test_preview_does_not_create_database(self):
        status, value = self.api('preview', {'request': 'remember <script>alert(1)</script>'})
        self.assertEqual(status, 200)
        self.assertFalse(value['executed'])
        self.assertFalse(Path(self.db).exists())

    def test_real_local_tools_and_note_persistence(self):
        status, value = self.api('run', {'request': 'calculate 2 + 3'})
        self.assertEqual(value['results'][0]['result']['value'], 5)
        self.api('run', {'request': 'remember test web note'})
        _, value = self.api('run', {'request': 'find web note'})
        self.assertEqual(value['results'][0]['result']['notes'][0]['text'], 'test web note')

    def test_review_revise_approval_single_use_and_no_send(self):
        _, value = self.api('run', {'request': 'draft person@example.test: original'})
        token = value['results'][0]['proposal_id']
        _, value = self.api('revise', {'id': token, 'recipient': 'new@example.test', 'text': 'changed'})
        new = value['proposal_id']
        self.assertEqual(self.api('approve', {'id': token})[0], 400)
        _, value = self.api('approve', {'id': new})
        self.assertEqual(value['status'], 'approved_not_sent')
        self.assertFalse(value['sent'])
        self.assertEqual(value['exact_action']['args']['text'], 'changed')
        self.assertEqual(self.api('approve', {'id': new})[0], 400)
        self.assertEqual(self.api('pending', {})[1]['pending'], [])

    def test_reject_pending(self):
        _, value = self.api('run', {'request': 'draft test@example.test: hi'})
        token = value['results'][0]['proposal_id']
        self.assertEqual(self.api('reject', {'id': token})[1]['status'], 'rejected')
        self.assertEqual(self.api('approve', {'id': token})[0], 400)

    def test_file_search_needs_explicit_root(self):
        Path(self.temp.name, 'notes.txt').write_text('findable idea')
        status, value = self.api('files', {'root': self.temp.name, 'query': 'findable'})
        self.assertEqual(status, 200)
        self.assertEqual(value['matches'][0]['path'], 'notes.txt')
        self.assertEqual(self.api('files', {'query': 'findable'})[0], 400)

    def test_invalid_json_and_fields_do_not_change_database(self):
        for raw in ['{broken', '[]', 'null', '"string"']:
            self.assertEqual(self.request('/api/run', raw=raw)[0], 400)
        self.assertEqual(self.api('run', {'request': 'time', 'provider': 'cloud'})[0], 400)
        self.assertFalse(Path(self.db).exists())

    def test_body_size_bound(self):
        self.assertEqual(self.request('/api/run', raw='x' * 17000)[0], 413)

    def test_expired_review_cannot_be_approved(self):
        _, value = self.api('run', {'request': 'draft person@example.test: expired'})
        token = value['results'][0]['proposal_id']
        memory = Memory(self.db)
        memory.db.execute("UPDATE proposals SET expires_at='2000-01-01T00:00:00+00:00'")
        memory.db.commit()
        memory.close()
        self.assertEqual(self.api('pending', {})[1]['pending'], [])
        self.assertEqual(self.api('approve', {'id': token})[0], 400)

    def test_duplicate_json_names_are_rejected_before_database_access(self):
        bodies = [
            r'{"request":"time","request":"remember must not be saved"}',
            r'{"request":"time","reque\u0073t":"remember must not be saved"}',
            r'{"request":{"nested":"first","nested":"second"}}',
        ]
        for raw in bodies:
            with self.subTest(raw=raw):
                status, _, value = self.request('/api/run', raw=raw)
                self.assertEqual(status, 400)
                self.assertNotIn(b'must not be saved', value)
                self.assertFalse(Path(self.db).exists())
        self.assertEqual(self.api('preview', {'request': 'calculate 2 + 2'})[0], 200)

    def test_duplicate_review_id_cannot_select_last_draft(self):
        tokens = []
        for text in ['first', 'second']:
            _, value = self.api('run', {'request': 'draft person@example.test: ' + text})
            tokens.append(value['results'][0]['proposal_id'])
        raw = '{"id":' + json.dumps(tokens[0]) + ',"id":' + json.dumps(tokens[1]) + '}'
        self.assertEqual(self.request('/api/approve', raw=raw)[0], 400)
        _, pending = self.api('pending', {})
        self.assertEqual({item['id'] for item in pending['pending']}, set(tokens))
        memory = Memory(self.db)
        try:
            self.assertEqual(memory.db.execute("SELECT count(*) FROM audit WHERE event='review.approve'").fetchone()[0], 0)
        finally:
            memory.close()

    def test_deep_json_returns_safe_error_and_server_keeps_serving(self):
        raw = '[' * 2000 + '0' + ']' * 2000
        with patch('sys.stderr', new_callable=io.StringIO) as errors:
            status, _, value = self.request('/api/run', raw=raw)
        self.assertEqual(status, 400)
        self.assertEqual(json.loads(value), {'error': 'Input rejected. Check the command, fields or review expiry.'})
        self.assertNotIn('Traceback', errors.getvalue())
        self.assertFalse(Path(self.db).exists())
        self.assertEqual(self.api('preview', {'request': 'time'})[0], 200)

    def test_notebook_pages_and_filters(self):
        m = Memory(self.db)
        try:
            for i in range(25):
                m.add_note('École ' + str(i))
        finally:
            m.close()
        status, page = self.api('notes', {'query': 'école', 'before': ''})
        self.assertEqual(status, 200)
        self.assertEqual(len(page['notes']), 20)
        self.assertEqual(page['next_before'], 6)
        status, last = self.api('notes', {'query': 'ÉCOLE', 'before': str(page['next_before'])})
        self.assertEqual(status, 200)
        self.assertEqual([n['id'] for n in last['notes']], [5, 4, 3, 2, 1])
        self.assertFalse(last['has_more'])

    def test_notebook_rejects_bad_fields_and_cursors(self):
        cases = ({'query': '', 'before': '0'}, {'query': '', 'before': '-1'},
                 {'query': '', 'before': '1e2'}, {'query': '', 'before': '１'},
                 {'query': '', 'before': str(2**63)}, {'query': '', 'before': 1},
                 {'query': 'x' * 201, 'before': ''}, {'query': '', 'before': '', 'extra': ''})
        for body in cases:
            with self.subTest(body=body):
                self.assertEqual(self.api('notes', body)[0], 400)
        self.assertEqual(self.api('notes', {'query': '', 'before': ''})[0], 200)

    def test_notebook_preserves_same_origin_gate(self):
        body = {'query': '', 'before': ''}
        self.assertEqual(self.request('/api/notes', body, origin=False)[0], 403)
        self.assertEqual(self.request('/api/notes', body, origin='https://example.test')[0], 403)
        self.assertEqual(self.request('/api/notes', body, host='foreign.test')[0], 403)
