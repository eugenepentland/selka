"""Prepare C2 documentation replacements; never edit current published pages."""
import hashlib
import json
from pathlib import Path

base = Path(__file__).resolve().parent
root = base.parents[3]
changes = {}
def load(name):
    return (root / 'docs' / name).read_text()
def save(name, text):
    dest = base / 'reference-docs' / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(text)
    original = root / 'docs' / name
    changes[str(original.relative_to(root))] = dict(original_sha256=hashlib.sha256(original.read_bytes()).hexdigest(), draft=str(dest.relative_to(root)), draft_sha256=hashlib.sha256(dest.read_bytes()).hexdigest())

s = load('performance.md')
s = s.replace('Memory is reference counted with\ncopy-on-write: a value is released when its last owner lets go of it, so there is no\ncollector to pause and no heap to tune.', 'The compiler checks ownership and inserts direct destruction. Ordinary\nallocation and container growth remain; there is no reference-counting runtime\nor collector to tune for generated guest programs.')
s = s.replace('how often a value is shared and then written', 'how often a program grows storage or explicitly copies it')
start = s.index('## Records are values, not copies')
end = s.index('```mylang', start)
s = s[:start] + '''## Moves, borrows and independent copies

Assignments of records or containers with managed storage can move ownership.
Ordinary function parameters borrow. Use `copy = xs.copy()` when both independent
values must remain usable; copying recursively duplicates managed children.
A `mut` parameter borrows exclusively during the call and writes its final value
back. Mutations can grow storage but never fall back to shared copy-on-write
storage. See [ownership](tooling/ownership.md) for the checked boundaries.

`mylang build --stats` reports the compiler's static decisions. These are sites,
not runtime events or allocation traffic. Historical `release` fields can describe
direct cleanup sites; they do not by themselves show runtime reference counting.

''' + s[end:]
s = s.replace('To keep a hot loop free of copies, write a value that only one name holds: build a\nlist in the function that changes it, or pass it as `mut` instead of returning a\nchanged copy of an argument the caller still reads.', 'To avoid unnecessary copies in a hot loop, build and update an owned list locally\nor pass it with a marked `mut` call. Make a snapshot with `.copy()` only when both\nindependent values are needed; preserve that source contract when comparing costs.')
start = s.index('```console\n$ mylang build scale.my')
end = s.index('```', start+4) + 3
s = s[:start] + '```bash\nmylang build scale.my -o scale --release --stats\n```\n\nThe counts depend on the exact source, compiler and build mode; save them with\nthose identities when making comparisons.' + s[end:]
s = s.replace('- [Value semantics](value-semantics.md): when a write copies.', '- [Value semantics](value-semantics.md): moves and independent explicit copies.')
save('performance.md', s)

s = load('python-syntax.md')
s = s.replace('lists, strings and dictionaries by reference counting with copy-on-write; there is\nno garbage collector to tune. There are no allocator arguments\nor ownership annotations in ordinary data code.', 'lists, strings and dictionaries with checked ownership and direct destruction.\nAssignments and returns can move; ordinary parameters borrow, and `.copy()` makes\nindependent storage. There are no allocator arguments or ownership annotations\nin ordinary data code.')
s = s.replace('Lists infer a homogeneous element type from nonempty literals. Assignment creates\nan independent value snapshot; managed storage is copied when a write needs it.', 'Lists infer a homogeneous element type from nonempty literals. Assignment can\nmove the owner; use `.copy()` when an independent snapshot must remain usable.')
s = s.replace('have a single inferred or annotated type. Updates through an alias are shared.', 'have a single inferred or annotated type. Assignment can move the dictionary;\n`.copy()` preserves an independent dictionary, including its managed children.')
s = s.replace('mut saved = items\n', 'mut saved = items.copy()\n')
s = s.replace('Assigning a record copies its value. Later writes preserve the other value\'s\nsnapshot, including managed fields.', 'Assigning a record with managed fields can move ownership. Use `.copy()` for\nan independent record that recursively copies those fields.')
s = s.replace('methods and no `len`; take it apart', 'indexing or `len`; `.copy()` makes an independent tuple. Take it apart')
s = s.replace('A tuple has no fields, no indexing, no\n', 'A tuple has no fields, no\n')
s = s.replace('small: dict[str, u8] = {k: 0 for k in names}', 'small: dict[str, u8] = {k.copy(): 0 for k in names}')
s = s.replace('mut doubled = {name: price * 2 for name, price in prices.items()', 'mut doubled = {name.copy(): price * 2 for name, price in prices.items()')
s = s.replace('mut paired = {k: v for k, v in zip', 'mut paired = {k.copy(): v for k, v in zip')
s = s.replace('    return player.name\n', '    return player.name.copy()\n')
s = s.replace('key=lambda p: (p.team, p.name)', 'key=lambda p: (p.team, p.name.copy())')
start = s.index('Iteration over a place reads its current value on every step.')
end = s.index('```mylang', start)
s = s[:start] + """A foreach over a managed collection borrows the root collection. Moving,
replacing or mutating that root during the loop is rejected, including a write to
a different constant index. Copies made before a loop remain independent and may
be changed separately. Managed loop elements borrow their container; use `.copy()`
when an independent element must escape.

Use an explicit index loop when the algorithm must change its source collection.
The example below tests the current length on every iteration, so appended values
are visited. Capture the initial length instead when an algorithm must visit only
the original extent. Reading the scalar element before mutation preserves its
value for the rest of that iteration.

""" + s[end:]
s = s.replace("""    for value in items:
        total += value
        items[1] = 9
        if value == 9:
            items.append(3)
""", """    mut index = 0
    while index < len(items):
        const value = items[index]
        total += value
        items[1] = 9
        if value == 9:
            items.append(3)
        index += 1
""")
save('python-syntax.md', s)

