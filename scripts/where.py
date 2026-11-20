#!/usr/bin/env python3
"""where.py QUERY...: where a diagnostic is raised, built, fixed, tested and documented, or who calls a function; its code.

  where.py E_OWN_MARKER             a code (E_, W_, L_ or R_ prefix): the places under src/ that raise it, where its message
                                    is built, whether it carries a `fix`, the tests that name it, and its guide section
  where.py "expected a name"        a piece of a message (any query with a space or a quote; --text WORD for one word):
                                    the same, starting from the text
  where.py takeNamedModifier        a function: its definition and first doc line, its callers, the tests that name it
  where.py A B "a message" E_X      several queries in one call: each argument is one query, answered in turn (at most 150 lines)
  where.py A B --body               the lines of each declaration (a function, type, constant, test; Zig, C, Selka, Python, shell):
                                    `path:first-last`, then the code cut at 60 lines with the range left; a name declared more
                                    than once lists each first line and how to choose (`where.py src/parser.zig:A --body`)
  where.py --around PATH:LINE [N]   the declaration that holds that line with the line marked `>` (the place of a compiler
                                    error or a failed test), or N lines around it

Without --body or --around, a single query is answered in at most 25 lines (--all lifts the limit) and comes from `git grep`
of the working tree, untracked files included, each time: there is no index and no build step. With --body, --around or
several queries a call prints at most 150 lines. `--body` also takes `A.b` (the `b` declared inside `A` or in file `A.*`),
`PATH:NAME` and `PATH:LINE`; for a code it prints its table row and the first function that raises it; for a piece of a
message the function that builds it. The finder is `where_body.py`: it blanks comments and strings with a regular expression and
matches declarations by how a line starts; it does not parse.

What it does not do: it does not parse Zig. The enclosing function of a line is the nearest `fn NAME(` (or `test "name"`)
above it at a smaller indentation; a line at the top level of a struct reports the `const` that opens it; in a C file the
enclosing function is the nearest line at column 0 that holds `NAME(` and does not end in `;`. A line in a comment is not a
raise site and not a caller. A code is "raised" where it is a quoted string in a non-test src file, or where a constant
holding it is used (`pub const marker_code = "E_X"`, then `own_parameters.marker_code`); a line that compares it
(`eql(`, `==`) is a read. A test is a hit in `src/*_test.zig`, `test/` (golden files) or `tests/` (guest tests), or inside a
`test "..."` block of any src file. `--selftest` runs six queries whose answers were checked by hand.
"""
import re
import subprocess
import sys
import time
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import where_body as wb  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
LIMIT = 25
CODE_QUERY = re.compile(r'^[EWLR]_[A-Z0-9_]+$')
NAME_QUERY = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
CODE_EXT = ('.zig', '.c', '.h')
FN_ZIG = re.compile(r'^\s*(?:(?:pub|export|inline|noinline|extern)\s+)*fn\s+([A-Za-z_]\w*)\s*\(')
TEST_ZIG = re.compile(r'^\s*test\s+("(?:[^"\\]|\\.)*"|[A-Za-z_]\w*)\s*\{')
TOP_CONST = re.compile(r'^(?:pub\s+)?(?:const|var)\s+([A-Za-z_]\w*)')
C_FN = re.compile(r'^[A-Za-z_][\w\s\*]*?\b([A-Za-z_]\w*)\s*\(')
C_NOT_FN = {'if', 'for', 'while', 'switch', 'return', 'else', 'case', 'typedef', 'enum', 'union', 'define', 'sizeof'}
FIX_SET = re.compile(r'\bprovenance\.fix\s*=(?!=)|\bprovenance\.fix\.\?|\.fix = |\b(?:fail|append)\w*Fix\w*\(')
READ_LINE = re.compile(r'eql\(|==|!=|indexOf|startsWith|endsWith|contains|\.rules = ')
CAPS = [dict(sites=6, zig=3, golden=2, guest=2), dict(sites=4, zig=2, golden=1, guest=1),
        dict(sites=3, zig=2, golden=1, guest=1), dict(sites=2, zig=1, golden=1, guest=1)]
FULL = dict(sites=10 ** 6, zig=10 ** 6, golden=10 ** 6, guest=10 ** 6)

_cache = {}


def pl(n, word):
    """'1 file', '2 files'."""
    return f'{n} {word}' + ('' if n == 1 else 's')


def lines_of(path):
    if path not in _cache:
        try:
            _cache[path] = (ROOT / path).read_text(errors='replace').split('\n')
        except OSError:
            _cache[path] = []
    return _cache[path]


