# Value semantics

This is the default value model of
[D9](adr/D9-value-semantics-then-rc.md). The default runtime implements it with
reference counting and copy-on-write; the `--gc-runtime` opt-out implements the
same rules over the tracing collector.
The one-release compatibility mode restores the previous shared-reference
behavior for code that has not yet migrated.

Under value semantics every `list`, `dict`, `set` and `byte_buffer` is an
independent value, like a record or an `int` already is. Assignment, argument
passing, storing into a field or element, and returning never make two names
reach the same collection. A function changes its caller's value only through a
`mut` parameter, marked `mut` at the call site.

```mylang
# doc: value-semantics
# doc: expect 12
def main() -> int:
    a = [1]
    b = a
    b.append(2)
    return len(a) * 10 + len(b)
```

This returns `12`: `b` is an independent value, so appending to `b` leaves `a`
with one element. Compatibility mode returns `22` because the names share one
list. The syntax resembles Python's; the value rule differs.

## Selecting a mode

- Value semantics need no flag. `--value-semantics` remains an explicit spelling
  for scripts that already use it.
- `--legacy-sharing` temporarily selects the old shared-reference behavior on
  commands that accept the value-semantics flag.
- `"value_semantics": false` in `mylang.json` or
  `MYLANG_VALUE_SEMANTICS=0` in the environment selects compatibility mode;
  `true` or `1` selects value semantics. A command-line flag takes priority over
  the environment, then project configuration, then the default.

The selected mode is part of every cache identity, so a cached check, object or test
result from one mode is never reused in the other. `.api` interface files do
not change.

## The rules

**A copy is your own value.** A local that received a value — from a
parameter, a field, an element, a call — owns it. Changing it needs no `mut`
and does not change the parameter it came from, and a returned value never
aliases an argument:

```mylang
# doc: value-semantics
# doc: expect 21
def appended(xs: list[int]) -> list[int]:
    ys = xs
    ys.append(9)
    return ys

def main() -> int:
    a = [1]
    b = appended(a)
    return len(a) + len(b) * 10
```

A parameter itself stays read-only: `xs.append(9)` in `appended` is
`E_MUTATION_MARKER`, and the message says to declare `xs: mut list[int]` or
to assign it to a local and change the copy.

**`mut` records are `inout`.** A `mut` parameter of a plain `record` or tuple
is the caller's variable: a field assignment, a nested field or collection
write and a rebinding of the whole parameter all reach the caller.

```mylang
# doc: value-semantics
# doc: expect 22
record Counter:
    n: int
    items: list[int]

def bump(c: mut Counter) -> None:
    c.n = c.n + 1
    c.items.append(c.n)

def main() -> int:
    c = Counter(n=0, items=[])
    bump(mut c)
    bump(mut c)
    return c.n * 10 + len(c.items)
```

