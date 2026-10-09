# Value semantics

This is mylang's one value model ([D9](adr/D9-value-semantics-then-rc.md)). The
runtime implements it with reference counting and copy-on-write; there is no
other mode and no switch to select one.

Under value semantics every `list`, `dict`, `set` and `byte_buffer` is an
independent value, like a record or an `int` already is. Assignment, argument
passing, storing into a field or element, and returning never make two names
reach the same collection. A function changes its caller's value only through a
`mut` parameter, marked `mut` at the call site.

```mylang
# doc: expect 12
func main() -> int:
    mut a = [1]
    mut b = a
    b.append(2)
    return len(a) * 10 + len(b)
```

This returns `12`: `b` is an independent value, so appending to `b` leaves `a`
with one element; Python would return `22`, because there both names reach one
list. The syntax resembles Python's; the value rule differs.

The retired flags `--value-semantics` and `--legacy-sharing` are refused with
status 2.

## The rules

**A copy is your own value.** A local that received a value — from a
parameter, a field, an element, a call — owns it. Changing it needs no `mut`
and does not change the parameter it came from, and a returned value never
aliases an argument:

```mylang
# doc: expect 21
func appended(xs: int[]) -> int[]:
    mut ys = xs
    ys.append(9)
    return ys

func main() -> int:
    mut a = [1]
    mut b = appended(a)
    return len(a) + len(b) * 10
```

A parameter itself stays read-only: `xs.append(9)` in `appended` is
`E_MUTATION_MARKER`, and the message says to declare `xs: mut list[int]` or
to assign it to a local and change the copy.

**`mut` records are `inout`.** A `mut` parameter of a plain `record` or tuple
is the caller's variable: a field assignment, a nested field or collection
write and a rebinding of the whole parameter all reach the caller.

```mylang
# doc: expect 22
record Counter:
    n: int
    items: int[]

func bump(mut c: Counter) -> Unit:
    c.n = c.n + 1
    c.items.append(c.n)

func main() -> int:
    mut c = Counter(n=0, items=[])
    bump(mut c)
    bump(mut c)
    return c.n * 10 + len(c.items)
```

