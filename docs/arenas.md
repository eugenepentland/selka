# Managed arenas

`with arena() as name:` opens a region for the managed values described in
[managed memory](managed-memory.md). Lists, strings, dictionaries and records
keep the same types. Native allocation uses aligned, zero-filled bump storage
inside shared chunks, without a garbage-collector header before each payload.
The chunks are released together when the block ends.

This is the language's only manual-memory control. There is no explicit storage
tier, no allocator parameter to thread and no borrow annotation to write: an
arena block is the single place where a program says anything about *when*
memory goes away.

```mylang
# doc: expect 204
def squares(limit: int) -> list[int]:
    values: list[int] = []
    for index in range(limit):
        values.append(index * index)
    return values

def main() -> int:
    total = 0
    with arena() as scratch:
        values = squares(9)
        for value in values:
            total = total + value
    return total
```

This prints `204`. `squares` has no idea an arena exists; it is the *dynamic*
extent of the block that decides where allocation lands, so helpers, nested calls
and standard-library code all allocate into `scratch`. The list is not traced at
the end of the block, it is simply freed.

Arenas nest, and the innermost one wins:

```mylang
# doc: expect 7
def sized(limit: int) -> list[int]:
    values: list[int] = []
    for index in range(limit):
        values.append(index)
    return values

def main() -> int:
    total = 0
    with arena() as outer:
        first = sized(3)
        with arena() as inner:
            second = sized(4)
            total = total + len(second)
        total = total + len(first)
    return total
```

This prints `7`. `second` is freed when `inner` ends; `first` survives until
`outer` ends, because it was allocated while `outer` was innermost.

## Getting a result out

Everything allocated inside the block dies with it, so a result has to be copied
out. `name.escape(value)` deep-copies the part of the graph reachable from `value`
that lives in the current arena into the enclosing region — the parent arena, or
the ordinary heap when there is no parent. Objects that already live in an older
region are shared, not copied, and sharing and cycles inside the copied part are
preserved.

```mylang
# doc: expect 34
def main() -> int:
    kept: list[list[int]] = []
    with arena() as scratch:
        shared: list[int] = [7]
        holder: list[list[int]] = [shared, shared]
        kept = scratch.escape(holder)
    return len(kept) * 10 + kept[0][0] + kept[1][0]
```

This prints `34`. `shared` appears twice in `holder`; the copy has two references
to a single new list, not two independent lists.

Assign the escaped value to a binding declared **before** the block, then use it
after the block. Locals are function-scoped, so a binding first created inside the
block is still in scope afterwards — but a managed one is *confined*: it lives in
the released region, so reading it after the block is a static `E_ARENA_ESCAPE`
rather than a dangling read. Reassigning the name after the block re-homes it to
the current region and clears the confinement, and a scalar carries nothing and is
read freely.

The arena binding itself is opaque. It cannot be stored in a variable, passed to a
function, returned, compared, or shadowed; the only thing you can write is
`name.escape(value)`, and it must name the innermost active arena. `with arena():`
without a name is also accepted when nothing needs to escape.

## What the checker rejects

Inside a block the checker rejects, with `E_ARENA_ESCAPE`, the ways a managed
value could outlive the arena:

- assigning a managed-bearing value to a binding declared before the block
- returning a managed-bearing value
- `outer.append(value)`, `outer[index] = value`, `outer[key] = value` and
  `outer.field = value` when `outer` was declared before the block

A *managed-bearing* type is any type whose values may hold a collected reference:
`list`, `dict`, `str`, and records, unions, options and results with such
payloads. Integers, floats, booleans, enums, domains over scalars and records
with only scalar fields carry nothing and may leave freely, which is why
accumulating a count or a sum in an outer binding works:

```mylang
# doc: expect 14
def main() -> int:
    total = 0
    with arena() as scratch:
        words: list[str] = ["alpha", "beta", "gamma"]
        for word in words:
            total = total + len(word)
    return total
```

This prints `14`.

The single exception is `escape`, whose result belongs to the enclosing region:

