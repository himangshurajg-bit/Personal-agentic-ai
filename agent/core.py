"""Bounded autonomy: validate once, perform safe work, stop at external review."""
from .providers import plan_with_provider
from .tools import REGISTRY, execute_safe, validate_step


def validate_plan(plan):
    if not isinstance(plan, dict) or set(plan) != {'steps'}:
        raise ValueError('Plan must contain only steps')
    if not isinstance(plan['steps'], list) or len(plan['steps']) > 4:
        raise ValueError('Plan must have at most four steps')
    for step in plan['steps']:
        validate_step(step)
    return plan['steps']


def _request_plan(request, provider):
    if not isinstance(request, str) or not request.strip() or len(request) > 4000:
        raise ValueError('Request must be 1–4000 nonblank characters')
    return validate_plan(plan_with_provider(request, provider))


def preview(request):
    """Inspect an offline demo plan without reading memory or executing any step.

    A preview is not an approval token, resumable checkpoint or execution result.
    It deliberately cannot select a network-backed planner.
    """
    steps = _request_plan(request, 'demo')
    return {'status': 'preview' if steps else 'unsupported', 'provider': 'demo',
            'executed': False, 'max_steps': 4,
            'steps': [{'position': i, 'step': step,
                       'risk': REGISTRY[step['tool']]['risk'],
                       'requires_review': REGISTRY[step['tool']]['risk'] == 'external_review'}
                      for i, step in enumerate(steps, 1)],
            'notice': 'Preview only: no tools, database or network used. No approval was created. '
                      'A later run is validated again and requires exact review for drafts. '
                      'Argument validation is not a guarantee that a tool will succeed.'}


def run(request, memory, provider='demo'):
    steps = _request_plan(request, provider)
    if not steps:
        return {'status': 'unsupported', 'help': 'Try: calculate 2 + 2, remember a note, find a word, time, or draft RECIPIENT: TEXT.'}
    results = []
    for step in steps:
        if REGISTRY[step['tool']]['risk'] == 'external_review':
            token = memory.propose(step)
            results.append({'status': 'awaiting_approval', 'proposal_id': token, 'exact_action': step,
                            'expires_in_minutes': 15, 'sent': False})
        else:
            try:
                results.append({'status': 'completed', 'step': step, 'result': execute_safe(step, memory)})
            except (ValueError, SyntaxError, ZeroDivisionError, OverflowError, RecursionError):
                results.append({'status': 'failed', 'step': step, 'error': 'Tool rejected the input or could not calculate it'})
                break
    return {'status': 'processed', 'provider': provider, 'plan': steps, 'results': results,
            'note': 'Safe steps ran without repeated permission; drafts are not sent.'}
