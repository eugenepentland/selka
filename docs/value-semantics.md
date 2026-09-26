# Value semantics

This is the default value model of
[D9](adr/D9-value-semantics-then-rc.md) on the current garbage-collected runtime.
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
read-only argument is lent without a copy. Before a write, an inline check
clones a shared payload and redirects the owning slot; nested writes repeat
that step along their path. Checks proven stable across a loop are hoisted.

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
