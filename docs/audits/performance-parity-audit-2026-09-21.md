# What separates mylang from Zig and Rust, and what closes it — 2026-09-21

> Rerun after the three §3 defects were fixed and merged (`a1a5e609`):
> [performance-parity-rerun-2026-09-21.md](performance-parity-rerun-2026-09-21.md).
> The schematic is now 2.06× Zig / 1.84× Rust; the parser is unchanged; the
> dictionary and arena cliffs are gone. The tables below are the pre-fix state.

**Headline.** On scalar code the LLVM arm of mylang is already at Zig's speed with
every check on: an integer loop runs at 0.9× Zig ReleaseFast, a record-building
loop at 1.0×. Everything above that is not code generation. It is, in order of
what the evidence supports: three outright defects (a dictionary that is a linear
list, a fixed array that is copied whole on every element write, an arena that
`calloc`s a fresh 64 KiB chunk per scope), the QBE backend that every `mylang
run`/`build` still uses by default (2.2–2.4× slower than LLVM on the same
source), a per-call frame protocol worth about 40% of a call-heavy program, and a
runtime representation (96-byte object headers, 4-byte-per-scalar strings, a
mark-sweep collector over `calloc`'d objects) that costs 1.8–2.5× Zig's memory and
10–17% of a parser's samples. The two real workloads stand at **1.8–3.0× Zig**
(S-expression parser, LLVM O3 + LTO) and **2.3× Zig / 2.1× Rust** (schematic
SVG). Nothing measured today puts a real workload under 1.2×; the composed
experimental arm of 2026-09-20 reached 1.25×/1.37× on the parser, and that
remains the best evidence of where the priced levers land.

This audit re-measures the current tree, adds a matched micro-kernel suite so the
gap can be attributed per primitive, takes the fresh profile the previous report
said was missing, and prices three things by counterfactual: the call protocol,
the checked multiply, and the fixed-array write. Evidence, sources and scripts:
[`experiments/perf-parity-audit-20260921`](../../experiments/perf-parity-audit-20260921/README.md).
No production source changed. No Guardian gate ran.

## 1. Where the current tree stands

Every row is a fresh process, output verified against Zig on every run, `taskset`
to one CPU, randomized interleaved rounds, medians. Hardware counters were
unavailable (`perf_event_paranoid=4`), so these are wall times. The parser,
counterfactual and start-up batches below were re-run on a quiet machine (load
average about 2) after the first pass; the micro suite, the dictionary and the
replace-loop probes ran while other sessions were running test gates (load
average 7–20), so their absolute times are inflated and only their within-batch
ratios are quoted. The arms of every batch are interleaved, so a ratio is fair
to both sides; the loaded parser pass and the quiet one agree within 0.1×.

**S-expression parser and printer** (`experiments/sexpr-port`, 101 functions,
compiled fresh from the working tree, 21 rounds, quiet machine; paired-bootstrap
95% intervals in `results/quiet/sexpr.json`):

| workload | Zig ReleaseFast | Zig ReleaseSafe | QBE (default) | LLVM O3 | LLVM O3 + LTO |
|---|---:|---:|---:|---:|---:|
| census 927 KB | 2.04 ms | 1.09× | **2.35×** | 1.91× | **1.80×** |
| render 927 KB | 2.50 ms | 1.09× | **3.51×** | 2.69× | **2.55×** |
| census 7.42 MB | 13.93 ms | 1.09× | **2.81×** | 2.23× | **2.12×** |
| render 7.42 MB | 17.75 ms | 1.09× | **3.98×** | 3.11× | **2.95×** |

The earlier batch of the same morning ([llvm-zig-benchmark](llvm-zig-benchmark-2026-09-21.md))
put LLVM O3 at 1.98×, 2.71×, 2.23×, 3.16×, and the loaded first pass of this
audit at 1.83×, 2.74×, 2.25×, 3.11×: three batches agree. Peak RSS on the large input: Zig 16.9 MB / 22.5 MB (census / render),
mylang 30.0 MB / 55.6 MB on every backend: **1.8× and 2.5× the memory**.

**Schematic SVG renderer** (same-output ports, from the
[production gap-fixes batch](svg-production-gap-fixes-2026-09-21.md) earlier
today): Zig 1.517 ms, Rust 1.707 ms, Go 2.214 ms, mylang GC LLVM O3 + LTO
3.530 ms, mylang arena 3.436 ms. That is **2.33× Zig and 2.07× Rust** at the
process level. Subtracting each side's empty-program floor (below) leaves
about 2.74 ms against 0.85 ms of actual work: **roughly 3.2× on compute**. Rust is within 13%
of Zig here, so "parity with Rust" and "parity with Zig" are the same target
within the noise of this corpus.

**Empty program** (30 rounds, quiet): Zig 0.67 ms, mylang QBE 0.83 ms, mylang
LLVM 0.79 ms. Start-up is 0.12–0.16 ms of the gap and not a lever; the binary is
dynamically linked against glibc and libm (51 syscalls to Zig's 8) and reserves
a 40 MB guest stack, all cheap.

**Matched micro-kernels** (11 kernels, mylang and Zig side by side, 15 rounds;
full table and per-kernel matching notes in
[`micro/results.md`](../../experiments/perf-parity-audit-20260921/micro/results.md)):

| kernel | Zig fast, ms | QBE | LLVM O3 | LLVM O3 + LTO | what it isolates |
|---|---:|---:|---:|---:|---|
| intloop | 113.9 | 2.37× | **0.93×** | 0.98× | checked `+ * %` in a loop |
| records | 77.2 | 2.18× | **0.99×** | 1.00× | record construction, by-value call |
| fib | 35.6 | 3.91× | 3.56× | 3.60× | 29.9 M real calls |
| list_records | 45.3 | 2.29× | 1.99× | 1.97× | iterate a list of 32-byte records |
| bytes_scan | 37.7 | 3.57× | 2.35× | 1.50× | `bytes[i]` over 8 MB |
| list_append_sum | 45.9 | 4.42× | 3.62× | 3.27× | append 10 M ints, then sum |
| float_loop | 32.2 | 3.15× | 4.09× | 3.05× | `x*0.999 + sqrt(i)` |
| str_build | 39.9 | 6.01× | 5.40× | 3.83× | byte-buffer append |
| alloc_churn | 66.2 | 6.13× | 4.38× | 3.92× | build and drop 1 M small lists (GC) |
| alloc_churn, `with arena()` | 66.2 | 18.6× | 17.1× | 16.4× | same body, one arena per batch |
| dict_count | 26.9 | 591× | 547× | 329× | 1,000 string keys, 6 M lookups |

Zig ReleaseSafe, the closer semantic match because it keeps overflow and bounds
checks, runs at 0.9–1.3× ReleaseFast on these kernels (2.0× on `fib`), so the
mylang ratios against ReleaseSafe are about 10% smaller; the ranking is unchanged.

Read down the LLVM column: scalar arithmetic and value records are done; calls,
collections, strings, allocation and dictionaries are where the time is. Read
across: QBE alone accounts for a factor of 2.2–2.4 on the kernels LLVM has
already closed.

## 2. Where the time goes

Self-PC samples from the repository's userspace SIGPROF sampler, no call stacks,
on the current LLVM O3 + LTO GC binaries; LTO folded 54 of 124 schematic functions
and 68 of 101 parser functions into their callers, so a surviving name carries its
inlinees. "Outside" is libc (`memcpy`, `memset`, `malloc`), which the sampler
cannot place; the QBE cross-check shows it is block copy and zeroing, not the
loader. Full tables and disassembly of the hottest addresses:
[`profiles/summary.md`](../../experiments/perf-parity-audit-20260921/profiles/summary.md).

**Schematic SVG, GC, LLVM O3 + LTO** (16,000 runs, 19,644 samples, 15.8% outside):

| function | share | what the hot instructions are |
|---|---:|---|
| `io::flush` | **42.5%** | eight 32-byte `vmovups` loads and stores plus one byte insert: a whole 256-byte `[256]u8` copied to scratch and back **per output byte** |
| `layout_routes::build` | 10.5% | the same 128-byte `Pin` record stored twice into two stack slots inside the O(pins²) scan |
| `text::write` / `escaped` / `decimal` | 8.9% | formatting into the byte buffer |
| `sexpr::at` / `sexpr::form` | 5.3% | input parsing |
| `layout::partPin`, `collectRows`, `nearest`, `innerPin` | 6.0% | placement |
| `buffer_grow_rooted` | 1.7% | the only runtime function with weight |
| collector, root operations | 0.04% | absent: 134 allocations, zero collections |
| host provider | 0.07% | the packed block I/O landed today is free |

The 42.5% is one line of guest code, `payload = replace(payload, i, u8(...))` in
[`src/schematic/guest/io.my:130`](../../src/schematic/guest/io.my#L130), staging
each byte of the SVG into the 256-byte value array the packed host call takes.
The emitted IL carries two `blit … 256` per byte, exactly the O(N)-per-element
cost [`docs/performance.md`](../performance.md#fixed-arrays-are-values-you-can-write-in-place)
documents for `[N]T`. Isolated, the same loop over 49,617 bytes costs **0.55–
0.60 ms** on either backend (probe `replace_loop.my`), against a total
render of 3.5 ms and a Zig-to-mylang gap of 2.0 ms.

**S-expression census, GC, LLVM O3 + LTO** (600 runs, 17,526 samples, 35.7%
outside): `tokenizer::next_raw` 11.0%, `trace` (the collector's mark) **10.9%**,
`bytes_find_any` 8.9%, `parse_node` 6.2%, `tally` 5.0%, `heap_collect` **4.9%**,
`read_string` 4.4%, `parser::advance` 3.6%. The collector, its allocator and root
operations are **16.5% of all samples (26% of the samples that could be
placed)**, and the hot instructions are pointer-chase compares and branches in
the mark phase. `find_any` is hot at a 64-bit bitset test in a one-byte-at-a-time
delimiter loop. The parser's own hot addresses are `vmovups` record stores, not
arithmetic. Render adds `push_node` 10.3%, `estimate_width` 4.6%, `scalar_len`
3.1%, `byte_builder::append` 2.7%, with the collector at 9.6%.

## 3. Three defects that are not constant factors

These are not "mylang is 2× slower"; they are wrong asymptotics or wrong policy,
and each has a small, local fix.

**Dictionaries are association lists.** `find` in
[`src/native_dictionary.c:26`](../../src/native_dictionary.c#L26) walks every
entry and compares keys one at a time; a write of a new key also `calloc`s and
`free`s a temporary entry. Cost is linear in the key count (300,000 operations):

| distinct keys | QBE | LLVM O3 + LTO |
|---:|---:|---:|
| 100 | 262 ms | 99 ms |
| 1,000 | 1,747 ms | 1,031 ms |
| 10,000 | 20,150 ms | 11,827 ms |

At 10,000 keys that is 40 µs per operation; a hash table does it in about 50 ns.
Any program that indexes by string (symbol tables, net names, counters) is not
2× off, it is hundreds of times off, and the ratio grows with the input. Fix: an
open-addressing table over the existing insertion-ordered entry list, with a
hash for `str` keys computed from the scalar array and the existing structural
equality for other keys. Insertion order, `pop`, `setdefault` and snapshots keep
their meaning; the entry list stays the iteration order.

**Fixed arrays copy the whole value on every element write.** `x = replace(x,
i, v)` blits the array to scratch, writes one element and blits it back; a
`[256]u8` staged one byte at a time is 512 bytes of copying per byte. This
is the value-semantics rule applied without the dead-source optimization every
other value type already gets: `QBE-CTORFWD-1` builds a record in place when
its staging slot is dead, and the same rule applies here. A `replace` whose
source local is dead after the assignment, or the ordinary spelling `x[i] = v`
on a `[N]T` local, should lower to one store. In the schematic this is the
single largest item: 0.6 ms of 3.5 ms.

**`with arena()` allocates and frees a zeroed chunk per scope.** `new_chunk` in
[`src/native_arena.c:80`](../../src/native_arena.c#L80) `calloc`s at least
64 KiB on the first allocation in a scope, and `myl_native_arena_release` frees
every chunk at scope exit. A loop that opens an arena per iteration pays a 64 KiB
`calloc` and its zeroing per iteration: the `alloc_churn` kernel is 2.7–4.2×
slower *inside* an arena than on the collecting heap, and 16–19× Zig, on the body
the arena documentation recommends arenas for. Fix: keep released chunks on a
free list, zero only the used prefix on reuse, and hand the first chunk back to
the next scope. This is the workload arenas exist for, and today they lose on it.

## 4. The structural items, ranked by measured price

Prices are what the evidence supports today: a counterfactual on this tree, a
kernel ratio, or the 2026-09-20 arm that composed the runtime levers. Each item
names the layer it changes.

**1. Make the LLVM backend the release path.** *Build driver.* Scalar code at
0.9–1.0× Zig on LLVM against 2.2–2.4× on QBE; the parser 1.7–3.0× against
2.3–4.1×; every kernel improves and most improve again with `--lto` (`bytes_scan`
2.35× → 1.50×, `str_build` 5.40× → 3.83×). Today the adapter is a Python script
(`qbe_llvm.py`, installed under `zig-out/lib/mylang-llvm`), reached only by
`mylang build --backend llvm`; `mylang run` and `mylang test` cannot select it,
[`docs/tooling/native-build.md`](../tooling/native-build.md) still says QBE is
the only backend, and one kernel (`float_loop`) is *slower* on O3 without LTO
than on QBE. Build cost is the trade: a cold build of the parser takes 12.6 s
against 3.2 s, but an unchanged rebuild is 0.16 s against 0.11 s and a
one-function edit 0.38 s against 0.23 s, because the per-function object cache
does the work. So the inner loop survives; only cold builds and the Python
dispatch per unit need attention. Parity is not reachable on QBE: it has no
loop-invariant code motion, no vectorizer, and a 2× floor on scalar code that no
runtime change recovers.

**2. Take the frame protocol off the call path.** *Compiler and runtime.* Every
call today allocates a 32-byte frame record, links it into `ctx->active_frame`
(a load and four stores), stores the function's metadata pointer, stores a
position before each call site, tests a sticky trap flag after each call, and,
in any function that calls, compares its frame against the stack floor. Priced
by editing the IL of `fib(32)` and rebuilding (15 rounds, quiet machine; the
loaded batch gave the same ratios within 0.06):

| arm | QBE | LLVM O3 + LTO |
|---|---:|---:|
| Zig ReleaseFast | 5.83 ms | |
| as compiled | 17.36 ms (2.98×) | 17.64 ms (3.03×) |
| without the frame record and floor check | 13.54 ms (2.32×) | 11.82 ms (2.03×) |
| also without the sticky trap test after calls | 14.12 ms (2.42×) | **10.46 ms (1.79×)** |
| also without position stores (loaded batch only) | 14.41 ms | 10.78 ms |

Forty percent of a call-heavy program on the LLVM arm, and the one item LLVM
cannot optimize away because the record escapes through `ctx`. Zig and Rust pay
nothing per call for a backtrace: they walk the native stack on the way out.
The replacement is the same idea, a return-address-to-source map emitted per
function, used only when a trap actually fires, plus unwinding for the trap
itself instead of a flag tested after every call. The `--max-frames` ceiling
keeps its exact semantics by counting on the native stack pointer, which the
floor check already reads. What is left after that, 1.8× on `fib`, is checked
subtraction and addition and the `%ctx` parameter, and it is close to Zig
ReleaseSafe's 2.0×.

**3. Shrink what an allocation touches.** *Runtime ABI.* A managed object is a
96-byte header from `calloc` (two list links, a descriptor pointer, two sizes,
three flags, 16 bytes of alignment padding) in front of the payload; a `list` is
a 72-byte header object plus a separately grown backing array, so one list is
168 bytes before its first element; a `str` is that header plus **four bytes per
scalar**. The parser's tree is 1.8–2.5× Zig's memory, and the 2026-09-20 audit
priced a 16-byte header at −11 M / −30 M cycles (census / render) and the
frozen-slice-plus-in-place-growth representation as the largest remaining item
after it. The string representation is a language decision as much as a runtime
one: UTF-8 storage with scalar indexing computed on demand is what every peer
does, and every I/O boundary today decodes into scalars and encodes back.

**4. Replace the collector's allocation and sweep.** *Runtime.* Allocation is
`calloc` per object; every collection traces from a root chain, then walks a
single linked list of every object ever allocated to sweep it; the trigger is
three times the live set plus 4 MiB. That is 16.5% of parser census samples and
3.9–6.1× Zig on `alloc_churn`. A bump allocator with size-classed free lists (or
a nursery) and a sweep that walks pages rather than a global list are the
standard answers; both need the header change above first, because the sweep
walks the header links.

**5. Give the runtime's fast paths to the optimizer.** *Build and runtime.*
Every list append, byte append, byte scan and element read of a non-scalar type
is a call into a separately compiled C object; LTO alone is worth 12–45% on the
kernels that lean on them, and inlining the capacity-sufficient path of
`list_append`, `bytes_buffer_append_*` and `buffer_grow_rooted` (which pushes
roots *before* it checks capacity) is worth more. `bytes_find_any` scans one byte
per iteration through a bitset; a one- or two-delimiter `memchr`/SIMD path is the
tokenizer's hottest single opportunity at 8.9% of census. The `for` loop over a
list re-reads the list's length and storage pointer and re-checks the generation
on every iteration; LLVM hoists these when the body has no calls, QBE never does.

**6. Stop materializing records the caller only reads.** *Compiler.* The
schematic's `layout_routes::build` spends 10.5% storing the same 128-byte `Pin`
twice; the parser's hot addresses are 64-byte `Node` copies out of lists into
stack scratch (`tally`, `is_short_list`, `advance`). The rule that already passes
read-only aggregate *parameters* by address (`QBE-AGGREF-1`) does not yet apply
to `pins[i]` or `for pin in pins`: the element is copied into scratch and its
address is then passed on. The 2026-09-20 audit put this at 2–4% of render user
cycles on the parser; on the schematic it is the second-largest guest item.

**7. Not levers, measured.** The checked 64-bit multiply is lowered as a
30-instruction manual 128-bit product because QBE has no overflow flags; removing
it changes nothing on LLVM and 6% on QBE (`mulloop`, quiet: 245.1 vs 230.4 ms on
QBE at 2.42× Zig, 89.5 vs 89.3 ms on LLVM, where mylang already runs at 0.88×
Zig). Process start-up is
0.12 ms. The host bridge is 0.07% of the schematic after today's packed I/O.
Instruction-step accounting doubles a bounded run and is not on the `mylang
run`/`build` path.

## 5. What parity would take, and what is proven

The acceptance target from the previous reports stands: within 10–20% of Zig
ReleaseFast (or within 10% of ReleaseSafe, the like-for-like comparator) on the
parser, the schematic, and this micro suite, at no more than 1.3× the memory,
with every check on and output byte-identical.

What is proven: items 1, 3 and parts of 5 were composed into one binary on
2026-09-20 and measured at **1.25× census / 1.37× render** on the parser, with
the tokenizer, parser and tally at Zig's cycle count and the residual entirely
memory volume. Item 2 is priced today at 40% of a call-bound program. The three
defects of §3 are each a bounded local change with a measured cost on the
workload that exposes them. Nothing is proven about the schematic beyond
§2's attribution: 42.5% in one fixable line, 10.5% in one copy pattern, and the
rest spread across placement and formatting at a few percent each.

The order that follows from the prices:

1. The three defects (§3): dictionary hashing, in-place fixed-array writes,
   arena chunk reuse. Small, local, and each removes an unbounded ratio.
2. LLVM as the release backend (item 1), with `mylang run` and `mylang test`
   able to select it and the build documented; measure cold-build cost and the
   `float_loop` regression as part of landing it.
3. The frame protocol (item 2), because it is the largest item the optimizer
   cannot touch and it prices the same on both backends.
4. Headers, strings and the collector (items 3 and 4) as one runtime
   representation change, since the sweep and the arena both depend on the
   header layout.
5. Runtime fast paths, LTO by default, and element-by-reference (items 5 and 6).

Then rerun this suite, the parser and the schematic on a quiet machine with
hardware counters enabled and declare the number.

## 6. Method and limits

- Builds: `zig-out/bin/mylang` from the working tree at `b8f6ec3f` plus
  uncommitted changes, `--mode ReleaseFast`; LLVM arms `--backend llvm --llvm-opt
  3` with and without `--lto`; Zig `0.17.0-dev.1683+5ceec001b`, `-O ReleaseFast`
  and `-O ReleaseSafe`, native target on both sides.
- Timing: `probes/bench.py` and `micro/run.py` run fresh processes pinned to one
  CPU (4, 6 or 8, an i7-12700H P-core), stdout to `/dev/null`, 3–5 warm-ups, 15–40
  randomized interleaved rounds, medians; the parser batch used the existing
  `experiments/llvm-backend/measure.py`. Every timed binary's stdout digest is
  checked against Zig's before timing. Startup is inside every interval.
- Load: the first pass of every batch ran while other sessions ran `zig build
  test` and this audit's subagents built their arms (load average 7–20). The
  parser, fib, multiply and start-up batches were re-run at load average 2 and
  those are the figures quoted (`results/quiet/`); the loaded pass is kept beside
  them and agrees on every ratio within 0.1×. The micro suite, dictionary and
  replace-loop probes have only the loaded pass, so only their ratios are quoted.
- Counterfactuals edit the emitted IL (`emit-qbe --drop-step-checks
  --drop-frame-checks`, then `patch_frames.py` / `patch_mul.py`, then `mylang build
  --manifest-file=`) and are diagnostics: a patched binary cannot report traps.
- Profiles are self-PC samples at about 1 kHz of process CPU time, no call
  stacks, with LTO inlining attributed to the surviving symbol; shares are of all
  samples including the unplaceable libc share. A 3,000-run control on a 6-byte
  input produced zero samples, so start-up is below one tick.
- The kernels are matched by algorithm, not by memory policy: Zig uses
  `ArrayList` over `smp_allocator`, an `ArenaAllocator` reset per batch, or
  `StringHashMap`; mylang uses its collecting heap or `with arena()`. `calls`
  does not isolate the call (its modulo dominates; use `fib`); `bytes_scan` and
  `list_append_sum` compare a vectorized Zig loop against a scalar mylang loop.
  Each mismatch is listed in `micro/results.md`.
