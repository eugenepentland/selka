# Performance

`mylang run prog.my` builds `prog.my` and runs the native executable; there is no
interpreter to outgrow. The compiler lowers the checked program to Core IR, runs its
passes, emits LLVM text, compiles it with `zig cc` and links it with the C runtime
([native builds](tooling/native-build.md)). Memory is reference counted with
copy-on-write: a value is released when its last owner lets go of it, so there is no
collector to pause and no heap to tune.

Most programs need no performance work. Four things change the answer: the build
mode, the budgets a run carries, how often a value is shared and then written, and C.
This page covers each, then how to measure a program of your own.

## Records are values, not copies

A record is a value: assigning one, passing one to a function or binding one in a
pattern match never lets a later write reach the original. The same holds for every
`list`, `dict`, `set` and `byte_buffer` a record holds
([value semantics](value-semantics.md)). The cost of that meaning is a copy only
when a shared value is written:

- Storage is shared until a write. `copy = xs` shares the list's storage, and the
  first write through either name copies it (copy-on-write).
- A write to a value nothing else shares happens in place. The ownership pass proves,
  where it can, that the old value is dead or has exactly one owner, and writes into
  it. Where it cannot prove that, the write tests the reference count at run time and
  copies only when the count says the storage is shared.
- A `mut` parameter is owned by the callee for the call: when the caller does not read
  its value again before the write-back, the call passes it without taking a new
  reference and the callee updates it in place.