def grep(pattern, paths, word=True, fixed=True):
    """`git grep` of the working tree (untracked files too): a list of (path, line number, text)."""
    cmd = ['git', '-C', str(ROOT), 'grep', '-n', '-I', '--untracked', '--no-color', '-F' if fixed else '-E']
    if word:
        cmd.append('-w')
    cmd += ['-e', pattern, '--'] + paths
    out = subprocess.run(cmd, capture_output=True, text=True, errors='replace').stdout
    found = []
    for row in out.split('\n'):
        parts = row.split(':', 2)
        if len(parts) == 3 and parts[1].isdigit():
            found.append((parts[0], int(parts[1]), parts[2]))
    return found


def ext_of(path):
    return path[path.rfind('.'):] if '.' in path.rsplit('/', 1)[-1] else ''


def test_kind(path):
    """'zig', 'golden' or 'guest' for a test file by its path, else None."""
    base = path.rsplit('/', 1)[-1]
    if path.startswith('tests/shard-plans/'):
        return None
    if path.startswith('tests/'):
        return 'guest'
    if path.startswith('test/'):
        return 'zig' if path.endswith(('.zig', '.c')) else 'golden'
    if path.startswith('src/'):
        if re.search(r'_tests?\.(zig|c)$|_test_support\.zig$', base) or base in ('tests.zig', 'test.zig'):
            return 'zig'
        if re.search(r'_fixture\.\w+$', base):
            return 'golden'
    return None


def code_part(text, ext):
    """The line without a trailing comment; '' for a comment line (a `///` doc line included)."""
    if text.lstrip().startswith('\\\\'):
        return text
    out, quoted, i = [], False, 0
    while i < len(text):
        ch = text[i]
        if quoted:
            out.append(ch)
            if ch == '\\' and i + 1 < len(text):
                out.append(text[i + 1])
                i += 2
                continue
            quoted = ch != '"'
        elif ch == '"':
            quoted = True
            out.append(ch)
        elif text.startswith('//', i) or (ext != '.zig' and text.startswith('/*', i)):
            break
        else:
            out.append(ch)
        i += 1
    kept = ''.join(out)
    return '' if ext != '.zig' and kept.lstrip().startswith('*') else kept


def indent(line):
    return len(line) - len(line.lstrip(' '))


def enclosing(path, n):
    """(kind, name, start line) of the function or test around line n, or ('const', NAME, line), or (None, None, 0)."""
    ls, i = lines_of(path), n - 1
    if ext_of(path) != '.zig':
        for j in range(i, -1, -1):
            m = C_FN.match(ls[j]) if ls[j] and not ls[j].rstrip().endswith(';') else None
            if m and ls[j].split()[0].rstrip('(') not in C_NOT_FN and m.group(1) not in C_NOT_FN:
                return 'fn', m.group(1), j + 1
        return None, None, 0
    own = indent(ls[i]) if i < len(ls) and ls[i].strip() else 10 ** 6
    if own == 0:
        m = TOP_CONST.match(ls[i]) if i < len(ls) else None
        return ('const', m.group(1), n) if m else (None, None, 0)
    for j in range(i - 1, -1, -1):
        s = ls[j]
        if not s.strip() or indent(s) >= own:
            continue
        m = FN_ZIG.match(s)
        if m:
            return 'fn', m.group(1), j + 1
        m = TEST_ZIG.match(s)
        if m:
            return 'test', m.group(1), j + 1
        if indent(s) == 0 and not s.lstrip().startswith(('}', ')', ']', '//')):
            m = TOP_CONST.match(s)
            return ('const', m.group(1), j + 1) if m else (None, None, 0)
    return None, None, 0


def extent(path, start):
    """The last line of the function that starts at line `start`: the first closing brace at its indentation."""
    ls = lines_of(path)
    if start - 1 >= len(ls):
        return start
    first, c = ls[start - 1], ext_of(path) != '.zig'
    if '{' in first and first.rstrip().endswith('}'):
        return start
    for j in range(start, len(ls)):
        s = ls[j]
        if s.startswith('}') if c else (s.strip() and indent(s) <= indent(first) and s.lstrip().startswith('}')):
            return j + 1
    return len(ls)


def label(encl):
    kind, name, _ = encl
    return f'test "{name.strip(chr(34))}"' if kind == 'test' else f'const {name}' if kind == 'const' else name or '(top level)'


def group(sites):
    """Sites [(path, n, encl)] as one entry per (path, function): (path, first line, label, [other lines], start)."""
    groups, order = {}, []
    for path, n, encl in sorted(sites, key=lambda s: (s[0], s[1])):
        key = (path, encl[1], encl[2])
        if key not in groups:
            groups[key] = [path, n, label(encl), [], encl[2]]
            order.append(key)
        else:
            groups[key][3].append(n)
    return [groups[k] for k in order]


