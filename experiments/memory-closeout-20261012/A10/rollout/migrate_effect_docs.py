"""Prepare two additional C2 pages without changing current published docs."""
import hashlib
import json
from pathlib import Path
import re

base = Path(__file__).resolve().parent
root = base.parents[3]
identities = {}


def save(name, text):
    original = root / 'docs' / name
    output = base / 'reference-docs' / name
    output.write_text(text)
    identities[str(original.relative_to(root))] = dict(
        original_sha256=hashlib.sha256(original.read_bytes()).hexdigest(),
        draft=str(output.relative_to(root)),
        draft_sha256=hashlib.sha256(output.read_bytes()).hexdigest())


s = (root / 'docs/module-constants.md').read_text()
s = s.replace('Ordinary reference counting and allocation budgets apply.',
              'Checked ownership, direct destruction and allocation budgets apply.')
save('module-constants.md', s)

s = (root / 'docs/effects.md').read_text()
s = s.replace('Copy-on-write and\n  runtime scratch count even on cold paths.',
              'Explicit independent copies and\n  runtime scratch count even on cold paths.')
s = s.replace('''The guarantee covers the complete value, including managed descendants of records,
arrays, options, unions and collections. Assignment and non-`mut` passing preserve
independent values. A `mut` argument marks the caller's place to update; the
compiler snapshots any read-only argument that might overlap it. Two overlapping
`mut` arguments still violate exclusivity. Definitely-fresh local storage may
always be built and mutated.''', '''The guarantee covers the complete value, including managed descendants of records,
arrays, options, unions and collections. Assignment can move ownership; ordinary
parameters borrow. A `mut` argument exclusively borrows the caller's place to
update. An overlapping read-only argument must use an explicit independent copy.
Multiple mutable child arguments rooted in the same collection are conservatively
rejected, even for distinct constant indices. Definitely-fresh local storage may
always be built and mutated.''')
s = s.replace('''Assignment preserves an independent value. A helper changes its caller's value
only through a `mut` parameter and a marked argument:''', '''Use `.copy()` to preserve an independent value. A helper changes its caller's
value only through a `mut` parameter and a marked argument:''')
s = s.replace('mut copy = original\n', 'mut copy = original.copy()\n')
s = s.replace('''The same rule applies to nested managed values. A copy of an outer list keeps
its inner lists independent when one of them is changed. The implementation may
share storage until a write, but that sharing has no observable mutation effect:''', '''The same rule applies to nested managed values. An explicit copy of an outer
list recursively copies its managed children, keeping both values independent:''')
s = s.replace('''A read-only argument can be the same value as a `mut` argument. The callee reads
its snapshot from before the call while the writable parameter changes the
caller's value. Two `mut` arguments are different: `E_MUTATION_OVERLAP` rejects
two `mut` arguments of one call whose places overlap, such as `f(mut a, mut a)`
or `f(mut a, mut a[0])` (see
[value semantics](value-semantics.md#the-rules)).''', '''A read-only argument cannot borrow a root that the same call mutably borrows.
Copy before the call when the callee needs the original snapshot while changing
the caller's value. Multiple mutable arguments must also have exclusive roots;
`f(mut a, mut a)` and two children rooted in `a` are rejected (see
[value semantics](value-semantics.md#the-rules)).''')
s = s.replace('    mut seen = touch(mut a, a)\n',
              '    const snapshot = a.copy()\n    mut seen = touch(mut a, snapshot)\n')
s = s.replace('''Returning a managed value, or wrapping it in another value, does not give the
caller write access to the callee's input. The returned value is independent;
a caller can update its own copy. A write through a read-only parameter itself
remains `E_MUTATION_MARKER`.''', '''Returning an owned managed value moves it to the caller. A borrowed parameter
cannot become an independent result without `.copy()`. That copy can allocate
and the function's effect ceiling must allow `managed_allocation`. A write
through the borrowed parameter itself remains rejected.''')
s = s.replace('func identity(values: int[]) -> int[] effects():\n    return values\n',
              'func identity(values: int[]) -> int[]:\n    return values.copy()\n')
s = s.replace('''Private helpers derive a return-origin bound from their bodies for ownership
optimization; it does not change the value rule seen by callers.''', '''The compiler checks each move and borrow before lowering. A returned owner must
remain valid independently of the caller's later input replacement; no reference
count or implicit copy is added to repair an invalid return.''')
s = s.replace('''Ordinary parameters are readonly snapshots. A parameter the body
writes with no `mut` is rejected at the write with `E_IMMUTABLE`:''', '''Ordinary parameters borrow read-only storage. A parameter the body
writes with no `mut` is rejected at the write with `E_IMMUTABLE`:''')
s = s.replace('''intersecting its permission mask. The derived capability is an ordinary typed
value: it can be passed, returned and stored in a record field, but it
performs no I/O when it is created and contributes no effect of its own. The old''', '''intersecting its permission mask. Use the dependent capability in a `with`
scope, so its provider stays alive through every use. It can be borrowed by
calls within that scope; storing or returning it beyond the scope is rejected.
Creating it performs no I/O and contributes no effect of its own. The old''')
# These three existing examples each keep the derived capability through the
# remainder of main; preserve all statements and error branches within its scope.
for variable, expression in [('read_only', 'fs.read_only()'),
                             ('scoped', 'fs.dir("data")'),
                             ('scoped', 'net.host("127.0.0.1:8000")')]:
    pattern = r'    mut ' + re.escape(variable) + r' = ' + re.escape(expression) + r'\n(.*?)^```'
    replacement = '    with ' + expression + ' as ' + variable + ':\n'
    def scoped(match):
        return replacement + ''.join('    ' + line if line.strip() else line for line in match.group(1).splitlines(True)) + '```'
    s, count = re.subn(pattern, scoped, s, flags=re.MULTILINE | re.DOTALL)
    assert count == 1, (expression, count)
save('effects.md', s)
(base / 'effect-docs-identities.json').write_text(json.dumps(identities, indent=2) + '\n')
