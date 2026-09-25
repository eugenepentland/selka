# Performance

`mylang run prog.my` builds `prog.my` through [QBE](tooling/native-build.md) and runs
the resulting native executable; there is no interpreter to outgrow. Most programs
need no performance work at all, and this page exists to say that with numbers, to
name the four things that genuinely change the answer — the optimize mode, the
instruction budget, the storage tier, and C — and to show how to measure a program
of your own.

The 14 September 2026 audit measured the native path at **20–34×** the bytecode VM
it replaced: 27× on a 1,000,000-iteration integer loop, 20× on 200,000 list appends
plus a sum, and 34× on 20,000 `dict[str, int]` writes. That VM no longer exists, so
those ratios cannot be re-run on this checkout; the absolute native times below
can, and they are what a reader can reproduce here. The lesson matches the
[Python-shaped surface](python-syntax.md): write ordinary managed code first, and
reach for the escape hatch only when a measurement says so.

Every number below was measured on 14 September 2026, on the machine that built
this checkout (Linux x86-64, 20 cores, with other builds running at the same time),
using `zig-out/bin/mylang` from `zig build`. Each row is the **smallest of five
runs** of a prebuilt binary, rounded to 10 ms. A shared machine inflates wall time,
so read the ratios and re-run the commands for your own absolute figures: the
numbers are indicative, not a promise. The loop benchmark below is shown in full;
the other rows use the same `run5` pattern with the work named in the table.

The [18 September 2026 runtime audit](audits/runtime-performance-2026-09-18.md)
measures where a native build still spends 30–90× Zig's instruction count on a
byte-loop workload and lays out the six-wave plan to close it.
The [21 September 2026 parity audit](audits/performance-parity-audit-2026-09-21.md)
re-measures the current tree against Zig and Rust, attributes the remaining gap
per primitive with a matched kernel suite, and ranks what closes it.
[The performance roadmap](performance-roadmap.md) turns that ranking into the
ordered list of changes to make next, each with its measured price and its
acceptance test.
The [22 September 2026 schematic audit](audits/schematic-parity-gap-2026-09-22.md)
measures the schematic SVG tool against its byte-identical Zig and Rust ports
phase by phase: the default build is 1.84× Zig, the shipped runner's QBE plus
step-accounting policy 5.8×, stripping every check and the frame protocol still
leaves 1.64×, and on the guest's own work the gap is 4.3× — aggregate copies,
container-header reloads, byte-granular I/O and the checked append path, ranked.
The [22 September 2026 parity plan](audits/performance-parity-plan-2026-09-22.md)
widens the comparison to thirteen idiomatic programs ported to Zig and Rust
(5.8× Zig on the geometric mean today, 1.02× for Rust). It prices each
language rule and lowering protocol separately by rewriting the emitted code,
and it orders the fixes into five waves. Among them: the aggregate lane,
failure paths that end in `unreachable`, canonicalizing NaN only when observed,
and runtime library algorithms. Its composed, measured ladder reaches 2.2×, and
the projection with the library work is about 1.6×.
[The aggregate lane](audits/schematic-lane-aggregates-2026-09-22.md) is the
first wave's code. It writes and reads a list element where the element lives,
so `xs[i] = v` is a bounds test and one store instead of a runtime call behind
the frame's GC roots. On the same thirteen programs it takes the geometric mean
from 5.8× to 3.0× Zig: `nbody` 72× → 4.9×, `matmul` 41× → 7.1×,
`fannkuch_redux` 16× → 1.3×, `sieve` 7.1× → 1.8×. The schematic render goes
from 1.98× to 1.73×. Its [results](audits/performance-parity-results-2026-09-23.md): the suite went from 5.81× to 1.20× Zig on the LLVM release build (`--release`; the default build until 2026-09-23) and from 8.40× to 2.41× on QBE.

## What is fast without trying

Python-shaped managed code compiled by this backend is fast enough that a program
has to work at being slow:

