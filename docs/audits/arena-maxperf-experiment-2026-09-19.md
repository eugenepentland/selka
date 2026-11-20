# Arena and unchecked runtime experiment — 2026-09-19

The compact invocation arena plus unchecked lowering reduces wall time by
**16–33% against the current safe LLVM build**. It is the fastest measured arm,
but remains **2.73–4.19× Zig** on these workloads. Removing GC and the measured
safety overhead does not reach the 2× product target. This is an opt-in experiment
under `experiments/llvm-backend/maxperf/`; production defaults are unchanged.

These are medians in milliseconds from one 31-round interleaved batch, with
stdout captured and checked on every execution. The process and parent were
pinned to CPU 6. All seven arms ran in every round, with three warmups.

| Workload | Safe LLVM | Compact unchecked | Zig | Time reduction | Compact / Zig |
|---|---:|---:|---:|---:|---:|
| Census 927 KB | 6.89 | 5.66 | 2.07 | 17.9% | 2.73× |
| Render 927 KB | 11.59 | 9.76 | 2.72 | 15.8% | 3.58× |
| Census 7.42 MB | 62.41 | 41.71 | 13.59 | 33.2% | 3.07× |
| Render 7.42 MB | 102.07 | 78.95 | 18.85 | 22.6% | 4.19× |

A separate 31-round batch redirected timed stdout to `/dev/null`, with output
verification before and after. Compact times were 5.60 / 9.43 / 41.72 / 77.22 ms;
its Zig ratios were 2.83 / 3.75 / 3.07 / 4.54×. Output handling changes the render
ratios, so these batches must not be mixed. Neither batch is compared with wall
times from a different machine state. The capture batch's paired bootstrap 95%
intervals for safe/compact speedup are recorded in `ratios.json`; all exclude 1.

The experiment separates allocator changes from safety removal and inlining:

| Workload | Rebuilt GC | Arena | Unchecked | Whole O3 | Compact O3 |
|---|---:|---:|---:|---:|---:|
| Census 927 KB | 7.20 | 6.39 | 6.06 | 6.07 | 5.66 |
| Render 927 KB | 11.76 | 10.94 | 10.39 | 10.62 | 9.76 |
| Census 7.42 MB | 63.55 | 50.23 | 47.88 | 46.54 | 41.71 |
| Render 7.42 MB | 103.79 | 89.93 | 87.15 | 86.48 | 78.95 |

`arena` replaces per-object allocation and tracing with zeroed bump-allocated
chunks, retains the original object headers, and removes guest root bookkeeping.
`unchecked` adds removal of recognized safety branches and diagnostic frame
traffic, plus unchecked runtime wrappers. `whole-o3` merges all 66 guest units
and permits inlining at O3. `compact-o3` also eliminates the 96-byte GC header,
runtime root operations, region distinctions, and allocator descriptor/overflow
checks. Ordinary parser/Result/Option logic remains.

The rebuilt GC control is 1.4–4.5% slower than the frozen safe executable in the
capture batch. All experimental arms use the same system `cc -no-pie` link,
because this Zig snapshot's linker rejects `--wrap`. Thus arena/unchecked/stage
comparisons use the rebuilt control; the headline end-to-end gain uses the actual
frozen safe build. Runtime C stays at its production O2 flags. O3 and merging
apply to guest code only, not cross-language LTO. Whole O3 by itself produces
small, mixed wall-time changes; it is not the main gain.

The unchecked guest transform removes, across the frozen closure: 1,727 root-head
stores, 32 root-mark calls, 113 overflow checks, 67 bounds checks, 23 cast checks,
26 physical-frame checks, 186 sticky-trap checks, 99 allocation checks, 11
capacity checks, four iterator checks, 321 diagnostic-frame loads, and 928
stores. These are static IR counts, not runtime frequencies. LLVM assembly
checks confirmed the selected root/failure helper references disappear. Runtime
wrappers cover list get/append, text at/slice, and integer cast/negation/binary
operations; internally bound calls inside the merged runtime retain their
original helpers.

A separate ten-round interleaved counter batch sampled userspace instructions
and cycles. Wall timing never includes `perf stat` startup.

| Workload | Safe instructions M | Compact instructions M | Safe cycles M | Compact cycles M | Zig cycles M |
|---|---:|---:|---:|---:|---:|
| Census 927 KB | 65.59 | 38.50 | 20.15 | 14.79 | 5.21 |
| Render 927 KB | 109.55 | 77.70 | 34.87 | 28.34 | 6.67 |
| Census 7.42 MB | 556.78 | 306.67 | 197.84 | 115.24 | 40.82 |
| Render 7.42 MB | 908.58 | 620.32 | 329.99 | 236.99 | 52.00 |

