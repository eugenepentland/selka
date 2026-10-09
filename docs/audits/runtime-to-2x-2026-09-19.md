# Runtime audit: the remaining path toward 2× Zig

19 September 2026. Fresh measurements and bounded experiments, after the
register-resident-loop work and with the installed compiler's fused slice/decode
lowering. This is an audit, not a production optimization landing.

## Decision

**The ~5× observation is reproducible, but another small runtime cleanup will
not get this workload to 2×.** The best next bounded runtime change is bulk text
output; a prototype saves 3.5–5.6% of rendering cycles across two batches. The larger program of work is
less token/text materialization, better aggregate lowering, and less repeated
work in byte loops. A backend replacement is an experiment to price after those
changes, not a demonstrated prerequisite.

The measured workload is the EDA **S-expression reader, tree census, and canonical
text printer** in `experiments/sexpr-port`. It does not measure SVG layout,
routing, evaluation, or the complete schematic application. Use this as a compiler
workload, and add the actual schematic command before treating 2× as an
application-wide result.

## Fresh baseline

Compiled executables only; compilation is outside the timer. One warm-up, 21
randomly interleaved repetitions, median wall time, parent and children pinned to
CPU 6 before launching. Output is captured identically on both sides. The source
is the existing 927,415-byte EDA fixture; the large case repeats that fixture eight
times (7,419,320 bytes). This is a scaling probe, not eight independent designs.

| Workload | mylang | Zig ReleaseFast | Ratio | mylang time allowed at 2× |
|---|---:|---:|---:|---:|
| Census, 927 KB | 15.15 ms | 2.76 ms | **5.50×** | 5.51 ms |
| Render, 927 KB | 24.80 ms | 3.81 ms | **6.51×** | 7.62 ms |
| Census, 7.42 MB | 130.06 ms | 19.06 ms | **6.82×** | 38.13 ms |
| Render, 7.42 MB | 203.74 ms | 26.10 ms | **7.81×** | 52.20 ms |

Reaching 2× needs roughly **64%, 69%, 71%, and 74% less elapsed time**,
respectively. These are required reductions, not forecasts.

A complete rerun of the saved reproduction script returned census/render ratios
of **5.46×/6.60×** on 927 KB and **7.19×/8.13×** on 7.42 MB. Absolute times
were lower, but the conclusion held. The slowest repeated case requires about
75% less runtime to reach 2×. Both batches' raw samples are preserved.

The process-launch control `/bin/true` was 0.66–0.67 ms. It explains why small
process benchmarks understate the sustained gap. Do not subtract that number
and call the result an exact computation time: loader, initialization, allocation,
I/O, and teardown differ between the programs. The larger-input result is better
evidence that startup is not the main remaining opportunity.

Independent seven-run, interleaved `perf stat` measurements:

| Workload | mylang user instructions | Zig user instructions | mylang user cycles | Zig user cycles |
|---|---:|---:|---:|---:|
| Census | 130.84 M | 19.42 M | 33.01 M | 5.23 M |
| Render | 213.01 M | 22.75 M | 53.50 M | 6.66 M |

The census executes 6.7× the instructions and takes 6.3× the user cycles. Its
branch-miss rate is about 0.31%; there is no evidence here that branch misses
explain most of the gap. These counters exclude kernel execution, unlike some
older reports; compare ratios within this batch, not absolute counts across
reports. The machine had other active processes and frequency/load changed
between batches. Ratios and changes below are always from the same batch.

Peak RSS for the census, one `/usr/bin/time` observation per case: mylang/Zig
13,268/2,852 KiB on 927 KB and 80,544/16,932 KiB on 7.42 MB. RSS is process
memory, not an allocation count, but its roughly 4.7× gap supports examining
representation and lifetime rather than only arithmetic instructions.

## The benchmark is doing different internal work

The end-to-end census and rendering outputs match byte-for-byte. Their internal
strategies differ substantially:

* [mylang tokenizer](../../experiments/sexpr-port/sexpr/tokenizer.my) constructs a
  full `list[Token]`, including EOF, and converts lexemes into managed `str`.
  [mylang parser](../../experiments/sexpr-port/sexpr/parser.my) retains that list
  while constructing the AST.
* [Zig parser](../../experiments/sexpr-port/zig-bench/src/sexpr/parser.zig) consumes
  `Tokenizer.next()` on demand. Tokens and AST text borrow slices of the input.
* [mylang printer](../../experiments/sexpr-port/sexpr/printer.my) collects
  `list[str]` fragments, joins them into a UTF-32 string, then encodes for output.
  The Zig printer writes into a byte-oriented writer.

This matters particularly for the existing `--tokens` comparison: Zig just
counts the stream, while mylang materializes and retains it. mylang also counts
EOF, so the two token-count outputs differ by one. The old phase harness neither
normalizes this nor asserts output equality, and measures implementations in
separate batches. Differences between independent cumulative medians are rough
diagnostics, not precise phase timers. The scripts accompanying this audit
interleave implementations and check outputs, explicitly handling the EOF count.

