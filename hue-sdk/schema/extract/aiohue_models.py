"""Prints the dataclasses and enums of aiohue's v2 models (aiohue/v2/models) as JSON, reading their sources."""
import ast
import json
import pathlib
import sys


def enum(node):
    bases = [ast.unparse(base) for base in node.bases]
    constants = [s for s in node.body if isinstance(s, ast.Assign) and isinstance(s.value, ast.Constant)]
    plain = not node.decorator_list and constants and all(isinstance(s, (ast.Assign, ast.Expr)) for s in node.body)
    return any(base.endswith('Enum') for base in bases) or plain


def dataclass(node):
    fields = [{'name': s.target.id, 'type': ast.unparse(s.annotation),
               'default': None if s.value is None else ast.unparse(s.value)}
              for s in node.body if isinstance(s, ast.AnnAssign) and isinstance(s.target, ast.Name)]
    return {'bases': [ast.unparse(base) for base in node.bases], 'fields': fields}


classes, enums = {}, {}
for path in sorted(pathlib.Path(sys.argv[1]).glob('*.py')):
    for node in ast.parse(path.read_text()).body:
        if not isinstance(node, ast.ClassDef):
            continue
        if enum(node):
            enums[node.name] = {'values': [ast.literal_eval(s.value) for s in node.body
                                           if isinstance(s, ast.Assign) and isinstance(s.value, ast.Constant)]}
        elif any(ast.unparse(decorator) == 'dataclass' for decorator in node.decorator_list):
            classes[node.name] = dataclass(node)
json.dump({'classes': classes, 'enums': enums}, sys.stdout, indent=1)
