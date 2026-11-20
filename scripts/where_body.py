#!/usr/bin/env python3
"""where_body.py: the declaration finder behind `where.py NAME... --body` and `where.py --around PATH:LINE [N]`.

It answers one question for an agent that has just found a name or a line: which lines are the declaration that holds it, so
that the next step can edit them. A declaration is a Zig `fn`, `test`, `const`, `var` or type (`const T = struct`), a C function,
macro, type or global, a Selka `func`, `record`, `enum`, `const` or `type`, a Python `def`, `class` or top-level assignment,
or a shell function or top-level assignment. The first line of a declaration is the first line of the doc comment (Zig `///`,
`#` in Selka, Python and shell, `//` or a block in C) or of the decorators above it; its last line is where its brackets close
(Zig, C) or the last line indented under it (Selka, Python).

It does not parse: comments and the inside of strings are blanked with a regular expression, and a line is a declaration when it
starts like one. It reads files, never builds, and keeps nothing between runs (`git grep` finds the files that may hold a name).
"""
import re
import subprocess
from pathlib import Path
from typing import NamedTuple

BODY_LINES = 60
CALL_LINES = 150
LIST_MATCHES = 12
AROUND_DEFAULT = 21
LINE_CHARS = 300
SEARCH = ('src', 'test', 'scripts', 'tests/lang')
LANGS = {'.zig': 'zig', '.c': 'c', '.h': 'c', '.selka': 'selka', '.py': 'py', '.sh': 'sh'}
NAME = re.compile(r'^[A-Za-z_]\w*$')
C_NOT_FN = {'__attribute__', 'if', 'for', 'while', 'switch', 'return', 'else', 'case', 'typedef', 'enum', 'union', 'define',
             'sizeof', 'struct'}


class Decl(NamedTuple):
    """One declaration: `first` is the first line with its doc comment, `line` the line that names it; both 1-based."""
    path: str
    first: int
    line: int
    last: int
    kind: str
    name: str


class Raw(NamedTuple):
    """A declaration line as the scanner sees it: `tier` 2 is a name too common to offer unless nothing else matches."""
    name: str
    kind: str
    i: int
    tier: int


def lang_of(path):
    """'zig', 'c', 'selka', 'py' or 'sh' from the extension, else None."""
    return LANGS.get(path[path.rfind('.'):]) if '.' in path.rsplit('/', 1)[-1] else None


def indent(s):
    return len(s) - len(s.lstrip(' '))


def is_test_path(path):
    """A test, fixture or golden file: it ranks after the code it tests when a name is declared in both."""
    base = path.rsplit('/', 1)[-1]
    return path.startswith(('test/', 'tests/')) or '/fixtures/' in path or '_test' in base or base.startswith('test_')


def _mask_with(pattern, comment_ok=None):
    def one(m):
        s = m.group(0)
        if s[0] in '"\'':
            tail = s[-1] if len(s) > 1 and s[-1] == s[0] else ''
            return s[0] + ' ' * (len(s) - 1 - len(tail)) + tail
        if comment_ok and not comment_ok(m):
            return s
        return ' ' * len(s)
    return lambda line: pattern.sub(one, line)


def _sh_comment(m):
    return m.start() == 0 or m.string[m.start() - 1] in ' \t;&|('


_STRINGS = r'"(?:[^"\\]|\\.)*"?'
_MASKERS = {
    'zig': _mask_with(re.compile(_STRINGS + r"|'(?:\\.[^']*|[^'\\])'|//.*")),
    'sh': _mask_with(re.compile(_STRINGS + r"|'[^']*'?|#.*"), _sh_comment),
}
_TRIGGERS = {'zig': '"\'/', 'sh': '"\'#'}
_PY_TOKEN = re.compile(r'"""|\'\'\'|' + _STRINGS + r"|'(?:[^'\\]|\\.)*'?|#.*")
_C_TOKEN = re.compile(_STRINGS + r"|'(?:[^'\\]|\\.)*'?|//.*|/\*.*?\*/|/\*.*")


