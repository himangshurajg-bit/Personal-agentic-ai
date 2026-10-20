"""Run with an installed release in a clean venv, from outside the source checkout.

    /path/to/venv/bin/python /path/to/tests/packaging/check_installed.py

Uses synthetic temporary data and loopback HTTP only. No model or external sends.
"""
import http.client
import importlib.metadata
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading


def main():
    import agent
    from agent.web import ASSETS

    version = importlib.metadata.version('personal-agentic-ai')
    assert version == agent.__version__, (version, agent.__version__)
    checkout = Path(__file__).resolve().parents[2]
    assert checkout not in Path(agent.__file__).resolve().parents, 'Imported checkout, not installed distribution'
    for name in ('index.html', 'style.css', 'app.js'):
        assert len((ASSETS / name).read_bytes()) > 500, name

    with tempfile.TemporaryDirectory(prefix='personal-agent-package-') as directory:
        root = Path(directory)
        db = root / 'memory.sqlite3'

        def cli(*args):
            result = subprocess.run([sys.executable, '-m', 'agent', '--db', str(db), *args],
                                    cwd=root, check=True, text=True, capture_output=True, timeout=15)
            return json.loads(result.stdout)

        diagnostic = subprocess.run([sys.executable, '-m', 'agent', '--db', str(db), 'check-local'],
                                    cwd=root, env={**os.environ, 'LOCAL_AGENT_MODEL': ''},
                                    check=True, text=True, capture_output=True, timeout=10)
        assert json.loads(diagnostic.stdout)['status'] == 'skipped'
        assert not db.exists(), 'Local check wrote a database'
        plan = cli('plan', 'goal: calculate 12 * 3; remember package check')
        assert plan['executed'] is False
        assert not db.exists(), 'Preview wrote a database'
        value = cli('run', 'calculate 12 * 3')
        assert value['results'][0]['result']['value'] == 36
        cli('run', 'remember package smoke note')
        value = cli('run', 'find package smoke')
        assert value['results'][0]['result']['notes'][0]['text'] == 'package smoke note'
        draft = cli('run', 'draft nobody@example.test: package check')
        token = draft['results'][0]['proposal_id']
        approved = cli('approve', token)
        assert approved['status'] == 'approved_not_sent' and approved['sent'] is False
        assert cli('pending')['pending'] == []
        (root / 'example.txt').write_text('package search needle\n', encoding='utf-8')
        if sys.platform.startswith('linux'):
            assert 'needle' in json.dumps(cli('files', 'needle', '--root', str(root)))

        process = subprocess.Popen([sys.executable, '-m', 'agent', '--db', str(db), 'web', '--port', '0'],
                                   cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        lines = queue.Queue()
        thread = threading.Thread(target=lambda: lines.put(process.stdout.readline()), daemon=True)
        thread.start()
        try:
            first = lines.get(timeout=10).strip()
            prefix = 'Personal agent: http://127.0.0.1:'
            assert first.startswith(prefix), first
            port = int(first[len(prefix):])
            for path, content_type in (('/', 'text/html'), ('/style.css', 'text/css'), ('/app.js', 'text/javascript')):
                connection = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
                connection.request('GET', path)
                response = connection.getresponse()
                data = response.read()
                assert response.status == 200, (path, response.status)
                assert response.getheader('Content-Type').startswith(content_type)
                assert len(data) > 500, path
                assert "frame-ancestors 'none'" in response.getheader('Content-Security-Policy')
                connection.close()
            connection = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
            connection.request('POST', '/api/preview', json.dumps({'request': 'calculate 2 + 3'}),
                               {'Origin': 'http://127.0.0.1:' + str(port), 'Content-Type': 'application/json'})
            response = connection.getresponse()
            assert response.status == 200
            assert json.loads(response.read())['executed'] is False
            connection.close()
        finally:
            process.terminate()
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate(timeout=5)
    print('Installed package checks passed:', version, 'Python', sys.version.split()[0])
    print('Assets, CLI tools, preview, local notes, approval-not-sent and loopback UI verified.')


if __name__ == '__main__':
    main()
