# Performance roadmap: the next changes, in order

Where mylang stands against Zig and Rust after the 21 September 2026 audit and
the three fixes it led to, and what to change next to reach parity. Every item
carries the measurement that ranks it; the numbers come from
[the parity audit](audits/performance-parity-audit-2026-09-21.md) and
[its rerun on the merged compiler](audits/performance-parity-rerun-2026-09-21.md),
and the harnesses that produced them live under
`experiments/perf-parity-audit-20260921`. Re-measure before and after each item
with those harnesses; do not add an item's projected gain to another's.

## Where we are (2026-09-21, `perf/lever-search` at `59bbce0a`)

| workload | mylang, LLVM O3 + LTO | mylang, QBE (the default) | target |
|---|---:|---:|---:|
| integer loop, records, checked multiply | 0.9–1.0× Zig | 2.2–2.4× Zig | ≤ 1.2× |
| schematic SVG render | 2.06× Zig, 1.84× Rust | not measured | ≤ 1.2× |
| S-expression parser, census / render | 1.8× / 2.4× (small), 2.1× / 3.0× (large) | 2.3× / 3.3×, 2.8× / 4.1× | ≤ 1.2× |
| worst micro-kernel | 3.9× (byte building) | 6.0× (dictionary) | ≤ 1.3× |
| peak memory, parser | 1.8× / 2.5× Zig | same | ≤ 1.3× |

Done and merged: hash-indexed dictionaries (`PY-DICT-2`), in-place fixed-array
writes (`QBE-ARRAYWRITE-1`), arena chunk reuse (`ARENA-MANAGED-10`). Nothing in
the measured set has an asymptotic cliff any more; everything left is a
constant factor with a known cause.

Zig ReleaseSafe, the like-for-like comparator (checks on), runs at about 1.1×
ReleaseFast on these workloads, so "≤ 1.2× ReleaseFast" is "≈ parity with
ReleaseSafe".

## The order

The items are ranked by measured price divided by the size of the change, with
dependencies respected: 1 first because it is a build-policy change that
halves the scalar gap on its own; 2 next because it is the largest item the
optimizer cannot touch; 3 and 4 together because they share the object layout;
5 and 6 are independent and can run alongside anything.

### 1. Make the LLVM backend the release path

*Build driver and tooling. Size: medium.*

**Evidence.** The same source runs 2.2–2.4× slower on QBE than on LLVM O3 for
scalar code, and LLVM is already at 0.9–1.0× Zig there with every check on. The
parser is 2.3–4.1× Zig on QBE against 1.8–3.0× on LLVM O3 + LTO. QBE has no
loop-invariant code motion and no vectorizer, so this floor cannot be recovered
by runtime work.

**Change.** Make `--backend llvm --llvm-opt 3 --lto` the default for a
ReleaseFast `mylang build` and `mylang run`, and let `mylang test --mode
ReleaseFast` select it. Keep QBE as the Debug and inner-loop backend. Ship the
runtime as bitcode so `--lto` sees it by default. Then take the cost out of the
cold build: today the adapter is `qbe_llvm.py`, one Python process per unit,
12.6 s cold against 3.2 s for QBE on 101 functions (an unchanged rebuild is
0.16 s against 0.11 s and a one-function edit 0.38 s against 0.23 s, so the
object cache already protects the inner loop). Batch units per process or port
the adapter to Zig. Fix the one regression the kernels show: `float_loop` is
slower on O3 *without* LTO (122.9 ms) than on QBE (89.9 ms); LTO recovers it
(95.1 ms). Update `docs/tooling/native-build.md`, which still says QBE is the
only backend.

**Acceptance.** The parser and schematic numbers above reproduce from a plain
`mylang build`; cold build within 2× of QBE's; incremental rebuild within
0.2 s of QBE's; every arm of the micro suite byte-identical to QBE's output.

### 2. Take the frame protocol off the call path

*Compiler and runtime. Size: medium to large.*