The argument of a `mut` record must be a mutable local: `mut holder.counter`
or `mut rows[i]` is `E_MUTATION_MARKER` ("copy the field or element into a
local, pass `mut` that local, and store it back"), and a `for` or `match`
binding is `E_IMMUTABLE`. A `mut` list or dict argument may still be an element
or a field, since the callee changes that collection in place.

**Loop variables and match bindings are copies, so writing through one is an
error.** `for row in grid: row.append(0)` would change a copy that is gone when
the iteration ends: it is `E_VALUE_BINDING_WRITE`. The same holds for
`enumerate`, `zip`, `reversed`, `d.values()`, `d.items()` and a named `match`
payload binding of a value another name holds.

```mylang
# doc: value-semantics
# doc: expect-error E_VALUE_BINDING_WRITE
def pad(grid: mut list[list[int]]) -> None:
    for row in grid:
        row.append(0)
```

Change the collection through its place instead, or copy the binding into a
local if the change is meant to stay local:

```mylang
# doc: value-semantics
# doc: expect 22
def pad(grid: mut list[list[int]]) -> None:
    for i in range(len(grid)):
        grid[i].append(0)

def main() -> int:
    grid = [[1], [2]]
    pad(mut grid)
    return len(grid[0]) + len(grid[1]) * 10
```

A `match` on a call result binds the result itself, which nothing else holds.
Under the default mode a `class` declaration is `E_VALUE_CLASS`: use a record or
recursive union for finite values, or a pool handle for stable graph identity.

**Writing into a returned value is an error.** `lookup(table, key).items.append(1)`
changes a temporary copy no name holds: `E_VALUE_TEMPORARY_WRITE`. Assign the
result to a local, change it, and store it back.

**No read-only/writable overlap errors.** `E_MUTATION_OVERLAP` is not
reported for a read-only argument, because it is a value of its own.
Where one could share storage with a `mut` argument of the same call, the
compiler passes a copy taken before the call:

```mylang
# doc: value-semantics
# doc: expect 23
def touch(target: mut list[int], source: list[int]) -> int:
    target.append(len(source))
    return len(source)

def main() -> int:
    a = [1, 2]
    seen = touch(mut a, a)
    return seen * 10 + len(a)
```

The callee sees `source` as `[1, 2]` even though it appends to `target`, which
is the same variable. The natural recursive helper
`walk(adj, node, mut path, mut found)` is accepted.

**Two `mut` arguments must name disjoint places.** A `mut` argument names a
place: a variable plus a path of fields, indices and dictionary keys. Two `mut`
arguments of one call may not name the same place, and one may not be part of
the other, so `f(mut b, mut b)`, `f(mut a, mut a[0])` and `f(mut r, mut r.rows)`
are `E_MUTATION_OVERLAP`. Two indices or keys count as different places only
when both are constants that differ. `f(mut xs[i], mut xs[j])` is rejected
because `i` and `j` may be equal. `f(mut xs[-1], mut xs[2])` is rejected
because a negative index counts back from the end. Different fields, different
constant indices of one sign and different constant keys are disjoint:

```mylang
# doc: value-semantics
# doc: expect 1 2 1 2 1 2
record Pair:
    left: list[int]
    right: list[int]

def fill(a: mut list[int], b: mut list[int]) -> None:
    a.append(1)
    b.append(2)

def main(out: Stream) -> int:
    p = Pair([], [])
    fill(mut p.left, mut p.right)
    rows = [[0], [0], [0]]
    fill(mut rows[0], mut rows[2])
    table = {"a": [0], "b": [0]}
    fill(mut table["a"], mut table["b"])
    out.print(p.left[0], p.right[0], rows[0][1], rows[2][1], table["a"][1], table["b"][1])
    return 0
```

```mylang
# doc: value-semantics
# doc: expect-error E_MUTATION_OVERLAP
def fill(a: mut list[int], b: mut list[list[int]]) -> None:
    a.append(1)
    b.append([2])

def main() -> int:
    rows = [[0]]
    fill(mut rows[0], mut rows)
    return len(rows)
```

The error points at the second of the two arguments and says why they overlap.
To pass one value twice, copy one into a local, pass `mut` that local and store
it back after the call. You can also pass the enclosing value once and reach
both parts through it:

```text
# doc: not-mylang
error[E_MUTATION_OVERLAP]: `fill` receives overlapping `mut` arguments
`mut rows[0]` and `mut rows`: `rows[0]` is part of `rows`, and two `mut`
arguments of one call must name disjoint places. Copy one into a local, pass
`mut` that local and store it back (`copy = rows[0]`, pass `mut copy`, then
`rows[0] = copy`), or pass the enclosing value `mut rows` once
```

The rule holds for every call that takes `mut` arguments, including keyword
arguments and calls through function values, and under `--legacy-sharing` too.
It compares `mut` arguments only: a read-only argument next to a `mut` one
still gets its snapshot, and a `mut` call nested inside another argument
(`emit(mut p, make(mut p))`) finishes before the outer call starts. Because two
`mut` parameters never name the same storage, a callee can read one while it
writes the other.

**A `mut` parameter changed only through a copy.** When the only change to a
`mut` parameter went to a local copy of it, the parameter is never written;
the error says how the change reaches the caller instead of suggesting to drop
`mut`:

```text
# doc: not-mylang
error[E_MUTATION_MARKER]: `rows` is declared `mut` but never written: the only
change goes to `row`, a copy of `rows[i]`; store the copy back after changing it
(`rows[i] = row`) so the change reaches the caller
```

## Explicit identity and immutable sharing

- A `class` declaration is `E_VALUE_CLASS`, including an unused declaration.
  A finite tree can use a recursive value type. A graph with cycles or
  observable identity uses `pool.Pool[T]` and `pool.Handle[T]`, or another
  explicit id with a store-back after mutation.
- The builtin `Cell[T]` is `E_VALUE_CELL` in type positions and calls. A local
  mutable slot is a record changed through `mut`; a shared slot uses a pool
  handle. An ordinary user-defined record named `Cell` remains legal.
- Under `--legacy-sharing`, existing classes and builtin Cells continue to
  compile during the one-release migration window.
- `str` and `bytes` are immutable, so sharing them is invisible.

```mylang
# doc: value-semantics
# doc: expect-error E_VALUE_CLASS
class Node:
    next: Option[Node]
```

```mylang
# doc: value-semantics
# doc: expect-error E_VALUE_CELL
def read(slot: Cell[int]) -> int:
    return slot.value
```

## Arenas and contracts

A transfer made inside `with arena()` usually marks an existing collection
shared without allocating. When a later write must clone a shared payload,
the clone uses that payload's owning region. In particular, writing an outer
value while an inner arena is open cannot leave its new storage dangling when
the inner arena ends. New collections still allocate in the current arena and
leave it only through `escape` ([arenas](arenas.md#getting-a-result-out)). The
static escape rules and runtime store barrier apply unchanged.

`old(xs)` of a collection is accepted in an `@ensures` clause: the capture is a
value of its own. The compatibility checker still rejects an `old(...)` value that
reaches a `class` or builtin Cell with `E_CONTRACT_OLD_SHARED`
([contracts](contracts.md)).

## How it is implemented

Lowering places one `value_copy` instruction after every transfer that is not
fresh. The ownership analysis of stage 2
([ownership](tooling/ownership.md)) then leaves out every copy it proves a move
(the source is never read again) or a borrow (neither side is written while
both are read); `mylang check --explain-ownership` lists each copy site with
`"copy": true` or `false`. A remaining copy takes shallow private scratch and
marks its held mutable collection payloads shared. Fixed flat records and
arrays mark up to eight payloads inline; boxed, variant and larger values use
a rooted runtime transfer, as does a pinned payload that must be cloned. A
read-only argument is lent without a copy, unless a later operand of the same
expression may write it: `lst(xs, xs.pop())` and `out.print(xs, push(mut xs))`
see `xs` as it was when it was evaluated, because lowering copies it then. Before a write, an inline check
clones a shared payload and redirects the owning slot; nested writes repeat
that step along their path, including fixed-array elements and alternating
list and dictionary lookups such as `changed[0]["items"][0].append(2)`.
Every intermediate collection belongs to the changed value, so an earlier snapshot keeps its
original contents. Receivers and keys still evaluate once in source order.
A read also captures its receiver value before evaluating the key. For example,
if `values` is `[7, 8]`, then `values[change(mut values)]` reads the captured
list even when `change` clears `values`, appends `91` and returns `0`: the read
returns `7`, and `values` is `[91]` afterward. A negative index is normalized
using the captured list's length. The same rule applies to dictionary keys;
copying an already pinned receiver preserves the caller's mutation target.
If an array index calls a function, the receiver evaluated before that call
keeps its identity. Replacing or removing its containing entry leaves the
pending write on the old value. Updating another entry, growing a dictionary,
or moving a list element keeps the pending write on the selected value.
This also holds when a replacement is equal to the old value or the callback
saves a snapshot of the parent. Temporary pins protect just the selected
field path and its possible array elements; unrelated recursive branches
stay lazy. The pins are released when evaluation finishes or returns early.
Checks proven stable across a loop are hoisted.

For internal measurements, `MYLANG_COW_COUNTING=1` in the default value mode
builds a separately cached instrumented binary. At exit it
prints a `cow-stats` JSON line on stderr with marks, checks, hoisted checks,
copies, copied bytes and pins. Legacy-sharing runs ignore this selector;
ordinary builds emit no counter calls.

## Limits

- A transfer carries immutable recursive boxes without walking their bodies.
  Projecting a box makes a private shallow snapshot and shares its immediate
  mutable children; a write through a box detaches it first. Box hops alone
  do not consume the copy-on-write depth budget, so a deep boxed chain can be
  copied and traversed. Inline record, array and variant descriptor walks
  remain bounded at 1,024 edges and trap `R_COW_DEPTH` if exceeded rather
  than leaving a mutable child unshared.
- A copy is not reported as a `managed_allocation` effect.
- Rebinding a whole `mut` list or dict parameter does not reach the caller; it
  is rejected as a `mut` that is never written.
- A function with a `mut` record parameter cannot be a function value, and a
  callback type with one cannot take a lambda.
- A write to a local copy that is never read or stored back afterwards is not
  diagnosed; only writes through bindings and into returned values are.
