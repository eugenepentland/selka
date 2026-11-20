# Closing the remaining full SVG performance gap

The measured priorities are bulk host I/O, better record reads and field
projection, and cheaper instruction-budget accounting. Real arenas do not
materially improve this single-render workload: it makes 134 managed allocations
and performs no normal collection. The earlier improvements were substantial,
but neither the production build nor the audit prototypes have reached native
performance parity.

This audit used three Sol agents for host/runtime, compiler, and algorithm
investigations, followed by coordinated qualification and measurement. It adds
experiments and documentation only. No production compiler, runtime, schematic
guest, or EDA source was changed by this audit.

## Current gap and demonstrated progress

These are fresh-process medians from one randomized, interleaved batch on CPU 6.
They include input reads, parsing, model construction, placement, routing, the
complete SVG file write, and shutdown. Mylang uses LLVM O3 plus LTO. “Tool limits”
retains instruction-step and call-depth accounting with a 100-million-step
budget. Ordinary language checks remain in the unaccounted build.

| Implementation | Original circuit, ms | Changed net, ms | Changed value, ms |
|---|---:|---:|---:|
| Zig direct port, ReleaseFast | 1.434 | 1.478 | 1.453 |
| Rust port, O3 | 1.565 | 1.596 | 1.584 |
| Go port, default optimization | 2.017 | 2.037 | 1.986 |
| Mylang GC, production baseline | 5.094 | 5.096 | 5.106 |
| Mylang GC, checked aggregate-read prototype | 4.744 | 4.773 | 4.795 |
| Mylang GC, combined aggregate + typed-host diagnostic | 3.652 | 3.627 | 3.679 |
| Mylang GC, production baseline with tool limits | 10.023 | 9.959 | 10.032 |
| Mylang GC, combined diagnostic with tool limits | 8.806 | 8.761 | 8.866 |

The combined diagnostic reduces original-circuit elapsed time by **28.3%**
(95% paired bootstrap interval: 27.2–29.1%), or **12.1%** with tool limits.
It still takes **2.55× Zig, 2.33× Rust, and 1.81× Go**. Its typed host path removes
parts of the generic host ABI contract, so this is evidence about an optimization
direction, not a shipping-safe performance claim. The checked aggregate probe
retains its bounds and snapshot behavior on the qualified cases.

Results and all raw rounds:
[combined batch](../../experiments/svg-gap-audit-20260921/headroom-measurements.json).
The original circuit produces exactly 49,617 SVG bytes in all four languages.
The direct Zig port is the comparator here; the actual EDA NetLisp renderer has
different output and remains separately documented in the
[previous comparison](real-arena-regions-2026-09-21.md).

## Ranked implementation work

| Priority | Work | Measured evidence | Remaining implementation |
|---|---|---|---|
| 1 | Replace byte-at-a-time host traffic with packed input and block output | 105,060 host calls per render; a typed scalar-host diagnostic reduces elapsed time by 22–23% | Owned byte input, a packed-byte host bridge, guest output buffering, explicit flush/error behavior |
| 2 | Inline checked aggregate reads, then eliminate unnecessary full-record projections | Checked read prototype saves 6.9%; a smaller 112-byte copy specialization saves 3.8% in a separate batch | General compiler lowering with exact layouts; field projection and helper scalarization after that |
| 3, first for bounded tool execution | Amortize step accounting while preserving budget semantics | Step checks alone add 94.7% elapsed time; frame checks alone add no clear cost | Account straight-line regions in batches with an exact slow path near exhaustion and at observable boundaries |
| 4 | Cache normalized net lookups in the schematic guest | Dense lookup prototype saves 4.5% unaccounted and 10.5% bounded | Promote the qualified source change, preserving encounter order and identity namespaces |

The percentages are measured against matched controls. They are not additive,
and the aggregate + typed-host combination above is the only measured combined
optimization. Full bulk I/O, field projection, and batched step accounting have
not yet been implemented or timed; the audit does not assign them invented gains.