def show(entry):
    path, n, name, more, _ = entry
    tail = f' (+{len(more)}: {", ".join(map(str, more[:3]))}{", ..." if len(more) > 3 else ""})' if more else ''
    return f'{path}:{n}: {name}{tail}'


def split_hits(hits):
    """Hits in src, test/ and tests/ as (tests, others): tests with their kind, others the non-comment src code lines."""
    tests, code = [], []
    for path, n, text in hits:
        kind = test_kind(path)
        if kind:
            tests.append((path, n, kind))
        elif path.startswith('src/') and path.endswith(CODE_EXT):
            code.append((path, n, text))
    return tests, code


def tests_in_src(code):
    """Splits non-test src lines into (lines outside tests with their enclosing function, lines inside `test` blocks)."""
    outside, inside = [], []
    for path, n, text in code:
        encl = enclosing(path, n)
        (inside if encl[0] == 'test' else outside).append((path, n, text, encl))
    return outside, inside


def test_lines(tests, caps):
    """The 'tests' section: counts per kind, then the top files per kind as `path: count (first three lines)`."""
    if not tests:
        return ['tests: none name it']
    per = defaultdict(lambda: defaultdict(list))
    for path, n, kind in tests:
        per[kind][path].append(n)
    total = sum(len(v) for k in per.values() for v in k.values())
    files = sum(len(k) for k in per.values())
    kinds = ', '.join(f'{k} {len(per[k])}' for k in ('zig', 'golden', 'guest') if k in per)
    out = [f'tests: {pl(total, "line")} in {pl(files, "file")} ({kinds})']
    for kind in ('zig', 'golden', 'guest'):
        ranked = sorted(per.get(kind, {}).items(), key=lambda kv: (-len(kv[1]), kv[0]))
        for path, nums in ranked[:caps[kind]]:
            out.append(f'  {kind:6} {path}: {len(nums)} ({", ".join(map(str, sorted(nums)[:3]))})')
        if len(ranked) > caps[kind]:
            out.append(f'  {kind:6} +{len(ranked) - caps[kind]} more files')
    return out


def code_row(code):
    """(path, line, meaning, guide topic) of the code's row in src/diagnostic_codes.zig, or None."""
    names = {'E': 'errors', 'W': 'warnings', 'L': 'lint', 'R': 'traps'}
    ls, group_name = lines_of('src/diagnostic_codes.zig'), None
    for i, s in enumerate(ls):
        m = re.match(r'^const (\w+) = \[_\]Row', s)
        if m:
            group_name = m.group(1)
        m = re.search(r'\.name = "%s", \.meaning = "(.*?)", \.guide = topic\.(\w+)' % re.escape(code[2:]), s)
        if m and group_name == names[code[0]]:
            return 'src/diagnostic_codes.zig', i + 1, m.group(1), m.group(2)
    return None


def guide_page(topic):
    """The docs page `selka docs TOPIC` shows, from the two tables in src/diagnostic_codes.zig and src/user_docs.zig."""
    text = '\n'.join(lines_of('src/diagnostic_codes.zig')[:50])
    m = re.search(r'const %s = "([^"]+)";' % topic, text)
    name = re.escape(m.group(1) if m else topic)
    m = re.search(r'\.name = "%s", \.path = "([^"]+)"' % name, '\n'.join(lines_of('src/user_docs.zig')))
    return m.group(1) if m else None


def heading_above(path, n):
    """The nearest markdown heading above line n, outside fenced blocks."""
    fence, cur = False, None
    for s in lines_of(path)[:n]:
        if s.startswith(('```', '~~~')):
            fence = not fence
        elif not fence and s.startswith('#'):
            cur = s.strip()
    return cur


def docs_lines(hits, page, what):
    """The 'guide' section: the guide page's first mention with its heading, then the other pages by mention count."""
    per = defaultdict(list)
    for path, n, _ in hits:
        per[path].append(n)
    out = []
    if page and page in per:
        n = min(per[page])
        out.append(f'guide: {page}:{n} under "{heading_above(page, n)}" ({pl(len(per[page]), "mention")})')
    elif page:
        out.append(f'guide: {page} (the row names it; it does not mention {what})')
    rest = sorted(((p, v) for p, v in per.items() if p != page), key=lambda kv: (-len(kv[1]), kv[0]))
    if rest:
        more = f'; +{len(rest) - 3} more pages' if len(rest) > 3 else ''
        out.append('docs: ' + '; '.join(f'{p}:{min(v)} ({len(v)})' for p, v in rest[:3]) + more)
    elif not out:
        out.append(f'docs: nothing under docs/ names {what}')
    return out


