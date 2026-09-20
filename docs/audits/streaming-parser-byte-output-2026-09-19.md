# Streaming parser and byte output — 2026-09-19

The streaming parser and allocation-free bulk indentation reduce wall time by
**12–16% in the compact-arena experiment**, relative to the previous compact
build in the same batch. The selected text renderer now runs **2.36–3.67× Zig**.
The 2× target remains unmet. The byte renderer is implemented and verified, but
does not consistently outperform text rendering, so the CLI retains text output.

## What is general purpose

- `Stream.write(bytes)` is a runtime/compiler improvement available to every
  program. It writes raw bytes without constructing intermediate text, preserves
  stdout/stderr capability routing and the output effect, and returns a byte
  count. NUL and invalid UTF-8 are preserved. Refused writes/flushes trap
  `R_OUTPUT`; the existing text overload still counts Unicode scalars.
- The embedded `byte_builder` standard module is reusable by any serializer,
  formatter, protocol encoder, or code generator. It accumulates immutable byte
  chunks and buffered individual octets, then joins them into an immutable
  snapshot. It supports UTF-8 text, checked individual bytes, and bulk spaces.
  Subsequent appends cannot alter earlier snapshots. This is a **chunk builder**,
  not a native growable byte buffer; appending text still allocates its encoding.
- Streaming tokenization and source-span tokens are reusable parsing techniques,
  implemented here in `sexpr.tokenizer` and `sexpr.parser`. Other mylang programs
  do not automatically receive this algorithm change. The parser keeps one token
  of lookahead instead of the complete token list. The old `tokenize` API remains.
  AST strings are still owned scalar strings, **not borrowed byte views**.
- Bulk indentation benefits this printer and the general byte builder. Shared
  64/32/16/8/4/2/1-space literals avoid per-column appends and remainder slicing.

Production GC, bounds/overflow checks, UTF-8 semantics, and diagnostics remain
enabled. The arena/unchecked builds reuse the explicitly opt-in experiment in
[`maxperf`](../../experiments/llvm-backend/maxperf/README.md).

## Matched wall time

Milliseconds, medians of 31 rounds. All ten arms ran in each shuffled round,
with three warmups, CPU 6 affinity, and stdout captured and checked on every
execution. No builds or tests ran concurrently. Instructions/cycles were sampled
in a separate ten-round matched batch, excluding `perf stat` startup from wall
timing. Ratios below divide these medians, not measurements from earlier reports.

| Workload | Previous arena | New text arena | New bytes arena | Zig | Text arena / Zig |
|---|---:|---:|---:|---:|---:|
| Census 927 KB | 5.508 | 4.835 | 4.768 | 2.051 | 2.36× |
| Render 927 KB | 9.835 | 8.504 | 8.722 | 2.614 | 3.25× |
| Census 7.42 MB | 42.694 | 35.977 | 36.176 | 13.517 | 2.66× |
| Render 7.42 MB | 80.271 | 69.501 | 69.139 | 18.957 | 3.67× |

Paired-round bootstrap 95% intervals for previous-arena/new-text-arena speedup:
**[1.116, 1.195], [1.139, 1.173], [1.177, 1.197], [1.141, 1.161]**.
The byte arena's apparent large-render lead is only 0.5%; the text/bytes interval
**[0.995, 1.017]** includes equality. Text wins small render by 2.5%. There is no
consistent byte-output performance win to justify making it the default.

| Workload | Previous LLVM + GC | New text LLVM + GC | New bytes LLVM + GC | Previous QBE + GC | New text QBE + GC |
|---|---:|---:|---:|---:|---:|
| Census 927 KB | 6.948 | 6.890 | 6.726 | 8.509 | 8.453 |
| Render 927 KB | 11.625 | 10.998 | 12.666 | 13.496 | 13.062 |
| Census 7.42 MB | 63.953 | 52.481 | 52.300 | 75.888 | 66.152 |
| Render 7.42 MB | 104.163 | 104.268 | 112.936 | 118.711 | 121.336 |

LLVM with GC improves **18% on large census and 5.4% on small render**. Small
census and large render are statistically flat. QBE improves large census by
12.8%, but **large render regresses 2.2%**: previous/new interval
**[0.975, 0.983]**. This is not an across-the-board production speedup. The
experiment prioritizes the requested arena configuration; the QBE render
regression remains a follow-up for aggregate lowering and runtime profiling.

The parser-only arm measured 6.956 / 11.474 / 52.658 / 107.868 ms. Streaming
provides the large-census gain; bulk indentation recovers the GC large-render
regression to approximately parity. This attribution is for the checked LLVM
arms; it does not isolate every contribution inside the whole-module arena arm.

## Work and allocation evidence

Userspace retired instructions, millions:

