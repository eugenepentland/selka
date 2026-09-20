# Runtime headroom, second pass — 2026-09-20

This closes the four items of
[`remaining-runtime-headroom-2026-09-19.md`](remaining-runtime-headroom-2026-09-19.md)
and measures what they bought on the compact-arena build. Headline: **25–30% of
retired instructions and 12–22% of wall time removed from every workload**, the
census gap to Zig closed from 1.70× to 1.19× on instructions, and the render gap
closed from 3.03× to 2.24×. Census's instruction target is effectively met;
rendering is still memory-bound and is the remaining work.

Everything is measured on the rig the previous audit used:
`.tmp/runtime-audit-20260919/input.sexp` (927 KB, "small") and `input8.sexp`
(7.42 MB, "large"), the compact-arena `compact-o3` arm built by
`.tmp/bench/rebuild.sh` from the current tree, Zig's frozen `before/zig` as the
reference, `/tmp/ab2.py` or `perf stat -e cpu_core/instructions/u` pinned to
CPU 6. Instruction counts are load-independent and are the reliable signal;
wall times are the minimum or median of interleaved rounds on a machine that was
shared with three other build agents for most of this work and are advisory.

## What each item became

### 1. Scanner state in local variables — landed, guest application

`experiments/sexpr-port/sexpr/tokenizer.my` copies `src`/`length`/`pos`/`line`/
`col` into locals for the whole scan and writes them back once per token through
a single `store_cursor`. The per-byte mutating `advance`/`peek_at` are gone; the
`Lexer` type, the public API and every `RawToken`/`SpanToken` field are
unchanged. A second pass then made the scans advance in runs: `read_string`
bumps the column once per run of ordinary characters rather than once per byte,
and the atom/number readers scan with a local position instead of re-reading the
object.

Effect, isolated in two builds that differ only in `tokenizer.my`: −13.7%
retired instructions on the frozen tree, −16.1% on the combined tree, and −7%
to −7.6% census wall time on the large input. The differential harness (7,868
inputs, old tokenizer vs new in one process, every field of every token plus the
cursor after every call) found 0 mismatches. The run-based pass then took the
large census from 197.7 M to 189.3 M instructions.

The general compiler improvement the audit asked for — promoting object fields
to scalars automatically — was **not** needed and was not attempted. The guest
change captured the win.

### 2. AST text as views into the source — landed, representation and API

A new `sexpr/view.my` holds `View { source: bytes, start: int, end: int }`, a
byte range of an immutable source buffer with no copy. `Node.atom`,
`Node.string` and `decimal.literal` carry a `View` instead of an owned `str`,
which is what Zig's `Node` does with `[]const u8`. Building a node allocates
nothing and widens nothing; `view.matches` compares a range against a fixed word
by decoding only that word; `view.text_of` is the single conversion to scalars
and reports invalid UTF-8 instead of substituting.

The parser no longer calls `tk.materialize` at all: `read_string` decodes only
the spellings `int`/`float` must see, and `parse_si` decides the SI multiplier by
scanning raw bytes. The printer writes a leaf's source range straight into its
output buffer, so an atom's spelling is never widened to Unicode scalars and
encoded back. This removes the two profiled stages outright — `native UTF-8 →
scalar text conversion` (7.0% of census cycles) and, with item 3, `native scalar
text → UTF-8 conversion` (14.5% of render) and `native text join` (4.7%).

### 3. A native growable byte writer — landed, runtime, compiler and library

`src/native_bytes.c` carries a mutable one-byte-stride buffer with
`myl_native_bytes_buffer_reserve`, `_append_byte`, `_append_range`,
`_append_utf8` and `_append_int`. `src/buffer_operations.zig` gained the matching
kinds on a `bytes` receiver, `src/sema.zig` and `src/bytecode.zig` accept them,
`src/qbe_bytes.zig` lowers each to exactly one runtime call, and
`src/stdlib/byte_builder.my` is a thin wrapper whose `Builder` is that buffer.
`append_range` is reserve-once plus one `memcpy`; `append_utf8` measures and
writes straight into capacity; `append_int` formats into a 20-byte C stack
buffer; `finish` is one allocation and one copy.