def fix_lines(entries, row, fix_doc):
    """Whether the raising functions carry a structured fix: inside the function, else elsewhere in the same file."""
    tail = f'; docs/tooling/fix.md:{fix_doc[0][1]}' if fix_doc else ''
    if row and re.search(r'report only|no `fix`', row[2]):
        return ['fix: none (the code table says report only)' + tail]
    inside, files = [], {e[0] for e in entries}
    for path, _, name, _, start in entries:
        if start:
            body = lines_of(path)
            end = extent(path, start)
            hit = next((k for k in range(start, end + 1) if k - 1 < len(body) and FIX_SET.search(body[k - 1])), None)
            if hit:
                inside.append((path, f'{path}:{hit}: {name}'))
    out = []
    if inside:
        more = f' (+{len(inside) - 3})' if len(inside) > 3 else ''
        out.append('fix: yes, set in the raising function: ' + '; '.join(i[1] for i in inside[:3]) + more)
    near = []
    for path in sorted(files - {i[0] for i in inside}):
        near += [(path, k, label(enclosing(path, k))) for k, s in enumerate(lines_of(path), 1)
                 if FIX_SET.search(code_part(s, ext_of(path)))]
    if near:
        more = f' (+{len(near) - 3})' if len(near) > 3 else ''
        out.append('fix: set in a raising file, not in the raising function: '
                   + '; '.join(f'{p}:{k}: {f}' for p, k, f in near[:3]) + more)
    if not out:
        out.append('fix: none found in the raising files')
    out[-1] += tail
    return out


def message_lines(entries_sites):
    """Where the message is built when that is another place: functions with 'message' in their name called at a site."""
    builders = []
    for path, n in entries_sites:
        ls = lines_of(path)
        window = ' '.join(code_part(ls[k], ext_of(path)) for k in range(max(0, n - 3), min(len(ls), n + 2)))
        for name in re.findall(r'\b([A-Za-z_]\w*[Mm]essage\w*)\s*\(', window):
            if name not in builders:
                builders.append(name)
    found = []
    if builders:
        hits = grep(r'\bfn (%s)\(' % '|'.join(builders[:8]), ['src'], word=False, fixed=False)
        found = [f'{h[2].split("fn ")[1].split("(")[0]} {h[0]}:{h[1]}' for h in hits if not test_kind(h[0])]
    if found:
        return ['message: built by ' + '; '.join(found[:4]) + (f' (+{len(found) - 4})' if len(found) > 4 else '')]
    return ['message: no `*Message` function at the raise sites (the text is written there or in a local)']


def raise_sites(code):
    """Non-test src lines that raise `code`, via its quoted string or a constant that holds it. Returns (raises, reads, tests)."""
    tests, code_hits = split_hits(grep(code, ['src', 'test', 'tests']))
    outside, inside = tests_in_src(code_hits)
    tests += [(p, n, 'zig') for p, n, _, _ in inside]
    raises, reads, aliases = [], [], []
    for path, n, text, encl in outside:
        part = code_part(text, ext_of(path))
        if f'"{code}"' not in part:
            continue
        (reads if READ_LINE.search(part) else raises).append((path, n, encl))
        m = re.match(r'^\s*(?:pub\s+)?const\s+(\w+)\s*(?::[^=]+)?=.*"%s"' % code, part)
        if m and encl[0] == 'const':
            aliases.append((path, n, m.group(1)))
    done = set()
    while aliases and len(done) < 8:
        path, n, name = aliases.pop(0)
        if (path, name) in done:
            continue
        done.add((path, name))
        stem = path.rsplit('/', 1)[-1][:-4]
        qualified = len(name) >= 8
        for p, k, text in grep(name, ['src']):
            if test_kind(p) or not p.endswith(CODE_EXT) or (p, k) == (path, n):
                continue
            part = code_part(text, ext_of(p))
            use = r'\.%s\b' % name if qualified else r'\b%s\.%s\b' % (stem, name)
            if not re.search(r'\b%s\b' % name, part) or (p != path and not re.search(use, part)):
                continue
            encl = enclosing(p, k)
            again = re.match(r'^(?:pub\s+)?const\s+(\w+)\s*(?::[^=]+)?=\s*[^;]*\b%s\s*;' % name, part)
            if again and encl[0] == 'const':
                aliases.append((p, k, again.group(1)))
            elif encl[0] == 'test':
                tests.append((p, k, 'zig'))
            else:
                (reads if READ_LINE.search(part) else raises).append((p, k, encl))
    seen, unique = set(), []
    for r in raises:
        if r[:2] not in seen:
            seen.add(r[:2])
            unique.append(r)
    return unique, reads, tests


