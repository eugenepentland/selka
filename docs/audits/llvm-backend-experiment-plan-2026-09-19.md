# LLVM backend experiment: implementation and measurement plan

Status: proposed implementation, 19 September 2026. No LLVM backend has been
implemented by this document.

## 1. Question and success criteria

Determine how much of mylang's remaining runtime gap comes from QBE optimizing
and generating code for the current lowering. Hold guest source, frontend
optimizations, object layouts, runtime, safety checks, and output constant.

The reference is the implementation described at `4919ea9f` in
[the landing report](runtime-to-2x-landed-2026-09-19.md): approximately 4.3× Zig
on the small census, 5.3× on the small render, and 5.8×/6.4× on the large cases.
Those are historical observations; rebuild and measure all comparison binaries
together instead of treating those timings as the new experiment's baseline.

The deliverable is a working, isolated LLVM route for the entire benchmark
closure, correctness evidence, and a same-batch QBE/LLVM/Zig report. Reaching 2×
Zig is the product target, not a prerequisite for a useful experimental result.

## 2. Recommended architecture

**Translate the existing emitted QBE IL into LLVM IR before QBE optimization.**
Expose the translator as an executable compatible with the existing `--qbe`
tool option. It accepts `-t amd64_sysv -o OUTPUT.s INPUT.ssa`, generates LLVM IR,
and invokes LLVM to produce the assembly the existing driver already assembles.

```text
                     frozen frontend manifest
                     (same function IL and metadata)
                              |
                    +---------+----------+
                    |                    |
                  QBE              IL → LLVM adapter
                    |                    |
               assembly          LLVM -O2 → assembly
                    |                    |
                    +---------+----------+
                              |
                existing assembler/linker pipeline
                same C metadata, entry, runtime archive
```

This is an LLVM backend experiment for the existing lowering. It deliberately
retains any limitations already baked into that lowering. A weak result would
not rule out a future LLVM emitter from a richer typed representation.

Implement the adapter and its runner under `experiments/llvm-backend/`; Python
is suitable for the first translator because translation is outside the runtime
timer. Emit LLVM IR directly rather than introducing generated C semantics into
the comparison. Use the installed native build driver instead of duplicating
metadata generation, entry generation, or link commands.

Relevant existing code:

| Location | Role in the experiment |
|---|---|
| [`src/qbe.zig`](../../src/qbe.zig) | Produces function IL, layouts, roots, checks, and source metadata |
| [`src/native_ir.zig`](../../src/native_ir.zig) | Typed operand-stack analysis; **not** a complete machine-level IR ready for LLVM |
| [`src/qbe_build.zig`](../../src/qbe_build.zig) | Consumes `--manifest-file`, compiles units, generates metadata/entry, links |
| [`src/qbe_build_cache.zig`](../../src/qbe_build_cache.zig) | Calls the selected QBE-compatible executable and assembles its output |
| [`src/qbe_build_outputs.zig`](../../src/qbe_build_outputs.zig) | Generates descriptors, literal definitions, locations, inline frames, and entry C |
| [`src/qbe_c_abi.zig`](../../src/qbe_c_abi.zig) | Existing foreign-call boundary behavior |
| [`vendor/qbe/amd64/sysv.c`](../../vendor/qbe/amd64/sysv.c) | Reference for the actual target ABI used by the baseline |

Keep the default backend and public language unchanged. General LLVM integration,
new architectures, JIT support, debugger metadata, a new collector, and application
rewrites are outside the first experiment.

## 3. Freeze inputs and inventory the required subset

Before implementing instructions:

1. Record git revision/dirty state and copy the compiler, QBE, Zig reference,
   benchmark guest sources, and inputs into a private scratch directory. Preserve
   existing working-tree edits. Hash the frozen files.
2. Emit one manifest per driver using the same frontend controls as an ordinary
   ReleaseFast executable: `--drop-debug`, `--drop-step-checks`, and
   `--drop-frame-checks`. Feed each frozen manifest to both backend builds.
   Create separate manifests with accounting enabled for correctness tests.
3. Inventory **every emitted unit**, including retained/unreachable functions
   the current driver still compiles: opcodes, types, calling conventions,
   direct/indirect calls, external symbols, data declarations, and constants.