Maintain two distinct benchmarks: the existing port with frozen source for
compiler regressions, and an idiomatic application implementation for the 2×
product target. Record source changes separately from compiler changes.

## Ranked work

### 1. Bulk UTF-8 output: a small, measured runtime improvement

[native_print.c](../../src/native_print.c) calls `encode()` for every Unicode
scalar; each call reaches the generic `myl_print_raw()` append/copy path.
Rendering samples attributed 10.7% to `memcpy` and 4.8% directly to
`myl_print_text`, although not all of the `memcpy` samples belong to output.

The prototype uses the existing `myl_native_text_utf8()` to size the output,
reserves buffer space once, and encodes directly into it. Nested/quoted printing
uses the original implementation. It preserves whole-line buffering.

| Same-batch render | Wall median | User instructions | User cycles |
|---|---:|---:|---:|
| Unmodified emitted-IR control | 20.91 ms | 213.01 M | 55.08 M |
| Bulk text-output prototype | 20.11 ms | 196.95 M | 51.97 M |
| Reduction | **3.8%** | **7.5%** | **5.6%** |

The normal build and emitted-IR control have effectively identical instruction
counts. Both prototype and control match the benchmark output. Prototype
validation: 17/17 rendering goldens and an additional non-ASCII differential case.
The complete reproduction rerun again saved 3.8% wall time, with 3.5% fewer
cycles and 7.5% fewer instructions; use the range rather than treating 5.6% as
a precise forecast.
This is enough to justify a production implementation, not a substitute for its
allocation-failure, nested repr, output-error, and full runtime checks.

### 2. Reduce token/text materialization: the largest priced opportunity

The installed compiler already calls `myl_qbe_bytes_decode_range` from `lexeme`;
removing the intermediate byte slice is already included in this baseline.
Do not count it again as future work.

[native_text.c](../../src/native_text.c) still stores Unicode scalars as `u32`
and constructs each string through `myl_native_list_new`. On this target the
managed object header is 96 bytes and the general list header is 72 bytes. A
nonempty dynamically allocated string therefore costs **264 fixed bytes plus
4 bytes per scalar**, before allocator overhead: two managed allocations, one
for the list-shaped object and one for backing storage. Static literals are
different and do not pay this per occurrence.

A deliberately incomplete variant replaces string/atom token text with `""`,
while retaining scanning, locations, numeric decoding, and tree construction.
Census instructions fall 130.84 → 99.50 M (**−24%**) and cycles 33.01 → 22.95 M
(**−30.5%**). Its census line still matches because the census never inspects
atom/string contents. Rendering would be wrong. This is an **upper-bound probe
for omitted text construction and its downstream costs**, not a valid speedup
or a prediction for a complete implementation.

Two useful implementation tracks:

1. Preserve language behavior: give immutable text a dedicated compact layout
   instead of a mutable-list header, coallocate header/data, and investigate
   ASCII storage with the current scalar representation as fallback. Keep
   Unicode scalar indexing, length, equality, and invalid-UTF-8 behavior exact.
2. For the application benchmark, consume tokens on demand and retain source
   offsets/slices until actual text is needed. Keep the input alive through a
   traced owner. Provide the existing public token-list API as a wrapper if
   compatibility requires it. Streaming alone still leaves AST strings; borrowed
   AST text is a separate representation change.

The second track changes the port's frozen `Token.text: str` convention unless
implemented behind an equivalent text representation. It belongs in a separate
application variant. Also check error precedence: lexing the whole file before
parsing can report a later lexical error before an earlier syntax error;
streaming can reverse that choice.

Even making all the work removed by the text probe free leaves 4.39× Zig's
census user cycles. Text work alone does not reach 2×.

### 3. Aggregate scalar replacement and copy elimination

The next compiler pass to investigate is scalar replacement of records/unions,
with copies materialized only at escapes, mutation boundaries, safepoints, or
ABI boundaries where they are actually needed.

Concrete locations:

* [qbe.zig](../../src/qbe.zig): aggregate local loads, stores, parameter copies,
  and returns use `blit`; scalar slots can be promoted, but these aggregates
  continue through memory.
* [qbe_aggregate.zig](../../src/qbe_aggregate.zig): record/variant construction,
  payload extraction, and snapshot copies.
* [qbe_managed.zig](../../src/qbe_managed.zig): aggregate list reads still use
  the generic `myl_native_list_get` copy path.

`Cursor`, `Token`, `Span`, `Step`, `Node`, and `Result[Step, ParseError]` pass
through these paths. The emitted `parse_node`, `parse_list`, and `push_node`
contain 29, 23, and 17 `blit` operations respectively. These are **static IR
counts**, not counts of executed copies or their cost. Census samples directly
attribute about 9.1% to the two parser functions, 3.8% to `memmove`, and 2.4%
to `memcpy`; these shares do not establish the saving a pass would achieve.

