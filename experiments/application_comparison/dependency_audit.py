"""Static application-entry dependency inventory; not proof against dynamic loading."""
import ast
import hashlib
from pathlib import Path
import re
import sys
from .storage import digest

TOKEN = re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|\\\\[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[A-Za-z_][A-Za-z_0-9]*|[^\s]')


def tokens(source):
    return [match.group() for match in TOKEN.finditer(source)
            if not match.group().startswith(('//', '/*', '\\\\'))]


def audit(root, language, entry):
    root = Path(root).resolve(strict=True)
    if language not in ('python', 'zig', 'my'):
        raise ValueError('unsupported audit language')
    queue, visited, edges, review = [entry], {}, [], []
    while queue:
        name = queue.pop()
        path = (root / name).resolve(strict=True)
        if not path.is_relative_to(root):
            raise ValueError('application dependency leaves source root')
        relative = path.relative_to(root).as_posix()
        if relative in visited:
            continue
        data = path.read_bytes()
        source = data.decode('utf-8')
        visited[relative] = hashlib.sha256(data).hexdigest()
        imports = []
        if language == 'python':
            tree = ast.parse(source, filename=relative)
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    imports.extend(alias.name for alias in node.names)
                elif isinstance(node, ast.ImportFrom):
                    if node.level:
                        review.append({'file': relative, 'reason': 'relative Python import requires package review'})
                    elif node.module:
                        imports.append(node.module)
                elif isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in ('exec', 'eval', '__import__'):
                    review.append({'file': relative, 'reason': 'dynamic Python execution/import', 'line': node.lineno})
            for target in imports:
                local = root / (target.replace('.', '/') + '.py')
                package = root / target.replace('.', '/') / '__init__.py'
                if package.is_file():
                    kind = 'local'
                    queue.append(package.relative_to(root).as_posix())
                    review.append({'file': relative, 'reason': 'local Python package requires package review'})
                elif local.is_file():
                    kind = 'local'
                    queue.append(local.relative_to(root).as_posix())
                    if '.' in target:
                        review.append({'file': relative, 'reason': 'dotted local import requires package review'})
                elif target.split('.')[0] in sys.stdlib_module_names:
                    kind = 'stdlib'
                    if target.split('.')[0] in ('importlib', 'ctypes', 'subprocess'):
                        review.append({'file': relative, 'reason': 'dynamic loading or external execution capability', 'module': target})
                else:
                    kind = 'unresolved'
                    review.append({'file': relative, 'reason': 'unresolved Python dependency', 'module': target})
                edges.append({'file': relative, 'target': target, 'kind': kind})
        else:
            words = tokens(source)
            for index, word in enumerate(words):
                if language == 'zig' and word == '@' and index + 1 < len(words):
                    builtin = words[index + 1]
                    if builtin == 'import':
                        if words[index + 2:index + 3] != ['('] or index + 4 >= len(words) or not words[index + 3].startswith('"') or words[index + 4] != ')':
                            review.append({'file': relative, 'reason': 'nonliteral Zig import'})
                        else:
                            imports.append(ast.literal_eval(words[index + 3]))
                    elif builtin in ('cImport', 'embedFile'):
                        review.append({'file': relative, 'reason': 'external Zig dependency capability', 'builtin': builtin})
                elif language == 'zig' and word == 'extern':
                    review.append({'file': relative, 'reason': 'external Zig symbol declaration'})
                elif language == 'my' and word == 'import':
                    if index + 2 < len(words) and words[index + 2] == ';':
                        imports.append(words[index + 1])
                    else:
                        review.append({'file': relative, 'reason': 'unrecognized .my import'})
                elif language == 'my' and word == 'host':
                    if words[index + 1:index + 2] == ['fn']:
                        edges.append({'file': relative, 'target': words[index + 2], 'kind': 'host-declaration'})
                        if relative != 'io.my' or words[index + 2] not in ('length', 'byte', 'put'):
                            review.append({'file': relative, 'reason': 'host declaration outside raw byte interface'})
            for target in imports:
                if language == 'zig' and target in ('std', 'builtin'):
                    kind = 'stdlib'
                else:
                    local = path.parent / target if language == 'zig' else root / (target + '.my')
                    if not local.is_file():
                        kind = 'unresolved'
                        review.append({'file': relative, 'reason': 'unresolved dependency', 'module': target})
                    else:
                        if not local.resolve().is_relative_to(root):
                            raise ValueError('application dependency leaves source root')
                        kind = 'local'
                        queue.append(local.relative_to(root).as_posix())
                edges.append({'file': relative, 'target': target, 'kind': kind})
    body = {'version': 'application-dependency-inventory-v1', 'language': language, 'entry': entry,
            'files': visited, 'edges': edges, 'review_required': review,
            'scope': 'static imports reachable from application entry; auxiliary test tools excluded',
            'stdlib_only_proven': False}
    return dict(body, sha256=digest(body))
