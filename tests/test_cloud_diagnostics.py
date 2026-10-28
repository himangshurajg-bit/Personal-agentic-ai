"""Socket-free tests for the explicit cloud smoke gate."""
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from agent.diagnostics import (CHECK_REQUEST, CLOUD_SMOKE_ACK,
                               CLOUD_SMOKE_MAX_TOKENS, check_cloud)
from agent.__main__ import main

VALID = {'steps': [{'tool': 'calculator', 'args': {'expression': '2 + 2'}}]}
BASE_ENV = {
    'OPENAI_API_KEY': 'secret-fixture-key',
    'CLOUD_AGENT_MODEL': 'fixture-model',
    'CLOUD_AGENT_SMOKE_BUDGET_USD': '0.05',
    'CLOUD_AGENT_SMOKE_ACK': CLOUD_SMOKE_ACK,
}


class CloudDiagnosticTests(unittest.TestCase):
    def test_missing_credentials_or_model_skips_without_call(self):
        for name in ('OPENAI_API_KEY', 'CLOUD_AGENT_MODEL'):
            env = {**BASE_ENV, name: ''}
            with self.subTest(name=name), patch.dict(os.environ, env, clear=True), \
                    patch('agent.diagnostics.plan_with_provider') as call:
                report = check_cloud()
            self.assertEqual(report['status'], 'skipped')
            self.assertEqual(report['attempts'], 0)
            call.assert_not_called()

    def test_missing_budget_or_ack_skips_without_call(self):
        for name, value in (('CLOUD_AGENT_SMOKE_BUDGET_USD', ''),
                            ('CLOUD_AGENT_SMOKE_ACK', '')):
            with self.subTest(name=name), patch.dict(os.environ, {**BASE_ENV, name: value}, clear=True), \
                    patch('agent.diagnostics.plan_with_provider') as call:
                report = check_cloud()
            self.assertEqual(report['status'], 'skipped')
            self.assertEqual(report['attempts'], 0)
            call.assert_not_called()

    def test_invalid_budget_fails_without_call(self):
        for budget in ('0', '1.01', '-0.01', 'NaN', '0.001', '0.05 USD'):
            with self.subTest(budget=budget), patch.dict(
                    os.environ, {**BASE_ENV, 'CLOUD_AGENT_SMOKE_BUDGET_USD': budget}, clear=True), \
                    patch('agent.diagnostics.plan_with_provider') as call:
                report = check_cloud()
            self.assertEqual(report['status'], 'failed')
            self.assertEqual(report['attempts'], 0)
            call.assert_not_called()

    def test_fixed_synthetic_prompt_one_bounded_call_no_secret_in_report(self):
        with patch.dict(os.environ, BASE_ENV, clear=True), patch(
                'agent.diagnostics.plan_with_provider', return_value=VALID) as call:
            report = check_cloud()
        call.assert_called_once_with(CHECK_REQUEST, 'cloud',
                                     max_completion_tokens=CLOUD_SMOKE_MAX_TOKENS)
        self.assertEqual(report['status'], 'schema_valid')
        self.assertEqual(report['attempts'], 1)
        self.assertFalse(report['executed'])
        self.assertEqual(report['operator_budget_usd'], '0.05')
        self.assertEqual(report['tools'], ['calculator'])
        serialized = json.dumps(report)
        for private in ('secret-fixture-key', 'fixture-model', '2 + 2', 'OPENAI_API_KEY'):
            self.assertNotIn(private, serialized)

    def test_unknown_transport_outcome_is_not_retried_or_called_success(self):
        from agent.providers import ProviderUnavailable
        with patch.dict(os.environ, BASE_ENV, clear=True), patch(
                'agent.diagnostics.plan_with_provider', side_effect=ProviderUnavailable('private-marker')) as call:
            report = check_cloud()
        call.assert_called_once()
        self.assertEqual(report['status'], 'unknown_outcome')
        self.assertEqual(report['attempts'], 1)
        self.assertNotIn('private-marker', json.dumps(report))

    def test_cli_skip_is_json_and_does_not_initialize_database(self):
        with tempfile.TemporaryDirectory() as directory:
            db = Path(directory) / 'unused.sqlite3'
            out = __import__('io').StringIO()
            with patch.dict(os.environ, {'AGENT_DB': str(db)}, clear=True), \
                    patch('sys.argv', ['agent', 'check-cloud']), \
                    patch('sys.stdout', out):
                code = main()
            self.assertEqual(code, 0)
            self.assertEqual(json.loads(out.getvalue())['status'], 'skipped')
            self.assertFalse(db.exists())