The first attempt at this item — a contiguous `list[int]` buffer written from
guest code — was measured and **rejected**: a `list[int]` has eight-byte
elements, so a byte range can only be appended by a per-octet guest loop, and
that loop alone cost 1,166 M instructions on the large render workload, twice
the arm it replaced. The one-byte-stride receiver with a bulk runtime entry
point is the shape that works, and an A/B with frozen guest sources measured it
at 0.47× the render wall time of the chunk builder it replaced (non-rendering
controls at 1.005×/1.013×).

`main.my --render` also stopped routing the rendered document through
`out.print`: it writes `printer.render_bytes(nodes)` and the terminating newline
with `out.write`, removing a full decode of the output and a full re-encode of
it. Verified byte-identical on all 17 goldens by a two-arm comparison that
differs only in that branch.

### 4. Collection calls and aggregate copies — landed, compiler, measured neutral

`src/qbe_managed.zig` now lowers a read of a **scalar** collection element to one
unsigned bounds check plus `storage + index * stride` and a width-correct load,
instead of `call $myl_native_list_get` plus an aggregate scratch round trip.
Records, unions, arrays, nested collections, `str`-as-element and dictionaries
keep the old path exactly, and the trap is byte-identical (`w[-1]`,
`w[-len(w)]`, `w[len(w)]` and `w[-len(w)-1]` all behave and report as before).

Measured honestly: **no measurable change on this workload** (−0.03% census8,
+0.009% render8 instructions in a controlled A/B; wall ratios 0.97–1.02 across
two runs). Only 2 of the workload's 13 `myl_native_list_get` sites are scalar
reads, and a measured what-if that inlines all 13 is worth −1.99%/−0.77%
instructions. The change is kept because it is correct, narrower and removes a
cross-translation-unit call from every scalar read; it is not where this
workload's remaining time is.

## Measured result

Final numbers, quiet machine, from `.tmp/bench/findanyused`, built from a tree
that had stopped moving. `frozen` is the post-audit compact-arena arm; `prev` is
the tree as it stood before this round's `find_any` work; `zig` is the frozen
reference.

Retired instructions, millions:

| Workload | frozen | prev | now | now/frozen | Zig | now/Zig |
|---|---:|---:|---:|---:|---:|---:|
| Census 927 KB | 33.66 | 22.35 | 21.73 | 0.646 | 21.48 | **1.01×** |
| Render 927 KB | 69.85 | 50.60 | 50.24 | 0.719 | 22.92 | 2.19× |
| Census 7.42 MB | 268.25 | 176.20 | 160.93 | **0.600** | 155.19 | **1.04×** |
| Render 7.42 MB | 558.05 | 402.23 | 386.96 | 0.693 | 181.78 | 2.13× |

Cycles, millions, and IPC:

| Workload | frozen cyc | now cyc | now IPC | Zig IPC |
|---|---:|---:|---:|---:|
| Census 927 KB | 18.97 | 9.67 | 2.25 | 3.74 |
| Render 927 KB | 36.13 | 20.30 | 2.47 | 3.41 |
| Census 7.42 MB | 141.44 | 69.48 | 2.32 | 3.69 |
| Render 7.42 MB | 287.66 | 152.06 | 2.54 | 3.39 |

Wall time, milliseconds, minima and medians of 21 interleaved rounds:

| Workload | frozen | now | Zig | now/Zig | frozen→now |
|---|---:|---:|---:|---:|---:|
| Census 927 KB | 4.71 | 3.39 | 2.27 | 1.49× | −28% |
| Render 927 KB | 8.19 | 6.86 | 2.87 | 2.39× | −16% |
| Census 7.42 MB | 35.87 | 23.18 | 14.39 | 1.61× | −35% |
| Render 7.42 MB | 68.23 | 54.71 | 18.08 | 2.87× | −20% |

**Census now retires essentially Zig's instruction count and is still 1.6× its
wall time.** The remaining census gap is entirely throughput: IPC 2.32 against
3.69. That is the single most useful fact in this document, and it says the next
census work has to be about how instructions retire (dependency chains, spills,
loop shape), not about how many there are.

The previous audit's distance-to-2× table, restated:

| Workload | was | now |
|---|---:|---:|
| Small census | 2.36× | 1.49× |
| Large census | 2.66× | 1.61× |
| Small render | 3.25× | 2.39× |
| Large render | 3.67× | 2.87× |