def mask(raw, lang):
    """Each line with comments and the inside of strings blanked (Zig `\\\\` lines, C block comments and Python and Selka triple
    quotes too), same length, so that brackets and keywords found in what is left are code."""
    out = []
    if lang in _MASKERS:
        fn, triggers = _MASKERS[lang], _TRIGGERS[lang]
        for s in raw:
            if lang == 'zig' and s.lstrip().startswith('\\\\'):
                out.append(' ' * len(s))
            else:
                out.append(fn(s) if any(c in s for c in triggers) else s)
        return out
    state = None
    for s in raw:
        res, pos = [], 0
        while pos < len(s):
            if state == 'c':
                k = s.find('*/', pos)
                end = len(s) if k < 0 else k + 2
                res.append(' ' * (end - pos))
                state, pos = (state if k < 0 else None), end
                continue
            if state:
                k = s.find(state, pos)
                end = len(s) if k < 0 else k + 3
                res.append(' ' * (end - pos))
                state, pos = (state if k < 0 else None), end
                continue
            m = (_C_TOKEN if lang == 'c' else _PY_TOKEN).search(s, pos)
            if not m:
                res.append(s[pos:])
                break
            res.append(s[pos:m.start()])
            tok = m.group(0)
            if tok in ('"""', "'''"):
                res.append(' ' * 3)
                state, pos = tok, m.end()
            elif tok.startswith('/*') and not tok.endswith('*/'):
                res.append(' ' * len(tok))
                state, pos = 'c', m.end()
            elif tok[0] in '"\'':
                tail = tok[-1] if len(tok) > 1 and tok[-1] == tok[0] else ''
                res.append(tok[0] + ' ' * (len(tok) - 1 - len(tail)) + tail)
                pos = m.end()
            else:
                res.append(' ' * len(tok))
                pos = m.end()
        out.append(''.join(res))
    return out


ZIG_FN = re.compile(r'^(\s*)(?:(?:pub|export|inline|noinline|extern(?:\s+"[^"]*")?)\s+)*fn\s+([A-Za-z_]\w*)\s*\(')
ZIG_TEST = re.compile(r'^(\s*)test\s+(?:"([^"]*)"|([A-Za-z_]\w*))\s*\{')
ZIG_CONST = re.compile(r'^(\s*)(pub\s+)?(?:(?:export|extern|threadlocal|comptime|inline)\s+)*(const|var)\s+([A-Za-z_]\w*)\b(.*)$')
ZIG_TYPE = re.compile(r'^\s*(?:=\s*)?(?:packed\s+|extern\s+)?(struct|enum|union|opaque)\b')
C_FN = re.compile(r'^(?:[A-Za-z_][\w\s\*]*?\b)?([A-Za-z_]\w*)\s*\(')
C_TYPE_LINE = re.compile(r'^[A-Za-z_][\w\s\*]*$')
C_MACRO = re.compile(r'^\s*#\s*define\s+([A-Za-z_]\w*)')
C_TAG = re.compile(r'^(?:typedef\s+)?(struct|union|enum)\s+([A-Za-z_]\w*)\s*\{')
C_TYPEDEF_END = re.compile(r'^\}\s*([A-Za-z_]\w*)\s*;')
C_GLOBAL = re.compile(r'^(?!typedef|return|#|\})[A-Za-z_][\w\s\*]*?\b([A-Za-z_]\w*)\s*(?:\[[^\]]*\]\s*)*=(?!=)')
SELKA = re.compile(r'^(\s*)(?:(?:public|private|async|builtin|extern|conversion)\s+)*(func|record|enum|const|type)\s+([A-Za-z_]\w*)')
PY_DEF = re.compile(r'^(\s*)(?:async\s+)?(def|class)\s+([A-Za-z_]\w*)')
PY_ASSIGN = re.compile(r'^([A-Za-z_]\w*)\s*(?::[^=]+)?=(?!=)')
PY_KEYWORDS = {'else', 'try', 'finally', 'if', 'elif', 'while', 'for', 'with', 'return', 'except', 'lambda', 'import', 'from',
               'assert', 'raise', 'del', 'pass', 'global', 'print'}