The argument of a `mut` record must be a mutable local: `mut holder.counter`
or `mut rows[i]` is `E_MUTATION_MARKER` ("copy the field or element into a
local, pass `mut` that local, and store it back"), and a `for` or `match`
binding is `E_IMMUTABLE`. A `mut` list or dict argument may still be an element
or a field, since the call updates that collection place, including a whole rebinding.

**A whole `mut` binding belongs to the caller.** Rebinding a `mut` list,
dictionary, set, record or tuple parameter updates the caller's variable,
including inside a loop or on only one branch. Values used as read-only
sources and copies saved before the call stay independent. A `mut` fixed
array can be updated element by element; rebinding it remains
`E_ASSIGNMENT_TARGET`.

A whole-local mut argument names the caller's current variable when the call
starts, after all arguments evaluate. An interior argument such as `mut rows[0]`
retains the collection selected when that argument evaluates. If a later
argument replaces that entry, the callee changes the held old collection and
leaves the replacement intact. If the entry is unchanged, whole rebinding by
the callee publishes its final value into that entry.

```mylang
# doc: expect 27

func replace(mut items: int[], source: int[], choose: bool):
    if choose:
        items = source
    items.append(7)

func main() -> int:
    mut items = [1]
    mut source = [2]
    replace(mut items, source, True)
    return items[0] * 10 + items[1]
```

**Loop variables and match bindings are copies, so writing through one is an
error.** `for row in grid: row.append(0)` would change a copy that is gone when
the iteration ends: it is `E_IMMUTABLE`. The same holds for
`enumerate`, `zip`, `reversed`, `d.values()`, `d.items()` and a named `match`
payload binding of a value another name holds.

```mylang
# doc: expect-error E_IMMUTABLE
func pad(mut grid: int[][]) -> Unit:
    for row in grid:
        row.append(0)
```

Change the collection through its place instead, or copy the binding into a
local if the change is meant to stay local:

```mylang
# doc: expect 22
func pad(mut grid: int[][]) -> Unit:
    for i in range(len(grid)):
        grid[i].append(0)

func main() -> int:
    mut grid = [[1], [2]]
    pad(mut grid)
    return len(grid[0]) + len(grid[1]) * 10
```

Match payloads are read-only too; make an explicit `mut` local copy to edit one.
A `class` declaration is `E_VALUE_CLASS`: use a record or recursive union for
finite values, or a pool handle for stable graph identity.

**Writing into a returned value is an error.** `lookup(table, key).items.append(1)`
changes a temporary copy no name holds: `E_VALUE_TEMPORARY_WRITE`. Assign the
result to a local, change it, and store it back.

**No read-only/writable overlap errors.** `E_MUTATION_OVERLAP` is not
reported for a read-only argument, because it is a value of its own.
Where one could share storage with a `mut` argument of the same call, the
compiler passes a copy taken before the call:

```mylang
# doc: expect 23
func touch(mut target: int[], source: int[]) -> int:
    target.append(len(source))
    return len(source)

func main() -> int:
    mut a = [1, 2]
    mut seen = touch(mut a, a)
    return seen * 10 + len(a)
```

The callee sees `source` as `[1, 2]` even though it appends to `target`, which
is the same variable. The natural recursive helper
`walk(adj, node, mut path, mut found)` is accepted.

**Finish an overlapping `mut` call before updating its receiver.** A statement
such as `items[selected(mut items)] = 9` or
`rows[0].append(clear_rows(mut rows))` is `E_MUTATION_OVERLAP`: the update's
receiver overlaps a mutable argument evaluated in the same statement. The
same-root rule follows field and index paths until either path ends. Disjoint
fields or roots stay legal, and read-only arguments keep their snapshots.
Save the call's result first, then select the receiver from its current value:

```mylang
# doc: expect 19

func selected(mut items: int[]) -> int:
    items.append(2)
    return 1

func main() -> int:
    mut items = [1]
    mut index = selected(mut items)
    items[index] = 9
    return items[0] * 10 + items[index]
```

For a simple unconditional update, `mylang fix` performs that split. An
expression with other effects or conditional evaluation needs an explicit
choice of order.

**Two `mut` arguments must name disjoint places.** A `mut` argument names a
place: a variable plus a path of fields, indices and dictionary keys. Two `mut`
arguments of one call may not name the same place, and one may not be part of
the other, so `f(mut b, mut b)`, `f(mut a, mut a[0])` and `f(mut r, mut r.rows)`
are `E_MUTATION_OVERLAP`. Different fields and distinct known indices or keys are disjoint. For dynamic
indices, keys or negative indices, the compiler captures each place once and
checks overlap before the function runs. `f(mut xs[i], mut xs[j])` is allowed
when the resolved elements differ and traps before the callee when they coincide:

```mylang
# doc: expect 1 2 1 2 1 2
record Pair:
    left: int[]
    right: int[]

func fill(mut a: int[], mut b: int[]) -> Unit:
    a.append(1)
    b.append(2)

func main(out: Stream) -> int:
    mut p = Pair(left=[], right=[])
    fill(mut p.left, mut p.right)
    mut rows = [[0], [0], [0]]
    fill(mut rows[0], mut rows[2])
    mut table = {"a": [0], "b": [0]}
    fill(mut table["a"], mut table["b"])
    out.print(p.left[0], p.right[0], rows[0][1], rows[2][1], table["a"][1], table["b"][1])
    return 0
```

```mylang
# doc: expect-error E_MUTATION_OVERLAP
func fill(mut a: int[], mut b: int[][]) -> Unit:
    a.append(1)
    b.append([2])

func main() -> int:
    mut rows = [[0]]
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
`mut` that local and store it back (`mut copy = rows[0]`, pass `mut copy`, then
`rows[0] = copy`), or pass the enclosing value `mut rows` once
```

The rule holds for every call that takes `mut` arguments, including keyword
arguments and calls through function values. It compares `mut` arguments only: a read-only argument next to a `mut` one
still gets its snapshot, and a `mut` call nested inside another argument
(`emit(mut p, make(mut p))`) finishes before the outer call starts. Because two
`mut` parameters never name the same storage, a callee can read one while it
writes the other.

**A change through a copy stays local.** A `mut` parameter permits updates to
the caller but does not require them. If the function copies `rows[i]` into a
local `mut row`, changing `row` leaves `rows` unchanged. Store the result back
with `rows[i] = row` when the update should reach the caller.

## Explicit identity and immutable sharing

- A `class` declaration is `E_VALUE_CLASS`, including an unused declaration.
  A finite tree can use a recursive value type. A graph with cycles or
  observable identity uses `pool.Pool[T]` and `pool.Handle[T]`, or another
  explicit id with a store-back after mutation.
- The builtin `Cell[T]` is `E_VALUE_CELL` in type positions and calls. A local
  mutable slot is a record changed through `mut`; a shared slot uses a pool
  handle. An ordinary user-defined record named `Cell` remains legal.
- `str` and `bytes` are immutable, so sharing them is invisible.

```mylang
# doc: expect-error E_VALUE_CLASS
class Node:
    next: Node?
```

```mylang
# doc: expect-error E_VALUE_CELL
func read(slot: Cell[int]) -> int:
    return slot.value
```

## Contracts

`old(xs)` of a collection is accepted in an `@ensures` clause: the capture is a
value of its own ([contracts](contracts.md)).

## How it is implemented

A `list`, `dict`, `set`, `byte_buffer` or recursive box keeps its contents in
heap storage with a single reference count. Assignment, argument passing, storing
and returning share that storage and add a reference; nothing is copied there. A write first tests the
count: storage with one owner is written in place, and shared storage is copied and
the copy written (copy-on-write). Nested writes repeat that step along their path,
including fixed-array elements and alternating list and dictionary lookups such
as `changed[0]["items"][0].append(2)`, so an earlier snapshot keeps its original
contents. Storage is freed when its last reference goes away; there is no
collector.

A release build's ownership pass removes most of that work. It proves where a
value's old version is never read again, so a write needs neither the count test
nor the copy, and where a retain and a release cancel. `mylang build --release
--stats` prints its counts: updates in place, writes left to a run-time count test,
copies, and the retains and releases it kept (see
[performance](performance.md#measure)).

Receivers and keys evaluate once, in source order, and a read captures its
receiver before evaluating the key. For example, if `values` is `[7, 8]`, then
`values[change(mut values)]` reads the captured list even when `change` clears
`values`, appends `91` and returns `0`: the read returns `7`, and `values` is
`[91]` afterward. A negative index counts from the captured list's length. The
same rule applies to dictionary keys. A read-only argument sees its value as it
was when it was evaluated, so `both(xs, xs.pop())` passes `xs` before the pop.
A statement that updates a receiver while an evaluated `mut` call overlaps it is
rejected; call first, then perform the update in a separate statement.

## Limits

- Copying a recursive value shares its boxes without walking their bodies, and a
  write through a box copies only the boxes on its path, so a deep chain can be
  copied and traversed.
- A copy is not reported as a `managed_allocation` effect.
- A function with a `mut` record parameter cannot be a function value, and a
  callback type with one cannot take a lambda.
- A write to a local copy that is never read or stored back afterwards is not
  diagnosed; only writes through bindings and into returned values are.