4. Establish a supported-opcode table from that inventory. An unsupported
   instruction/type/calling convention must fail with function, instruction, and
   reason. Never silently fall back to QBE or replace missing behavior with zero.

Start with `e_scan`, then the census/render entry and its complete emitted
closure. Add the other audit microdrivers and trap fixtures to the inventory.
This is a bounded subset of QBE, but the subset must be sufficient for all
reported programs and validation cases.

Toolchain observation: the installed pinned Zig is
`0.17.0-dev.1683+5ceec001b`; `zig cc --version` reports Clang 22.1.8.
Standalone `clang`, `opt`, and `llc` were not found on PATH during planning.
First verify that this `zig cc` accepts a minimal `.ll` input and can produce
both assembly and optimized IR. If it cannot, use an explicitly pinned LLVM
toolchain and record its version; keep the production Zig version unchanged.

Proposed compiler invocation to smoke-test, not an already-verified command:

```sh
zig cc -x ir -S -O2 -fPIC -g0 unit.ll -o unit.s
```

Generate/check the target triple and data layout against this toolchain. Record
the actual CPU/features, relocation mode, and optimization flags. The first
comparison uses an x86-64 feature baseline QBE can also target; a host-specific
LLVM build can be reported as a separate additional arm. Identify any target
differences in the frozen Zig reference rather than hiding them in the ratio.

## 4. Translator implementation

Suggested files:

```text
experiments/llvm-backend/
  README.md                 scope, limitations, exact commands
  qbe_llvm.py                executable implementing the QBE tool interface
  il_parser.py              tokens, types, instructions, CFG, diagnostics
  llvm_emit.py              semantic translation and LLVM output
  amd64_abi.py               supported SysV aggregate/scalar ABI lowering
  build.py                  freeze inputs and build named comparison arms
  verify.py                 backend differential verification
  measure.py                interleaved timings and hardware counters
  tests/                    small semantic and ABI fixtures
  evidence/                 hashes, raw samples, coverage, report
```

Use a parsed representation with explicit types and basic blocks. Do not build
the translator as a sequence of textual substitutions.

### 4.1 SSA and scalar operations

QBE input is not necessarily SSA: a temporary may be assigned more than once.
LLVM requires SSA. A practical first implementation stores mutable temporaries
in private, entry-block slots, then allows LLVM promotion to eliminate them.
Use direct SSA for temporaries whose definition/use structure proves it valid.
Represent explicit phi inputs on predecessor edges; handle critical edges and
parallel phi assignments correctly.

Translate integer widths, signed/unsigned loads, comparisons, truncations,
extensions, floating operations, bit casts, branches, and calls from their QBE
semantics. Comparisons must produce the requested QBE integer width containing
0 or 1, not leave an `i1` where an integer is expected. Audit every implicit
word/long conversion instead of guessing sign extension.

Keep integer overflow checks exactly as emitted. Plain modular arithmetic does
not receive LLVM `nsw`, `nuw`, or `exact` flags without proof. Invalid shift
counts, division by zero, signed `MIN / -1`, and out-of-range float conversions
must reach the existing mylang trap path rather than introducing LLVM poison or
undefined behavior first. Some machine operations can be harmlessly computed
before a guard in QBE but are poison-producing in LLVM; move such computation
behind its guard or lower it to a total equivalent that preserves behavior.

Preserve float bit patterns, signed zero, NaN handling, rounding-environment
checks, and checked conversion behavior. No fast-math flags or contraction that
changes results. Use constrained operations if required by the existing floating
environment contract; exercise that contract in differential tests.

### 4.2 Pointers, memory, and roots

QBE represents pointers as integer-width values. LLVM can represent them as
opaque `ptr`. Do not assume every QBE `l` value is either always a pointer or
always an arithmetic integer.

For initial correctness, integer values plus explicit pointer casts are allowed.
Before interpreting a poor performance result, inspect whether those casts block
promotion or alias analysis. Preserve pointer identity for proven address values
such as allocations and symbol addresses; express proven pointer-offset
operations as byte GEPs. Derive address information from operations/signatures
and dataflow, not temporary names. Ambiguous integer/pointer uses keep a
conservative representation. Record which mode was benchmarked.