SH_FN = re.compile(r'^(\s*)(?:function\s+)?([A-Za-z_][\w-]*)\s*\(\)')
SH_ASSIGN = re.compile(r'^(?:export\s+|readonly\s+)?([A-Za-z_]\w*)=')


def scan_zig(raw, masked):
    out = []
    for i, m in enumerate(masked):
        s = m.lstrip()
        if not s:
            continue
        if 'fn ' in s:
            f = ZIG_FN.match(m)
            if f:
                out.append(Raw(f.group(2), 'fn', i, 1))
                continue
        if s.startswith('test '):
            t = ZIG_TEST.match(m)
            if t:
                name = raw[i][t.start(2):t.end(2)] if t.group(2) is not None else t.group(3)
                out.append(Raw(name, 'test', i, 1))
            continue
        if s.startswith(('const ', 'var ', 'pub ', 'export ', 'extern ', 'threadlocal ', 'comptime ', 'inline ')):
            c = ZIG_CONST.match(m)
            if c:
                tp = ZIG_TYPE.match(c.group(5))
                out.append(Raw(c.group(4), tp.group(1) if tp else c.group(3), i, 1 if c.group(2) or not c.group(1) else 2))
    return out


def scan_c(raw, masked):
    out = []
    for i, m in enumerate(masked):
        if not m or m[0] in ' \t\n}' and not C_TYPEDEF_END.match(m):
            continue
        d = C_MACRO.match(m)
        if d:
            out.append(Raw(d.group(1), 'macro', i, 1))
            continue
        t = C_TYPEDEF_END.match(m)
        if t:
            j = i
            while j > 0 and not raw[j].startswith('typedef') and i - j < 400:
                j -= 1
            start = j if raw[j].startswith('typedef') else i
            out = [r for r in out if not (r.i == start and r.name == t.group(1))]
            out.append(Raw(t.group(1), 'typedef', start, 1))
            continue
        tag = C_TAG.match(m)
        if tag:
            out.append(Raw(tag.group(2), tag.group(1), i, 1))
            continue
        if m[0] == '#':
            continue
        f = C_FN.match(m)
        if f and f.group(1) not in C_NOT_FN and m.split()[0].rstrip('(') not in C_NOT_FN and not m.rstrip().endswith(';'):
            out.append(Raw(f.group(1), 'fn', i, 1))
            continue
        g = C_GLOBAL.match(m)
        if g:
            out.append(Raw(g.group(1), 'var', i, 1))
    return [r for r in out if r.kind != 'fn' or brace_end(masked, r.i)[1]]


def scan_selka(raw, masked):
    out = []
    for i, m in enumerate(masked):
        if 'func ' in m or 'record ' in m or 'enum ' in m or 'const ' in m or 'type ' in m:
            s = SELKA.match(m)
            if s:
                out.append(Raw(s.group(3), s.group(2), i, 2 if s.group(2) == 'const' and s.group(1) else 1))
    return out


def scan_py(raw, masked, assigns=True):
    """Python declarations: `def` and `class` at any indent, and (unless `assigns` is off) top-level assignments."""
    out = []
    for i, m in enumerate(masked):
        if 'def ' in m or 'class ' in m:
            d = PY_DEF.match(m)
            if d:
                out.append(Raw(d.group(3), d.group(2), i, 1))
                continue
        a = PY_ASSIGN.match(m) if assigns and (m[:1].isalpha() or m[:1] == '_') else None
        if a and a.group(1) not in PY_KEYWORDS:
            out.append(Raw(a.group(1), 'const', i, 1))
    return out


def scan_sh(raw, masked):
    """Shell functions and top-level assignments, and the Python `def` and `class` of a heredoc."""
    out = scan_py(raw, masked, assigns=False)
    for i, m in enumerate(masked):
        f = SH_FN.match(m) if '()' in m else None
        if f:
            out.append(Raw(f.group(2), 'fn', i, 1))
        elif m[:1].isalpha() or m[:1] == '_':
            a = SH_ASSIGN.match(m)
            if a:
                out.append(Raw(a.group(1), 'const', i, 1))
    return sorted(out, key=lambda r: r.i)