| Program | Work | Time | Peak RSS |
| --- | --- | --- | --- |
| `empty.my` | `def main() -> int: return 0` | 4 ms | 1.7 MB |
| 10,000,000-iteration loop | `total = (total + i) % 1000003` | 0.27 s | 1.5 MB |
| 200,000 `list.append` + sum | 200,000-element `list[int]` | 30 ms | 4.4 MB |
| 20,000 `dict[str, int]` writes | `counts[key] = counts.get(key, 0) + 1` | 80 ms | 2.2 MB |
| 2,500,000 appends, 50,000 short-lived lists | each list built, used, and dropped | 90 ms | 1.8 MB |
| 20 × 300,000-element list | each built, used, and dropped | 0.25 s | 8.2 MB |

The dictionary row predates the hash index of 21 September 2026 and has not been
rerun as written, because the table does not record how many distinct keys it
used. A program matching its description with 1,000 distinct keys was measured
on both sides of that change, same binary pair, interleaved: **127 ms before and
3 ms after**. Dictionary reads and writes are no longer linear in the key count;
see [the dictionary index audit](audits/dict-hash-index-2026-09-21.md).

Counting slices of one text by dictionary key — `key = seq[i:i + k]` followed by
`counts[key] = counts.get(key, 0) + 1` — builds no `str` per slice: a slice whose
only reader is a dictionary key is looked up by the octet range it names, and a
key is built only when it is new. A write of a key that is already present
publishes no GC roots. Together they take the `knucleotide` benchmark from about
3.4× Zig to about 1.4× Zig; see
[the text and dictionary leftovers report](audits/text-dict-leftovers-2026-09-23.md).

The first row is the floor: about 4 ms of process start-up and 1.7 MB of resident
memory before the program does anything, so a program that finishes in tens of
milliseconds is mostly start-up and its memory figure means little. The last three
rows are the memory story: the managed collector reclaims the dropped lists as they
go, so peak resident memory stays near the *live set*, not the total allocated. The
loop below is the whole benchmark for the second row.

```bash
zig build                                     # installs zig-out/bin/mylang once
export PATH="$PWD/zig-out/bin:$PATH"          # so `mylang ...` below resolves
cat > loop10.my <<'EOF'
def main() -> int:
    total = 0
    i = 0
    while i < 10000000:
        total = (total + i) % 1000003
        i += 1
    return total
EOF
mylang build loop10.my -o loop10
run5() { for i in 1 2 3 4 5; do /usr/bin/time -f '%e s  %M kB' "$@" >/dev/null; done; }
run5 ./loop10
```

`run5` prints wall seconds and peak resident kilobytes for each of five runs; the
smallest wall time is what this page quotes. A built binary still takes
`--max-steps=N`, `--max-frames=N` and `--timeout=SECONDS` as ordinary arguments,
because the program itself parses them at start-up; with none of them it runs
unbounded.

## Records are values, not copies

A record is a value: assigning one, passing one to a function, or binding one in a
pattern match never lets a later write reach the original. The backend keeps that
meaning without paying for it. A read-only aggregate parameter crosses the call by
address, a short-lived local is named by its own slot, a record constructed
straight into a local is built there rather than in scratch and then copied, and a
match arm whose binding owns nothing reads the payload where it already lives, so
field reads, tag tests and payload projections are loads through a pointer rather
than aggregate copies. A list element works the same way. `x = xs[i]`, the
loop variable of `for x in xs`, and `return xs[i]` name the element inside
the list instead of a copy when nothing between the read and its last use can
move or change the list. A record a call returns
stays in the call's own result buffer when the caller only reads it, and
`xs[i] = v` writes the element in place. Writes still get their own storage,
and a write to a copied value stays a copy's write.

Field writes are in place too when nothing can see the difference. The
compiler's ownership analysis ([Ownership analysis](tooling/ownership.md))
proves when a record's old value is never read again: `p.x = v` then writes the
field into `p` itself rather than into a fresh copy that is copied back, and a
temporary that only renames `p` shares `p`'s storage. A record that is read again
after another name was written keeps its own copy, exactly as before. The same
analysis lets the collector skip a root record for a value a live collection,
dictionary or object already holds (`row` in `for row in rows`), since the
owner's root reaches it anyway.

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