`mylang build --stats` prints what the ownership pass did for a build: how many
updates it made in place, how many it left to a run-time count test and how many it
copied, plus the retains and releases it emitted (see [Measure](#measure)).

```mylang
# doc: expect 42
record Point:
    x: int
    y: int


def shifted(point: Point) -> Point:
    return Point(x=point.x + 1, y=point.y + 1)


def total(point: Point) -> int:
    return point.x + point.y


def main() -> int:
    start = Point(x=1, y=2)
    moved = shifted(start)
    if start.x != 1 or start.y != 2:
        return 1
    if moved.x != 2 or moved.y != 3:
        return 2
    if total(start) + total(moved) != 8:
        return 3
    return 42
```

To keep a hot loop free of copies, write a value that only one name holds: build a
list in the function that changes it, or pass it as `mut` instead of returning a
changed copy of an argument the caller still reads.

## Build for speed

`mylang build`, `mylang run` and `mylang test` build in **debug** mode by default: one
LLVM unit per source module (plus units for generic instances, adapters and the
entry), compiled without optimization, so an edit recompiles only the units whose
text changed. `--release` (also spelled `--mode ReleaseFast`) builds the whole
program as one LLVM unit and optimizes it: the core's release passes run first
(inlining, the fact pass that proves checks, loop unswitching and versioning,
ownership), then LLVM optimizes across every module boundary.

```bash
mylang build prog.my -o prog                  # debug: the edit-loop build
mylang build prog.my -o prog-fast --release   # optimized whole program
mylang run prog.my --release
mylang test tests/ --release
```

Use `--release` for a binary you ship or time, and the default in the edit loop: a
release build recompiles the whole program after any change, while a debug build
recompiles only the changed modules. C sources passed with `--link` are compiled at
the program's level (`-O0` in debug, `-O3` in release); the runtime is compiled once
per machine at `-O2` in both.

Nothing about the language's safety changes with the mode. Overflow, narrowing-cast,
bounds, division-by-zero and budget checks run in every build and trap with the same
code and message, so a program's result never depends on the mode; `--unchecked` is
refused. What a release build does differently is prove checks away: a check the fact
pass shows can never fail is not emitted.

```mylang
# doc: expect 45
def total(values: list[int]) -> int:
    sum = 0
    for value in values:
        sum += value
    return sum


def main() -> int:
    values: list[int] = []
    for i in range(10):
        values.append(i)
    return total(values)
```

## Loops that prove their own checks

A release build analyses each function's loops before emitting it. The fact pass
works out the range of every counter, length and accumulator it can, and a check it
proves cannot fail is dropped:

- a counted loop's counter stays between its start and its bound, so `xs[i]` over a
  list whose length the pass knows needs no bounds check;
- a list filled by a counted loop with one append per iteration has a known length
  and its elements lie between the smallest and largest value appended;
- a list holds at most 2^47 elements (the x86-64 user address space), so a counter or
  sum bounded by a length cannot overflow `int`;
- a small helper whose body is one block ending in `return` is inlined first, so its
  arithmetic is proven in the caller; a trap still reports the helper's line.

A sum the pass cannot bound outright gets a trip-count guard: when the guard holds, a
copy of the loop with the sum proven runs, and otherwise the original loop runs with
every check. An innermost loop branching on a value that does not change inside it is
unswitched: the branch is decided once, before the loop. A summing loop over a list
whose elements are proven small is lowered to vector code on a CPU with AVX2. None of this changes a
result or a trap: the guarded copies run only when their conditions hold, and the
original loop reports a failing index at the same iteration with the same message.

```mylang
# doc: expect 42
def scale(row: mut list[float], factor: float) -> None:
    for j in range(len(row)):
        row[j] = row[j] * factor


def count(data: list[int], wanted: int) -> int:
    found = 0
    for value in data:
        if value == wanted:
            found += 1
    return found


def main() -> int:
    row = [1.0, 2.0, 3.0]
    scale(mut row, 2.0)
    if row[2] != 6.0:
        return 1
    return 40 + count([7, 1, 7], 7)
```

A list parameter whose length or elements the function cannot see keeps its checks,
as does a sum of unbounded terms. `mylang build --release --stats` counts what the
passes did, and `mylang dump-ir --facts` shows which operations were proven
(`list_get.proven`, `add.proven`) and which keep their check (`.exact`).

## Budgets are opt-in

A run is bounded only when you ask for it. `mylang run` and `mylang build --run` have
no step or frame ceiling by default; their one default limit is the byte ceiling of
4 GiB. A binary built with `mylang build -o` carries no budget at all.

| Flag (on `run` and `build --run`) | Bounds | Trap |
| --- | --- | --- |
| `--max-steps N` | executed blocks of program functions | `R_STEP_LIMIT` |
| `--max-frames N` | call depth of program functions | `R_FRAME_LIMIT` |
| `--max-memory SIZE` | bytes the program holds (default 4 GiB; `0` removes it) | `R_MEMORY_BUDGET` |
| `--timeout SECONDS` | wall-clock time | `R_TIMEOUT` |

```console
$ mylang run loop10.my --max-steps 200
error[R_STEP_LIMIT]: native execution failed
instruction budget exhausted; raise it with --max-steps=N
```

Each trap exits with status 1 and names the flag that raises it. A frame budget
reserves 32 KiB of stack per frame plus 8 MiB, which must fit under the byte ceiling.
`--max-memory` falls back to `MYLANG_MEMORY_LIMIT`, then to `limits.run.max_memory`
in `mylang.json`. The runtime also lowers `RLIMIT_AS` to the ceiling plus 256 MiB.

`mylang test` is the exception that keeps a budget by default: 1,000,000 steps,
1,024 frames, 512 MiB and 60 seconds per test, because a tight guard is useful
there; `--max-steps`, `--max-frames`, `--max-memory` and `--timeout-ms` change them.
See [runtime budgets](tooling/runtime-budgets.md).

## Fixed arrays are values you can write in place

`[N]T` is a value type that carries no header and no growth check. A read is one
bounds check and one load, and `x = replace(x, i, v)`, with the result landing back in
the array it read, is one bounds check and one store into `x`'s own storage, not a
copy of the array (`array_set` in `mylang dump-ir`).

```mylang
# doc: expect 14
def main() -> int:
    data: [8]int = [1, 1, 1, 1, 1, 1, 1, 1]
    index = 0
    while index < 8:
        data = replace(data, index, index * 2)
        index += 1
    return data[7]
```

Reach for `[N]T` whenever the length is part of the type (wire records, tables,
staging buffers) and write its elements freely. Reach for `list[T]` when the length is
not known up front. A `bytes` value is the immutable byte-shaped alternative.

## Call C when you need a library

`extern def` declares a C function with scalar parameters, and `--link FILE.c`
compiles a C source and links it into the program. A C library function such as
`hypot` needs no flag:

```console
$ cat > hyp.my <<'EOF'
extern def hypot(host: Host, a: float, b: float) -> float effects(host)


def main(host: Host) -> int:
    return int(hypot(host, 3.0, 4.0)) * 10 + int(hypot(host, 5.0, 12.0))
EOF
$ mylang run hyp.my --print-result
63
$ mylang build hyp.my -o hyp --link kernels.c    # your own C, compiled at the program's level
```

Floats cross the boundary as C `double` and integers as C fixed-width integers;
pointers, aggregates, variadic calls and callbacks are rejected with
`E_EXTERN_SIGNATURE`, so a C kernel cannot be handed a guest array. See
[C interop](c-ffi.md) for the exact surface. A foreign call is not counted, so a step
budget does not bound the time spent inside it.

## Measure

`mylang run prog.my --timings` (also on `build --run`) prints
`timings: native_ns=N` on standard error once the program exits: the nanoseconds from
starting the program's process to its exit, the build excluded.

`--report` on `build`, `build --run` and `run` answers a different question: what the
build cost and what the caches served. It prints one `cache-report-v1` JSON line on
standard error:

```console
$ mylang build loop10.my -o loop10 --report
{"version":"cache-report-v1","program":"linked","units":2,"reused":0,"compiled":2,"verified":0,"processes":3}
$ mylang build loop10.my -o loop10 --release --report
{"version":"cache-report-v1","program":"linked","units":1,"reused":0,"compiled":1,"verified":0,"processes":2}
```

`program` is `linked`, `reused` (the program store served the executable) or
`replayed` (an identical earlier build was repeated without checking or compiling).

`--stats` on `build` prints what the core's passes did:

```console
$ mylang build scale.my -o scale --release --stats
mylang-core: inlined 1 calls, unswitched 0 loops, versioned 0 loops, proved 10 checks, vectorized 0 loops
mylang-core: ownership: 7 updates in place, 1 tested, 0 copied; 0 retains, 2 releases (0 pairs elided); 0 lists on the stack
```

[`mylang cost ENTRY.my [FUNCTION]`](tooling/cost.md) shows these counts per function,
plus kept checks and possible allocation sites. `--json` writes `cost-v1`; its
unfiltered totals match a release build's `--stats`. LLVM vectorization stays
unknown without optimization remarks and is separate from Core vector plans.

`mylang dump-ir prog.my --facts` prints the Core IR with the fact pass applied, so a
check that survived (`.exact`) can be traced to the value the pass could not bound.

For wall time and peak memory, build once and time the binary with the system timer,
more than once:

```bash
mylang build prog.my -o prog --release
run5() { for i in 1 2 3 4 5; do /usr/bin/time -f '%e s  %M kB' "$@" >/dev/null; done; }
run5 ./prog                                 # %e seconds, %M peak kilobytes
```

Five runs are enough to see a 2× difference on a quiet machine and not enough on a
busy one. `mylang test` reports pass/fail outcomes, not per-case timings.

## Prove a hot function does not allocate

`noalloc` is a checked effect bound, not a performance hint: a function declared
`noalloc` that allocates is rejected at check time, so the guarantee cannot rot as the
body changes. Records, ordinary calls and `list` reads all still work under it.

```mylang
# doc: expect 46
record Point:
    x: int
    y: int


def first(values: list[int]) -> int noalloc:
    return values[0]


def dot(a: Point, b: Point) -> int noalloc:
    return a.x * b.x + a.y * b.y


def main() -> int:
    values: list[int] = [7, 39]
    return first(values) + dot(Point(x=3, y=4), Point(x=5, y=6))
```

Build a list inside `first` and the checker answers `E_EFFECT_BOUND` (effect
`managed_allocation` exceeds declared bound).

## See also

- [Native builds](tooling/native-build.md): the driver, its caches and `--report`.
- [Runtime budgets](tooling/runtime-budgets.md): step, frame and byte ceilings.
- [Value semantics](value-semantics.md): when a write copies.
- [C interop](c-ffi.md): the exact `extern def` surface.
- [Standard library](standard-library.md) and [floating point](floating-point.md):
  what the shipped modules provide.
