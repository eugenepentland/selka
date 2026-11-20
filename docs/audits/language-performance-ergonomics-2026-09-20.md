# Making fast parser code easier to write — 2026-09-20

The strongest language additions are **owner-retaining byte views and a distinct
mutable byte buffer**, backed by operations that compare, parse, measure and write
without constructing temporary strings. The strongest compiler work is eliminating
aggregate copies while preserving ordinary value semantics. Most of this needs
better types, library operations and lowering; it does not need a new loop syntax
or a keyword that disables checks.

This audit covers the S-expression reader used by the schematic tooling:
`experiments/sexpr-port`, its vendored Zig reference, recent runtime experiments,
and the relevant language/runtime implementation. The timed workloads read, parse
and then either count nodes or render canonical S-expressions. They do not measure
the entire schematic layout, electrical analysis or SVG pipeline.

Evidence and executable/source identities are retained in
[language-performance-audit-20260920](../../experiments/language-performance-audit-20260920/README.md).
The checkout had extensive existing changes. This audit added this report and
evidence files; it did not implement the recommendations.

**What the comparisons establish.**

Fresh checked-QBE measurements and the concurrently updated compiler comparison
are recorded in the evidence directory. Both use a frozen copy of the same guest
source, the existing Zig ReleaseFast executable, 927,415-byte and 7,419,320-byte
inputs, CPU 6, and 21 randomized interleaved rounds after three warmups. Timed
output goes to `/dev/null`; status/stderr are checked on every run and output bytes
before and after timing. These are process wall times on a shared machine, with
paired bootstrap intervals, not isolated parser-kernel timings. Neither this
audit's initial nor follow-up build disabled mylang's ordinary safety checks.

The final matched batch compared the initial compiler and the captured compiler
with the concurrent aggregate-parameter change:

| Workload | Initial QBE ms | Updated QBE ms | Zig ms | Updated QBE / Zig, 95% interval |
|---|---:|---:|---:|---:|
| Census, 927 KB | 5.28 | 5.31 | 2.03 | 2.61× [2.47, 2.71] |
| Render, 927 KB | 11.75 | 11.23 | 2.62 | 4.30× [4.20, 4.38] |
| Census, 7.42 MB | 42.51 | 41.45 | 14.06 | 2.95× [2.91, 2.97] |
| Render, 7.42 MB | 99.53 | 96.80 | 17.91 | 5.40× [5.38, 5.44] |

The updated build reduced large census time by approximately **2.5%**, small
render by **4.4%**, and large render by **2.7%**. Small census had no resolved
improvement. This is a useful measured gain from existing source syntax, but it
does not support attributing the whole performance gap to parameter copies.
It compares the two captured compiler builds, not a fully isolated source-patch
ablation. The preceding two-arm batch had much higher absolute times on this
shared machine; its raw samples are retained separately and are not pooled here.

The earlier compact-arena experiment is a separate configuration: experimental
LLVM, whole-module optimization, no collecting GC and deliberately removed
checks. Recomputing **medians** from its saved `findanyused-*.json` gives:

| Historical compact-arena workload | mylang ms | Zig ms | mylang / Zig |
|---|---:|---:|---:|
| Census, 927 KB | 3.627 | 2.403 | 1.509× |
| Render, 927 KB | 7.163 | 3.017 | 2.374× |
| Census, 7.42 MB | 23.693 | 14.594 | 1.623× |
| Render, 7.42 MB | 55.099 | 18.471 | 2.983× |

Do not compare those absolute times against a later batch to estimate a compiler
speedup. The second-pass report's headline wall table uses minima, despite
discussing both minima and medians. Its large-render 2.87× also does not follow
from its displayed minima (54.71 / 18.08 is approximately 3.03). The medians above
leave **33.0%** of large-render time to remove to reach 2× in that configuration.
The old files sort each arm's samples, so original paired round order is lost.

Another correction matters for prioritization: the saved instruction totals are
386.96 M versus 181.78 M for large render, a 205.18 M difference. Census is
160.93 M versus 155.19 M, a difference of only 5.74 M. Subtracting census from
render on both sides gives an incremental-work difference of **199.45 M**, not
the roughly 45 M claimed in the second-pass report. Census includes a tree tally
that render omits, so this subtraction is a comparison of whole workloads,
not an isolated measurement of printing. It still strongly favors investigating
rendering. IPC and cache-miss counts alone do not establish that memory stalls
or aggregate copies explain the entire remaining gap.

**1. Make byte views a standard type with a complete nonallocating API.**

The port manually implements `View { source, start, end }` in
[view.my](../../experiments/sexpr-port/sexpr/view.my). Retaining source offsets has
already avoided materializing ordinary AST text, but routine operations fall
back to allocation:

- `matches` calls `text_of`, decoding the viewed bytes into `str` before comparing.
  Its comment says comparison needs no decoded string; the implementation does.
- `equal` slices both sources through `bytes_of`, creating two byte strings.
  Its identity-oriented comment also disagrees with its content equality and test.
- `printer.estimate_width` decodes atoms and strings just to call `len`;
  `literal_width` does the same for numeric spellings.