s = load('current-language.md')
s = s.replace('Value semantics: lists, dictionaries, sets and byte buffers are independent values; one-count reference counting with copy-on-write releases each value when its last owner goes away; no collector and no runtime choice', 'Checked ownership: assignments and returns can move; ordinary parameters borrow; `.copy()` recursively creates independent storage; direct destruction ends each owner')
s = s.replace('Immutable reference-counted byte strings', 'Immutable owned byte strings')
s = s.replace('Memory safety combines automatic reclamation (one-count reference counting) with\nthe runtime\'s checked pool handles and generations.', 'Memory safety combines compiler-checked moves and borrows, direct destruction,\nand the runtime\'s checked pool handles and generations.')
s = s.replace('Fifteen embedded modules over managed types:', 'Embedded modules over managed types include')
s = s.replace('The [standard library guide](standard-library.md) lists the fifteen embedded modules that ship with the compiler, their signatures and their bounded contracts.', 'The [standard library guide](standard-library.md) lists the embedded modules that ship with the compiler, their signatures and their bounded contracts.')
s = s.replace('guest-source JSON operations were removed with the explicit storage tier', 'the `json` module borrows lookup inputs and returns independent selected values')
save('current-language.md', s)

s = load('tooling/native-build.md')
s = s.replace('one-count reference counting with copy-on-write: collections and records are values,\nand nothing is collected or traced.', 'compiler-checked ownership and direct destruction. Assignments and returns can\nmove, ordinary parameters borrow, and `.copy()` makes independent storage.\nUnsupported ownership shapes are rejected before guest lowering. Allocation,\ncontainer growth and direct freeing remain ordinary runtime operations.')
s = s.replace('  updates, copies, retains and releases.', '  updates and copy/cleanup sites. Historical retain/release labels in the static\n  schema do not measure runtime RC events.')
s = s.replace('  the release passes, with their intervals); `--emit-llvm PATH` writes the LLVM text.', '  the release passes, with their intervals). It can expose intermediate Core that\n  native lowering subsequently refuses; dump success is not executable admission.\n  `--emit-llvm PATH` on build writes emitted LLVM text.')
save('tooling/native-build.md', s)

s = load('tooling/guest-tests.md')
s = s.replace('It is neither a pass nor a failure.', 'It is neither a pass nor a failure under the current exit-status contract.\nA qualification gate must inspect the report and require `unsupported == 0`;\nprocess status 0 alone does not qualify every selected test.')
s = s.replace('none: one-count reference counting and value semantics are the only modes', 'none: checked ownership is the ordinary guest contract; use `.copy()` for independent values')
s += '''\n## Ownership and cached tests\n\nTests use the same checked moves, borrows and explicit copies as ordinary builds.\nThis includes generated property inputs, provider stand-ins, directory children\nand cached runs. Source ownership checking stays eager: an old success receipt\ncannot admit a new invalid move in an unused helper. Receipts bind the compiler\nidentity and selected ABI; old RC artifacts cannot become checked-owned artifacts.\n\nSee [ownership](ownership.md) for source migrations and the separate qualification\nboundary for installed compiler components.\n'''
save('tooling/guest-tests.md', s)

s = load('tooling/cost.md')
s = s.replace('Ownership decisions: proved unique, run-time uniqueness branch, or unconditional copy', 'Static update decisions; checked-owned updates never use a reference-count uniqueness test')
s = s.replace('growth and conditional copies count even when an execution does not allocate', 'growth counts even when an execution already has sufficient capacity')
s = s.replace('RC operations inserted by ownership, after paired operations are elided', 'Historical schema labels for retain/cleanup sites; a direct owned cleanup is not a runtime RC event')
s = s.replace('including cold error paths. It runs before release optimization, after debug\nownership exposes conditional and unconditional copy-on-write allocations.', 'including cold error paths. It runs before release optimization, after eager\nsource ownership checking and selected owned lowering expose explicit copies,\nmaterialization and potentially allocating runtime helpers.')
s += '''\nBorrowed text/byte ranges and audited identity helpers are allocation-free.\nIndependent text encoding, buffer reversal and `.copy()` may allocate even when\nthe output length is unchanged. A source foreign function cannot acquire a native\nhelper's audited contract by using a similar name. Static costs, runtime allocation\ntraffic, managed peak bytes and process RSS are different measurements.\n'''
save('tooling/cost.md', s)
(base / 'reference-docs' / 'identities.json').write_text(json.dumps(changes, indent=2) + '\n')
