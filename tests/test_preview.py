import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from agent import core
from agent.memory import Memory


class PlanPreviewTests(unittest.TestCase):
    def cli(self, *args):
        return subprocess.run([sys.executable, '-m', 'agent', *args],
                              text=True, capture_output=True, timeout=5)

    def test_exact_plan_and_risk_labels_without_execution(self):
        request = 'goal: calculate 12 * 3; remember Practice; find Practice; draft friend@example.test: Hello'
        with patch.object(core, 'execute_safe', side_effect=AssertionError('No execution')):
            result = core.preview(request)
        self.assertEqual(result['status'], 'preview')
        self.assertFalse(result['executed'])
        self.assertEqual(result['max_steps'], 4)
        self.assertEqual([s['position'] for s in result['steps']], [1, 2, 3, 4])
        self.assertEqual([s['risk'] for s in result['steps']],
                         ['read', 'local_prepare', 'read', 'external_review'])
        self.assertEqual([s['requires_review'] for s in result['steps']], [False, False, False, True])
        self.assertEqual(result['steps'][-1]['step']['args'],
                         {'recipient': 'friend@example.test', 'text': 'Hello'})
        self.assertNotIn('proposal_id', json.dumps(result))

    def test_validation_shared_with_run(self):
        for request in ('', ' ', 'x' * 4001, None, 4,
                        'goal: time; time; time; time; time', 'draft x: '):
            with self.subTest(request=request), self.assertRaises(ValueError):
                core.preview(request)

    def test_unknown_request_is_unsupported_not_success(self):
        result = core.preview('control all my apps')
        self.assertEqual(result['status'], 'unsupported')
        self.assertEqual(result['steps'], [])
        self.assertFalse(result['executed'])

    def test_whole_plan_validation_before_return(self):
        bad = {'steps': [{'tool': 'notes.add', 'args': {'text': 'valid'}},
                         {'tool': 'shell', 'args': {'command': 'anything'}}]}
        with patch.object(core, 'plan_with_provider', return_value=bad), self.assertRaises(ValueError):
            core.preview('time')

    def test_only_demo_provider_with_cloud_environment(self):
        env = {'OPENAI_API_KEY': 'fictional-unused', 'CLOUD_AGENT_MODEL': 'fictional',
               'LOCAL_AGENT_MODEL': 'fictional'}
        original = core.plan_with_provider
        with patch.dict(os.environ, env), patch.object(core, 'plan_with_provider', wraps=original) as planner, \
                patch('agent.providers.post_json', side_effect=AssertionError('No network')):
            self.assertEqual(core.preview('time')['provider'], 'demo')
            planner.assert_called_once_with('time', 'demo')

    def test_no_calculation_result_or_clock_read(self):
        result = core.preview('goal: calculate 1 / 0; time')
        self.assertEqual(result['status'], 'preview')
        self.assertNotIn('result', json.dumps(result['steps']))
        self.assertIn('not a guarantee', result['notice'])

    def test_cli_creates_no_database_or_approval(self):
        with tempfile.TemporaryDirectory() as directory:
            db = Path(directory) / 'not-created' / 'memory.sqlite3'
            result = self.cli('--db', str(db), 'plan', 'goal: remember Hello; draft x@example.test: Hello')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(json.loads(result.stdout)['executed'])
            self.assertFalse(db.parent.exists())

    def test_existing_memory_and_pending_reviews_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            db = Path(directory) / 'memory.sqlite3'
            memory = Memory(str(db))
            memory.add_note('original note')
            memory.close()
            before = db.read_bytes()
            result = self.cli('--db', str(db), 'plan', 'goal: remember New note; draft x@example.test: Hello')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(db.read_bytes(), before)
            memory = Memory(str(db))
            try:
                self.assertEqual(len(memory.search('original')), 1)
                self.assertEqual(memory.search('New note'), [])
                self.assertEqual(memory.pending(), [])
            finally:
                memory.close()

    def test_cli_structured_validation_error(self):
        result = self.cli('plan', 'goal: time; time; time; time; time')
        self.assertEqual(result.returncode, 1)
        self.assertIn('at most four', json.loads(result.stderr)['error'])
        self.assertNotIn('Traceback', result.stderr)

    def test_cli_has_no_network_provider_switch(self):
        result = self.cli('plan', 'time', '--provider', 'cloud')
        self.assertEqual(result.returncode, 2)
        self.assertIn('unrecognized arguments', result.stderr)

    def test_cli_escapes_untrusted_controls(self):
        result = self.cli('plan', 'remember Hello \x1b[31mred')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('\x1b', result.stdout)
        self.assertIn('\\u001b', result.stdout)