def answer_code(code, caps):
    raises, reads, tests = raise_sites(code)
    row = code_row(code)
    entries = group(raises)
    files = pl(len({e[0] for e in entries}), 'file')
    out = [f'{code}: a code; {pl(len(raises), "raising line")} in {pl(len(entries), "function")} of {files}'
           + (f', {pl(len(reads), "line")} that read it or list it ({pl(len({r[0] for r in reads}), "file")})' if reads else '')]
    if row:
        out.append(f'  table: {row[0]}:{row[1]}: {row[2][:85]}')
    out += ['  ' + show(e) for e in entries[:caps['sites']]]
    if len(entries) > caps['sites']:
        out.append(f'  +{len(entries) - caps["sites"]} more functions')
    out += message_lines([(r[0], r[1]) for r in raises[:12]])
    fix_doc = [h for h in grep(code, ['docs/tooling/fix.md'])]
    out += fix_lines(entries, row, fix_doc)
    out += test_lines(tests, caps)
    docs = grep(code, ['docs', ':!docs/audits'])
    page = guide_page(row[3]) if row else None
    out += docs_lines(docs, page, code)
    return out


def codes_near(path, encl):
    """Codes raised in the function around a message: quoted codes in its body, or constants holding one."""
    ls = lines_of(path)
    lo, hi = (encl[2], extent(path, encl[2])) if encl[0] == 'fn' else (1, len(ls))
    body = '\n'.join(code_part(s, ext_of(path)) for s in ls[lo - 1:hi])
    found = list(dict.fromkeys(re.findall(r'"([EWLR]_[A-Z0-9_]+)"', body)))
    for name in dict.fromkeys(re.findall(r'\b(\w*_code|e[A-Z]\w+)\b', body)):
        for _, _, text in grep(f'{name} = "', ['src'], word=False):
            m = re.search(r'\b%s\s*(?::[^=]+)?=\s*"([EWLR]_[A-Z0-9_]+)"' % name, text)
            if m and m.group(1) not in found:
                found.append(m.group(1))
    return found


def answer_text(text, caps):
    tests, code_hits = split_hits(grep(text, ['src', 'test', 'tests'], word=False))
    outside, inside = tests_in_src(code_hits)
    tests += [(p, n, 'zig') for p, n, _, _ in inside]
    sites = [(p, n, e) for p, n, t, e in outside if text in code_part(t, ext_of(p))]
    entries = group(sites)
    out = [f'"{text}": message text; built in {pl(len(sites), "line")} of {pl(len(entries), "function")}']
    out += ['  ' + show(e) for e in entries[:caps['sites']]]
    if len(entries) > caps['sites']:
        out.append(f'  +{len(entries) - caps["sites"]} more functions')
    codes = []
    for path, n, encl in sites[:6]:
        codes += [c for c in codes_near(path, encl) if c not in codes]
    rows = [(c, code_row(c)) for c in codes[:3]]
    if codes:
        out.append('code: ' + '; '.join(f'{c}' + (f' (table {r[0]}:{r[1]}, guide {r[3]})' if r else '') for c, r in rows)
                   + (f'; +{len(codes) - 3}' if len(codes) > 3 else ''))
    else:
        out.append('code: none found in the building functions')
    if entries:
        row = rows[0][1] if rows else None
        out += fix_lines(entries, row, [])
    out += test_lines(tests, caps)
    docs = grep(text, ['docs', ':!docs/audits'], word=False)
    page = guide_page(rows[0][1][3]) if rows and rows[0][1] else None
    out += docs_lines(docs, page, 'the text')
    return out


def doc_comment(path, n):
    """The first line of the doc comment that ends just above line n, or None."""
    ls, k = lines_of(path), n - 2
    while k >= 0 and ls[k].lstrip().startswith(('@', 'inline', 'export')) and not ls[k].lstrip().startswith(('///', '//')):
        k -= 1
    first = None
    while k >= 0 and ls[k].lstrip().startswith(('///', '//')):
        first = ls[k].lstrip().lstrip('/').strip()
        k -= 1
    return first