SCANNERS = {'zig': scan_zig, 'c': scan_c, 'selka': scan_selka, 'py': scan_py, 'sh': scan_sh}


def brace_end(masked, i):
    """(last line index, whether a `{` opened) of the statement that starts at line i: where its brackets close on a line that
    ends in `;` or `}`."""
    depth, saw = 0, False
    for j in range(i, len(masked)):
        m = masked[j]
        opened = m.count('{')
        saw = saw or bool(opened)
        depth += opened + m.count('(') + m.count('[') - m.count('}') - m.count(')') - m.count(']')
        if depth <= 0 and m.rstrip().endswith((';', '}')):
            return j, saw
    return len(masked) - 1, saw


def indent_end(raw, masked, i):
    """Last line index of the Selka or Python declaration at line i: the last code line indented under it or inside its
    brackets."""
    base, depth, end = indent(raw[i]), 0, i
    for j in range(i, len(masked)):
        m = masked[j]
        code = bool(m.strip())
        if j > i and depth <= 0 and code and indent(m) <= base:
            break
        depth += sum(m.count(c) for c in '([{') - sum(m.count(c) for c in ')]}')
        if code:
            end = j
    return end


def extent_of(raw, masked, r, lang):
    """Last line index of the declaration `r`."""
    if lang == 'c':
        if r.kind == 'macro':
            end = r.i
            while end + 1 < len(raw) and raw[end].rstrip().endswith('\\'):
                end += 1
            return end
        if r.kind == 'typedef':
            return next((j for j in range(r.i, len(masked)) if C_TYPEDEF_END.match(masked[j])), r.i)
        return brace_end(masked, r.i)[0]
    if lang == 'zig':
        return brace_end(masked, r.i)[0]
    if lang == 'sh' and r.kind == 'fn' and SH_FN.match(masked[r.i]):
        if masked[r.i].rstrip().endswith('}'):
            return r.i
        base = indent(raw[r.i])
        return next((j for j in range(r.i + 1, len(masked)) if indent(raw[j]) == base and masked[j].lstrip().startswith('}')),
                    len(masked) - 1)
    if lang == 'sh' and r.kind == 'const':
        end = r.i
        while end + 1 < len(raw) and raw[end].rstrip().endswith('\\'):
            end += 1
        return end
    return indent_end(raw, masked, r.i)


def doc_start(raw, i, lang):
    """0-based index of the first line of the doc comment (and decorators) directly above line i, else i."""
    j = i
    if lang in ('py', 'sh'):
        while j > 0 and raw[j - 1].lstrip().startswith('@') and indent(raw[j - 1]) == indent(raw[i]):
            j -= 1
    marks = {'zig': ('///',), 'c': ('//',)}.get(lang, ('#',))
    k = j
    while k > 0 and raw[k - 1].lstrip().startswith(marks) and not raw[k - 1].startswith(('////', '#!')):
        k -= 1
    if lang == 'c' and k == j and j > 0 and raw[j - 1].rstrip().endswith('*/'):
        k = j - 1
        while k > 0 and '/*' not in raw[k]:
            k -= 1
    return k