Avoid unjustified `inbounds`, `noalias`, `nonnull`, `dereferenceable`, memory-effect,
or TBAA annotations. In particular, managed references can alias, and collector
roots and active-frame records escape into runtime state. External runtime calls
can read roots, write traps, and allocate or collect unless proven otherwise.
Do not mark all guest memory volatile either: that would disable valid LLVM
optimizations and make the comparison uninformative.

Preserve load/store sizes and proven alignment. QBE `blit` permits disjoint
ranges or identical source/destination. A conservative `llvm.memmove` lowering
is acceptable; use `memcpy` only with its overlap requirements established.
Retain explicit root pushes, root restoration, value-carrying roots, zeroed traced
storage, arena barriers, and position/frame updates.

Put translator-created scalar slots at the beginning of the LLVM entry block.
Preserve the execution/lifetime of source `alloc4/8/16` operations first. Hoist
source scratch allocations only after proving their single-execution and
address-observability conditions; never hoist a repeated allocation blindly.
The existing emitter deliberately puts some aggregate scratch outside QBE's
entry block. Inspect its LLVM optimization consequences instead of assuming
those allocations will disappear.

### 4.3 ABI: an early acceptance gate

**Do not translate a QBE aggregate argument to an arbitrary pointer and assume
it remains ABI-compatible.** LLVM IR function signatures need explicit target
ABI lowering; LLVM does not turn every source-shaped struct signature into the
same C ABI that QBE uses.

The existing emitter produces scalar words, aligned opaque byte aggregates,
`:myl_slice`, aggregate returns, large-value pointer parameters/results, and
packed argument vectors. Preserve the current calling convention across guest
calls, runtime functions, generated metadata callbacks, and C entry wrappers.
Preserve `ctx`, hidden result storage, register/stack classification, argument
alignment, and narrow integer extension rules.

Implement the SysV cases actually present in the inventory, explicitly rejecting
others. Use tiny C definitions compiled to LLVM IR with the selected Clang as
an ABI oracle, checking the representation against QBE's target implementation.
An arbitrary LLVM `[N x i8]` parameter is not sufficient evidence of correctness.

Required cross-language probes include both QBE-caller/LLVM-callee and
LLVM-caller/QBE-callee directions, plus C boundaries: scalar results, 1/8/16-byte
aggregates, aggregates larger than 16 bytes, required alignments, more register
arguments than fit, real Token/Span/Step shapes, recursion, indirect callbacks,
and the packed/large-value conventions when exercised by supported fixtures.

Avoid inventing a new guest ABI in this phase. Once the complete benchmark works,
a different internal ABI or whole-module optimization can be measured separately.

### 4.4 Symbols and data

Preserve public function symbols, references to runtime metadata, constant
bit patterns, external addresses, and all data layout/alignment. The manifest's
`# myl-lit` records are also consumed by the existing C metadata generator;
keep the original manifest intact so literal definitions are emitted exactly once.
Maintain explicit external function and data declarations; validate conflicting
call signatures instead of emitting generic variadic declarations to hide them.

## 5. Build integration and cache isolation

The first LLVM arm uses **one LLVM module per existing guest function unit**,
compiled at `-O2`, then assembled/linked through the existing driver. This holds
the current compilation boundaries fixed. Keep `--keep-symbols` on every arm.

The `--qbe` option already supports an explicit executable path. A wrapper tool
is sufficient for the first integration; a new default/public backend switch is
unnecessary. Preserve tool failures and stderr, retain failed `.ll` inputs, and
implement the small tool-interface options the driver actually needs.

Use separate cache directories for QBE and each LLVM variant. Include adapter
source hash, imported Python-module hashes, LLVM version, optimizer flags, target
features, and translation mode in a recorded build identity. The current cache
stamps the selected tool, but changes to its imported modules or environment
need not change that stamp. Use a fresh/cache-identity-specific root on such a
change; never accept a hit merely because the wrapper path stayed the same.

The runtime archive, text-format object, generated C metadata and executable
entry must be identical between arms. Verify their hashes. If separate cache
builds do not reproduce identical support objects, capture and explicitly reuse
those artifacts through a minimal experiment-only build seam. Do not infer
identity from matching source names. Both arms must retain the same final-run
heap-teardown policy.