## This round: an offset-taking byte search, and one rejected experiment

**`bytes.find_any(values, start) -> int`** — the primitive the tokenizer was
missing: the index of the first octet at or after `start` that occurs anywhere in
`values`, or -1. One octet in `values` uses `memchr`; otherwise a 256-bit
membership word in one cache line. `myl_native_bytes_find` and its `str`
counterpart also became `memchr`/`memmem`, replacing a `memcmp` per position.

The isolated numbers are what justify it: scanning a 4 MB body for `"` or
newline costs 27.0 instructions per byte as a guest comparison loop, 8.99 through
the bitmap path, and 0.094 through `memchr` for a one-octet set. Wiring it into
the port's two run scans — the string body and the comment tail — took the large
census from 176.2 M to 160.9 M instructions (−8.7%) and the large render from
402.2 M to 387.0 M (−3.8%), and dropped `read_string` from 27% of census cycles
to 3.6%. The scan itself is now the top entry at 16.8%, which is the sign that
the per-byte guest loop is gone.

**A rejected experiment, recorded so it is not retried:** memoizing the printer's
width estimate. `estimate_width` is called once per node per ancestor that
measures it, so it looks quadratic and a pre-order memo looks free. Built and
measured, it made things worse — the layout estimate went from 8.4% to 9.8% of
render cycles and a new `root_push` cost appeared, for a net instruction
increase. Reverted; `printer.my` is byte-identical to before the attempt. The
walk is shallow in practice because a list over the width limit stops measuring.

**A refused compiler change, also recorded:** the frontend normalizes a negative
index by rebinding the slot, and `src/qbe_managed.zig` then re-guards it with
`index + (index >> 63 & length)`. That looked like three dead instructions per
access. It is dead only for `list[T]` reads, which already have no guard; for
`bytes[i]` and `str[i]` the operand is the caller's raw index, and removing the
guard makes `b[-1]` trap. Built, measured, proven to break `python_bytes.my`, and
reverted — with a new regression test that pins negative indexing for lists, byte
strings and text, because no existing `str` test read a negative index and the
break would otherwise have shipped silently.

## The measurement that settles the next step

Counters on the large inputs, quiet machine, `cpu_core` PMU:

| Workload | binary | instructions | cycles | IPC | L1 miss | LLC load misses |
|---|---|---:|---:|---:|---:|---:|
| census | mylang | 179.7 M | 70.3 M | 2.65 | 196,948 | 42,262 |
| census | Zig | 159.1 M | 49.9 M | 3.79 | 39,504 | 4,311 |
| render | mylang | 404.8 M | 153.1 M | 2.69 | 313,108 | 96,756 |
| render | Zig | 185.3 M | 53.8 M | 3.47 | 87,965 | 10,428 |

Census retires 1.13× Zig's instructions but takes 1.41× its cycles: **the work is
nearly matched and the throughput is not**. Nine to ten times the last-level
misses, at 2.5–3.6× the L1 miss rate. Splitting the 70.3 M cycles by that ratio,
about 15 M are the extra instructions and about 25 M are the throughput penalty.

This is the compact-**arena** build, so no collector is walking the heap and
allocation is a bump pointer — the misses are not allocator bookkeeping. They are
the representation: a form is a heap `list[Node]` object plus a separate backing
array, so a 48-byte node lives in one place, its children in another, and each
form costs two pointers and two cache lines to reach. The AST is roughly 60 MB
against a 24 MiB L3, so it does not fit and every traversal re-fetches it.

The consequence for the plan below: another instruction-count change cannot close
this. A 15% instruction reduction moved wall time by well under 15% in this
round's own numbers (34% fewer instructions bought 16–21% less wall time on
render), and the parser's remaining instructions are cheap ones. The next
substantial win has to reduce the number of distinct memory objects the parser
creates per form, or the size of a node, or both.

## Aggregate parameters now cross by address

