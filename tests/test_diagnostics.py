"""Socket-free tests for the opt-in, side-effect-free local model check."""
import contextlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from agent.__main__ import main
from agent.diagnostics import CHECK_REQUEST, check_local
from agent.providers import ProviderUnavailable, local_config

VALID = {'steps': [{'tool': 'calculator', 'args': {'expression': '2 + 2'}}]}


class DiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {'LOCAL_AGENT_MODEL': 'fictional-model',
                                          'LOCAL_AGENT_URL': 'http://127.0.0.1:11434'})
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_missing_model_skips_without_network(self):
        with patch.dict(os.environ, {'LOCAL_AGENT_MODEL': ''}), patch('agent.diagnostics.plan_with_provider') as call:
            result = check_local()
        self.assertEqual(result['status'], 'skipped')
        self.assertEqual(result['attempts'], 0)
        call.assert_not_called()

    def test_invalid_config_fails_before_network(self):
        for endpoint in ('https://example.test', 'http://127.0.0.1:bad', 'http://user:secret@localhost',
                         'http://localhost/private', 'http://localhost:0', 'http://localhost:65536'):
            with self.subTest(endpoint=endpoint), patch.dict(os.environ, {'LOCAL_AGENT_URL': endpoint}), \
                    patch('agent.diagnostics.plan_with_provider') as call:
                result = check_local()
                self.assertEqual(result['status'], 'failed')
                self.assertEqual(result['attempts'], 0)
                self.assertNotIn('secret', json.dumps(result))
                call.assert_not_called()

    def test_fixed_prompt_one_attempt_and_no_step_arguments_in_report(self):
        with patch('agent.diagnostics.plan_with_provider', return_value=VALID) as call:
            result = check_local()
        call.assert_called_once_with(CHECK_REQUEST, 'local')
        self.assertEqual(result['status'], 'schema_valid')
        self.assertEqual(result['tools'], ['calculator'])
        self.assertEqual(result['attempts'], 1)
        self.assertFalse(result['executed'])
        self.assertIsNone(result['runtime_version'])
        self.assertNotIn('expression', json.dumps(result))

    def test_no_safe_or_external_steps_are_executed(self):
        plan = {'steps': [{'tool': 'notes.add', 'args': {'text': 'private-marker'}},
                          {'tool': 'message.prepare', 'args': {'recipient': 'fictional@example.test',
                                                               'text': 'private-marker'}}]}
        with patch('agent.diagnostics.plan_with_provider', return_value=plan), \
                patch('agent.core.execute_safe') as execute, patch('agent.__main__.Memory') as memory:
            result = check_local()
        self.assertEqual(result['status'], 'schema_valid')
        execute.assert_not_called()
        memory.assert_not_called()
        self.assertNotIn('private-marker', json.dumps(result))
        self.assertNotIn('fictional@example.test', json.dumps(result))

    def test_empty_or_invalid_plan_fails(self):
        for plan in ({'steps': []}, {'steps': [{'tool': 'shell', 'args': {}}]},
                     {'steps': [{'tool': 'clock', 'args': {'extra': 'private-marker'}}]},
                     {'steps': [{'tool': 'clock', 'args': {}}] * 5}, [], {'steps': [], 'extra': True}):
            with self.subTest(plan=plan), patch('agent.diagnostics.plan_with_provider', return_value=plan):
                result = check_local()
                self.assertEqual(result['status'], 'failed')
                self.assertNotIn('private-marker', json.dumps(result))

    def test_unreachable_runtime_skips_without_retry(self):
        with patch('agent.diagnostics.plan_with_provider', side_effect=ProviderUnavailable('private-marker')) as call:
            result = check_local()
        self.assertEqual(result['status'], 'skipped')
        self.assertEqual(call.call_count, 1)
        self.assertNotIn('private-marker', json.dumps(result))

    def test_response_errors_are_sanitized_not_retried(self):
        for exc in (ValueError('private-marker'), OSError('private-marker')):
            with self.subTest(error=type(exc)), patch('agent.diagnostics.plan_with_provider', side_effect=exc) as call:
                result = check_local()
                self.assertEqual(result['status'], 'failed')
                self.assertEqual(call.call_count, 1)
                self.assertNotIn('private-marker', json.dumps(result))

    def test_cli_does_not_open_or_create_database(self):
        with tempfile.TemporaryDirectory() as directory:
            db = Path(directory) / 'missing' / 'memory.sqlite3'
            with patch.object(sys, 'argv', ['agent', '--db', str(db), 'check-local']), \
                    patch('agent.diagnostics.plan_with_provider', return_value=VALID), \
                    patch('agent.__main__.Memory') as memory, contextlib.redirect_stdout(io.StringIO()) as output:
                code = main()
            self.assertEqual(code, 0)
            self.assertEqual(json.loads(output.getvalue())['status'], 'schema_valid')
            self.assertFalse(db.parent.exists())
            memory.assert_not_called()

    def test_cli_failed_and_skip_exit_codes(self):
        for plan, expected in ((VALID, 0), ({'steps': []}, 1)):
            with patch.object(sys, 'argv', ['agent', 'check-local']), \
                    patch('agent.diagnostics.plan_with_provider', return_value=plan), \
                    contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(main(), expected)
        with patch.dict(os.environ, {'LOCAL_AGENT_MODEL': ''}), \
                patch.object(sys, 'argv', ['agent', 'check-local']), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(), 0)

    def test_local_config_retains_loopback_ipv6(self):
        with patch.dict(os.environ, {'LOCAL_AGENT_URL': 'http://[::1]:11434/'}):
            self.assertEqual(local_config(), ('http://[::1]:11434', 'fictional-model'))