## Build for speed

`mylang build` and `mylang run` build **ReleaseFast** unless told otherwise; the
unoptimized build is the explicit `--mode Debug`, and `--report` states which mode
a build used. The same loop as above, measured both ways:

| Build | Time |
| --- | --- |
| `mylang build loop10.my -o loop10` (ReleaseFast, the default) | 0.27 s |
| `mylang build loop10.my -o loop10 --mode Debug` | 0.68 s |

That is **2.5×** on integer arithmetic with bounds and overflow checks intact in
both builds. Nothing about the language's safety changes with the mode: overflow,
bounds, division-by-zero and budget traps are runtime checks and behave identically;
what changes is how much work the optimizer does on both the guest's QBE units and
the C runtime units linked beside them.

```bash
mylang build loop10.my -o loop10-fast                    # ReleaseFast
mylang build loop10.my -o loop10-debug --mode Debug
run5 ./loop10-fast
run5 ./loop10-debug
```

`--mode` is a *build* flag. `mylang run prog.my` builds in the default mode and has
no mode flag, so comparing modes means building twice and running the binaries; a
guest test run keeps its own `Debug` default, which `mylang test --mode ReleaseFast`
overrides. The mode is part of the object-cache key and of the run identity, so
switching modes never reuses another mode's objects.

The backend is a separate choice, and every mode builds with QBE unless asked
otherwise, because a build that finishes in a second is what an edit-test loop
needs. The fastest executable is `--release` — ReleaseFast through the LLVM
backend at `-O3` with full LTO, the build the parity benchmark times — on
`mylang build`, `mylang run` and `mylang test` alike:

```bash
mylang build loop10.my -o loop10-release --release       # LLVM -O3 + LTO
mylang run loop10.my --release
```

