"""Opt-in, fake-only execution boundary for reviewed demo messages.

There is intentionally no live messaging adapter in this package. The fake adapter is useful
for state-machine tests and local demonstrations only; provider acceptance is never delivery.
"""
from copy import deepcopy


class FakeMessagingProvider:
    """Deterministic test/demo provider that performs no I/O."""

    def __init__(self, outcome='accepted'):
        if outcome not in ('accepted', 'rejected', 'unknown', 'timeout'):
            raise ValueError('Fake provider outcome must be accepted, rejected, unknown, or timeout')
        self.outcome = outcome
        self.calls = []

    def send(self, *, exact_action, payload_hash, idempotency_key):
        self.calls.append({'exact_action': deepcopy(exact_action),
                           'payload_hash': payload_hash,
                           'idempotency_key': idempotency_key})
        if self.outcome == 'timeout':
            raise TimeoutError('Simulated indeterminate fake-provider response')
        return self.outcome


def execute_fake_approved(memory, proposal_id, validator, provider, *, enabled=False):
    """Claim and invoke only the built-in fake provider; disabled unless explicitly enabled.

    A durable claim is committed before invocation. Repeated calls return the saved state and
    never invoke a provider again, including for a crashed or unknown outcome.
    """
    if enabled is not True:
        raise ValueError('Fake message execution is disabled unless explicitly enabled')
    if type(provider) is not FakeMessagingProvider:
        raise ValueError('Only the built-in fake messaging provider is permitted')

    claim = memory.claim_execution(proposal_id, validator)
    if not claim['claimed']:
        return {'state': claim['state'], 'proposal_id': proposal_id,
                'payload_hash': claim['payload_hash'],
                'idempotency_key': claim['idempotency_key'],
                'provider_called': False, 'sent': False,
                'meaning': 'No new provider call; delivery is not verified'}

    try:
        outcome = provider.send(exact_action=claim['exact_action'],
                                payload_hash=claim['payload_hash'],
                                idempotency_key=claim['idempotency_key'])
        if outcome not in ('accepted', 'rejected', 'unknown'):
            outcome = 'unknown'
    except Exception:
        # The request may have reached a provider before the exception; never retry it blindly.
        outcome = 'unknown'

    saved = memory.record_execution_outcome(proposal_id, claim['idempotency_key'], outcome)
    return {'state': saved['state'], 'proposal_id': proposal_id,
            'payload_hash': saved['payload_hash'],
            'idempotency_key': saved['idempotency_key'],
            'provider_called': True, 'sent': False,
            'meaning': 'Fake-provider result only; no real message was sent or verified'}