### 1. Remove host crossings from byte loops

The original circuit has 25,845 input bytes, but the guest invokes `io::byte`
55,437 times as tokenization and string handling revisit source spans. SVG output
adds 49,617 `io::put` calls; six setup calls bring the total to **105,060**.
The native ports read complete input files and write a completed output buffer.
The current provider already uses buffered stdio: these are host ABI crossings,
not 49,617 kernel write calls.

The unchanged GC LTO profile attributes 22.6% of all samples to the host-invoke
function. A matched typed-host experiment reduces original-circuit wall time
from 5.104 to 3.965 ms for the host-only pair in the headroom batch. It keeps startup registry/signature
validation, call limits, two work charges per call, reentry state, document and
output bounds, and I/O errors. It removes copied-node construction, indirect
dispatch, per-call node/arity/capacity validation, result node/type/range checks,
and generic callback work-charge propagation. Production must define and retain
equivalent contracts for any typed path.

The implementation should start with an immutable owned byte payload for each
input document and a bounded packed-byte output operation. This can use existing
language byte types; a raw borrowed pointer is unnecessary. A borrowed alternative
would need an explicit lifetime/capability contract. The bridge must transfer
packed bytes, rather than encode every byte as a `MylangHostNode`.

Buffer guest output and flush explicitly, with defined partial-write and failure
behavior. Preserve capability checks, bounds, byte-based work charging, memory
limits, and reentry handling. A validated typed thunk with a generic fallback is
useful for scalar host operations that remain after the bulk conversion.

Changing only the provider to accumulate output in memory saved 3.2%; removing
only provider checks saved about 0.8%. Both shortcuts weaken contracts. They
do not address the main per-byte bridge cost. Relevant implementation:
[host runtime](../../src/qbe_host_runtime.c),
[host generation](../../src/host_native.zig), and the schematic I/O provider.
[Host evidence and probe contracts](../../experiments/svg-gap-audit-20260921/host/README.md).

### 2. Make record access visible to LLVM

An untimed non-LTO counter run intercepted **288,066 aggregate list reads**,
requesting **22,899,360 bytes** of record copies. The 112-byte `Pin` descriptor
accounted for 111,020 calls and 54.3% of those bytes. These are copy requests at
the runtime boundary, not measured memory traffic; LTO may eliminate some work.

At [qbe_managed.zig](../../src/qbe_managed.zig), the managed-list read caller
selects its inline path only for scalar elements. `inlineIndexRead` already has
an aggregate branch that can check bounds and copy a statically known layout
into the same frame scratch. The audit's guarded manifest rewrite takes that
direction by adding guarded direct paths at 178 of 179 sites, falling back to the original runtime call when
the descriptor size does not match the inferred scratch capacity. All 179 static
runtime call sites remain present because of those fallbacks.

That experiment lowers wall time from 5.094 to 4.744 ms, a **6.9% reduction**
(95% interval: 4.7–7.7%). The rewrite retains the original out-of-bounds failure
path structurally; a dedicated invalid-index trap test is still required for
production. Value snapshots, root-visible scratch, and backing-storage lifetime
remain intact on the qualified cases. One earlier unguarded layout inference produced incorrect SVG
and was rejected. Production lowering should use the actual type layout instead
of deriving layout from frame spacing.

Next, teach the compiler to load only the field needed by expressions such as
`pins[i].part` when the full record snapshot is unobservable. The same applies
to helpers that return a large `Pin` merely so the caller can read a few fields.
This must preserve evaluation order, aliasing and mutation semantics, bounds
failures, managed-field roots, and observable trap/debug state.

The fresh combined profile still contains `partPin` (9.7% of samples), routing
construction (8.4%), `nearest` (5.5%), and `findId` (3.3%). Static inspection of
validated passive parts indicates `partPin` already takes its indexed fast path;
its profile is not evidence that the old fallback scan is executing. The likely
remaining costs are calls, checks, full-record returns, and projections. This is
an inference from source and profiles; their individual savings are unmeasured.