The throughput finding above had a direct fix, and it landed: **read-only
aggregate parameters cross as the address of the caller's storage** instead of a
private copy (`[QBE-AGGREF-1]`). The ABI follows from the parameter type alone, so
direct calls, callbacks, host wrappers and exports cannot disagree; move-only
layouts and any parameter the body writes, moves, drops or binds a match payload
into keep the old by-value copy, and a type that releases something keeps its
entry copy so ownership and cleanup are unchanged. A second, narrower rule names
an ordinary local by its own slot when the very next instruction alone consumes
it, instead of copying it into an aggregate scratch.

Static blits across the port's 97 units: **445 → 209**. Parameter-entry blits
(`blit %aN, %lM`): **40 → 0**.

| function | blits before | after |
|---|---:|---:|
| `sexpr.parser::parse_leaf` | 41 (64 B: 21) | 20 (64 B: 2) |
| `sexpr.parser::parse_node` | 49 (64 B: 14) | 37 (64 B: 2) |
| `sexpr.printer::push_node` | 23 | 10 |
| `sexpr.ast::span_of` | 26 | 12 |
| `main::tally` | 12 | 6 |

```
parse_leaf BEFORE                      AFTER
 storel %a0, %l0                        storel %a0, %l0
 blit %a1, %l1, 64                      storel %a1, %l1
 blit %l1, %agg0, 64                    %v18 =l loadl %l1
 storel %agg0, %s0                      storel %v18, %s0
```

Effect on the large inputs, interleaved paired rounds (the machine was shared, so
these are paired medians, not absolutes):

| Workload | instructions | cycles | wall, base/new |
|---|---:|---:|---:|
| Census 7.42 MB | −0.9% | −8.6% | 1.074× |
| Render 7.42 MB | −1.9% | −10.0% | 1.040× |

**About 1% of instructions bought 9–10% of cycles.** That is the throughput gap
this document identified, confirmed by fixing it: the copies were never about
instruction count. The `wv`/`wi` probe moves the same way (−4.0% instructions,
−4.6% cycles at depth 8, against an identical-binary control that reads 100.03%),
and its per-node cost falls from 779.4 to 747.2 instructions.

Value semantics are pinned by nine guest tests (`tests/lang/aggregate_refs.my`,
tag `QBE-AGGREF-1`) covering a written parameter, a written field inside a callee,
returned-then-stored, returned-then-passed-on, a record read out of a list
argument while the callee appends to that list, records from instantiated generic
bodies, a match payload bound from a record local, a returned union payload, and a
returning path beside a trapping one — all asserting the caller's value is
untouched, run normally and under `--gc-stress`. A probe prints byte-identical
output from the base and new compilers in both modes. Five Zig IL tests pin the
shapes, including that `Result[TextFile, str]` keeps its entry copy and its drop.

**Return-slot forwarding was priced and not taken.** The parse path consumes its
`Result` through `match`/`?`, which reads tag and payload straight through the
returned pointer, so there is no return copy there to remove. Forwarding only
pays at call sites that immediately store a result or write it as a union payload
— about 30 of the 445 blits — and it requires moving the return ABI to an
out-pointer across every callee, callback, host wrapper and export before a
destination can even be named. The parameter path owned 147 of the 445.

## What is left

The two workloads now have different bottlenecks, and neither is instruction
count.

**Census: throughput.** It retires 1.04× Zig's instructions and takes 1.61× the
wall time, at IPC 2.32 against 3.69. Nothing about the instruction mix explains a
gap that size — the profile is flat now, spread over `find_any` (16.8%),
`next_raw` (11.4%), `parse_node` (11.1%), `tally` (9.0%), `parser::advance`
(5.7%). The next investigation is why the emitted code retires instructions at
half Zig's rate: dependency chains through the per-node value copies (a `Node` is
a 48–64 byte union passed by value through every recursive parse and tally call,
where Zig passes a pointer), the stack traffic those copies imply, and the
per-access index guard discussed above. A `perf` cycle-frontend breakdown of the
top three functions, or a counter run with the copies removed from a probe,
would settle which.