def answer_function(name, caps):
    found = grep(r'\b(fn|func|def) %s\(' % name, ['src'], word=False, fixed=False)
    defs = [(p, n, t) for p, n, t in found if p.endswith(('.zig', '.selka'))]
    defs += [(p, n, t) for p, n, t in grep(r'^[A-Za-z_][A-Za-z0-9_ *]*[ *]%s\(' % name, ['src'], word=False, fixed=False)
             if p.endswith(('.c', '.h')) and not t.rstrip().endswith(';')]
    tests, code_hits = split_hits(grep(name, ['src', 'test', 'tests']))
    outside, inside = tests_in_src(code_hits)
    tests += [(p, n, 'zig') for p, n, _, _ in inside]
    def_lines = {(p, n) for p, n, _ in defs}
    callers = [(p, n, e) for p, n, t, e in outside
               if (p, n) not in def_lines and re.search(r'\b%s\s*\(' % name, code_part(t, ext_of(p)))]
    shared = ' (by name: same-named functions are counted together)' if len(defs) > 1 else ''
    out = [f'{name}: a function; {pl(len(defs), "definition")}, {pl(len(callers), "caller")}' + shared]
    for p, n, _ in defs[:3]:
        doc = doc_comment(p, n)
        out.append(f'  def {p}:{n}: ' + (f'/// {doc[:100]}' if doc else '(no doc comment)'))
    entries = group(callers)
    shown = sorted(callers)[:5]
    out += [f'  caller {p}:{n}: {label(e)}' for p, n, e in shown]
    if len(callers) > 5:
        out.append(f'  +{len(callers) - 5} more callers in {len({c[0] for c in callers[5:]})} files')
    out += test_lines(tests, caps)
    return out


def answer(query, full=False, text_only=False):
    caps = FULL if full else CAPS[0]
    kind = 'code' if CODE_QUERY.match(query) else 'function' if NAME_QUERY.match(query) else 'text'
    kind = 'text' if text_only else kind
    needle = query.strip().strip('"\'`') if kind == 'text' else query
    run = {'code': answer_code, 'function': answer_function, 'text': answer_text}[kind]
    for caps in ([FULL] if full else CAPS):
        out = run(needle, caps)
        if len(out) <= LIMIT or full:
            return out
    return out[:LIMIT - 1] + [f'... {len(out) - LIMIT + 1} more lines (--all shows them)']


PATH_QUERY = re.compile(r'^([^\s:]+\.[A-Za-z]+):([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?|\d+)(?::\d+)*$')
AROUND_SPEC = re.compile(r'^(.+?):(\d+)(?::\d+)*$')
QUALIFIED = re.compile(r'^([A-Za-z_]\w*)\.([A-Za-z_]\w*)$')
ALSO = 8


def body_code(index, code, limit):
    """`--body` for a code: its row in the table, then the first function that raises it and the others by first line."""
    row, (raises, _, _) = code_row(code), raise_sites(code)
    fns = []
    for path, _, _, _, start in group(raises):
        d = index.at(path, start) if start else None
        if d and d not in fns:
            fns.append(d)
    fns.sort(key=lambda d: d.kind != 'fn')
    if not row and not fns:
        return [f'{code}: not in the code table and not raised under src/ (`where.py {code}` shows reads and tests)']
    out = [f'{code}: its table row, then {"the first of " if len(fns) > 1 else ""}{pl(len(fns), "raising function")}']
    if row:
        out += wb.body(index, wb.Decl(row[0], row[1], row[1], row[1], 'row', code), limit)
    if fns:
        out += wb.body(index, fns[0], limit)
    out += [f'also raised in: {wb.span(d)}: {d.kind} {d.name}' for d in fns[1:ALSO + 1]]
    if len(fns) > ALSO + 1:
        out.append(f'... {len(fns) - ALSO - 1} more raising functions (`where.py {code}` lists them)')
    if len(fns) > 1:
        out.append(f'choose one: where.py {fns[1].path}:{fns[1].name} --body')
    return out


def body_text(index, text, limit):
    """`--body` for a piece of a message: the function (or constant) that builds it; else the tests whose name holds it."""
    hits = grep(text, ['src', 'test', 'tests'], word=False)
    _, code_hits = split_hits(hits)
    outside, _ = tests_in_src(code_hits)
    found = []
    for path, _, _, _, start in group([(p, n, e) for p, n, t, e in outside if text in code_part(t, ext_of(p))]):
        d = index.at(path, start) if start else None
        if d and d not in found:
            found.append(d)
    if not found:
        found = [d for d in (index.at(p, n) for p, n, t in hits if TEST_ZIG.match(t) and text in t) if d and d.kind == 'test']
    return wb.declared(index, f'"{text}"', found, limit)


