"""Explicit local-planner check: fixed fictional prompt, no database or tool execution."""
import os
import platform
import re
from decimal import Decimal, InvalidOperation

from .core import validate_plan
from .providers import (ProviderUnavailable, local_config, local_runtime_version,
                        plan_with_provider)

CHECK_REQUEST = 'Calculate 2 + 2 using the calculator tool. Return one step only.'
CLOUD_SMOKE_ACK = 'I_ACCEPT_ONE_OPENAI_REQUEST'
CLOUD_SMOKE_MAX_TOKENS = 128


def check_local():
    """Validate one inference response, not the tool's result or model reliability.

    Missing setup/unreachable runtime is a skip. A responding runtime's malformed or
    unsupported plan fails. There is one inference attempt and no automatic retry.
    """
    report = {'provider': 'local', 'python_version': platform.python_version(),
              'runtime_version': None, 'runtime_version_status': 'not_attempted',
              'executed': False, 'attempts': 0,
              'notice': 'Schema check only; no tools, database or approvals used. '
                        'A valid plan does not prove task accuracy or production readiness.'}
    if not os.environ.get('LOCAL_AGENT_MODEL', ''):
        return {**report, 'status': 'skipped', 'reason': 'Set LOCAL_AGENT_MODEL to an already installed model'}
    try:
        endpoint, model = local_config()
    except ValueError:
        return {**report, 'status': 'failed', 'reason': 'Invalid local provider configuration'}
    report.update(endpoint=endpoint, model=model, attempts=1)
    report['runtime_version'] = local_runtime_version(endpoint)
    report['runtime_version_status'] = ('reported' if report['runtime_version'] is not None
                                        else 'unavailable_or_unrecognized')
    try:
        steps = validate_plan(plan_with_provider(CHECK_REQUEST, 'local'))
    except ProviderUnavailable:
        return {**report, 'status': 'skipped', 'reason': 'Local runtime unavailable; no retry or download attempted'}
    except (ValueError, OSError):
        return {**report, 'status': 'failed', 'reason': 'Local response failed transport, JSON or plan validation'}
    if not steps:
        return {**report, 'status': 'failed', 'reason': 'Local model returned an empty plan for the fixed check'}
    return {**report, 'status': 'schema_valid', 'step_count': len(steps),
            'tools': [step['tool'] for step in steps]}


def check_cloud():
    """Make one explicitly authorized, fixed-prompt cloud schema check.

    No caller prompt, tools, memory, database, retry or fallback is involved. The
    operator must supply credentials, a stated USD budget and an exact acknowledgement.
    The budget is disclosure/confirmation only; provider-side billing limits are needed
    for an enforceable monetary cap.
    """
    report = {'provider': 'cloud', 'python_version': platform.python_version(),
              'executed': False, 'attempts': 0,
              'notice': 'One fixed synthetic prompt; no tools, database or approvals used. '
                        'Schema validity does not prove model accuracy or readiness.'}
    key = os.environ.get('OPENAI_API_KEY', '')
    model = os.environ.get('CLOUD_AGENT_MODEL', '')
    budget_text = os.environ.get('CLOUD_AGENT_SMOKE_BUDGET_USD', '')
    approval = os.environ.get('CLOUD_AGENT_SMOKE_ACK', '')
    if not key or not model:
        return {**report, 'status': 'skipped', 'reason': 'Set OPENAI_API_KEY and CLOUD_AGENT_MODEL externally'}
    if not budget_text:
        return {**report, 'status': 'skipped', 'reason': 'Set an explicit CLOUD_AGENT_SMOKE_BUDGET_USD before the paid smoke'}
    if approval != CLOUD_SMOKE_ACK:
        return {**report, 'status': 'skipped', 'reason': 'Set CLOUD_AGENT_SMOKE_ACK to the documented one-request acknowledgement'}
    if not re.fullmatch(r'(?:0|[1-9][0-9]*)(?:\.[0-9]{1,2})?', budget_text):
        return {**report, 'status': 'failed', 'reason': 'Budget must be a positive USD amount with at most two decimals'}
    try:
        budget = Decimal(budget_text)
    except InvalidOperation:
        return {**report, 'status': 'failed', 'reason': 'Budget must be a positive USD amount with at most two decimals'}
    if not Decimal('0') < budget <= Decimal('1.00'):
        return {**report, 'status': 'failed', 'reason': 'Budget must be greater than zero and no more than 1.00 USD'}
    report.update(operator_budget_usd=f'{budget:.2f}', attempts=1)
    try:
        steps = validate_plan(plan_with_provider(CHECK_REQUEST, 'cloud',
                                                 max_completion_tokens=CLOUD_SMOKE_MAX_TOKENS))
    except ProviderUnavailable:
        return {**report, 'status': 'unknown_outcome',
                'reason': 'Provider transport ended without a confirmed response; no retry was made'}
    except (ValueError, OSError):
        return {**report, 'status': 'failed',
                'reason': 'Cloud response failed transport, JSON or plan validation; details were withheld'}
    if not steps:
        return {**report, 'status': 'failed', 'reason': 'Cloud model returned an empty plan for the fixed check'}
    return {**report, 'status': 'schema_valid', 'step_count': len(steps),
            'tools': [step['tool'] for step in steps]}