Illustrative commands once the adapter exists, with absolute tool/manifest paths:

```sh
zig-out/bin/mylang build experiments/sexpr-port/main.my \
  --manifest-file=/ABS/experiment/census.json \
  --qbe /ABS/frozen/qbe --mode ReleaseFast --keep-symbols \
  --cache-dir=/ABS/experiment/cache-qbe -o /ABS/experiment/census-qbe

zig-out/bin/mylang build experiments/sexpr-port/main.my \
  --manifest-file=/ABS/experiment/census.json \
  --qbe /ABS/experiments/llvm-backend/qbe_llvm.py \
  --mode ReleaseFast --keep-symbols \
  --cache-dir=/ABS/experiment/cache-llvm-o2 -o /ABS/experiment/census-llvm-o2
```

The wrapper's configuration, including optimization level, must be explicit in
the build receipt even though the existing driver sees a QBE-compatible tool.

After the first comparison, add `-O3` as a separate arm. Whole-guest-module LLVM
optimization is a useful later arm, but requires a manifest-aware build path
rather than pretending a per-function wrapper provides cross-function inlining.
Keep native runtime LTO, PGO, new inlining policies, and hand-tuned lowering out
of the initial comparison. They can each receive their own named later arm.

## 6. Milestones and exit criteria

| Milestone | Required result before proceeding |
|---|---|
| M0: freeze and inventory | Reproducible QBE baseline, opcode/ABI coverage report, LLVM tool smoke test |
| M1: scalar adapter | Arithmetic, checked traps, branches, loops, repeated assignments, loads/stores pass differentially at LLVM O0 and O2 |
| M2: ABI and managed values | Bidirectional ABI probes, aggregate/variant cases, roots, GC stress, and runtime calls pass |
| M3: full workload | All emitted census/render units compile through LLVM; zero QBE fallback; all goldens and semantic gates pass |
| M4: benchmark | QBE, LLVM O2, LLVM O3, and Zig measured together; raw samples and profiles saved |
| M5: decision | Report states speedups, residual gap, compilation costs, limitations, and the next investment supported by evidence |

If one ABI or opcode family dominates implementation time, report that concrete
blocker and keep the scalar results labeled as partial. Do not turn a successful
scan microbenchmark into a claim that the full application has an LLVM backend.

## 7. Correctness gates

Correctness failures block performance conclusions. Run:

* The translator's semantic fixtures through QBE and LLVM, including optimized
  and unoptimized LLVM. Exercise signed/unsigned boundaries, negative indexes,
  overflow, division/remainder, shifts, casts, float edge cases, aliasing,
  zero-length aggregates, and control-flow joins.
* All 17 existing sexpr rendering goldens, the port's guest tests, and census
  plus rendering on both benchmark inputs. Compare stdout, stderr, and status;
  include malformed input and exact locations, not only a census digest.
* The existing [differential trap fixtures](../../experiments/sexpr-audit/evidence/hot-loops/trapdiff/run.py),
  adapted to select backend tools with the same compiler. Cover ordinary fast,
  explicit step/frame-accounted, Debug, GC-stress, nested and inlined traps.
  Forward the selection through `mylang run`/test child builds or use explicit
  equivalent build-and-execute paths and state any interface not covered.
* GC stress across allocations, nested calls, aggregate roots, list growth,
  and arena escape. For guest tests that use native library entry points, verify
  the LLVM tool selection reaches their builds and that repeated execution still
  reclaims memory; the final-process teardown shortcut must not leak into them.
* Deep recursion and large frames to verify stack safety. Logical frame/step
  budgets and located trap behavior remain exact. Physical stack exhaustion
  depth can differ with backend frame size; document that distinction and check
  that the stack-floor mechanism remains safe rather than assuming QBE's frame
  estimate accounts for LLVM spills and stack allocations.

If production compiler/build code changes, run its appropriate focused tests and
the repository's required gates before a landing. A standalone adapter does not
by itself require rebuilding the compiler. Whenever Guardian is exercised, follow
the user's global instruction: append a concrete entry to
`~/ai/canopy/guardian-zig/FEEDBACK.md` and commit that feedback in its repository.

## 8. Measurement protocol

