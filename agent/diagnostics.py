"""Explicit local-planner check: fixed fictional prompt, no database or tool execution."""
import os
import platform

from .core import validate_plan
from .providers import ProviderUnavailable, local_config, plan_with_provider

CHECK_REQUEST = 'Calculate 2 + 2 using the calculator tool. Return one step only.'


def check_local():
    """Validate one inference response, not the tool's result or model reliability.

    Missing setup/unreachable runtime is a skip. A responding runtime's malformed or
    unsupported plan fails. There is one inference attempt and no automatic retry.
    """
    report = {'provider': 'local', 'python_version': platform.python_version(),
              'runtime_version': None, 'executed': False, 'attempts': 0,
              'notice': 'Schema check only; no tools, database or approvals used. '
                        'A valid plan does not prove task accuracy or production readiness.'}
    if not os.environ.get('LOCAL_AGENT_MODEL', ''):
        return {**report, 'status': 'skipped', 'reason': 'Set LOCAL_AGENT_MODEL to an already installed model'}
    try:
        endpoint, model = local_config()
    except ValueError:
        return {**report, 'status': 'failed', 'reason': 'Invalid local provider configuration'}
    report.update(endpoint=endpoint, model=model, attempts=1)
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
