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

| workload | mylang, LLVM O3 + LTO (the ReleaseFast default since item 1) | mylang, QBE (Debug and explicit `--backend qbe`) | target |
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

Since this snapshot, **item 1 has landed** and **item 2 has landed in part**.
Each section below now records what shipped and the measurement that came with
it. The headline table stays as the 21 September audit measured it, so its two
columns name the ReleaseFast default and the Debug/explicit arm rather than
"the default".

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

**Landed 2026-09-21** (`BUILD-BACKEND-1` … `BUILD-BACKEND-5`). A plain
`mylang build`/`run` now resolves to `--backend llvm --llvm-opt 3 --lto`; a
`Debug` build or an explicit `--qbe PATH` stays on QBE and is never upgraded.
The installed adapter, four prebuilt runtime archives keyed by backend and LTO,
an overlapped per-unit codegen wave with a `--signatures-only` prepass, and
link reuse for an unchanged output are in. Measured on the 101-function parser
(independent re-run by the integrator): cold 4.33 s against QBE's 3.88 s
(**1.12×**, was 12.7 s), unchanged rebuild 1.05 s against 1.00 s (**0.05 s**
delta), all 11 micro kernels byte-identical between a plain build and
`--backend qbe`, and `float_loop` recovered (`-O3` without LTO 122.7 ms →
`-O3 --lto` 101.8 ms, QBE 101.2 ms). Two acceptance caveats, stated plainly:
the audit's exact parser and schematic ratios were *not* reproduced because its
inputs and Zig comparator are gitignored `.tmp` trees absent from this
checkout; and a real one-function edit still pays the ~0.85 s LTO relink, so
only the unchanged case meets the 0.2 s delta. Landing this also restored
adapter behavior the integration base had reverted (LTO-object emission,
installed-runtime source resolution, `llvm_emit` runtime and target
attributes) and fixed three latent adapter gaps the QBE arm never hit:
callbacks declared as globals, and the `split`/`ord`/`chr` and dir-resource
runtime helpers absent from the signature table.

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

**Landed in part, 2026-09-21.** Trap delivery is now a non-local exit
(`setjmp` in the guest-stack trampoline, `longjmp` from the first failing
`myl_qbe_fail_*` after the trace is built), so a fast build emits no
`loadl %trap` after a call; accounting builds and the direct C entry points
keep the sticky path, and `requireAccounting` still refuses a runtime ceiling a
build cannot honor. The record itself was **not** removed: the depth-indexed
replacement this item suggested was implemented, measured, and reverted —
`alloc8 32` is only a compile-time stack adjustment, so the record's roughly
one load and four stores per call beat a `ctx`-relative load, `imul $16`,
index add, store and matching return decrement, with the floor guard still
present (built binaries 0.22–0.25 s against 0.10–0.12 s; the harness put the
LLVM arm near 5.9×). Trap parity is intact: 504 built-binary comparisons
across 21 fixtures and 6 accounting modes, each with and without
`--gc-stress`, **0 mismatches**; `--max-frames` still trips at the same depth.
The performance acceptance is **not met**: `fib` is 3.11× Zig ReleaseFast, not
≤ 1.9×. Reaching it needs the record, the floor guard and the position store
all gone, which needs an exact return-address→source-position map consulted
only at trap time. QBE emits `push %rbp; movq %rsp, %rbp` for every non-leaf
function, so a native walk can recover the return addresses; the position half
needs interior-label addresses that QBE cannot place in a `data` section, so
the smallest credible next step is a driver-side pass annotating each call site
with a distinct symbol (or an IL extension giving each call site a label
reference), after which the map is built and read only on a trap.

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

**Landed in part, 2026-09-21** (`GC-OBJECT-1`, `GC-SEGMENT-1`). The managed
header is two words — a mark word (mark bit, immortal-literal flag, element
count) and the element descriptor — and the collector's worklist is a heap-side
array; the generated frozen-literal block initialises the mark word, the native
ABI moves to `mylang-qbe-native-v7` and the cache contract to
`runtime-abi-v2`. Objects come from size-classed segments: a class bump-
allocates zero-filled slots and reuses slots a previous sweep reclaimed through
a per-class free list, and the sweep walks segments instead of a global link
chain. Measured on the default `o3-lto` arm with `.tmp/verify/measure.py`
(interleaved, 25 rounds, arm outputs byte-identical), `alloc_churn` falls
**2.65× → 1.85×** Zig ReleaseFast (target ≤ 2×, **met** on `o3-lto` and `qbe` at
1.81×; the non-default `o3` arm is 2.07×), and no other kernel regresses. The
parser's census profile falls from 16.5% to 12.3% of samples in `trace` +
`heap_collect` (collect alone 4.9% → 1.8%, target ≤ 5% **not met** — the mark
phase over the live graph remains). Peak RSS on the 7.42 MB `input8.sexp` falls
1.78× → 1.70× Zig census and 2.46× → 2.29× render (target ≤ 1.3×, **not met**;
the header is no longer the bulk of the parser's bytes, which are the 4-bytes-
per-scalar `str` payload of item 4 and the list header/backing pair of the third
change above). The list representation half of this item is **not attempted**:
coallocating a list's header and inline elements requires the collector to trace
the elements through the header object's own descriptor, and the frozen
`{ptr, len}` slice is a representation the compiler must choose and every
consumer must understand, so it is left for a change that can pay its own way on
both the fast paths item 5 and item 6 already read.

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

