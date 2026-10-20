import argparse
import json
import os
import sys
import sqlite3
from .core import run
from .memory import Memory
from .tools import validate_step


def main():
    parser = argparse.ArgumentParser(description='Local-first bounded personal-agent starter')
    parser.add_argument('--db', default=os.environ.get('AGENT_DB', '.agent-data/memory.sqlite3'))
    sub = parser.add_subparsers(dest='command', required=True)
    ask = sub.add_parser('run', help='Plan and run safe preparation; prepare exact external reviews')
    ask.add_argument('request')
    ask.add_argument('--provider', choices=['demo', 'local', 'cloud'], default='demo')
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