class Index:
    """The files of one checkout: lines, masked lines and scans are read once and kept for the life of the call."""

    def __init__(self, root):
        self.root = Path(root)
        self._lines, self._masked, self._scans, self._decls = {}, {}, {}, {}

    def lines(self, path):
        if path not in self._lines:
            try:
                self._lines[path] = (self.root / path).read_text(errors='replace').split('\n')
            except OSError:
                self._lines[path] = []
            if self._lines[path] and self._lines[path][-1] == '':
                self._lines[path].pop()
        return self._lines[path]

    def masked(self, path):
        if path not in self._masked:
            self._masked[path] = mask(self.lines(path), lang_of(path) or 'zig')
        return self._masked[path]

    def scan(self, path):
        """Every declaration line of a file as Raw tuples (extents not yet worked out)."""
        if path not in self._scans:
            lang = lang_of(path)
            self._scans[path] = SCANNERS[lang](self.lines(path), self.masked(path)) if lang else []
        return self._scans[path]

    def decl(self, path, r):
        """The Decl for scan entry `r`, with its extent."""
        key = (path, r.i, r.name)
        if key not in self._decls:
            lang, raw = lang_of(path), self.lines(path)
            last = extent_of(raw, self.masked(path), r, lang)
            top = r.i - 1 if lang == 'c' and r.kind == 'fn' and r.i and C_TYPE_LINE.match(raw[r.i - 1]) else r.i
            self._decls[key] = Decl(path, doc_start(raw, top, lang) + 1, r.i + 1, last + 1, r.kind, r.name)
        return self._decls[key]

    def decls(self, path):
        """Every declaration of a file that holds code, with its extent: a local `const` is not one."""
        return [self.decl(path, r) for r in self.scan(path) if r.tier == 1]

    def at(self, path, line):
        """The innermost declaration of `path` that holds line `line` (1-based), else None."""
        best = None
        for d in self.decls(path):
            if d.first <= line <= d.last and (best is None or (d.line, -d.last) > (best.line, -best.last)):
                best = d
        return best

    def containers(self, d):
        """Names of the declarations that enclose `d` in its file, outermost first."""
        up = [o for o in self.decls(d.path) if o.first <= d.line <= o.last and o != d and (o.line, o.last) != (d.line, d.last)
              and (o.line < d.line or o.last > d.last)]
        return [o.name for o in sorted(up, key=lambda o: (o.line, -o.last))]

    def files(self, names, pathspecs=SEARCH):
        """Files under `pathspecs` with a line that may declare one of `names`: one `git grep` for the words (untracked files
        included), then a regular expression over the lines it found, so that a common name does not scan every file."""
        cmd = ['git', '-C', str(self.root), 'grep', '-n', '-I', '--untracked', '--no-color', '-F', '-w']
        for n in names:
            cmd += ['-e', n]
        out = subprocess.run(cmd + ['--'] + list(pathspecs), capture_output=True, text=True, errors='replace').stdout
        alt = '|'.join(re.escape(n) for n in names)
        declish = re.compile(r'\b(?:fn|func|def|record|enum|const|var|type|class|test|define|struct|union|typedef)\s+(?:%s)\b'
                             r'|^(?:[^\s#/].*\b)?(?:%s)\s*(?:\[[^\]]*\]\s*)*[(=]|^(?:%s)\b|^\}' % (alt, alt, alt))
        found = set()
        for row in out.split('\n'):
            parts = row.split(':', 2)
            if len(parts) == 3 and parts[0] not in found and lang_of(parts[0]) and declish.search(parts[2]):
                found.add(parts[0])
        return sorted(found)

    def find(self, name, qualifier=None, within=None):
        """Declarations of `name` ranked code before tests: in `within` (a list of paths) or in the searched folders. A
        `qualifier` keeps those inside a declaration of that name or in a file of that stem. Names too common to offer
        (a local `const`, an indented Selka `const`) count only when nothing else is declared."""
        paths = within if within is not None else self.files([name])
        found = {1: [], 2: []}
        for p in paths:
            for r in self.scan(p):
                if r.name == name:
                    found[r.tier].append(self.decl(p, r))
        hits = found[1] or found[2]
        if qualifier:
            hits = [d for d in hits if Path(d.path).stem == qualifier or qualifier in self.containers(d)]
        return sorted(hits, key=lambda d: (is_test_path(d.path), d.path, d.line))

    def resolve(self, spec):
        """The checkout-relative paths a file spec names: itself, else every file whose path ends with `/spec`."""
        spec = spec[len(str(self.root)) + 1:] if spec.startswith(str(self.root) + '/') else spec
        if (self.root / spec).is_file():
            return [spec]
        out = subprocess.run(['git', '-C', str(self.root), 'ls-files', '--cached', '--others', '--exclude-standard'],
                             capture_output=True, text=True, errors='replace').stdout.split('\n')
        return sorted(f for f in out if f == spec or f.endswith('/' + spec))


