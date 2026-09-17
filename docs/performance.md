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

## Budgets are opt-in

A run is bounded only when you ask for it. `mylang run`, `mylang build --run` and
a binary you built and started yourself have **no instruction or frame ceiling** by
default, because the byte ceiling below already stops a runaway allocation and a
development loop should not stop an honest program. The old default stopped the
loop above after roughly 660,000 iterations — about 18 ms of native work, measured
by bisecting `--max-steps` against the built binary.

When you want a ceiling, ask for one and the trap names the flag that applies it:

```console
$ ./loop10 --print-result --max-steps=200
loop10.my:5:24: error[R_STEP_LIMIT]: instruction budget exhausted; raise it with --max-steps=N
  in main at loop10.my:5:24
$ ./loop10 --print-result --max-steps=2000000000
155298
```

Set the ceiling on whichever command runs the program: `mylang run prog.my
--max-steps=N`, a built binary `./prog --max-steps=N`, and `mylang build prog.my
--run -- --max-steps=N` (runtime options follow `--`). `--max-frames=N` bounds call
depth the same way and its trap names that flag instead. To bound elapsed time
rather than work, `--timeout=SECONDS` arms a monotonic wall-clock timer on `mylang
run`, `mylang build --run` and a built binary; when it fires the process writes
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

## Fixed arrays are wire data, not buffers

`[N]T` is a value type, and the native backend copies it at every boundary and at
every element read. The copies are visible in the emitted QBE of a function that
scans a `[4096]int` parameter, where 32768 is the array's size in bytes: four
`blit`s of the whole array appear, one at entry and three around the indexed read.

```bash
mylang emit-qbe scan4096.my | grep -o 'blit [^\\]*' | wc -l
4
mylang emit-qbe scan4096.my | grep -o 'blit [^\\]*' | grep -c 32768
4
```

The consequence is that indexing an `[N]T` is **O(N) per access**, not O(1): the
table below grows the array while holding the element access and the call count
fixed, and then compares the same complete scan over an array and over a list. All
rows are prebuilt `--mode ReleaseFast` binaries.

| Work | Time |
| --- | --- |
| 100,000 calls of `peek(values: [8]int)` returning `values[0]` | 9 ms |
| 100,000 calls of the same function over `[1024]int` | 0.26 s |
| 100,000 calls of the same function over `[4096]int` | 1.15 s |
| 1,000 calls scanning every element of a `[4096]int` parameter | 6.00 s |
| 1,000 calls scanning every element of a `list[int]` of the same length | 0.23 s |

The first three rows hold the work constant and grow only the array, so the cost is
the copy, not the call. The last two rows are the same scan over the same data, and
the managed list is **26× faster** because a list carries a pointer instead of a
snapshot.

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

for n in (8, 1024, 4096):
    open(f"peek{n}.my", "w").write(fixed(n, False, 100000))
open("scan4096.my", "w").write(fixed(4096, True, 1000))
open("scanlist4096.my", "w").write(managed(4096, 1000))
PY
for name in peek8 peek1024 peek4096 scan4096 scanlist4096; do
  mylang build $name.my -o $name && run5 ./$name
done
```

`scan4096` and `scanlist4096` run the identical kernel body over the identical
4,096 values and both answer `4096000`; only the storage differs.

So: keep `[N]T` for wire-shaped data — records, tables, `bytes`, values whose length
is part of their type and that cross a function boundary rarely. Use `list[T]` for
anything a hot loop reads, because the managed list *is* the mutable buffer in this
language, and a managed `list` read is a pointer load with a bounds check. Passing a
large `[N]T` to a function that is called in a loop is the single most expensive
habit available here; a `bytes` value is the immutable byte-shaped alternative.

## Call C when you need a library

`extern def` declares a C function with scalar parameters, and the build links it
with `--link` or `--link-library`. This is how a program reaches a library function
the language does not provide — `hypot`, `tgamma`, `clock_gettime` and the rest:

```text
# doc: not-mylang
# C's `hypot`; the build below links libm.
extern def hypot(a: float, b: float) -> float effects(host)


def main() -> int:
    return int(hypot(3.0, 4.0)) * 10 + int(hypot(5.0, 12.0))
```

```console
$ cat > hyp.my <<'EOF'
extern def hypot(a: float, b: float) -> float effects(host)


def main() -> int:
    return int(hypot(3.0, 4.0)) * 10 + int(hypot(5.0, 12.0))
EOF
$ mylang build hyp.my -o hyp --link-library m
$ ./hyp --print-result
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

`with arena()` is a lifetime tool, not a speed tool — it buys predictable bulk
release, never faster allocation. Measured on 200,000 rounds of building a
ten-element list: **135 ms** without a region and **116 ms** inside
`with arena() as scratch:`, a difference well inside the noise of a shared machine.
Read [managed arenas](arenas.md) for what a region does guarantee.

## See also

- [Native builds](tooling/native-build.md) — the driver, its cache, and `--report`.
- [Runtime budgets](tooling/runtime-budgets.md) — instruction, frame and byte ceilings.
- [Managed arenas](arenas.md) — when bulk release, not speed, is the goal.
- [C interop](c-ffi.md) — the exact `extern def` surface.
- [Standard library](standard-library.md) and [floating point](floating-point.md) —
  what the shipped modules cost, and why `math.sqrt` calls the hardware instruction.