Start with one reduced `Token → Result → list.append` case and one recursive
`Step` return, retaining value-snapshot semantics and GC roots. Measure the
counterfactual before building a general pass. In particular, never replace an
aggregate snapshot with an interior pointer across a list mutation or growth.

This recommendation agrees with LLVM's own advice to frontend authors to avoid
unnecessary aggregate values and enable scalar promotion; changing backend alone
does not make the frontend's representation choices disappear.
[LLVM frontend performance guidance](https://llvm.org/docs/Frontend/PerformanceTips.html).

### 4. Eliminate repeated checked byte reads; make loops easier to optimize

A source-only scan probe changes:

```text
if source[index] == 40 or source[index] == 41:
```

to one byte load into a local followed by the two comparisons. With identical
output, instructions fall 35.69 → 27.39 M (**−23.3%**) and cycles 6.64 → 5.44 M
(**−18.0%**). This is a microbenchmark result, not an 18% application improvement.

Compiler targets: common checked loads, branch-sensitive range facts, reuse of
immutable receiver lengths, and a canonical induction variable. Reuse must be
invalidated by writes/calls that can change the relevant receiver or index;
removing a check must preserve the first observable trap and its location.

The two largest census sample buckets remain `read_string` (16.7%) and
`tokenize` (16.2%). However, rewriting `read_string` to carry the source, cursor,
line, and column in local scalars saves only **2.3% of total cycles**. It passed
17 goldens and eight differential escape/newline/Unicode/error cases. Generic
class-field caching is therefore not justified as the first large project by
this evidence. Bulk byte-search/classification primitives could address more
of these loops; their payoff is not measured here.

### 5. Allocation/GC and output builders: follow the representation work

Mark tracing, collection, heap allocation, and teardown together account for
about 10.4% of census samples. The heap currently uses `calloc` per allocation;
the managed arena implementation also uses this allocation path. Adding
`with arena()` therefore does not automatically provide Zig-style bump allocation.

First reduce object count and retained token state, then remeasure. If allocation
remains expensive, price a page/slab or region bump allocator with precise roots,
memory budgets, and correct reclamation. GC tuning alone cannot remove the
majority of this workload's runtime.

For rendering, investigate a reusable byte/text builder after bulk output.
`push_indent` currently appends one fragment per space, and the renderer joins a
fragment list into UTF-32 before encoding. Avoid guessing its payoff from the
number of source-level calls: `push_indent` itself was only 0.7% of samples.

## What to deprioritize

* More startup reductions, frame-record tweaks, or indiscriminate check removal.
  Earlier landed/retracted experiments are documented in
  [the hot-loop report](hot-loops-landed-2026-09-19.md).
* Treating reduced instruction count as proof of equal wall improvement.
* Assuming a switch to LLVM reaches 2×. The prior checked scalar-loop floor is
  already around 1.5–1.7× Zig using QBE. That is evidence about one loop, not the
  entire parser. QBE also exposes scalar temporaries and aggregate-memory
  operations explicitly; a frontend can improve what it emits.
  [QBE IL reference](https://c9x.me/compile/doc/il.html).
* Rewriting all strings to UTF-8 without pricing scalar-indexing and compatibility
  costs, or doing a collector rewrite before reducing object traffic.

## Sequence and acceptance

1. Adopt the corrected benchmark protocol and freeze compiler, QBE, Zig binary,
   source, input, and output hashes. Add representative complete schematic runs.
2. Land bulk raw-text output with its full correctness checks; expected scale is
   the measured few percent of rendering, not a step straight to 2×.
3. Price compact/coallocated text and a separate streaming/span application
   variant. Measure allocations, peak RSS, cycles, and full rendering correctness.
4. Price aggregate scalar replacement and checked-load reuse on reduced examples
   and then the unchanged application. Reprofile after each landing.
5. If the remaining code-generation gap is large, compare the same optimized
   representation under QBE and a small LLVM/C lowering experiment before
   committing to a new backend.

Define success as **≤2× Zig on each agreed end-to-end workload and input size**,
with identical outputs and agreed diagnostics, repeated quiet-machine runs, and
no regression outside this one fixture. Keep compilation latency separate so
runtime gains do not silently undermine the agent-development goal.

There is enough evidence to choose the next work; there is **not yet evidence
that the proposed changes, combined, achieve 2×**. The text ceiling, copying,
GC, and loop improvements overlap and must not be added as independent savings.

## Evidence and scope

[Raw evidence and reproduction instructions](../../experiments/sexpr-audit/evidence/next-2x-20260919/README.md).
The compiler/QBE were copied before builds because the checkout already contained
uncommitted runtime changes and other processes were active. The compiler hash,
input hashes, source hashes, CPU information, all timing samples, counter samples,
symbolized profiles, and prototype patches are saved there. The exact installed
compiler's correspondence to the dirty source tree is not assumed.

Only new audit/evidence files were added. Production source was not edited, no
whole-project build or Guardian gate was run, and no production/full-suite
validation is claimed. The bounded prototypes remain experiments.
