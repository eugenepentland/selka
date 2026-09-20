# Remaining runtime headroom — 2026-09-19

There is substantial remaining representation and loop overhead in the fastest
compact-arena build. Reaching 2× Zig looks credible for census; rendering needs
a larger, coordinated change. This is an engineering judgment, not a measured
promise of an additional speedup. The existing gap is not evidence that all of
it is recoverable through one optimization.

## Distance to the target

Using the final streaming experiment's same-batch wall medians:

| Workload | Current / Zig | Further reduction in mylang wall time needed for 2× |
|---|---:|---:|
| Small census | 2.36× | 15.1% |
| Small render | 3.25× | 38.5% |
| Large census | 2.66× | 24.9% |
| Large render | 3.67× | 45.4% |

These are compact-arena numbers. The ordinary GC builds have a different,
larger gap. In the arena build, collections are already zero. Census still
retires 1.72× Zig's instructions; render retires 3.06×. On large input, IPC is
2.63 versus 3.77 for census and 2.65 versus 3.49 for render. The extra work and
lower throughput both matter. IPC alone does not identify cache misses or prove
that the program is memory-bandwidth-bound.

## Fresh profile after the streaming changes

Recorded 48 executions of each large-input workload for both final compact
mylang and frozen Zig, pinned to CPU 6, with `cycles:u` and period 200,000.
Output went to `/dev/null`. These are sampled self-cycle shares, not new wall
benchmarks or isolated optimization measurements. Inlining affects attribution.
Kernel-labelled/unknown-DSO samples were excluded: 10.7%/9.0% for mylang
census/render and 2.8%/4.2% for Zig census/render. Some libc samples remain
address-only and are not assigned to a specific copy routine.

| Mylang function | Census share | Render share |
|---|---:|---:|
| tokenizer.read_string | 23.8% | 10.9% |
| tokenizer.next_raw | 16.4% | 7.8% |
| parser.parse_node | 8.0% | 3.8% |
| parser.parse_leaf | 7.7% | 3.7% |
| native UTF-8 → scalar text conversion | 7.0% | 3.5% |
| main.tally | 10.3% | — |
| printer.push_node | — | 15.6% |
| native scalar text → UTF-8 conversion | — | 14.5% |
| printer.estimate_width | — | 8.3% |
| native text join | — | 4.7% |

Zig's resolved census samples are concentrated in tokenizer.next (60.5%),
parseNode (24.2%), tally (6.7%), and arena allocation (5.2%). Its renderer writes
byte slices and numeric formatting directly to an allocating writer. It has no
matching whole-output scalar-string join and UTF-8 conversion stage. Shares
between programs have different denominators and cannot be compared as absolute
costs.

## Concrete remaining costs and changes

### 1. Scanner state still travels through memory on every byte

The final `read_string` machine code contains **no function calls**: the tiny
helpers have already been inlined in this arena build. However, its loop still
writes Lexer.pos/col fields, reloads the source and length through that object,
and normalizes potentially negative indices (`sar`, `and`, `add`) before byte
loads. Removing helper calls again is not the answer for this function.

Guest experiment: scan with local source/position/line/column variables and
write the cursor back at the token boundary. Preserve newline and escape rules.
A bulk find-until quote/backslash/newline primitive is a later option.

General compiler improvement: promote nonescaping object fields to scalar
values, preserve immutable-buffer and aliasing facts, and prove nonnegative
index ranges. Existing `mutates(...)` information is not automatically a
no-alias proof. Only proven facts should reach LLVM as such. This can retain
ordinary checked indexing while removing redundant normalization/checks.

### 2. Text is copied and widened when the AST could retain source spans

`tokenizer.materialize` calls `lexeme`, which decodes every consumed spelling to
an owned `str`. The existing compiler already fuses `src[a:b].decode()` into
decode_range, so there is no extra byte-slice copy to remove there. The remaining
allocation, UTF-8 validation, and widening copy are real.