**Landed in part, 2026-09-24** (`UTF8-TEXT-1`, `QBE-TEXT-BLOCK-1`). A `str` is
now a 24-byte header — the Unicode scalar count at offset 0, which generated
code still loads as `len(text)`, the payload's octet count, and a flag word
whose bit 0 says every scalar is below 0x80 and whose fourth word caches the
payload hash a dictionary computes — followed by the value's UTF-8 payload in
the same managed block. Equality is one byte compare, order is UTF-8 byte order,
and `from_utf8`, `utf8`, `bytes.encode`, `bytes.hex`, `bytes.fromhex`, a file
path and a print sink copy octets instead of decoding and re-encoding scalars.
Scalar indexing, slicing, a stepped slice and `ord` compute byte offsets on
demand: a scalar index is a byte index on ASCII text and one payload walk
otherwise, and the same walk turns an octet offset back into a scalar index for
`find`. `find`, `count`, `split`, `replace`, `splitlines` and `split()` scan
octets, because an ASCII scalar is its own octet and no octet of a non-ASCII
scalar is below 0x80. The payload holds no pointer, so the collector still sees
a leaf; the arena escape copier clones a text as one payload copy and a
whole-path file helper borrows a payload only for the write helpers that consume
one. ABI v8 and cache contract `runtime-abi-v3` retire every v7 manifest and
object.

Measured with the audit's harness (interleaved arms, byte-identical stdout on
every arm). Baseline is `dcbcc2fd` measured on this machine with
`.tmp/verify/measure.py --kernels str_build dict_count list_append_sum
list_records fib --rounds 15`; final is the same command over ten kernels;
`o3-lto` is the default arm:

| kernel | baseline `o3-lto` | final `o3-lto` | target |
|---|---:|---:|---:|
| `dict_count` | 99.4 ms (2.77×) | 67.9 ms (2.09×) | ≤ 1.5×, **not met** |
| `str_build` | 173.1 ms (3.17×) | 177.2 ms (3.50×) | ≤ 1.5×, **not met** |
| `list_append_sum` | 144.6 ms (2.32×) | 123.7 ms (2.25×) | no regression |
| `list_records` | 109.0 ms (2.02×) | 102.4 ms (1.87×) | no regression |
| `fib` | 139.2 ms (3.37×) | 129.8 ms (3.30×) | no regression |

A same-session interleaved A/B of the two compilers (`.tmp/verify/ab.py
--kernels str_build dict_count --rounds 21`) puts `dict_count` at 100.4 → 71.4 ms
(**0.711×**, −29%) and `str_build` at 168.3 → 173.8 ms (1.033×, with identical
per-run minima, 162.2 vs 162.6 ms). The remaining kernels show no regression:
`records` 0.92×, `intloop` 0.97×, `calls` 0.95×, `alloc_churn` 2.00×,
`bytes_scan` 1.41× on the final run.