def body_in_file(index, spec, what, limit):
    """`--body` for PATH:NAME (a name, or `A.b`) or PATH:LINE: the lookup in the one file the path names."""
    paths = index.resolve(spec)
    if not paths:
        return [f'{spec}: no such file']
    if len(paths) > 1 and what.isdigit():
        return [f'{spec}: {len(paths)} files end with it; give more of the path'] + ['  ' + p for p in paths[:wb.LIST_MATCHES]]
    if what.isdigit():
        return wb.around(index, paths[0], int(what), None, limit)
    name, qual = (what.split('.')[1], what.split('.')[0]) if '.' in what else (what, None)
    return wb.declared(index, f'{spec}:{what}', index.find(name, qual, within=paths), limit, ' and '.join(paths[:3]))


def body_answer(index, query, text_only, limit):
    """`--body` for one query, as a list of lines: a code, a name, `A.b`, `PATH:NAME`, `PATH:LINE` or a piece of a message."""
    path_form = PATH_QUERY.match(query)
    qualified = QUALIFIED.match(query)
    if path_form and not text_only:
        return body_in_file(index, path_form.group(1), path_form.group(2), limit)
    if text_only or not (CODE_QUERY.match(query) or NAME_QUERY.match(query) or qualified):
        return body_text(index, query.strip().strip('"\'`'), limit)
    if CODE_QUERY.match(query):
        return body_code(index, query, limit)
    if qualified:
        return wb.declared(index, query, index.find(qualified.group(2), qualified.group(1)), limit)
    return wb.declared(index, query, index.find(query), limit)