Primary workloads are the unchanged sexpr census and canonical rendering on
927,415 bytes and 7,419,320 bytes. Include scan and selected microdrivers as
diagnostics. These workloads do not establish full schematic-layout performance.

1. Build all arms before timing. Record every executable/support-object/input
   hash, manifest hash, compiler/backend version, CPU, OS, flags, and policy.
2. Pin parent and children to one available physical core; avoid concurrent
   compilations/profiling and check its SMT sibling's activity. Record machine
   conditions. Warm each binary/input pair before collecting samples.
3. Run at least 31 randomized/interleaved rounds including QBE, LLVM, and Zig.
   Capture output identically, verify it on every run, and record raw wall times.
   Repeat the batch to see whether the conclusion survives machine variation.
4. Report medians, IQRs, and a resampled interval for the speedup. Preserve round
   grouping in resampling. A small apparent win inside the observed spread is
   inconclusive. Do not use ratios from separate historical batches.
5. Collect instructions, cycles, task-clock, branches/misses, and peak RSS in
   separate matched measurement rounds. Label user-only versus all-mode counters
   explicitly. Collect cache/stall evidence before claiming memory boundedness.
   Profile guest functions separately from unchanged runtime functions.
6. Record a process-launch control, but do not subtract it and call the remainder
   exact computation time. The larger input is the primary startup-resistant
   check. If adding in-process repetitions, use identical lifecycle/reset and
   teardown policies on both sides and report that as a distinct workload.
7. Record cold backend compilation time, warm rebuild time, and object/executable
   sizes separately from runtime. QBE's fast development path is part of the
   tradeoff being evaluated.

Report both ratios: `QBE time / LLVM time` is the backend speedup;
`LLVM time / Zig time` is the residual product gap. Compute each within the same
batch. IPC is instructions divided by cycles; lower IPC cannot explain a
friendlier wall ratio by itself.

## 9. Interpret the result and finish

Use this report table for both input sizes, with uncertainty/spread alongside it:

| Workload | QBE ms | LLVM O2 ms | LLVM O3 ms | Zig ms | QBE/LLVM | LLVM/Zig |
|---|---:|---:|---:|---:|---:|---:|
| Census | | | | | | |
| Render | | | | | | |

Include correctness totals, backend coverage, compiler costs, and profiles. When
LLVM improves a loop, show the relevant optimized IR/assembly and identify the
removed work. When it does not, inspect promotion, integer/pointer casts, ABI
copies, escaped roots, and runtime-call opacity before concluding LLVM cannot
help. Also inspect the unchanged runtime fraction: even a large speedup confined
to guest code may yield a modest end-to-end improvement.

Suggested decision thresholds, to agree before examining results rather than
adjusting them afterward:

* A repeatable **≥1.5× whole-program speedup** on the large workloads, with
  correctness intact, warrants evaluating LLVM as an optimized/release backend.
  It still does not imply the 2×-Zig target is met.
* A repeatable **10–50% speedup** warrants pricing the implementation and compile
  time cost against representation/collector work and a whole-guest LLVM arm.
* A result inside noise or **<10% speedup**, after translator-quality checks,
  supports prioritizing representation and runtime work for this lowering.
  It does not prove a universal QBE floor.

Finish with `docs/audits/llvm-backend-experiment-results-2026-09-19.md` and a
reproduction README plus raw evidence under `experiments/llvm-backend/evidence/`.
State clearly which experiments actually ran and whether ≤2× Zig was achieved
on each primary workload. Keep the backend opt-in until a separate integration
decision is supported by those results.

## References

The architecture and semantic requirements above are primarily grounded in this
checkout. Consult the matching toolchain's documentation during implementation:

* [QBE IL reference](https://c9x.me/compile/doc/il.html): non-SSA input,
  integer/pointer representation, aggregate types, calls, and `blit` semantics.
* [LLVM language reference](https://llvm.org/docs/LangRef.html): types, poison,
  attributes, memory operations, calls, and overflow/FP intrinsics.
* [LLVM frontend performance guidance](https://llvm.org/docs/Frontend/PerformanceTips.html):
  entry-block promotion, aggregate representation, and pointer conversion costs.

Online LLVM documentation may track a newer revision; verify syntax and attributes
against the selected compiler rather than assuming every documented feature is
available in the pinned toolchain.
