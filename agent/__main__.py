import argparse
import json
import os
import sys
import sqlite3
from .core import preview, run
from .memory import Memory
from .file_search import search_files
from .tools import validate_step


def main():
    parser = argparse.ArgumentParser(description='Local-first bounded personal-agent starter')
    parser.add_argument('--db', default=os.environ.get('AGENT_DB', '.agent-data/memory.sqlite3'))
    sub = parser.add_subparsers(dest='command', required=True)
    ask = sub.add_parser('run', help='Plan and run safe preparation; prepare exact external reviews')
    ask.add_argument('request')
    ask.add_argument('--provider', choices=['demo', 'local', 'cloud'], default='demo')
    plan = sub.add_parser('plan', help='Preview offline demo steps and risk labels; no tools, memory or network')
    plan.add_argument('request')
    files = sub.add_parser('files', help='Search eligible local text files; explicit root, no model or network')
    files.add_argument('query', help='Literal case-insensitive text, not a regular expression')
    files.add_argument('--root', required=True, help='Owner-selected directory; no default or whole-device scan')
    web = sub.add_parser('web', help='Start local-only liquid-glass interface')
    web.add_argument('--port', type=int, default=8765)
    sub.add_parser('check-local', help='Opt-in fixed-prompt local model schema check; no tools or memory')
    notes = sub.add_parser('notes', help='Browse/filter saved notes with ID-based pagination; no model')
    notes.add_argument('--query', default='', help='Literal Unicode case-insensitive substring')
    notes.add_argument('--limit', type=int, default=20, help='Page size 1–100')
    notes.add_argument('--before', type=int, help='Use next_before from the preceding page')
    sub.add_parser('export-notes', help='Print notes only as plaintext JSONL; no drafts or audit records')
    sub.add_parser('pending', help='Review exact pending actions; nothing executes')
    approve = sub.add_parser('approve', help='Approve one exact demo draft; DOES NOT send')
    approve.add_argument('proposal_id')
    reject = sub.add_parser('reject', help='Reject one pending action')
    reject.add_argument('proposal_id')
    edit = sub.add_parser('revise', help='Edit a draft, invalidate old approval and create fresh review')
    edit.add_argument('proposal_id')
    edit.add_argument('--recipient', required=True)
    edit.add_argument('--text', required=True)
    args = parser.parse_args()
    memory = None
    try:
        if args.command == 'check-local':
            from .diagnostics import check_local
            output = check_local()
            print(json.dumps(output, indent=2, ensure_ascii=True))
            return 1 if output['status'] == 'failed' else 0
        if args.command == 'web':
            from .web import serve
            serve(args.db, args.port)
            return 0
        if args.command == 'plan':
            print(json.dumps(preview(args.request), indent=2, ensure_ascii=True))
            return 0
        if args.command == 'files':
            print(json.dumps(search_files(args.root, args.query), indent=2, ensure_ascii=True))
            return 0
        if args.command in ('notes', 'export-notes'):
            # Inspection/export must not initialize or chmod the source database.
            memory = Memory(args.db, read_only=True)
            if args.command == 'export-notes':
                for note in memory.export_notes():
                    print(json.dumps(note, ensure_ascii=True))
                return 0
            print(json.dumps(memory.list_notes(args.query, args.limit, args.before), indent=2, ensure_ascii=True))
            return 0
        memory = Memory(args.db)
        if args.command == 'run':
            output = run(args.request, memory, args.provider)
        elif args.command == 'pending':
            output = {'pending': memory.pending()}
        elif args.command == 'approve':
            output = memory.approve_review(args.proposal_id, validate_step)
        elif args.command == 'revise':
            step = {'tool': 'message.prepare', 'args': {'recipient': args.recipient, 'text': args.text}}
            token = memory.revise(args.proposal_id, step, validate_step)
            output = {'status': 'awaiting_approval', 'proposal_id': token, 'exact_action': step, 'sent': False}
        else:
            memory.reject(args.proposal_id)
            output = {'rejected': args.proposal_id}
        # JSON escapes control characters in untrusted model/user text.
        print(json.dumps(output, indent=2, ensure_ascii=True))
        return 0
    except sqlite3.Error:
        print(json.dumps({'error': 'Local database operation failed; check path and permissions'}), file=sys.stderr)
        return 1
    except (ValueError, OSError) as exc:
        print(json.dumps({'error': str(exc)}), file=sys.stderr)
        return 1
    finally:
        if memory:
            memory.close()


if __name__ == '__main__':
    raise SystemExit(main())