def share(used, left):
    """The body limit for the next query: its fair share of the 150 lines that remain, at least 8 and at most 60."""
    return max(8, min(wb.BODY_LINES, (wb.CALL_LINES - used) // max(1, left) - 3))


def cut_to(lines, count, query):
    """The first `count` lines of one answer in a call of several, with how to see the rest."""
    if len(lines) <= count:
        return lines
    return lines[:count - 1] + [f'... {len(lines) - count + 1} more lines (`where.py {query}` alone shows them)']


def cap_call(lines):
    """At most 150 lines in a call, whatever was asked."""
    if len(lines) <= wb.CALL_LINES:
        return lines
    return lines[:wb.CALL_LINES - 1] + [f'... {len(lines) - wb.CALL_LINES + 1} more lines cut at the {wb.CALL_LINES}-line limit '
                                       '(ask for fewer names)']


def parse(argv):
    """(queries, arounds, flags) from the arguments; an `--around` takes `PATH:LINE` and an optional count."""
    queries, arounds, flags, i = [], [], set(), 0
    while i < len(argv):
        a = argv[i]
        if a == '--around':
            spec = argv[i + 1] if i + 1 < len(argv) else ''
            count = argv[i + 2] if i + 2 < len(argv) and argv[i + 2].isdigit() else None
            arounds.append((spec, int(count) if count else None))
            i += 3 if count else 2
            continue
        (flags.add(a) if a in ('--all', '--text', '--body') else queries.append(a))
        i += 1
    return queries, arounds, flags


def run_calls(queries, arounds, flags):
    """The output of one call with several queries, `--body` or `--around`: blocks separated by a blank line, at most 150 lines."""
    index, blocks, text_only = wb.Index(ROOT), [], '--text' in flags
    total = len(arounds) + len(queries)
    for spec, count in arounds:
        m = AROUND_SPEC.match(spec)
        used = sum(len(b) + 1 for b in blocks)
        if not m:
            blocks.append([f'{spec}: --around takes PATH:LINE (the form a compiler error or a failed test prints)'])
            continue
        paths = index.resolve(m.group(1))
        blocks.append([f'{m.group(1)}: no such file'] if not paths else wb.around(index, paths[0], int(m.group(2)), count,
                                                                                 share(used, total - len(blocks))))
    for query in queries:
        used = sum(len(b) + 1 for b in blocks)
        left = total - len(blocks)
        if '--body' in flags:
            blocks.append(body_answer(index, query, text_only, share(used, left)))
        else:
            blocks.append(cut_to(answer(query.strip(), '--all' in flags, text_only), max(8, (wb.CALL_LINES - used) // left), query))
    lines = []
    for block in blocks:
        lines += block + ['']
    return cap_call(lines[:-1])


SELFTEST = [
    ('E_OWN_MARKER', False, ['src/core/single_owner.zig:5956: unplacedMarker', 'src/own_parameters.zig:18', 'src/sema_calls.zig',
                             'src/sema_receiver_marker.zig:20: require', 'src/diagnostic_codes.zig:274', 'readMarkerMessage',
                             'src/core/single_owner.zig:8608: diagnosticOf', 'docs/tooling/fix.md:81', 'test/fix_cli_test.zig: 33',
                             'src/fix_directory.zig: 1', 'test/fixtures/ownership-matrix/verdicts.tsv: 259',
                             'tests/borrowed_const/manifest.txt: 16', 'tests: 446 lines in 44 files',
                             'docs/managed-memory.md:771 under "## Checked ownership"', 'docs/ownership-rules.md']),
    ('R_TEXT_BOUNDARY', False, ['src/core/runtime/core_rt.c:1701: myl_core_trap', 'src/core/s1_views_test.zig: 6',
                                'src/native_execute.zig: 1', 'src/prelude_scalar_test.zig: 1', 'test/fix_wave3_fixes_test.zig: 1',
                                'test/library_trap_cli_test.zig: 2', 'tests/lang/text_slice_boundaries.selka: 1',
                                'docs/text.md:108', 'tests: 12 lines in 6 files']),
    ('"expected a name"', False, ['src/parser.zig:450: reservedNameFailure', 'E_SYNTAX', 'src/diagnostic_codes.zig:346',
                                  'tests: none name it']),
    ('"a fresh value is already owned"', False, ['src/core/single_owner.zig:5958: unplacedMarker', 'E_OWN_MARKER',
                                                 'src/core/own_arguments_test.zig: 3', 'src/escape_shape_test.zig: 2',
                                                 'src/accepted_shapes_test.zig: 1']),
    ('takeNamedModifier', False, ['src/parser.zig:857', 'src/parser.zig:957: callbackType',
                                  'src/parser.zig:1623: functionParameters', '2 callers', 'tests: none name it']),
    ('writableReceiverReusing', False, ['src/core/build.zig:2633', 'src/core/build.zig:2627: writableReceiverOf',
                                        'src/core/build.zig:5145: bufferOperationRaw', '2 callers']),
]


def digits_off(text):
    """`text` with every number replaced by N: the hand-checked answers name files and functions, and line numbers move."""
    return re.sub(r'\d+', 'N', text)


BODY_SELFTEST = [(['takeNamedModifier', 'reservedNameFailure', 'myl_core_trap', 'standard_alphabet', 'doc_comment'],
                  ['fn takeNamedModifier', 'fn reservedNameFailure', 'fn myl_core_trap', 'func standard_alphabet',
                   'def doc_comment'])]


def selftest():
    """Six queries: each answer is at most 25 lines and under three seconds, and the full answer names the files checked by hand
    (numbers compared as N). Then `--body` of five names of five languages: at most 150 lines, under a second, each declared."""
    failures, start = 0, time.time()
    for query, text_only, wanted in SELFTEST:
        begin = time.time()
        short = answer(query, text_only=text_only)
        elapsed = time.time() - begin
        full = digits_off('\n'.join(answer(query, full=True, text_only=text_only)))
        missing = [w for w in wanted if digits_off(w) not in full]
        problems = [f'missing {m}' for m in missing]
        problems += [f'{len(short)} lines'] if len(short) > LIMIT else []
        problems += [f'{elapsed:.1f}s'] if elapsed > 3 else []
        failures += bool(problems)
        detail = ' (' + '; '.join(problems) + ')' if problems else ''
        print(f'{"FAIL" if problems else "ok  "} {query}: {len(short)} lines, {elapsed:.2f}s{detail}')
    for names, wanted in BODY_SELFTEST:
        begin = time.time()
        out = run_calls(names, [], {'--body'})
        elapsed = time.time() - begin
        problems = [f'missing {w}' for w in wanted if w not in '\n'.join(out)]
        problems += [f'{len(out)} lines'] if len(out) > wb.CALL_LINES else []
        problems += [f'{elapsed:.1f}s'] if elapsed > 1 else []
        failures += bool(problems)
        detail = ' (' + '; '.join(problems) + ')' if problems else ''
        print(f'{"FAIL" if problems else "ok  "} --body {" ".join(names)}: {len(out)} lines, {elapsed:.2f}s{detail}')
    total = len(SELFTEST) + len(BODY_SELFTEST)
    print(f'where.py selftest: {total - failures} of {total} ok in {time.time() - start:.1f}s')
    return 1 if failures else 0


def main(argv):
    if argv == ['--selftest']:
        return selftest()
    queries, arounds, flags = parse(argv)
    if (not queries and not arounds) or argv[0] in ('-h', '--help'):
        print('\n\n'.join(__doc__.split('\n\n')[:2]).rstrip())
        return 0 if argv and argv[0] in ('-h', '--help') else 2
    if len(queries) == 1 and not arounds and not flags & {'--body'}:
        print('\n'.join(answer(queries[0], '--all' in flags, '--text' in flags)))
        return 0
    print('\n'.join(run_calls(queries, arounds, flags)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