def clip(text):
    """A source line without trailing blanks, cut at LINE_CHARS."""
    text = text.rstrip()
    return text if len(text) <= LINE_CHARS else text[:LINE_CHARS] + f' ... (+{len(text) - LINE_CHARS} chars)'


def numbered(index, path, lo, hi, mark=None):
    """Lines lo..hi (1-based, inclusive) as `NNNN: text`, `NNNN> text` on line `mark`."""
    ls = index.lines(path)
    width = len(str(hi))
    return [f'{n:>{width}}{">" if n == mark else ":"} {clip(ls[n - 1])}' for n in range(lo, min(hi, len(ls)) + 1)]


def span(d):
    """`path:first-last`, or `path:first` for one line."""
    return f'{d.path}:{d.first}' + (f'-{d.last}' if d.last > d.first else '')


def body(index, d, limit=BODY_LINES, mark=None):
    """The declaration as a header line and its code, cut at `limit` lines with the range that is left."""
    out = [f'{span(d)}: {d.kind} {d.name}']
    cut = d.first + max(1, limit) - 1
    out += numbered(index, d.path, d.first, min(d.last, cut), mark)
    if d.last > cut:
        out.append(f'  ... not shown: {d.path}:{cut + 1}-{d.last} ({d.last - cut} lines; Read it with offset and limit)')
    return out


def first_line(index, d):
    """`path:line: the declaration line`, cut at 110 characters: one row of a list of matches."""
    return f'  {d.path}:{d.line}: {index.lines(d.path)[d.line - 1].strip()[:110]}'


def choose(index, label, hits):
    """The answer for a query whose name is declared more than once: each match's first line, then how to choose."""
    out = [f'{label}: {len(hits)} declarations; name the file to choose one']
    out += [first_line(index, d) for d in hits[:LIST_MATCHES]]
    if len(hits) > LIST_MATCHES:
        out.append(f'  ... {len(hits) - LIST_MATCHES} more')
    same = len({d.path for d in hits}) < len(hits)
    out.append(f'  choose: where.py {hits[0].path}:{hits[0].line if same else hits[0].name} --body'
               + ('  (PATH:LINE when one file declares it twice)' if same else '  (PATH:NAME)'))
    return out


def declared(index, label, hits, limit=BODY_LINES, scope=None):
    """The `--body` answer for the declarations a query found: none, the one body, or the list to choose from. `scope` names
    where a lookup that found none looked, and defaults to the searched folders."""
    if not hits:
        uses = label.rsplit(':', 1)[-1].strip('"')
        return [f'{label}: no declaration found in {scope or ", ".join(SEARCH)} (`where.py {uses}` shows its uses)']
    return body(index, hits[0], limit) if len(hits) == 1 else choose(index, label, hits)


def window(index, path, line, n):
    """`n` lines around `line`, with the declaration that holds it named in the header."""
    total = len(index.lines(path))
    lo = max(1, min(line - n // 2, total - n + 1))
    hi = min(total, lo + n - 1)
    held = index.at(path, line)
    where = f'; in {held.kind} {held.name} {held.first}-{held.last}' if held else ''
    return [f'{path}:{lo}-{hi}: {hi - lo + 1} lines around line {line}{where}'] + numbered(index, path, lo, hi, line)


def around(index, path, line, n=None, limit=BODY_LINES):
    """The declaration that holds `path:line` with that line marked; `n` lines around it when `n` is given or no declaration
    holds it; a window of `limit` lines around it when the declaration is longer."""
    total = len(index.lines(path))
    if not 1 <= line <= total:
        return [f'{path}:{line}: the file has {total} lines']
    if n:
        return window(index, path, line, min(n, CALL_LINES))
    d = index.at(path, line)
    if d is None:
        return window(index, path, line, AROUND_DEFAULT)
    if d.last - d.first + 1 <= limit:
        return body(index, d, limit, line)
    lo = max(d.first, min(line - limit // 2, d.last - limit + 1))
    hi = min(d.last, lo + limit - 1)
    return ([f'{span(d)}: {d.kind} {d.name} ({d.last - d.first + 1} lines; showing {lo}-{hi} around line {line})']
            + numbered(index, path, lo, hi, line))