- `parser.parse_si` copies a byte range, decodes the number, then decodes a
  one-byte suffix. Other numeric leaves decode before `int`/`float` parsing.

Fresh `noalloc` probes against the actual view module reject both `matches` and
`equal` with `E_EFFECT_BOUND`, naming the corresponding decoding/slicing paths.
These hidden allocations are confirmed; their individual wall-time contribution
has not been isolated in this audit. `matches` is particularly relevant to later
schematic consumers that inspect form names, even if it is not hot in census.

Proposed surface, **not currently implemented**:

```text
token = source.view(start, end)       # ByteView; retains its source owner
if token == b"net":                   # compare the range directly
    ...
number = token.parse_float()          # Option[float], no intermediate str
width = token.scalar_count()          # Result[int, ...], validates UTF-8
byte_builder.append_view(output, token)
```

Start with `ByteView`, not a generic borrowing language. Specify bounds once at
construction, retain the owner for GC, and implement slicing, equality, search,
numeric parsing and output against the range. Keep `bytes[a:b]` copying as today;
an explicit `.view(a, b)` makes the different retention/copy behavior visible.
Views of a large document retain that document, so provide an explicit owned-copy
operation for small values that must outlive it. A validated UTF-8 view can follow
if repeated validation is measurably costly; arbitrary byte slicing must not
silently inherit UTF-8 boundary validity.

Preserve scalar-counting semantics where the mylang printer already tests them.
The Zig printer uses byte lengths; its Unicode layout is therefore not a universal
oracle for this operation. Count UTF-8 scalars without allocating, with an ASCII
fast path and explicit invalid-input behavior. Do not replace `len(str)` with
byte length. Numeric range parsing must retain full-consumption, overflow,
floating-point and suffix behavior.

**2. Give mutable bytes their own type, then simplify output around it.**

The native byte builder is already a useful general improvement. The previous
attempt to store bytes in `list[int]` was rejected because it used eight-byte
elements and per-byte guest loops. Keep the one-byte storage and bulk append path.

Today [byte_builder.Builder](../../src/stdlib/byte_builder.my) stores an ordinary
`bytes`. Heap `bytes` accepts mutating append methods, but literals of the same
type refuse them. The audit's alias probe obtains `snapshot = finish(builder)`,
aliases it, then appends through that alias. It prints `True 2 True False`:
the heap snapshot becomes `b"ab"`, while appending to literal `b"a"` is refused.
`finish` successfully separates storage from the original builder; the returned
type does not itself enforce immutability.

Introduce a distinct `ByteBuffer` or `bytearray` type, leaving `bytes` immutable.
Put append/reserve operations only on the mutable type. This makes source-view
invariants and stable length/content substantially easier to reason about. It
also eliminates the need for an append operation to discover at runtime whether
its receiver happens to be a literal. Mutation through an alias must remain
explicit in the type/effect contract.

Build these operations on that boundary:

- A capacity-sufficient append fast path before rooting/growth machinery.
  `buffer_grow_rooted` currently pushes roots before testing capacity in
  `buffer_grow`.
- Direct float formatting and numeric width calculation. `append_float` currently
  constructs `str`, encodes it to `bytes`, then appends; integer output already has
  a direct path. Preserve the exact established float spelling.
- `write_to(Stream)` to synchronously write existing buffer storage without the
  final snapshot copy. Retain copying `finish` semantics. Do not claim that
  removing one 5.6 MB output copy alone closes the measured gap.
- A bounded buffered writer if large-output measurements justify it. Flush in
  bulk: the current stream write path flushes each call, so per-token writes are
  not a substitute for buffering.

A later convenience could lower `writer.write(f"{value}mm")` directly into the
writer, avoiding a temporary formatted string. This is a **proposed sink-aware
formatting operation**, not existing syntax with an automatic performance
guarantee. First provide and measure direct formatting primitives; preserve
left-to-right evaluation and error behavior before adding interpolation fusion.
Zero-copy `finish` would require consuming/invalidating the buffer or a proven
unique owner; ordinary freely shared aliases do not supply that proof.

The prior [next-steps review](runtime-next-steps-review-2026-09-20.md) also reproduced
a compact-arena bug: `buffer_frozen` reads an object header that headerless compact
allocations do not have. The same header read remains in the inspected
`native_bytes.c`. This is a prerequisite for trusting that experimental allocator
with the new writer; it is not a reason to replace the normal checked baseline
with its faster numbers. This audit did not rerun that C reproducer.

**3. Finish aggregate optimization in the compiler; retain simple value syntax.**

Initial probes confirmed two full 64-byte IR copies for `return record.a` and
two full 512-byte copies for `return array[0]`. Passing this IR through the bundled
QBE optimizer left one full record copy and both array copies in assembly.
These are independently compiled functions; inlining can remove costs in some
callers. `noalloc` accepted both, correctly: it excludes managed allocations,
not stack copies.

During the audit, a concurrent change introduced `parameterAddresses`,
`byReference` and `argumentType` in `src/qbe.zig`, with a rebuilt compiler. I froze
that executable separately and repeated the probes. Both simple parameter-read
probes then emitted **zero `blit`s**. This part of the recommendation is already
being implemented in the working tree and should not be presented as missing
language syntax.