Five large generated frames reserve 290,400 bytes in total. A diagnostic moving
them from heap allocation to the stack did not improve performance (1.5% slower
unaccounted; no clear bounded gain). It also bypasses correct native-stack
admission accounting. Do not raise the stack-frame threshold as the fix. Reduce
unneeded record temporaries and copies instead.

[Compiler findings and preserved contracts](../../experiments/svg-gap-audit-20260921/codegen/AUDIT.md),
[dynamic copy counts](../../experiments/svg-gap-audit-20260921/algorithm/list-get-counts.json).

### 3. Make bounded execution cheaper

The accounting matrix uses identical source, compiler and LTO settings, changing
only the existing step/frame emission switches:

| Accounting | Original-circuit median, ms | Ratio to neither, 95% interval |
|---|---:|---:|
| Neither | 5.317 | 1.000 |
| Step only | 10.351 | 1.947 [1.926, 1.957] |
| Frame only | 5.338 | 1.004 [0.990, 1.015] |
| Both | 10.503 | 1.975 [1.952, 1.995] |

This isolates instruction-step accounting as the dominant bounded-mode penalty.
The render executes 10,943,705 logical language steps; these are not hardware
instructions. Step emission adds 13,505 static check sites. The final executable
grows from 74,865 to 162,209 disassembled instructions and from 3,937 to 17,212
conditional branches in the step-only arm. These are static counts, not dynamic
CPU events.

Implement a fast path for straight-line regions whose cost and observable
behavior are known. Charge their cost together only when sufficient budget
remains and intermediate accounting is unobservable. Near exhaustion, retain
the exact per-instruction path so failure occurs at the same instruction, before
the same side effects. Calls, host operations, traps, and debugging/trace
observation require explicit boundaries or reconciliation. Keep call-depth
protection; its measured standalone cost is negligible.

The relevant emission is `Emitter.emitInstructions` / `Emitter.step` in
[qbe.zig](../../src/qbe.zig), with failure/accounting behavior in
[qbe_runtime.c](../../src/qbe_runtime.c). Qualification must compare budget
boundaries and trap positions across backends, not merely successful output and
one trivially small budget. L5 record/replay is not measured by this task family
and should not be credited with closing the SVG gap.

[Accounting census](../../experiments/svg-gap-audit-20260921/codegen/accounting-census.json),
[matched timings](../../experiments/svg-gap-audit-20260921/measurements.json).

### 4. Remove repeated identity lookup in layout

The tested guest change builds a dense display-identity-to-net-index table and
threads it through layout helpers. It preserves source order, tie-breaking,
recursion, and mutations. It saves **4.5%** in ordinary LTO and **10.5%** with
tool accounting on the original circuit, with consistent gains on both mutations.

This is the most concrete application-level change ready for promotion after
review. The patch and qualification are retained in
[algorithm evidence](../../experiments/svg-gap-audit-20260921/algorithm/README.md).
Qualification includes declaration and pin order changes, raw/display namespace
collisions, NC cases, and empty-net rejection under normal and GC-stress runs.

The native ports retain nearly all of the same nested layout and routing scans.
Therefore a fundamentally better native algorithm is not the explanation for
the current language gap. Per-part layout facts, row ownership, and ordered
routing buckets are credible later improvements, particularly on larger
circuits, but their gains remain unmeasured. The separate normalization
early-exit experiment did not produce a clear speedup and is not recommended
from this evidence.

## Lower priorities and rejected shortcuts

| Candidate | Result | Decision |
|---|---|---|
| More arena/GC work for this render | Arena/GC ratio 0.996 [0.978, 1.012]; 134 managed allocations, zero collections | Defer as a parity lever for this workload; allocation-heavy workloads are separate |
| Remove provider checks | About 0.8% faster, weakened contracts | Keep checks; fix bridge granularity |
| Buffer only inside the provider | 3.2% faster, deferred/unreported cleanup errors | Replace with an explicit checked block-output API |
| Normalize early exit | Interval includes no change in all three cases | Do not promote on performance grounds |
| Move large generated frames to stack | No gain, incorrect stack-admission accounting in the diagnostic | Reject threshold increase; optimize temporaries |
| Record/replay debugging | No debugging workload measured | Separate goal; no SVG speed claim |