| Workload | Previous safe LLVM | New text safe LLVM | Previous arena | New text arena | New bytes arena | Zig |
|---|---:|---:|---:|---:|---:|---:|
| Census 927 KB | 65.60 | 62.34 | 38.50 | 33.48 | 33.48 | 19.42 |
| Render 927 KB | 109.56 | 102.78 | 77.70 | 69.66 | 77.54 | 22.75 |
| Census 7.42 MB | 556.79 | 472.17 | 306.68 | 266.55 | 266.55 | 155.02 |
| Render 7.42 MB | 908.58 | 862.32 | 620.32 | 556.03 | 619.02 | 181.60 |

Untimed diagnostic builds, large input:

| Metric | Previous census | New text census | Previous render | New text render | New bytes render |
|---|---:|---:|---:|---:|---:|
| Logical allocations | 159,179 | 159,161 | 190,854 | 190,835 | 367,718 |
| GC collections | 4 | 3 | 4 | 4 | 4 |
| Compact-arena payload bytes | 68,955,060 | 47,983,644 | 110,680,864 | 81,320,840 | 76,028,211 |
| Compact-arena peak RSS KiB | 66,256 | 49,984 | 109,372 | 87,224 | 78,296 |

All compact builds report zero collections. Payload bytes fall about 30% for
census and 27% for text render. The token list used a small number of large
backing allocations, so removing it saves bytes rather than many allocations.
GC live bytes and arena cumulative payload bytes have different meanings; the
table deliberately compares arena payload with arena payload. RSS readings are
single diagnostic observations, not confidence intervals.

The byte renderer roughly doubles render allocations because it encodes each
leaf into a separate managed byte object. The existing text renderer reuses AST
strings, joins scalar text, then encodes the final result. A chunked bytes API
alone does not eliminate this representation cost. A native growable builder
that encodes text directly into its destination, or fused text-join/UTF-8 output,
is the next general-purpose experiment; neither is implemented or claimed here.

## Regressions caught during implementation

The first streaming `parse_node` exceeded the compiler's 32 KiB estimated-frame
threshold (42,080 bytes), introducing `calloc`/free on every node. Splitting leaf
dispatch into `parse_leaf` removed those calls without raising the threshold.
Native QBE prologues reserve 872/1,112/600 bytes for parse_node/parse_leaf/
parse_list. Neither final 83-unit manifest references `myl_qbe_frame_allocate`.

The first printer shared a mode switch between text and byte emission on every
piece. Separate traversals avoid that overhead. The first bulk-indent version
sliced remainder padding, adding 45,000 text allocations and 90,000 byte
allocations in the large render. Shared power-of-two literals remove them. The
preceding 31-round batch is retained as `indent-slices-measure.json`; its source
variant and binaries differ from the final batch and its timings are not pooled.

The LLVM adapter's fail-closed C signature table was extended for the byte
operations and frame helpers exercised by these implementations/tests. No ABI
layout or production allocator changed in this iteration.

## Validation and evidence

- Full `zig build test`: **60/60 steps**, 1,321 selected tests passed; 214 language
  fixture tests and 42 existing stdlib fixtures passed or were cached. Documentation
  examples and coverage passed. Guardian passed all 88 configured checks.
- Both QBE and LLVM: **87/87 port tests under GC stress**. Streaming preserves
  lexical-error precedence, byte-based spans, numeric suffixes, depth failures,
  raw escapes, Unicode widths, and malformed-UTF-8 behavior.
- Final binaries: **730/730 valid-input comparisons** across five arms, both
  modes, 17 goldens, 50 generated cases, four special inputs, and both benchmark
  sizes. Safe binaries also passed **360/360** golden/error/GC-stress comparisons.
- Additional deterministic malformed-input mutations: **600/600** comparisons
  against the frozen executable (same parser, before final padding-only change).
- Builder snapshot/aliasing, binary data, all padding remainder branches, and
  forced collection pass. Stream tests cover raw NUL/0xff, routing, return counts,
  type/effect rejection, and a real executable writing to `/dev/full`.
- Final padding-only edits passed the 18-step production build/Guardian gate,
  12 focused builder tests including collection stress, 29 printer tests, and the
  final differential gates. The full suite preceded that contained final edit.
- LLVM adapter: **10/10 tests**. `git diff --check` passed.

Raw samples, hashes, paired intervals, diagnostic counters, qualification cases,
and build receipts are in
[`evidence/streaming-20260919`](../../experiments/llvm-backend/evidence/streaming-20260919/README.md).
The previous safe LLVM control uses the old port source at `4919ea9f` rebuilt
with the current compiler/runtime; the prior QBE and arena controls are frozen
executables from the preceding experiment. Their hashes are recorded. Runtime C
remains O2; safe LLVM uses separate O2 units and arena uses the existing compact
whole-module O3 configuration. This measures this Linux/AMD64 machine and these
inputs, not a general language-wide speedup.
