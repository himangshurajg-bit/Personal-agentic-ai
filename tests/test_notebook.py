"""Synthetic notebook data only: pagination, portability and read-only boundaries."""
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from agent.memory import Memory
from agent.core import run


class NotebookTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / 'notes.sqlite3'
        self.memory = Memory(self.path)

    def tearDown(self):
        self.memory.close()
        self.tmp.cleanup()

    def cli(self, *args):
        return subprocess.run([sys.executable, '-m', 'agent', '--db', str(self.path), *args],
                              text=True, capture_output=True, timeout=10)

    def test_unicode_literal_search(self):
        self.memory.add_note('École Straße Σίσυφος हिंदी 100% _')
        for query in ('éCOLE', 'STRASSE', 'σίσυφος', 'हिंदी', '%', '_', 'E\u0301cole'):
            with self.subTest(query=query):
                self.assertEqual(len(self.memory.search(query)), 1)
        self.assertEqual(self.memory.search('absent'), [])

    def test_normalization_is_not_transliteration(self):
        self.memory.add_note('café')
        self.assertEqual(self.memory.search('cafe'), [])

    def test_empty_notebook(self):
        self.assertEqual(self.memory.list_notes(), {'notes': [], 'next_before': None, 'has_more': False, 'limit': 20})

    def test_paging_no_duplicates_and_new_inserts_excluded(self):
        for i in range(45):
            self.memory.add_note(str(i))
        page = self.memory.list_notes()
        ids = [n['id'] for n in page['notes']]
        self.assertEqual(ids, list(range(45, 25, -1)))
        self.memory.add_note('new while browsing')
        while page['has_more']:
            page = self.memory.list_notes(before=page['next_before'])
            ids.extend(n['id'] for n in page['notes'])
        self.assertEqual(ids, list(range(45, 0, -1)))
        self.assertIsNone(page['next_before'])

    def test_exact_page_size_has_no_false_continuation(self):
        for i in range(20):
            self.memory.add_note(str(i))
        self.assertFalse(self.memory.list_notes()['has_more'])

    def test_filter_precedes_limit_and_cursor(self):
        for i in range(30):
            self.memory.add_note('target' if i % 2 else 'other')
        page = self.memory.list_notes('target', 3)
        self.assertEqual([n['id'] for n in page['notes']], [30, 28, 26])
        self.assertEqual([n['id'] for n in self.memory.list_notes('target', 3, page['next_before'])['notes']], [24, 22, 20])

    def test_invalid_limits(self):
        for value in (0, -1, 101, True, '20', None):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.memory.list_notes(limit=value)

    def test_invalid_cursors(self):
        for value in (0, -1, 2**63, True, '1', 1.2):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.memory.list_notes(before=value)

    def test_invalid_queries(self):
        for value in (None, 1, 'a' * 201):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.memory.list_notes(query=value)

    def test_export_notes_only_preserves_text(self):
        text = 'हिंदी\n<script>alert(1)</script>\t"École"'
        self.memory.add_note(text)
        run('draft private@example.test: not for export', self.memory)
        rows = list(self.memory.export_notes())
        self.assertEqual(rows[0]['text'], text)
        self.assertEqual(set(rows[0]), {'id', 'text', 'created_at'})
        self.assertNotIn('private@example', json.dumps(rows))
        self.assertEqual(len(self.memory.pending()), 1)

    def test_export_empty(self):
        self.assertEqual(list(self.memory.export_notes()), [])

    def test_read_only_handle_cannot_write(self):
        m = Memory(self.path, read_only=True)
        try:
            with self.assertRaises(sqlite3.OperationalError):
                m.add_note('not written')
        finally:
            m.close()
        self.assertEqual(self.memory.search('not written'), [])

    def test_cli_browse_and_export_do_not_mutate(self):
        self.memory.add_note('हिंदी\nfirst')
        self.memory.add_note('second')
        original = self.path.read_bytes()
        for args in (('notes', '--limit', '1'), ('export-notes',)):
            with self.subTest(args=args):
                result = self.cli(*args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.path.read_bytes(), original)
        data = json.loads(self.cli('notes', '--limit', '1').stdout)
        self.assertTrue(data['has_more'])
        self.assertEqual(data['next_before'], 2)
        rows = [json.loads(line) for line in self.cli('export-notes').stdout.splitlines()]
        self.assertEqual([n['text'] for n in rows], ['हिंदी\nfirst', 'second'])

    def test_cli_missing_database_not_created(self):
        other = Path(self.tmp.name) / 'missing' / 'memory.sqlite3'
        for cmd in ('notes', 'export-notes'):
            result = subprocess.run([sys.executable, '-m', 'agent', '--db', str(other), cmd], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('error', json.loads(result.stderr))
            self.assertNotIn('Traceback', result.stderr)
            self.assertFalse(other.parent.exists())

    def test_cli_invalid_cursor_rejected(self):
        for val in ('0', '-1', str(2**63)):
            self.assertEqual(self.cli('notes', '--before', val).returncode, 1)

    def test_listing_does_not_change_proposals_or_audit(self):
        run('draft nobody@example.test: review', self.memory)
        before = self.path.read_bytes()
        with patch('urllib.request.OpenerDirector.open', side_effect=AssertionError('no network')):
            self.memory.list_notes()
            list(self.memory.export_notes())
        self.assertEqual(self.path.read_bytes(), before)