The managed allocation count excludes the separate C allocations for oversized
generated frames. The frame experiment tests that distinct hypothesis.
The previous arena implementation remains useful for repeated temporary
allocation: its separate allocation-heavy benchmark improved by 14.8% and
reduced peak managed budget charges by 95.4%. That does not imply the same
benefit for one SVG render.

## Evidence quality and acceptance criteria

Two main intervention batches contain **2,976 timed executions**, with three
warmup rounds and 31 measured rounds per configuration and case. All timed runs
check complete SVG hashes, status, stdout, stderr, and issue output. Configurations
and cases are interleaved in randomized order on one CPU. Results use medians and
4,000 paired bootstrap resamples. No gains are inferred by subtracting timings
from different batches.

The baseline compiler had changed since the previous report, so the audit froze
a private compiler and rebuilt controls. Both ordinary and bounded LTO controls
are byte-identical to the previous qualified binaries. Binary hashes are checked
before and after timing. The evidence refers to these recorded snapshots, not
unrelated concurrent edits in the shared working tree.

Four unchanged configurations were profiled over 1,200 runs each, producing
51,127 actual CPU-timer samples. The combined prototype received another 1,200
profiled runs. Hardware/software perf events were unavailable. Sampling reports
self-PC attribution, includes outside-executable/unmapped samples in its
denominator, and provides neither caller stacks nor wall-time decomposition.
No performance claim uses instrumented-run wall times.

A separate non-LTO phase probe places much of bounded work in placement (5.35
million logical steps). Its CPU phase times are diagnostic only: system-linker
controls differ in code layout and wall time from the original binaries.
[Phase calibration](../../experiments/svg-gap-audit-20260921/phases.json) records
that difference explicitly.

Eight later prototypes passed 160 extended executions across ten inputs and
normal/GC-stress modes, plus bounded step/frame rejection checks. These are
useful regression cases, not proof of general compiler or host ABI safety.
[Extended qualification](../../experiments/svg-gap-audit-20260921/extended-qualification.json).

This is an application comparison, not equalized memory or safety policy.
Mylang has a 256 MiB managed budget; the native ports do not share that limit.
Go uses its default GC, Rust owned vectors, and direct Zig `init.gpa`; they do
not all use arenas. Zig ReleaseFast also differs in checking policy. An unchanged
ReleaseSafe port was built and byte-qualified, but this Zig toolchain also selects
a different allocator in that mode and emits retained-allocation diagnostics.
It was not timed as a supposed isolated bounds-check comparison.
[ReleaseSafe provenance](../../experiments/svg-gap-audit-20260921/algorithm/zig-safe-build.json).

Measurements ran on an i7-12700H. Audit builds finished before timed batches,
but unrelated background activity on the shared machine was not controlled.
Bootstrap intervals describe this batch, not all machines. The timed corpus
is one real circuit and two mutations, not a representative scale study.

Before declaring parity, implement and qualify bulk I/O and compiler changes,
then rerun the full comparison on several circuit sizes and topologies. Track
ordinary and bounded execution separately, retaining both GC and arena rows.
Add production tests for aggregate mutation/snapshot behavior, negative and
out-of-range indexing, managed fields under GC stress, arena ownership, host
failure/partial-write behavior, and exact budget/trap boundaries. Preserve SVG
bytes and malformed-input diagnostics. Broader source optimizations also need
adversarial ordering/tie fixtures.

A practical proposed parity target is elapsed time within 10–20% of each native
port across that corpus under documented build policies. The audit establishes
a ranked path toward that target; it does not demonstrate that the remaining
unimplemented changes will achieve it.

[Reproduction scripts and complete evidence index](../../experiments/svg-gap-audit-20260921/README.md).
