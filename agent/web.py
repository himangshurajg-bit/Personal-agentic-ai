"""Local-only visual interface; no remote planner, external sender or file server."""
import json
import sqlite3
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from .core import preview, run
from .file_search import search_files
from .memory import Memory
from .tools import validate_step

ASSETS = Path(__file__).with_name('web_assets')
MAX_BODY = 16384


def make_server(db_path, port=8765):
    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(5)

        def log_message(self, *args):
            pass  # Never log note text, paths or draft recipients.

        def trusted_host(self):
            return self.headers.get('Host') in {
                '127.0.0.1:' + str(self.server.server_port),
                'localhost:' + str(self.server.server_port)}

        def answer(self, value, status=200, mime='application/json'):
            raw = json.dumps(value, ensure_ascii=True).encode() if mime == 'application/json' else value
            self.send_response(status)
            self.send_header('Content-Type', mime + '; charset=utf-8')
            self.send_header('Content-Length', str(len(raw)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Content-Security-Policy', "default-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
            self.end_headers()
            self.wfile.write(raw)

        def do_GET(self):
            if not self.trusted_host():
                return self.answer({'error': 'Local host required'}, 403)
            assets = {'/': ('index.html', 'text/html'), '/style.css': ('style.css', 'text/css'),
                      '/app.js': ('app.js', 'text/javascript')}
            if self.path in assets:
                name, mime = assets[self.path]
                return self.answer((ASSETS / name).read_bytes(), mime=mime)
            return self.answer({'error': 'Not found'}, 404)

        def do_POST(self):
            if (not self.trusted_host() or self.headers.get('Origin') != 'http://' + self.headers.get('Host', '')
                    or self.headers.get('Content-Type') != 'application/json'
                    or self.headers.get('Transfer-Encoding')):
                return self.answer({'error': 'Same-origin JSON request required'}, 403)
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if size <= 0 or size > MAX_BODY:
                    return self.answer({'error': 'Request too large or empty'}, 413)
                body = json.loads(self.rfile.read(size))
                if not isinstance(body, dict):
                    raise ValueError('Expected an object')
                fields = {'/api/preview': {'request'}, '/api/run': {'request'}, '/api/pending': set(),
                          '/api/files': {'root', 'query'}, '/api/approve': {'id'}, '/api/reject': {'id'},
                          '/api/revise': {'id', 'recipient', 'text'}}
                if self.path not in fields:
                    return self.answer({'error': 'Not found'}, 404)
                if set(body) != fields[self.path] or any(not isinstance(v, str) for v in body.values()):
                    raise ValueError('Invalid request fields')
                if self.path == '/api/preview':
                    result = preview(body['request'])
                elif self.path == '/api/files':
                    result = search_files(body['root'], body['query'])
                else:
                    memory = Memory(db_path)
                    try:
                        if self.path == '/api/run':
                            result = run(body['request'], memory, 'demo')
                        elif self.path == '/api/pending':
                            result = {'pending': memory.pending()}
                        elif self.path == '/api/approve':
                            result = memory.approve_review(body['id'], validate_step)
                        elif self.path == '/api/reject':
                            memory.reject(body['id'])
                            result = {'status': 'rejected'}
                        else:
                            step = {'tool': 'message.prepare', 'args': {'recipient': body['recipient'], 'text': body['text']}}
                            token = memory.revise(body['id'], step, validate_step)
                            result = {'status': 'awaiting_approval', 'proposal_id': token, 'sent': False}
                    finally:
                        memory.close()
                return self.answer(result)
            except (ValueError, KeyError, UnicodeError):
                return self.answer({'error': 'Input rejected. Check the command, fields or review expiry.'}, 400)
            except (OSError, sqlite3.Error):
                return self.answer({'error': 'Local operation failed. Check the chosen path and permissions.'}, 400)
    server = HTTPServer(('127.0.0.1', port), Handler)
    server.timeout = 10
    return server


def serve(db_path, port=8765):
    server = make_server(db_path, port)
    print('Personal agent: http://127.0.0.1:' + str(server.server_port), flush=True)
    print('Local computer only. Keep this terminal open; Ctrl+C stops it. No messages are sent.', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