Native text uses a list-shaped header and u32 scalars. Zig's Token/Node use
borrowed byte slices. Mylang's streaming tokens retain source offsets, but the
AST then materializes scalar strings. This leaves the largest representational
difference intact.

Guest experiment: a Document owns the immutable source bytes, and its text
leaves store start/end offsets plus any required cached metadata. Materialize
text only when a consumer requests it. Rendering copies source ranges directly.
This changes the AST representation/API and should be measured as its own arm.

General language/library improvement: immutable byte/UTF-8 views that retain
their owner, plus range-aware parsing/output operations. A view should preserve
the required validation and Unicode scalar-width behavior. Replacing `str`
globally with UTF-8 has indexing/length tradeoffs; it is a broader design change
than adding views.

### 3. Output still builds a full scalar string and then encodes it

The chosen text renderer accumulates `list[str]`, joins it into one scalar-text
object, then encodes it for output. UTF-8 encoding and text join together account
for about 19% of resolved render self cycles. Their removal alone would not
close the 45% large-render target gap, and a replacement still has to write bytes.

The current byte_builder queues chunks and allocates an encoded bytes object
for each appended text. It therefore still makes 367,718 logical allocations
on large render versus the text path's 190,835. It is not yet a contiguous
native writer.

General runtime/library experiment: a growable byte buffer with reserve,
append-byte-range, append-text, and append-number operations that write directly
into its capacity. Numeric width/formatting helpers should avoid constructing
temporary managed strings. Keep immutable finish snapshots. This would benefit
formatters, serializers, protocol writers, and code generators.

Guest application: use that writer and source spans in the printer; compute
formatted numeric spelling or width once when reuse justifies the storage.
Both Zig and mylang perform width estimation, so deleting the width pass would
change behavior rather than establish a fair improvement.

### 4. Generic collection operations and aggregate copies remain

The final printer still calls list get/append wrappers and recursive helpers.
Some reads are already emitted inline, but the managed buffer-operation read
path calls a generic runtime routine. That routine loads element size from a
descriptor and copies through an output pointer. The runtime C object is not
part of the whole-guest LLVM optimization unit.

Compiler experiment: specialize known-element list loops and reserved-capacity
append paths; eliminate aggregate temporaries and copies when values do not
escape; preserve value semantics and mutation behavior. The 83-unit guest module
already permits O3 inlining, so a blanket "turn on inlining" recommendation is
insufficient. Runtime LTO is an experiment, not an assumed win.

Guest experiment: compact internal tokens, avoiding redundant start/end/offset
fields; use a flat node pool and child ranges if profiling demonstrates that
recursive list storage matters. Keep these separate from source-span changes so
the gains can be attributed. Zig already stores nodes by value too; being a
tagged union is not intrinsically the problem.

LLVM's [frontend performance guidance](https://llvm.org/docs/Frontend/PerformanceTips.html)
supports scalar field operations, entry-block allocation promotion, and
preserving pointer/alias information. It does not provide a percentage gain for
this program.

## Suggested order and confidence

1. Local scanner state: small guest change, directly supported by the hottest
   loop's assembly; establish how much of this can then be generalized in lowering.
2. A real native byte writer: reusable runtime change with a clear allocation and
   conversion target; compare against both current renderers.
3. Source-backed AST leaves: larger guest/API change, likely necessary to approach
   Zig's work and memory use; a useful proving case for general safe views.
4. Typed collection/aggregate lowering: general compiler work, guided by remaining
   assembly and counters after the above changes.

My expectation is meaningful gains measured in tens of percent from coordinated
changes, not a reliable numeric forecast for any one item. Census's required
15–25% reduction appears attainable. Render's 39–45% is ambitious and likely
requires several of these changes together. Gains overlap and must not be added.
The current evidence does not establish a QBE/LLVM or language-design ceiling.

No production code was changed for this audit, and no Guardian gate was run.
Profile commands, binary hashes, raw tables, summary, and three disassemblies
are saved with the prefix `headroom-` under
[`streaming evidence`](../../experiments/llvm-backend/evidence/streaming-20260919/README.md).