The parser still has material work after that change:

| Function | Initial static IR copies | After parameter change |
|---|---:|---:|
| `parse_leaf` | 41 | 23 |
| `parse_node` | 49 | 49 |
| `estimate_width` | 23 | 21 |
| `push_node` | 23 | 21 |

These count copy sites across all branches, not copies executed per node. They
identify investigation targets, not a measured speedup or proof of the dominant
stall source. Inspect optimized machine code and measure each lowering change.
The initial ABI declarations show `Node` at **72 bytes**, `Result[Node, ParseError]`
at **80 bytes**, and `RawToken` at 64 bytes; the second-pass report's 56-byte Node
and 64-byte Result do not describe this inspected source.

Next remove unnecessary local snapshots, forward result destinations through
constructors, `return` and `?`, and project match fields without copying entire
payload records when safe. The compiler already has indirect-result machinery;
the task is forwarding/eliminating intermediates, not introducing indirect
returns as a wholly new concept.

Preserve record/list snapshot semantics, argument evaluation order, alias-visible
mutation, GC roots, resource drops, callbacks and ABI/cache compatibility.
A read-only parameter does not by itself mean the entire reachable object graph
is immutable or unaliased. Avoid requiring `ref`, `borrow` or `move` at every
recursive call before exhausting compiler-proven optimizations. Turning every
record into a `class` would change aliasing and add heap objects.

**4. Make compact read-only trees easy, after measuring simpler changes.**

Parsed forms retain growable `list[Node]` objects even though rendering only reads
them. A frozen sequence/builder API could eventually provide stable contiguous
storage, fewer mutable headers, and stronger facts for iteration. A flat node
array with child ranges is an application experiment that can test this value
before adding a general language feature. It must preserve traversal order,
spans, public AST use cases and malformed-input behavior.

Also test narrower source metadata using **existing** integer types. Mylang's
Span uses three 64-bit `int`s; Zig uses three `u32`s. Mylang already gives `u32`
four-byte native storage, so no new packed-record syntax is needed to try this.
Use checked conversion and an explicit maximum document/position range. A more
compact span may reduce union stride and copied bytes; the exact resulting layout
and speedup need a measurement, not a packing assumption.

Keep a bump-allocated document/region mode as a separate experiment. Existing
`with arena()` still uses ordinary managed allocations and GC; it does not select
the experimental headerless allocator. A safe faster region needs a coherent
escape, ownership, rooting, budget and bulk-release contract. Avoid making users
disable bounds/overflow checks to obtain allocation locality.

**5. Use existing contracts to keep simple code fast.**

`noalloc`, `mutates(...)`, `bytes.find_any` and native byte building already exist.
Use `noalloc` as an acceptance condition for view comparison/counting/parsing
operations. It catches the exact hidden-allocation regressions found here.
Retain its current meaning; it is not a promise of zero copies or zero CPU cost.

Add a cost/explanation report alongside ordinary compiler diagnostics: inferred
allocation sites and their call chains, aggregate sizes/copy sites, and why a
checked index or root could not be removed. Report static facts separately from
profiled counts. This would make performance discoverable without forcing users
to inspect emitted IR or learn a second programming style.

For loops, keep optimizing existing `for`/`while` code: scalarize provably safe
cursor fields, propagate index ranges, and remove repeated checks only when
mutation/alias facts permit it. `find_any` is already used by the tokenizer;
constant delimiter specialization or a faster native multi-delimiter scan is
runtime/compiler work to measure later. The earlier scanner-local-variable change
already captured a useful guest-level win. New SIMD, single-assignment or
unchecked-block syntax is not justified by this parser evidence.

**Implementation order and acceptance.**

First finish qualification of the concurrent aggregate change, and fix the
compact-writer header incompatibility before further compact-arena claims.
For the next feature slice, establish immutable `bytes` versus mutable buffer
storage, add `ByteView` plus nonallocating operations, and migrate the printer's
width calculation and parser's numeric ranges. Benchmark direct float formatting
and writer fast paths independently, then tackle destination forwarding and
compact AST storage using the measured remaining profile.

Keep checked QBE and checked LLVM results separate from experimental unchecked
arms. Use identical frozen guest sources, exact output/error checks, raw unsorted
rounds, binary/toolchain/input hashes and an isolated comparison per change.
Add representative independent schematics, Unicode near the line-width boundary,
escape-heavy strings and deeper nesting: repeating one board tests scaling but
does not establish a general language-wide speed ratio. New views/writers need
GC-stress, alias/growth, invalid UTF-8, numeric boundaries and low-memory coverage;
aggregate lowering additionally needs value-snapshot and ABI regression coverage.

The parser suite passed **114/114** tests across eight programs with both captured
compiler versions. Both versions also matched **17/17** retained Zig printer
goldens, and the final benchmark checked all four full outputs against Zig.
This is focused audit validation, not a full compiler qualification. No Guardian
gate was exercised: the audit used already-built compilers and direct guest/QBE
commands, not `zig build`.