**Evidence.** Every call allocates a 32-byte frame record, links it into
`ctx->active_frame` (a load and four stores), stores the function's metadata
pointer, stores a source position before each call site, tests a sticky trap
flag after each call, and compares against the stack floor in any function
that calls. Removing the record and the flag test by IL counterfactual takes
`fib(32)` from 3.03× to 1.79× Zig on LLVM (2.98× to 2.32× on QBE): about 40% of
a call-bound program, and LLVM cannot remove it because the record escapes
through `ctx`. Zig and Rust pay nothing per call for a backtrace.

**Change.** Emit a per-function map from return address to source position
and consult it only when a trap fires, walking the native stack the way a
debugger does. Deliver the trap itself by unwinding to the runtime's failure
handler instead of a flag tested after every call (a trap is fatal, so no guest
code runs after it; resource cleanup that the sticky flag drove today moves to
the unwinder). Keep `--max-frames` exact by comparing the native stack pointer
against a computed floor, which the existing floor check already reads. Keep
the current record only in builds with step accounting, where every
instruction already stores its position.

**Acceptance.** `fib` ≤ 1.9× Zig ReleaseFast (≈ 1.0× ReleaseSafe); every trap
in the trap corpus renders the same code, message and `in f at file:line`
trace as today; `--max-frames=N` trips at the same depth.

### 3. Shrink what an allocation touches, and replace the collector's allocator and sweep

*Runtime ABI. Size: large.*

**Evidence.** A managed object carries a 96-byte header (two list links, a
descriptor pointer, two sizes, three flags, alignment padding) in front of its
payload and is allocated with `calloc`; a `list` is a 72-byte header object
plus a separately grown backing array, so one list costs 168 bytes before its
first element. The collector marks from a root chain, then walks a single
linked list of every object to sweep. That is 1.8–2.5× Zig's peak memory on
the parser, 16.5% of its census samples in `trace` and `heap_collect`, and
3.7–5.5× Zig on the allocation-churn kernel. The 2026-09-20 audit priced a
16-byte header at −11 M / −30 M cycles (census / render) and the list
representation as the largest remaining memory item after it.

**Change.** A mark word plus a descriptor-and-size word per object; `next` and
`pending` links moved to a side table or per-segment map; bump allocation
inside size-classed segments with a sweep that walks segments; a list whose
header and backing can be one object when the capacity is fixed, and a frozen
`{ptr, len}` slice for finished lists. The arena code, descriptors, immortal
literals and the heap-aware metadata queries (`myl_native_object_element`,
`_immortal`, `_region`) all read the header and move with it.

**Acceptance.** Parser peak RSS ≤ 1.3× Zig on both inputs; `alloc_churn` on the
GC path ≤ 2× Zig; `trace` + `heap_collect` ≤ 5% of parser census samples; every
GC-stress test and the ten native-memory C suites green under ASan/UBSan.

### 4. Store strings as UTF-8

*Language and runtime. Size: large.*

**Evidence.** A `str` is a list header plus **four bytes per scalar**, so text
costs 4× Zig's memory and every I/O boundary decodes into scalars and encodes
back; the byte-building kernel is 3.9× Zig, the dictionary kernel's remaining
3.2× is mostly hashing and comparing scalar arrays, and the earlier profiles
had "native UTF-8 → scalar text" and back as named stages.

**Change.** Store UTF-8 bytes with a cached scalar count and an "is ASCII"
flag; keep Python's scalar-indexing semantics (`s[i]`, `len`, slicing) by
computing offsets on demand, O(1) on ASCII text and O(n) otherwise, or through
a small breadcrumb index for long non-ASCII strings. Equality, hashing, `find`,
`split`, `join`, comparison and rendering become byte operations. Views and
`bytes` interop become free. This is a representation change visible to every
text method, codec and the host boundary; do it after item 3 so the header
change is not paid twice.

**Acceptance.** `str_build` ≤ 1.5× Zig; `dict_count` ≤ 1.5×; text-method tests,
`docs/text.md` examples and the SVG/parser goldens byte-identical.

### 5. Give the runtime's fast paths to the optimizer

*Runtime and build. Size: small, incremental.*

