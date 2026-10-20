"""Local SQLite memory and exact prepared-action reviews; plaintext, not a vault."""
import hashlib
import json
import secrets
import sqlite3
import unicodedata
from datetime import datetime, timedelta, timezone
from pathlib import Path


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def digest(payload):
    return hashlib.sha256(payload.encode()).hexdigest()


def folded(text):
    return unicodedata.normalize("NFC", unicodedata.normalize("NFC", text).casefold())


def now():
    return datetime.now(timezone.utc)


class Memory:
    def __init__(self, path, read_only=False):
        path = Path(path)
        if not read_only:
            path.parent.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True) if read_only else sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        # SQLite lower() only handles ASCII. Literal Unicode matching stays local.
        self.db.create_function('note_contains', 2, lambda text, query:
                                folded(query) in folded(text), deterministic=True)
        if read_only:
            return
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY, text TEXT NOT NULL, created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS proposals (
            id TEXT PRIMARY KEY, payload TEXT NOT NULL, payload_hash TEXT NOT NULL,
            expires_at TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending'
        );
        CREATE TABLE IF NOT EXISTS audit (
            id INTEGER PRIMARY KEY, event TEXT NOT NULL, detail TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        ''')
        self.db.commit()
        try:
            path.chmod(0o600)
        except OSError:
            pass

    def close(self):
        self.db.close()

    def search(self, query):
        return self.list_notes(query=query)['notes']

    def list_notes(self, query='', limit=20, before=None):
        """Newest first; cursor excludes new inserts, not a frozen database snapshot."""
        if not isinstance(query, str) or len(query) > 200:
            raise ValueError('Note query must be text of at most 200 characters')
        if type(limit) is not int or not 1 <= limit <= 100:
            raise ValueError('Note page limit must be 1–100')
        if before is not None and (type(before) is not int or not 1 <= before <= 9223372036854775807):
            raise ValueError('Note cursor must be a positive SQLite integer ID')
        rows = [dict(row) for row in self.db.execute(
            'SELECT id,text,created_at FROM notes WHERE (? IS NULL OR id < ?) '
            'AND note_contains(text, ?) ORDER BY id DESC LIMIT ?', (before, before, query, limit + 1))]
        more = len(rows) > limit
        notes = rows[:limit]
        return {'notes': notes, 'next_before': notes[-1]['id'] if more else None,
                'has_more': more, 'limit': limit}

    def export_notes(self):
        """Stream only notes in one SQLite SELECT snapshot; never approvals or audit."""
        for row in self.db.execute('SELECT id,text,created_at FROM notes ORDER BY id ASC'):
            yield dict(row)

    def add_note(self, text):
        with self.db:
            cursor = self.db.execute('INSERT INTO notes(text,created_at) VALUES(?,?)', (text, now().isoformat()))
            self.db.execute('INSERT INTO audit(event,detail,created_at) VALUES(?,?,?)',
                            ('note.add', canonical({'note_id': cursor.lastrowid}), now().isoformat()))
        return {'note_id': cursor.lastrowid, 'saved': True}

    def _insert_proposal(self, step):
        payload = canonical(step)
        token = secrets.token_hex(12)
        self.db.execute('INSERT INTO proposals(id,payload,payload_hash,expires_at) VALUES(?,?,?,?)',
                        (token, payload, digest(payload), (now() + timedelta(minutes=15)).isoformat()))
        return token

    def propose(self, step):
        with self.db:
            return self._insert_proposal(step)

    def pending(self):
        """List actionable reviews; retain expired rows unchanged as history."""
        current = now()
        return [dict(row) for row in self.db.execute(
            "SELECT id,payload,payload_hash,expires_at FROM proposals WHERE status='pending' ORDER BY rowid DESC")
            if datetime.fromisoformat(row['expires_at']) > current]

    def reject(self, token):
        with self.db:
            cursor = self.db.execute("UPDATE proposals SET status='rejected' WHERE id=? AND status='pending'", (token,))
            if cursor.rowcount != 1:
                raise ValueError('No pending proposal with that ID')

    def revise(self, token, step, validator):
        """Editing creates a new review and invalidates the old one atomically."""
        validator(step)
        if step['tool'] != 'message.prepare':
            raise ValueError('Only message drafts have a review')
        with self.db:
            cursor = self.db.execute("UPDATE proposals SET status='superseded' WHERE id=? AND status IN ('pending','approved_not_sent')", (token,))
            if cursor.rowcount != 1:
                raise ValueError('No editable proposal with that ID')
            return self._insert_proposal(step)

    def approve_review(self, token, validator):
        """One review, exact saved payload, no model replan and NO external dispatch."""
        self.db.execute('BEGIN IMMEDIATE')
        try:
            row = self.db.execute('SELECT * FROM proposals WHERE id=?', (token,)).fetchone()
            if not row or row['status'] != 'pending':
                raise ValueError('No pending proposal with that ID')
            if datetime.fromisoformat(row['expires_at']) <= now():
                raise ValueError('Proposal expired; request a fresh plan')
            if digest(row['payload']) != row['payload_hash']:
                raise ValueError('Payload changed; review a new proposal')
            step = json.loads(row['payload'])
            validator(step)
            if step['tool'] != 'message.prepare':
                raise ValueError('Only prepared demo messages have a review')
            self.db.execute("UPDATE proposals SET status='approved_not_sent' WHERE id=?", (token,))
            self.db.execute('INSERT INTO audit(event,detail,created_at) VALUES(?,?,?)',
                            ('review.approve', canonical({'proposal_id': token, 'payload_hash': row['payload_hash']}), now().isoformat()))
            self.db.commit()
            return {'status': 'approved_not_sent', 'proposal_id': token, 'payload_hash': row['payload_hash'],
                    'exact_action': step, 'sent': False,
                    'reason': 'No messaging connector or external executor exists in this starter'}
        except Exception:
            self.db.rollback()
            raise
