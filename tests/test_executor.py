import threading
import unittest
from pathlib import Path
import tempfile

from agent.core import run, validate_step
from agent.execution import FakeMessagingProvider, execute_fake_approved
from agent.memory import Memory, digest


class FakeExecutionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / 'memory.sqlite3'
        self.memory = Memory(self.path)

    def tearDown(self):
        self.memory.close()
        self.tmp.cleanup()

    def proposal(self, text='Hello'):
        result = run('draft friend@example.test: ' + text, self.memory)
        return result['results'][0]['proposal_id']

    def approved(self, text='Hello'):
        token = self.proposal(text)
        result = self.memory.approve_review(token, validate_step)
        self.assertFalse(result['sent'])
        return token, result

    def execute(self, token, provider=None):
        return execute_fake_approved(self.memory, token, validate_step,
                                     provider or FakeMessagingProvider(), enabled=True)

    def test_execution_is_disabled_by_default_and_rejects_live_adapter(self):
        token, _ = self.approved()
        fake = FakeMessagingProvider()
        with self.assertRaisesRegex(ValueError, 'disabled'):
            execute_fake_approved(self.memory, token, validate_step, fake)
        self.assertEqual(fake.calls, [])
        with self.assertRaisesRegex(ValueError, 'built-in fake'):
            execute_fake_approved(self.memory, token, validate_step, object(), enabled=True)
        self.assertIsNone(self.memory.execution_status(token))

    def test_exact_payload_hash_and_idempotency_are_bound_to_claim(self):
        token, approved = self.approved('Exact draft')
        provider = FakeMessagingProvider()
        result = self.execute(token, provider)
        self.assertEqual(provider.calls[0]['exact_action'], approved['exact_action'])
        self.assertEqual(provider.calls[0]['payload_hash'], approved['payload_hash'])
        self.assertEqual(result['payload_hash'], digest(self.memory.db.execute(
            'SELECT payload FROM proposals WHERE id=?', (token,)).fetchone()[0]))
        self.assertEqual(provider.calls[0]['idempotency_key'], result['idempotency_key'])
        self.assertEqual(result['state'], 'provider_accepted')
        self.assertFalse(result['sent'])

    def test_duplicate_execution_never_calls_provider_twice(self):
        token, _ = self.approved()
        provider = FakeMessagingProvider('accepted')
        first = self.execute(token, provider)
        second = self.execute(token, provider)
        self.assertEqual(len(provider.calls), 1)
        self.assertTrue(first['provider_called'])
        self.assertFalse(second['provider_called'])
        self.assertEqual(first['idempotency_key'], second['idempotency_key'])
        self.assertEqual(second['state'], 'provider_accepted')
        self.assertFalse(second['sent'])

    def test_rejected_or_stale_review_cannot_be_claimed(self):
        token = self.proposal()
        self.memory.reject(token)
        with self.assertRaisesRegex(ValueError, 'approved, unclaimed'):
            self.execute(token, FakeMessagingProvider())
        token, _ = self.approved()
        self.memory.db.execute('UPDATE proposals SET expires_at=? WHERE id=?',
                               ('2000-01-01T00:00:00+00:00', token))
        self.memory.db.commit()
        with self.assertRaisesRegex(ValueError, 'expired'):
            self.execute(token, FakeMessagingProvider())

    def test_edited_saved_payload_cannot_be_claimed_after_review(self):
        token, _ = self.approved('Original')
        self.memory.db.execute('UPDATE proposals SET payload=? WHERE id=?',
                               ('{"tool":"message.prepare","args":{"recipient":"evil@example.test","text":"Edited"}}', token))
        self.memory.db.commit()
        with self.assertRaisesRegex(ValueError, 'Payload changed'):
            self.execute(token, FakeMessagingProvider())
        self.assertIsNone(self.memory.execution_status(token))

    def test_payload_hash_mismatch_before_approval_is_rejected(self):
        token = self.proposal()
        self.memory.db.execute('UPDATE proposals SET payload=? WHERE id=?',
                               ('{"tool":"message.prepare","args":{"recipient":"evil@example.test","text":"Edited"}}', token))
        self.memory.db.commit()
        with self.assertRaisesRegex(ValueError, 'Payload changed'):
            self.memory.approve_review(token, validate_step)

    def test_provider_rejection_is_persisted_and_not_retried(self):
        token, _ = self.approved()
        provider = FakeMessagingProvider('rejected')
        result = self.execute(token, provider)
        self.assertEqual(result['state'], 'provider_rejected')
        self.assertFalse(result['sent'])
        self.execute(token, provider)
        self.assertEqual(len(provider.calls), 1)

    def test_unknown_outcome_is_terminal_for_dispatch_and_can_be_reconciled(self):
        token, _ = self.approved()
        provider = FakeMessagingProvider('unknown')
        first = self.execute(token, provider)
        self.assertEqual(first['state'], 'unknown')
        second = self.execute(token, provider)
        self.assertFalse(second['provider_called'])
        self.assertEqual(len(provider.calls), 1)
        resolved = self.memory.reconcile_execution(token, first['idempotency_key'], 'accepted')
        self.assertEqual(resolved['state'], 'reconciled_accepted')
        self.assertEqual(resolved['resolution'], 'accepted')
        again = self.execute(token, provider)
        self.assertEqual(again['state'], 'reconciled_accepted')
        self.assertFalse(again['provider_called'])
        with self.assertRaisesRegex(ValueError, 'unresolved execution'):
            self.memory.reconcile_execution(token, first['idempotency_key'], 'not_accepted')
        self.assertEqual(len(provider.calls), 1)

    def test_reconciliation_can_record_definite_nonacceptance(self):
        token, _ = self.approved()
        claim = self.memory.claim_execution(token, validate_step)
        resolved = self.memory.reconcile_execution(token, claim['idempotency_key'], 'not_accepted')
        self.assertEqual(resolved['state'], 'reconciled_not_accepted')
        self.assertEqual(resolved['resolution'], 'not_accepted')
        self.assertFalse(self.execute(token, FakeMessagingProvider())['provider_called'])

    def test_exception_after_claim_is_unknown_and_never_retried(self):
        token, _ = self.approved()

        # A deterministic fake timeout models a request whose external result cannot be known.
        provider = FakeMessagingProvider('timeout')
        first = self.execute(token, provider)
        self.assertEqual(first['state'], 'unknown')
        self.assertFalse(self.execute(token, provider)['provider_called'])
        self.assertEqual(len(provider.calls), 1)

    def test_reject_after_claim_cannot_cancel_or_reopen(self):
        token, _ = self.approved()
        self.memory.claim_execution(token, validate_step)
        with self.assertRaisesRegex(ValueError, 'already claimed'):
            self.memory.reject(token)
        with self.assertRaisesRegex(ValueError, 'editable proposal'):
            self.memory.revise(token, {'tool': 'message.prepare', 'args': {
                'recipient': 'friend@example.test', 'text': 'Changed'}}, validate_step)

    def test_parallel_claims_have_one_winner(self):
        token, _ = self.approved()
        results = []
        errors = []
        barrier = threading.Barrier(2)

        def claim():
            connection = Memory(self.path)
            try:
                barrier.wait()
                results.append(connection.claim_execution(token, validate_step))
            except Exception as exc:
                errors.append(exc)
            finally:
                connection.close()

        threads = [threading.Thread(target=claim) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=5)
        self.assertFalse(any(thread.is_alive() for thread in threads))
        self.assertEqual(errors, [])
        self.assertEqual(sum(bool(result['claimed']) for result in results), 1)
        self.assertEqual(len({result['idempotency_key'] for result in results}), 1)
        self.assertEqual(self.memory.db.execute('SELECT count(*) FROM executions WHERE proposal_id=?',
                                                (token,)).fetchone()[0], 1)

    def test_approve_still_reports_not_sent(self):
        token = self.proposal()
        result = self.memory.approve_review(token, validate_step)
        self.assertEqual(result['status'], 'approved_not_sent')
        self.assertIs(result['sent'], False)
        self.assertIn('No messaging connector', result['reason'])


if __name__ == '__main__':
    unittest.main()