```mylang
# doc: expect 38
record Reading:
    sensor: int
    samples: list[int]

def collect(sensors: int, per_sensor: int) -> list[Reading]:
    readings: list[Reading] = []
    for sensor in range(sensors):
        samples: list[int] = []
        for index in range(per_sensor):
            samples.append(sensor * per_sensor + index)
        readings.append(Reading(sensor=sensor, samples=samples))
    return readings

def main() -> int:
    kept: list[int] = []
    with arena() as scratch:
        readings = collect(3, 4)
        kept = scratch.escape(readings[2].samples)
    total = 0
    for sample in kept:
        total = total + sample
    return total
```

This prints `38`. The runnable version of this program is
[examples/arena-managed/main.my](../examples/arena-managed/main.my).

A diagnostic names the escaping expression, the arena, and the binding that would
outlive it, and is available through `--diagnostics=json` like every other
diagnostic.

## What the runtime enforces

The static rules are deliberately shallow: they only look at direct stores in the
block's own text. A helper can still be handed an outer collection and an arena
value and asked to put one in the other. Runtime allocation metadata records the arena
depth that owns it, and every store of a managed reference into a heap object —
list append, list slot write, dictionary key or value write, a record snapshot
holding either — checks that depth. Storing a younger object into an older
container traps with a located `R_ARENA_ESCAPE` rather than leaving a dangling
reference:

```text
# doc: not-mylang
def stash(outer: list[list[int]], inner: list[int]) -> None:
    outer.append(inner)

def main() -> int:
    keeper: list[list[int]] = []
    with arena() as scratch:
        temp: list[int] = [1]
        stash(keeper, temp)
    return len(keeper)
```

That program checks cleanly and traps with `R_ARENA_ESCAPE` on the
`outer.append(inner)` line, which is why it is not tagged as a runnable example.
Depth comparison is enough because every live object belongs to an arena that is
still on the stack.

At the end of a block the runtime also rescans the bindings declared before it and
traps if any of them still reaches arena storage, then frees the arena. Normal
exit, `return`, `?` propagation, `break` and `continue` out of the block, and
traps unwinding through it all release the arena exactly once.

Both QBE and LLVM native builds use the same arena runtime, store barrier, bulk
release and `escape` copy. A program with no arena scope pays for neither the
barrier nor the per-frame depth bookkeeping. In an arena-using program, only
functions that open a scope save and restore their depth; other helpers still
check managed stores. Growing an older collection inside
a younger arena allocates its replacement backing in the collection's own region.

## Interaction with collection

Arenas do not turn collection off. Ordinary GC allocations still use the tracing
heap, and `--gc-stress` still collects at allocation safepoints inside an arena.
Arena allocations remain alive until scope exit, including old collection backing
after growth. They are never individually swept or queued for graph marking.

An arena may hold the last reference to an older GC object. Compact side
descriptors let a collection scan arena contents for these references, retaining
the GC objects safely. This scan retains references from all allocations in the
live arena, including values the program no longer uses. A pure arena workload
does not trigger automatic collection just because its arena grows: the normal
collection threshold measures GC bytes. Chunk growth can request collection to
recover GC bytes before reporting a memory-budget failure.

The memory budget charges the actual reserved chunks, including alignment,
descriptor space and unused capacity. Small budgets use smaller chunks; a failed
reservation does not consume budget. Runtime statistics separately count scopes,
arena allocations, objects bulk released, escape copies, chunk allocations and
current/peak reserved arena bytes. No guest module exposes these counters.

Allocation inside an arena is still allocation: it contributes the
`managed_allocation` effect, so `noalloc` rejects it exactly as it rejects
allocation outside a block, and `escape` carries that effect too. Entering the
block itself needs no effect.

## Limits

Current limits:

- Allocation metadata still occupies compact side records in each chunk. GC can
  scan those records to preserve older references; this is not a proof that every
  arena is isolated from the GC heap.
- Arena backing is retained until scope exit. A long-lived arena can use more
  memory than ordinary GC; use shorter scopes for repeated temporary work.
- `with` supports only `with arena()`. It is not yet the general resource
  statement; `acquire_resource`/`complete_resource` keep their existing spelling.
- Arena scopes are rejected inside generic function bodies with
  `E_GENERIC_BODY_UNSUPPORTED`.
- The static rules are conservative in one direction and shallow in the other.
  They reject some safe programs (any assignment of a managed-bearing value to an
  outer binding, even one that could never reach arena storage) and they do not
  attempt to see through helpers — the runtime barrier does that instead.
- `escape` copies. There is no move or promotion of an object that happens to be
  uniquely referenced.