**Why the two targets are still short.** `str_build` is a *byte-buffer* kernel
with no `str` in it at all: its emitted IL is **byte-identical** between the two
commits (27,937 bytes, zero `myl_native_text_*` symbols) and its manifest carries
`"text_format":false`, so item 4 cannot move it. What its 3.2–3.5× is made of is
the per-iteration root chain around `byte_buffer.append_range` plus the buffer's
growth copies: a self-PC profile of the `o3-lto` binary puts 43% of samples on
the eight-byte append store itself, inside the `entry_run` LTO built out of the
guest `main`, with 30% outside the executable in `memcpy`/page-fault territory.
`dict_count`'s remaining 0.6× is not text either. After the hash cache, `find`
is still 53% of its samples, and the kernel's own spelling — `counts[key] =
counts.get(key, 0) + 1` — is *two* lookups, exactly what the audit's
`zig-fast-getorput` arm measures the cost of. Removing the second lookup
entirely bounds the kernel near 53 ms ≈ 1.5× and no further, so the target needs
the `get`/write fusion (and the emitted call and root overhead around it), not a
different string representation.

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

**Landed in part, 2026-09-21** (`QBE-APPEND-FAST-1`, `PY-BYTES-21`). A list
`append` in a root-keeping frame now lowers its capacity-sufficient case in the
emitted IL — a length/capacity compare, one element store and a
`length`/`generation` bump, with the grow helper and the frame's root protocol
reached only when the element does not fit — and `bytes.find_any` answers one-
and two-octet sets with libc `memchr`. Measured on the default `o3-lto` arm,
interleaved, arm outputs byte-identical: `list_append_sum` **3.00× → 2.2–2.5×**
(2.15× at 15 interleaved rounds, 2.44× on the full 11-kernel harness; target
≤ 2×, **not met**; the residual is the memory-resident list header's
read-modify-write per append and the checked-add sum loop, neither of which is
an item-5 lever), and `find_any` falls from **8.85% to 1.15%** of parser census
samples (target ≤ 3%, **met**). `bytes_scan` measures 1.23–1.49× across runs and
is untouched by this change; its hot loop is already hoisted by LTO and Zig wins
by unrolling the byte compare, so no item-5 lever remains there and the
acceptance is **not claimed**. The already-landed LTO runtime archive means part
of item 5's projected gain was present before these changes.

### 6. Stop materializing records the caller only reads

*Compiler. Size: medium.*

**Evidence.** `layout_routes::build` spends 10.5% of the schematic render
storing the same 128-byte `Pin` twice; the parser's hot addresses are 64-byte
`Node` copies out of lists into stack scratch (`tally`, `is_short_list`,
`advance`); `list_get` plus its `memcpy` is 2–4% of parser render. Two smaller
copies were found during the fixes: array-typed record fields still copy on
`r.cells = replace(r.cells, i, v)`, and `frameBytes` sizes a frame from every
per-pc aggregate scratch even when forwarding removes it, so a function taking
a `[1024]int` parameter heap-allocated an 82 KB frame per call until
`QBE-FRAMEFIT-1` and `QBE-AGGREF-9` landed
([frame-fit-2026-09-21](audits/frame-fit-2026-09-21.md)).

**Change.** Apply `QBE-AGGREF-1`'s by-address rule to `xs[i]` and `for x in
xs` when the consumer only reads: pass `storage + i * stride` with the
generation check hoisted out of the loop. Extend `QBE-ARRAYWRITE-1` to array
fields through `update_record`. Frames are now sized from the scratch that
survives forwarding (done). Return-slot forwarding for call sites that immediately store an
aggregate result (about 30 of the parser's 209 blits).

**Acceptance.** `list_records` ≤ 1.3× Zig; `layout_routes::build` ≤ 5% of the
schematic profile; `peek1024`/`peek4096` in `docs/performance.md` within 2× of
`peek8` (met: 1.46 ms and 1.48 ms against 1.30 ms).

**Landed in part, 2026-09-21** (`QBE-AGGREF-1`). A list element whose only
consumer is the `store_local` that copies it — `x = xs[i]` and the loop variable
of `for x in xs` — is now read through its checked own address instead of being
blitted into per-pc aggregate scratch and then copied again, so one of the two
copies disappears; bounds, generation and trap behavior are unchanged. Measured
on the default `o3-lto` arm, interleaved, arms byte-identical: `list_records`
**2.16× → 1.88×** (131.13 ms → 102.73 ms, ~21% absolute; the Zig arm also moved
7–10% between the runs, so part of the ratio gain is drift), and `records`
0.87× → 0.95× is drift, not a regression — that kernel has no list and the diff
cannot reach it. The target is **not met**: the surviving copy into the
destination local, the per-iteration generation check, the length reload and the
bounds check still dominate. Removing them needs a sound proof that the loop
body cannot mutate or alias the receiver across the borrow's live range, which
is the next step. The remaining named changes — a by-reference destination local,
array-typed record fields through `update_record`, and return-slot forwarding
(about 30 of the parser's 209 blits) — are not done, and the
`layout_routes::build` profile share and schematic `peek` numbers were not
measured, so no claim is made about them.

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

Item 1 is now production rather than experimental, so the composed 1.25× / 1.37×
reference is one landed item closer; item 2's price did not fall, because the
record replacement that would have delivered it regressed and was reverted.
The projection is otherwise unchanged, and it still depends on items 3 through
6.