It costs an LTO link on every rebuild that changed a function, so keep it for the
executable you ship or measure ([native builds](tooling/native-build.md#backends)).

## Budgets are opt-in

A run is bounded only when you ask for it. `mylang run`, `mylang build --run` and
a binary you built and started yourself have **no instruction or frame ceiling** by
default, because the byte ceiling below already stops a runaway allocation and a
development loop should not stop an honest program. The old default stopped the
loop above after roughly 660,000 iterations — about 18 ms of native work, measured
by bisecting `--max-steps` against the built binary.

When you want a ceiling, ask for one and the trap names the flag that applies it:

```console
$ MYLANG_OPTIONS='--print-result --max-steps=200' ./loop10
loop10.my:5:24: error[R_STEP_LIMIT]: instruction budget exhausted; raise it with --max-steps=N
  in main at loop10.my:5:24
$ MYLANG_OPTIONS='--print-result --max-steps=2000000000' ./loop10
155298
```

Set the ceiling on whichever command runs the program: `mylang run prog.my
--max-steps=N`, a built binary `MYLANG_OPTIONS=--max-steps=N ./prog`, and `mylang
build prog.my --run --max-steps=N` (runtime options precede `--`; a built binary
reads them only from `MYLANG_OPTIONS`, so its arguments are all the program's). `--max-frames=N` bounds call
depth the same way and its trap names that flag instead. To bound elapsed time
rather than work, `--timeout=SECONDS` arms a monotonic wall-clock timer on `mylang
run`, `mylang build --run` and a built binary (in `MYLANG_OPTIONS`); when it fires the process writes
`R_TIMEOUT` to standard error and exits 1. `mylang test` is the exception that keeps
a budget by default — 1,000,000 instructions and 1,024 frames per test process —
because a tight guard is useful there; `--max-steps=N` and `--max-frames=N` bound
each test process.

The byte ceiling is a *different* knob and not a speed one. `--max-memory=BYTES` and
`MYLANG_MEMORY_LIMIT` (see [runtime budgets](tooling/runtime-budgets.md#guest-memory-ceilings))
cap how much a guest may hold; the collector enforces the cap. Measured on twenty
300,000-element lists built and dropped in turn: **0.25 s** with no ceiling and
**0.25 s** with `MYLANG_MEMORY_LIMIT=16M` — no measurable difference while the live
set fits. At `MYLANG_MEMORY_LIMIT=4M`, below the live set, the same program traps
`R_MEMORY_BUDGET` rather than merely slowing down.

## What safety costs

The language's traps are code the emitter generates: a comparison and a cold
branch per checked arithmetic operation, per narrowing cast and per container
index, plus a 32-byte frame record linked on every call and one store of the
current instruction position. The
[schematic parity audit](audits/schematic-parity-gap-2026-09-22.md#2-what-safety-costs-the-strip-ladder)
priced each class separately on a 2.4 ms SVG render, by rewriting the emitted IL
and rebuilding — every arm produced the byte-identical 49,617-byte output:

| removed from the render | static sites | render, ms | vs default |
|---|---:|---:|---:|
| nothing (the default build) | — | 2.390 | — |
| add/sub/neg/div overflow guards | 736 | 2.385 | −0.2% |
| narrowing-cast guards | 290 | 2.348 | −1.8% |
| list and array index guards | 313 | 2.354 | −1.5% |
| allocation and capacity guards | 86 | 2.395 | +0.2% |
| all four check classes | 1,425 | 2.288 | **−4.3%** |
| frame record, floor test, 1,909 position stores | 3,872 IL lines | 2.083 | **−12.8%** |
| both | — | 2.030 | **−15.1%** |

Two things follow. The value checks are cheap — a correctly predicted branch on
a path the optimizer already knows is cold — so removing them is not where a
slow program gets fast. The per-call frame protocol is three times as expensive
as all of them together, because it is unconditional work on every call and it
inflates every function body past the inliner's threshold.

No build omits them. Every build keeps the value guards and the frame protocol,
so an overflow, an out-of-range cast or an out-of-bounds index is always a named
trap and optimization never changes a program's result (see
[checks in every build](tooling/native-build.md#checks-in-every-build)). The
frame protocol's cost is paid down instead: a ReleaseFast executable with no
ceiling links no frame record and names each call's position in a
return-address table read only when a trap fires, and a counted loop proves its
own checks once (below).

## Loops that prove their own checks

A counted loop pays for its checks once, not once per element, when the compiler
can see that nothing inside it can resize a list. The native emitter plans every
innermost `for i in range(...)`, `for x in xs`, `enumerate(...)` and
`while i < n: ...; i = i + step` loop whose body makes no call, allocates
nothing and never pops, inserts or slices, and appends at most once, to a list
of numbers it does not otherwise read (`QBE-LOOP-FACTS-1`). For
such a loop it proves, from values it can compute before the first iteration:

- an index `i`, `i + c`, `k - i` or `i * w + j` is inside the list for every
  iteration when its smallest and its largest value are;
- a checked `+`, `-` or `*` over counters, loop-invariant locals and lengths
  cannot overflow once each of those is within `2^b` for a bound `b` the
  expression's degree allows (`(i + j) * (i + j + 1)` allows `2^29`);
- `count += 1`, or any accumulator adding a bounded amount once per
  iteration, cannot overflow when its starting value is within the same bound;
- the length checks of `for x in xs` hold on every iteration;
- a row `c[i]` read inside `for j in range(n)` is the same row every time;
- the list a comprehension such as `[True for _ in range(n)]` fills was
  created with room for every element, so each append is a plain store.

The loop is then compiled twice (`QBE-LOOP-VERSION-1`). A guard in front of it
checks those conditions once; when they hold and the loop has at least 16
iterations ahead of it (a shorter loop saves less than the guard costs), a copy
without the proven checks
runs — and because nothing is left in it that can exit early, LLVM vectorizes
it — and when any fails, the original loop runs with every check in place, so a
bad index still traps at the same iteration with the same message. Nothing
about the language changes: the result, every trap and its trace are exactly
what the unversioned program produces.

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

A loop keeps one copy, and every check, when its body calls a function that is
not inlined, prints, builds a string or grows a list: put that work before or
after the hot loop. A step-accounted build (`--max-steps`) never versions a
loop. The
[loop range facts audit](audits/loop-range-facts-2026-09-23.md) has the
measurements.

## Fixed arrays are values you can write in place

`[N]T` is a value type, but an element access no longer pays for the value: a read
is one bounds check and one load, and `x = replace(x, i, v)` — the result landing
back in the array it read — is one bounds check and one store into `x`'s own
storage. Neither emits a copy of the whole array, which the emitted QBE shows: a
function that scans a `[4096]int` parameter and a function that stages a
`[4096]int` one element at a time both carry no `blit` at all.

```bash
mylang emit-qbe scan4096.my | grep -o 'blit [^\\]*' | wc -l
0
mylang emit-qbe stage4096.my | grep -o 'blit [^\\]*' | wc -l
0
```

Until 2026-09-21 the write did copy: `replace` blitted the array into scratch,
wrote one element and the store copied it back, so an element write was **O(N)**
and staging a `[256]u8` one byte at a time cost 512 bytes of copying per byte
(`QBE-ARRAYWRITE-1`). The table is one program — 409,600 element writes into a
`[4096]int` local — built by the compiler before that change and by the compiler
after it. Prebuilt `--mode ReleaseFast` binaries, `taskset` to one CPU, 15
interleaved rounds, medians, machine load average 5–10.

| 409,600 element writes into `[4096]int` | before | after |
| --- | ---: | ---: |
| QBE | 2349.7 ms | **7.3 ms** |
| LLVM O3 + LTO | 1423.3 ms | **7.2 ms** |

A batch holding a multi-second arm inflates the short arms beside it, so the two
fast columns were re-measured on their own against the same writes into a
`list[int]`: **1.91 ms** into the array against 3.43 ms into the list on QBE, and
**1.76 ms** against 2.50 ms on LLVM. A fixed array is now a usable buffer, and on
writes it beats the managed list, because it carries no header and no growth
check.

Reads were already O(1) and did not move: 4,096,000 reads out of a `[4096]int`
local take 30.0 ms on QBE and 17.8 ms on LLVM, against 25.6 ms and 13.0 ms for the
same reads out of a `list[int]`.

**Passing** a large `[N]T` to a function called in a loop is cheap too, since
2026-09-21 (`QBE-FRAMEFIT-1`, `QBE-AGGREF-9`). The argument crosses by address, the
callee's slot for it is one word, and the callee's frame is sized from the scratch
its lowered body really declares rather than from every buffer the lowering might
have declared, so a callee that only reads the array keeps its frame on the native
stack instead of allocating, zeroing and freeing one on the heap per call. Until
that change the frame was estimated before the body existed, and the estimate for
`kernel(values: [1024]int)` came to 82 KB of heap per call:

| Work | before | after |
| --- | ---: | ---: |
| 100,000 calls of `kernel(values: [8]int)` returning `values[0]` | 1.34 ms | 1.24 ms |
| 100,000 calls of the same function over `[1024]int` | 115.0 ms | **1.59 ms** |
| 100,000 calls of the same function over `[4096]int` | 440.8 ms | **1.45 ms** |
| 1,000 calls scanning every element of a `[4096]int` parameter | 14.7 ms | **3.60 ms** |
| 1,000 calls scanning every element of a `list[int]` of the same length | 4.63 ms | 4.53 ms |

The `[8]int` row is the process floor, and the last row is the same scan over a
`list[int]`, whose binary the change leaves byte-identical: the fixed array is now
the faster of the two to hand to a function. Prebuilt `--mode ReleaseFast` QBE
binaries from the compiler before and after the change, `taskset` to one CPU, 15
interleaved rounds, medians, machine load average 1.7; the details are in
[frame-fit-2026-09-21](audits/frame-fit-2026-09-21.md). Every row above comes from
these programs:

```bash
python3 - <<'PY'
def scan_kernel(bits, n):
    return (f"def kernel(values: {bits}) -> int:\n    index = 0u64\n    total = 0\n"
            f"    while index < {n}u64:\n        total += values[index]\n        index += 1u64\n"
            "    return total\n")

def fixed(n, scan, calls):
    head = scan_kernel(f"[{n}]int", n) if scan else f"def kernel(values: [{n}]int) -> int:\n    return values[0]\n"
    return head + (f"\n\ndef main() -> int:\n    data: [{n}]int = [{', '.join(['1'] * n)}]\n"
                   f"    total = 0\n    call = 0\n    while call < {calls}:\n"
                   "        total += kernel(data)\n        call += 1\n    return total\n")

def managed(n, calls):
    return scan_kernel("list[int]", n) + (
        f"\n\ndef main() -> int:\n    data: list[int] = []\n    i = 0\n"
        f"    while i < {n}:\n        data.append(1)\n        i += 1\n"
        f"    total = 0\n    call = 0\n    while call < {calls}:\n"
        "        total += kernel(data)\n        call += 1\n    return total\n")

def stage(n, rounds, array):
    head = (f"def main() -> int:\n    data: [{n}]int = [{', '.join(['1'] * n)}]\n" if array else
            f"def main() -> int:\n    data: list[int] = []\n    fill = 0\n"
            f"    while fill < {n}:\n        data.append(1)\n        fill += 1\n")
    write = "data = replace(data, index, index + round)" if array else "data[index] = index + round"
    return head + (f"    total = 0\n    round = 0\n    while round < {rounds}:\n        index = 0\n"
                   f"        while index < {n}:\n            {write}\n            index += 1\n"
                   f"        total = (total + data[{n - 1}]) % 1000003\n        round += 1\n    return total\n")

def read(n, rounds, array):
    head = (f"def main() -> int:\n    data: [{n}]int = [{', '.join(['1'] * n)}]\n" if array else
            f"def main() -> int:\n    data: list[int] = []\n    fill = 0\n"
            f"    while fill < {n}:\n        data.append(1)\n        fill += 1\n")
    return head + (f"    total = 0\n    round = 0\n    while round < {rounds}:\n        index = 0\n"
                   f"        while index < {n}:\n            total += data[index]\n            index += 1\n"
                   "        round += 1\n    return total\n")

for n in (8, 1024, 4096):
    open(f"peek{n}.my", "w").write(fixed(n, False, 100000))
open("scan4096.my", "w").write(fixed(4096, True, 1000))
open("scanlist4096.my", "w").write(managed(4096, 1000))
open("stage4096.my", "w").write(stage(4096, 100, True))
open("stagelist4096.my", "w").write(stage(4096, 100, False))
open("read4096.my", "w").write(read(4096, 1000, True))
open("readlist4096.my", "w").write(read(4096, 1000, False))
PY
for name in peek8 peek1024 peek4096 scan4096 scanlist4096 stage4096 stagelist4096 read4096 readlist4096; do
  mylang build $name.my -o $name --mode ReleaseFast && run5 ./$name
done
```

`stage4096` and `stagelist4096` perform the identical 409,600 element writes over
the identical 4,096 values and both answer `414450`; `read4096` and `readlist4096`
both answer `4096000`. Only the storage differs.

So: reach for `[N]T` whenever the length is part of the type — wire records,
tables, staging buffers a host call takes — and write its elements freely. Reach
for `list[T]` when the length is not known up front. Handing either to a function a
hot loop calls costs the same: a `list` argument is a pointer, and an `[N]T`
argument is the address of the caller's array, held in one word of the callee's
frame. A `bytes` value remains the immutable byte-shaped alternative.

## Call C when you need a library

`extern def` declares a C function with scalar parameters, and the build links it
with `--link` or `--link-library`. This is how a program reaches a library function
the language does not provide — `hypot`, `tgamma`, `clock_gettime` and the rest:

```text
# doc: not-mylang
# C's `hypot`; the build below links libm.
extern def hypot(host: Host, a: float, b: float) -> float effects(host)


def main(host: Host) -> int:
    return int(hypot(host, 3.0, 4.0)) * 10 + int(hypot(host, 5.0, 12.0))
```

```console
$ cat > hyp.my <<'EOF'
extern def hypot(host: Host, a: float, b: float) -> float effects(host)


def main(host: Host) -> int:
    return int(hypot(host, 3.0, 4.0)) * 10 + int(hypot(host, 5.0, 12.0))
EOF
$ mylang build hyp.my -o hyp --link-library m
$ MYLANG_OPTIONS=--print-result ./hyp
63
```

Floats cross the boundary as C `double` and integers as C fixed-width
integers; pointers, aggregates, variadic calls and callbacks are rejected with
`E_EXTERN_SIGNATURE`, so a C kernel cannot be handed a guest array — see
[C interop](c-ffi.md#boundary-contract) for the exact surface. Two things worth
knowing before you reach for it: `mylang run` cannot link C, so use `mylang build`
(or `mylang build prog.my --run --link-library m -- --print-result`), and a foreign
call is not instrumented, so the instruction budget does not bound the time spent
inside it. C sources passed with `--link` are compiled in the same optimize mode as
the guest, so a `--mode Debug` build's C is unoptimized too.

## Measure

Three tools answer three different questions.

`mylang run prog.my --timings` prints `timings: native_ns=N` on standard error: how
long the spawned program took, including process start-up. A warm run of a program
that does nothing reports about 2 ms, and the 200,000-append benchmark reports about
33 ms against the 30 ms its prebuilt binary takes; the first run after the program
changes also pays the build and reports far more (150 ms for the empty program).
`--report` on a build answers a different question — what the build cost and whether
anything was reused — and always states the mode:

```console
$ mylang build listapp.my -o listapp --report
{"version":"qbe-build-v1",...,"mode":"ReleaseFast","target":"amd64_sysv",
 "compiled_functions":0,"reused_functions":1,"runtime_installed":true,
 "frontend_seconds":0.032,"codegen_seconds":0.005,"link_seconds":0.039,
 "native_seconds":0.044,"output_changed":true}
```

For anything else, measure the prebuilt binary with the system timer and run it more
than once:

```bash
mylang build prog.my -o prog
run5 ./prog                                 # %e seconds, %M peak kilobytes
```

Five runs are enough to see a 2× difference on a quiet machine and not enough on a
busy one, which is why every table here quotes a best-of-five. `--timings=json`
reports the same interval as the `native_execution` record in phase-timings JSON
Lines when a script needs to read it; `mylang test` reports pass/fail outcomes, not
per-case timings.

## Track parity with Zig and Rust

`zig build bench-parity` is the standing benchmark behind the parity plan: the
eleven-program suite with its variants, the runtime-library scans and the
micro-kernels under `bench/parity/`, each written in mylang, Zig and Rust and
required to print the same bytes. It builds every arm with the compiler this
checkout installs (or `-Dbench-mylang=PATH`), times fresh processes pinned to one
CPU in interleaved rounds, and fails when a program's ratio to Zig ReleaseFast
grows past its threshold in `bench/parity/thresholds.json`. Ratios, not
milliseconds, are checked, because both sides of a ratio ran in the same round.
The step is opt-in; `zig build test` never runs it.

A plain `zig build bench-parity` times the guest binaries of the Debug compiler it
installs. That is deliberate. The compiler's own optimization mode does not change
what it emits: `python3 bench/parity/bench_parity.py same-binaries --other
PATH/bin/mylang` builds every mylang arm with both compilers and requires
identical bytes. So a ReleaseFast compiler build buys nothing here. Timed processes run
on the first of `MYLANG_TIMING_CPUS` (default CPU 2) unless `-Dbench-cpu` says
otherwise. That is a core `scripts/build-slot.sh` keeps free of builds
([many agents on one machine](tooling/many-agents.md)). The harness warns before
timing when that core or its SMT sibling is already busy.

```bash
zig build bench-parity -Dbench-filter=sieve -Dbench-cpu=10 -Dbench-rounds=7
zig build bench-parity -Dbench-filter=micro/ -- --json parity-micro.json
python3 bench/parity/bench_parity.py rebaseline .mylang-cache/bench-parity/result.json --label quiet
```

It prints one table row per program (Zig milliseconds, then `zig-safe`, `rust`,
`rust-checked`, `my`, its limit and the variants as ratios), the
suite's geometric means beside the plan's targets, and one line per regression
naming the program, arm, ratio and threshold. A program over its limit is timed
a second time, and the step fails only when both passes exceed it. Rust arms are skipped with a notice
when `rustc` is missing. When `kernel.perf_event_paranoid` allows `perf stat`,
each arm also gets instruction, cycle, branch-miss and cache-miss counts,
printed as a second table of instruction ratios to Zig and Rust, IPC and misses
per thousand instructions. Rewriting the thresholds is a
separate, deliberate command; `bench/parity/README.md` gives the tolerance policy
and the layout.

## Prove a hot function does not allocate

`noalloc` is a checked effect bound, not a performance hint: a function declared
`noalloc` that allocates is rejected at check time, so the guarantee cannot rot as
the body changes. Records, ordinary calls, `list` reads and `print` all still work
under it.

```text
# doc: not-mylang
# This example prints 39 and returns 7.
record Point:
    x: int
    y: int


def first(values: list[int]) -> int noalloc:
    return values[0]


def dot(a: Point, b: Point) -> int noalloc:
    return a.x * b.x + a.y * b.y


def main() -> int:
    values: list[int] = [7, 39]
    print(dot(Point(x=3, y=4), Point(x=5, y=6)))
    return first(values)
```

That prints `39` and returns `7`; replace `return values[0]` with an append and the
checker answers `E_EFFECT_BOUND: effect 'managed_allocation' exceeds declared bound`.
There is deliberately no `nogc` bound to reach for as well: the collector only runs
while the managed heap grows, so `noalloc` already proves a hot function never
reaches it, and a second spelling for the same proof would be a synonym rather than
a bound.

`with arena()` is a lifetime tool first — it buys predictable bulk release — and
since 2026-09-21 it is also the faster way to allocate a batch you then drop
whole. A closed scope hands its chunk to the next scope instead of returning it
to the host, so a loop of short scopes no longer reserves and zero-fills 64 KiB
per iteration. Measured on one million batches that each build and fold a
sixteen-element `list[int]` (the `alloc_churn` kernel, interleaved arms on one
CPU of a shared machine, so read the ratios and not the absolute times):

| arm | before | after | against the same body on the collecting heap |
|---|---:|---:|---|
| QBE | 17.7× Zig | **4.2× Zig** | 3.1× slower → **1.35× faster** |
| LLVM O3 + LTO | 15.8× Zig | **2.2× Zig** | 4.3× slower → **1.65× faster** |

"Zig" is `std.heap.ArenaAllocator` reset once per batch. Peak resident memory is
unchanged at 2.4 MB, because the retained chunk is one the scope had already
reserved. Read [managed arenas](arenas.md) for what a region guarantees and what
the retention bound is.

## See also

- [Native builds](tooling/native-build.md) — the driver, its cache, and `--report`.
- [Runtime budgets](tooling/runtime-budgets.md) — instruction, frame and byte ceilings.
- [Managed arenas](arenas.md) — bulk release, chunk retention, and what a region guarantees.
- [C interop](c-ffi.md) — the exact `extern def` surface.
- [Standard library](standard-library.md) and [floating point](floating-point.md) —
  what the shipped modules cost, and why `math.sqrt` calls the hardware instruction.
