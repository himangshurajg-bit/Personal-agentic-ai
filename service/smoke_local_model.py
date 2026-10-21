"""Explicit local-model smoke: synthetic facts only; never downloads a model.

uv run --project service python service/smoke_local_model.py --model INSTALLED_NAME
Requires an already-running loopback Ollama. Nonzero exit means failed/not verified.
"""
from __future__ import annotations
import argparse
import asyncio
import json
import secrets
import tempfile
import time
from pathlib import Path
import httpx
from app import Ollama, create_app

async def run(model: str, url: str) -> dict:
    provider = Ollama(model, url)  # Enforces loopback-only origin, no credentials.
    async with httpx.AsyncClient(timeout=15, follow_redirects=False) as runtime:
        version_response = await runtime.get(provider.url + '/api/version')
        version_response.raise_for_status()
        info_response = await runtime.post(provider.url + '/api/show', json={'model': model})
        info_response.raise_for_status()
        info = info_response.json()
    token = secrets.token_urlsafe(32)
    with tempfile.TemporaryDirectory(prefix='personal-assistant-smoke-') as temp:
        app = create_app(Path(temp) / 'test.sqlite3', provider=provider, token=token)
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://test', headers={'Authorization': 'Bearer ' + token}, timeout=150) as client:
            async def request(method, path, **kwargs):
                response = await client.request(method, path, **kwargs)
                response.raise_for_status()
                return response
            async def chat(prompt):
                start = time.monotonic()
                response = await request('POST', '/chat', json={'conversation': 'synthetic', 'text': prompt})
                events = [json.loads(line) for line in response.text.splitlines()]
                return {'text': ''.join(event.get('text', '') for event in events), 'done': bool(events) and events[-1]['type'] == 'done', 'seconds': round(time.monotonic() - start, 2)}
            ids = []
            for scope, fact in [('synthetic', 'My favorite color is blue.'), ('synthetic', 'My pet is named Snow.'), ('other', 'My favorite color is red.')]:
                response = await request('POST', '/memories', json={'conversation': scope, 'fact': fact})
                ids.append(response.json()['id'])
            first = await chat('What is my favorite color? Reply with just the color.')
            for id in ids:
                await request('DELETE', '/memories/' + id)
            await request('DELETE', '/conversations/synthetic')
            second = await chat('What is my favorite color? If you have no saved fact, say unknown. Reply briefly.')
            await request('DELETE', '/conversations/synthetic')
    return {'runtime': version_response.json(), 'model': model, 'details': info.get('details'), 'with_saved_fact': first, 'after_forget_and_history_delete': second, 'positive_recall_pass': first['done'] and 'blue' in first['text'].casefold() and 'red' not in first['text'].casefold(), 'forget_pass': second['done'] and 'unknown' in second['text'].casefold(), 'scope': 'synthetic temporary database; no personal data; not broad model-quality or device qualification'}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', required=True, help='Exact already-installed Ollama model name')
    parser.add_argument('--url', default='http://127.0.0.1:11434', help='Loopback-only Ollama origin')
    args = parser.parse_args()
    try:
        result = asyncio.run(run(args.model, args.url))
    except Exception as error:
        print(json.dumps({'verified': False, 'reason': type(error).__name__, 'note': 'Local runtime/model unavailable or failed; no model downloaded and no success claimed.'}))
        raise SystemExit(1)
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['positive_recall_pass'] and result['forget_pass'] else 1)

if __name__ == '__main__':
    main()