**Evidence.** Every list append, byte append, byte scan and non-scalar element
read is a call into a separately compiled C object; LTO alone is worth 12–45%
on the kernels that lean on them (`bytes_scan` 2.33× → 1.74×, `str_build` 5.25×
→ 3.86×, `dict_count` 5.31× → 3.17×). `bytes_find_any` scans one byte per
iteration through a bitset and is 8.9% of parser census samples;
`buffer_grow_rooted` pushes roots before it checks capacity.

**Change.** Inline the capacity-sufficient path of `list_append` and
`bytes_buffer_append_*` in the emitted IL; check capacity before rooting in
`buffer_grow_rooted`; a one- or two-delimiter `memchr`/SIMD path for
`find_any`; hoist a `for` loop's list length and storage loads out of the loop
when the body has no calls (LLVM already does this; QBE does not). With item 1
landed, ship the runtime as bitcode so the rest inlines by itself.

**Acceptance.** `bytes_scan` ≤ 1.3×, `list_append_sum` ≤ 2× Zig; `find_any` ≤
3% of parser census samples.

### 6. Stop materializing records the caller only reads

*Compiler. Size: medium.*

**Evidence.** `layout_routes::build` spends 10.5% of the schematic render
storing the same 128-byte `Pin` twice; the parser's hot addresses are 64-byte
`Node` copies out of lists into stack scratch (`tally`, `is_short_list`,
`advance`); `list_get` plus its `memcpy` is 2–4% of parser render. Two smaller
copies were found during the fixes: array-typed record fields still copy on
`r.cells = replace(r.cells, i, v)`, and `frameBytes` sizes a frame from every
per-pc aggregate scratch even when forwarding removes it, so a function taking
a `[1024]int` parameter heap-allocates an 82 KB frame per call (in progress as
a separate task).

**Change.** Apply `QBE-AGGREF-1`'s by-address rule to `xs[i]` and `for x in
xs` when the consumer only reads: pass `storage + i * stride` with the
generation check hoisted out of the loop. Extend `QBE-ARRAYWRITE-1` to array
fields through `update_record`. Size frames from the scratch that survives
forwarding. Return-slot forwarding for call sites that immediately store an
aggregate result (about 30 of the parser's 209 blits).

**Acceptance.** `list_records` ≤ 1.3× Zig; `layout_routes::build` ≤ 5% of the
schematic profile; `peek1024`/`peek4096` in `docs/performance.md` within 2× of
`peek8`.

### 7. Dictionary follow-ups

*Runtime. Size: small.*

`pop` rebuilds the index and is O(n), so a pop loop is O(n²); dictionary
equality in `native_equal.c` is still O(n²); the hash is unseeded FNV-1a, so
adversarial keys can degrade it (a keyed hash needs a per-process seed, which
means a sanctioned entropy source for the runtime). Do these when a workload
shows them; none is on the parity path.

### 8. Bounded execution

*Compiler. Size: medium.*

Instruction-step accounting doubles a bounded run (schematic 7.6 ms bounded
against 2.7 ms). It is not on the `mylang run`/`build` path, but it is what
the schematic host and `mylang test` pay. Batch straight-line regions and
charge them together, with the exact per-instruction path near exhaustion, as
the 2026-09-21 gap audit specified.

## Measuring

- Re-run `experiments/perf-parity-audit-20260921` (micro suite, probes, parser
  batch, SVG harness copy) before and after each item, on a quiet machine, and
  record both arms in one interleaved batch. `results/merged/chain.log` is the
  sequence to repeat.
- Get hardware counters back (`kernel.perf_event_paranoid` ≤ 1) so instruction
  and cycle counts can be quoted again; wall time alone hides IPC changes.
- Keep the composed 2026-09-20 LLVM arm (1.25× census / 1.37× render on the
  parser with items 1, 3 and 5 applied experimentally) as the reference for
  where the priced levers land; the roadmap is done when a production build
  reproduces it and the schematic and the kernels follow.

## Projection, stated as such

Items 1, 3 and 5 were composed experimentally on 2026-09-20 and measured at
1.25× / 1.37× Zig on the parser; item 2 is priced at 40% of a call-bound
program; items 4 and 6 are priced by kernel and profile share, not by a
composed build. A production build that lands 1 through 6 should put the
parser and the schematic inside the 1.2× target; that is a projection from
those measurements, not a result.