GC was material: the fresh safe-build sample profile attributed about 28% of
resolved census cycles and 17% of render cycles to tracing/collection. The
fastest arm has no collection calls or tracing work. Diagnostic builds confirm
zero collections and actual chunk allocation:

| Workload | Logical allocations | GC collections | Compact collections | Compact chunks | GC peak RSS MiB | Compact peak RSS MiB |
|---|---:|---:|---:|---:|---:|---:|
| Census 927 KB | 19,943 | 2 | 0 | 3 | 12.3 | 12.4 |
| Render 927 KB | 23,895 | 2 | 0 | 4 | 16.7 | 15.4 |
| Census 7.42 MB | 159,179 | 4 | 0 | 17 | 72.1 | 64.7 |
| Render 7.42 MB | 190,854 | 4 | 0 | 23 | 114.0 | 106.6 |

These RSS readings are untimed diagnostic observations, not confidence intervals;
small cases can be dominated by process-launch high-water behavior. The large
inputs show that eliminating object headers more than compensates for retaining
some dead temporaries in this particular workload. The noncompact arena uses
more memory than GC. A long-lived process cannot keep accumulating invocation
storage: it must reset/destroy the arena after all borrowed values are finished.
The CLI already skips its final heap sweep in every arm and relies on process
exit. The arena implementation separately tests explicit bulk destruction.

What still prevents 2× is now predominantly the work and representation of the
benchmark. In the compact large-census profile, `read_string` accounts for 24.7%
and `tokenize` 19.0% of resolved userspace cycle samples; UTF-8-to-scalar decoding
adds 6.3%. In large render, `push_node` is 13.6%, scalar-to-UTF-8 encoding 13.3%,
`read_string` 11.6%, width estimation 9.6%, tokenization 8.9%, and text joining
4.2%. Profiles used 32 runs, cycles:u with period 200,000. Unknown/kernel-labelled
samples were excluded from these percentages (13.5% census, 10.7% render); some
libc samples retain only addresses. Inlining also changes symbol attribution.
These are sampled self-cycle shares, not additive guaranteed speedups.

The source explains the remaining work:

- `sexpr/tokenizer.my::tokenize` materializes a complete token list, and `lexeme`
  slices/decodes token strings. `parser.my::parse_with_depth_cap` then consumes
  that list. The Zig parser advances a tokenizer directly and borrows source
  byte spans where possible.
- Mylang text is a 72-byte list-shaped header plus four bytes per Unicode scalar.
  The compact arena removes the outer GC header, but not this representation.
  Token strings and quoted-string construction still allocate and copy. Repeated
  ASCII indexing already shares the 128-entry scalar cache; it does not allocate
  a fresh string on every access.
- The printer builds `list[str]`, appends indentation one space at a time, joins
  scalar strings, and re-encodes them as UTF-8. Zig avoids much of that materialized
  intermediate work.

The next substantial experiments should therefore be a streaming tokenizer with
source-span tokens and a byte-oriented output builder with bulk indentation.
Keep decoding/materialization at boundaries that need it, preserving Unicode
behavior. These are representation/algorithm changes, not another backend swap.
From the fastest capture result, reaching 2× still requires roughly 27%, 44%,
35%, and 52% additional time reduction across the four workloads respectively.
This experiment does not establish an absolute global performance ceiling.

Validation: all five arms passed **730/730 byte-exact valid-input comparisons**
against the safe build, including committed goldens, generated expressions,
Unicode strings, both benchmark sizes, and both modes. All timed outputs also
passed the Zig oracle. Seven lowering tests passed; strict-warning allocator,
compact allocator, runtime shim, and production integer differential tests
passed. The differential test covers widths 1–64, both signs, all 26 operations,
and boundary values on successful oracle calls. It caught and fixed the valid
`INT64_MIN % -1 == 0` case. Compact allocator ASan/UBSan and leak detection passed
with small chunks, multi-heap reuse, alignment, zero initialization, and bulk
release. No Guardian gate was exercised by this isolated experiment.

Unchecked behavior is intentionally restricted: invalid indices, overflowing
checked arithmetic, OOM, iterator invalidation, excessive recursion, and
out-of-range slice endpoints have no production guarantees. UTF-8 validation,
strict floating point, resource cleanup, real I/O, growth logic, and necessary
zero initialization remain. No fast-math flag was used.

Reproduction and exact arm contracts are in
[the experiment README](../../experiments/llvm-backend/maxperf/README.md).
Raw wall/counter samples, round orders, binary/source hashes, transformation
inventories, heap statistics, qualification cases, and profiles are in
[evidence/maxperf-20260919](../../experiments/llvm-backend/evidence/maxperf-20260919/).
The fastest local executable is `.tmp/llvm-maxperf-20260919/compact-o3.bin`.