**Render: instructions and calls.** 386.96 M against Zig's 181.78 M, still 2.13×,
and 2.87× wall. Of the 205 M instruction difference, roughly 161 M is parse work
that render shares with census — so the render-only excess is about 45 M. The
profile says it is the per-fragment appends and the recursive `push_node`
(18.5% of cycles before this round's changes). Batching the fixed punctuation
into one append per child, and streaming through a bounded buffer instead of
materialising 5.6 MB and copying it again into the `finish` snapshot, is the
available work; neither needs new language surface.

## The throughput finding, pinned down

Three measurements say the same thing, so this is where the next round starts.

**1. The gap is throughput.** Census now retires 1.04× Zig's instructions and
takes 1.61× its wall time: IPC 2.32 against 3.69.

**2. Aggregate copies cause it.** `.tmp/bench/probe/wv.my` and `wi.my` build the
same tree with the same node shape and walk it two ways — one takes the union by
value through the recursion, the other walks a `list[Node]`. The by-value walk is
**2.5% more instructions and 22% more cycles**: 937.7 instructions/node at IPC
1.95 against 915.0 at IPC 2.43. Copying aggregates costs throughput out of all
proportion to the instruction it adds.

**3. The parse path is full of them.** From the IL of the current benchmark arm:

| function | blits | sizes |
|---|---:|---|
| `sexpr.parser::parse_node` | 49 | 18×72 (match payload), 14×64 (`Result`), 14×32, 2×24 |
| `sexpr.parser::parse_leaf` | 41 | 21×64 (`Result`), 11×24, 5×32, 3×72 |
| `sexpr.printer::push_node` | 23 | 8×32, 6×24, 4×48, 3×64 |
| `sexpr.printer::estimate_width` | 23 | 8×32, 6×24, 4×48, 3×64 |

`Result[Node, ParseError]` is 64 bytes, `Node` is 56, and a match payload is 72.
Every recursive parse return crosses a local slot, and every aggregate parameter
is copied twice — once at entry and again where it is used:

```
 storel %a0, %l0
 blit %a1, %l1, 64        # the whole 64-byte RawToken parameter, at entry
 ...
 blit %l1, %agg7, 64      # and again where it is read
```

Zig's `Token`/`Node` are passed as pointers and returned through an out-pointer
slot the callee writes directly, so it pays neither. That is the concrete shape
of the remaining census gap, and it is a compiler change, not a guest one: a
return-slot forward (let a callee write its aggregate result straight into the
caller's destination) plus read-only aggregate parameters passed by reference.

**Both: the representation.** The AST is roughly 60 MB against a 24 MiB L3, and
each form is a heap list object plus a separate backing array. That is real, but
the counters say it is not the dominant term: L1 misses are 36% of references
against Zig's 15%, yet at ~200 K L1 misses and ~42 K LLC misses over 70 M cycles
the memory stalls account for well under 10% of cycles. Fix this if it is cheap,
but do not expect it to close a 1.6× wall gap on its own.

## Verification

- Guest: `mylang test experiments/sexpr-port` 103 passed / 0 failed across 8
  programs; `compare.py` 4/4 fixtures agree with the independent Python reader;
  `golden_compare.py` 17/17 byte-identical against the real Zig printer.
- Gate: `zig build test --summary all` green, `zig build test-qbe` green,
  `zig build test-qbe-build` green, `zig build fmt-check` clean,
  `mylang doc-coverage .` 0 failures, `mylang doctest .` 597 blocks with
  0 failed. Two tests (`generic_concrete_test` process-spawn errno,
  `io_files_test` temp-dir errno, and a `semantic_cache_test` allocation-rollback
  count) failed only while three agents ran gates concurrently and pass in
  isolation; they are environment contention, not regressions.
- The byte writer was verified independently of its author: 52 contract checks
  through the module API plus 23 direct-surface checks, each under plain,
  `--gc-stress`, `--max-memory=32M` and both together, plus a 1 TiB reservation
  attack that traps `R_MEMORY_BUDGET` cleanly. Evidence and a re-runnable script
  are under `.tmp/bench/verify-bytewriter/`.

## Evidence

- Arms and raw counter runs: `.tmp/bench/{baseline,sourceast,final1,bulkscan,...}/`
  with measurement JSON beside each arm; the table above is
  `.tmp/bench/final-counters.json`.
- Harness: `.tmp/bench/rebuild.sh` builds one arm from the current tree in about
  25 s and drops the formatter object the compiler now publishes into the guest
  object directory; `.tmp/bench/measure.sh` runs the four paired workloads;
  `/tmp/ab2.py` reports `cpu_core` instruction and cycle counts.
