"""Risk-based explicit registry; no real external action handlers exist."""
import ast
import math
import operator
from datetime import datetime, timezone

# Reads and local reversible preparation do not ask for approval.
# A prepared message requires exact-payload review before any future dispatch.
REGISTRY = {
    'calculator': {'fields': {'expression': 200}, 'risk': 'read'},
    'notes.search': {'fields': {'query': 200}, 'risk': 'read'},
    'notes.add': {'fields': {'text': 2000}, 'risk': 'local_prepare'},
    'message.prepare': {'fields': {'recipient': 200, 'text': 2000}, 'risk': 'external_review'},
    'clock': {'fields': {}, 'risk': 'read'},
}


def validate_step(step):
    if not isinstance(step, dict) or set(step) != {'tool', 'args'}:
        raise ValueError('Each step must contain only tool and args')
    if not isinstance(step['tool'], str) or step['tool'] not in REGISTRY:
        raise ValueError('Tool is not allowed')
    fields = REGISTRY[step['tool']]['fields']
    args = step['args']
    if not isinstance(args, dict) or set(args) != set(fields):
        raise ValueError('Wrong tool arguments')
    for field, limit in fields.items():
        value = args[field]
        if not isinstance(value, str) or not value.strip() or len(value) > limit:
            raise ValueError('Argument must be nonempty text within the documented limit')


def calculate(expression):
    if len(expression) > 200:
        raise ValueError('Expression too long')
    tree = ast.parse(expression, mode='eval')
    if sum(1 for _ in ast.walk(tree)) > 60:
        raise ValueError('Expression too complex')
    binary = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
              ast.Div: operator.truediv, ast.FloorDiv: operator.floordiv, ast.Mod: operator.mod}
    unary = {ast.UAdd: operator.pos, ast.USub: operator.neg}

    def evaluate(node):
        if isinstance(node, ast.Constant) and type(node.value) in (int, float):
            value = node.value
        elif isinstance(node, ast.BinOp) and type(node.op) in binary:
            value = binary[type(node.op)](evaluate(node.left), evaluate(node.right))
        elif isinstance(node, ast.UnaryOp) and type(node.op) in unary:
            value = unary[type(node.op)](evaluate(node.operand))
        else:
            raise ValueError('Only numbers, + - * / // % and parentheses are supported')
        if not math.isfinite(value) or abs(value) > 1e12:
            raise ValueError('Result out of bounds')
        return value
    return evaluate(tree.body)


def execute_safe(step, memory):
    validate_step(step)
    name, args = step['tool'], step['args']
    if REGISTRY[name]['risk'] not in ('read', 'local_prepare'):
        raise ValueError('External actions must go through exact-payload review')
    if name == 'calculator':
        return {'value': calculate(args['expression'])}
    if name == 'notes.search':
        return {'notes': memory.search(args['query'])}
    if name == 'notes.add':
        return memory.add_note(args['text'])
    if name == 'clock':
        return {'utc_time': datetime.now(timezone.utc).isoformat()}
    raise ValueError('No safe handler')
