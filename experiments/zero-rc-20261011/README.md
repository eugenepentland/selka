# Zero-RC prototype plan

Status: **Stage 1 implemented and qualified for the supported subset.** All 27
supported census programs finish with zero observed reference-count operations
throughout execution, including argument construction and cleanup. The earlier
Stage 0 baseline and the later stages remain documented below.

Priorities, in order: fast runtime execution, understandable code with local
reasoning, and fast compilation. Heap allocation is allowed. Reference counting
and copy-on-write sharing are excluded from this design.

Work continues in the existing main-derived Core/LLVM worktree
`codex/borrow-call-stack-20261010`. Keep the earlier experiments and their frozen
executables/results as comparison baselines. No QBE work is involved.

## Stage 1 results

The new flag extends the move/borrow checker to text, bytes, mutable buffers,
and their aggregate fields. `.copy()` recursively duplicates owned children;
substring results are owned. Mutation and cleanup use owned storage directly.
Static literals and built-in ASCII characters use a storage-kind tag. Runtime
helper declarations carry checked borrow/transfer/result contracts; unlisted
helpers fail at lowering. IR and emitted-code guards reject RC/uniqueness paths,
and the runtime aborts on any reached legacy count read.

| Census measure | Frozen single-owner control | Zero-RC stage 1 |
| --- | ---: | ---: |
| Supported examples | 27/30 | 27/30 |
| Examples with RC somewhere in complete execution | 27 | **0** |
| Examples with workload RC | 6 | **0** |
| Workloads allocating on the heap (inputs 4 and 11) | 20 | **20** |
| Candidate executions / outputs / leak checks | — | **330 passed** |

All five configurations were counted: release, unoptimized, optimized debug,
release with fact verification, and release without facts. Each of the 27 cases
ran at inputs 4 and 11; the six text/buffer/mixed cases additionally ran at 0 and
64, with outputs obtained from the frozen control compiler. All 135 emitted LLVM
files passed the structural guard. All 330 whole-execution counter reports passed
[audit.py](audit.py), with zero retains, counted releases, uniqueness tests,
runtime/shared count events, and live managed bytes at exit. Direct destruction
is recorded separately and still runs. These tests include heap allocation during
startup even for the seven workloads that allocate nothing themselves.

The only new census source migration is
[25_text_snapshot.my](migrated/25_text_snapshot.my): `const snapshot = text.copy()`.
The seven earlier list migrations remain in use. The three dictionary samples
and the original implicit text alias are still explicitly refused; see
[boundaries.json](boundaries.json).

Memory use is unchanged in 26 cases at both original inputs. For the text snapshot
case, the explicit owned copy plus direct mutation avoids an additional block:

| Input | Allocations before → after | Allocated bytes before → after | Peak managed bytes before → after |
| --- | ---: | ---: | ---: |
| 4 | 9 → 8 | 608 → 512 | 544 → 448 (−17.6%) |
| 11 | 17 → 16 | 1,280 → 1,152 | 1,152 → 1,024 (−11.1%) |

Those are whole-execution managed-memory counters, not process RSS. Counted copy
bytes are unchanged in the census; the new explicit octet-copy helper is included
in copy counters. The unused four-byte count slot and allocator size classes
remain in this stage, so removing RC alone does not shrink object headers.

### Runtime and compile-time observations

Uninstrumented release executables ran twice for warmup and then in nine paired,
alternating repetitions. Each pair produced the same output. These are shared-host
observations with overlapping ranges, not a proven general speedup.

| Workload | Size | Median runtime before → after | Observed change |
| --- | ---: | ---: | ---: |
| Mixed records and owned children | 1,000,000 rows | 94.73 → 117.78 ms | +24.3% |
| Text growth | 10,000,000 appends | 107.49 → 115.95 ms | +7.9% |
| Preserved text copy | 10,000,000 iterations per loop | 222.56 → 210.18 ms | −5.6% |
| Byte-buffer growth | 30,000,000 appends | 91.03 → 81.05 ms | −11.0% |

For the preserved text copy benchmark, median maximum RSS was 118,864 → 89,580 KiB
(−24.6%). The other three RSS measurements were nearly unchanged. The mixed-record
slowdown needs investigation; this stage uses a general iterative destructor
rather than the old generated release callbacks. That is a possible cause, not
an established attribution. Do not enable the prototype by default based on these
measurements.

Cold language-cache builds took 89–115 ms after versus 90–116 ms before;
warm executable-cache builds took 11–14 ms after versus 8–14 ms before. Isolated
source checks took 4–7 ms after. Reported lowering/optimization/emission totaled
4–12 ms after versus 3–7 ms before. The LLVM/runtime/link stage remained 71–94 ms
after. These are one cold/warm pair per benchmark, with Zig's global cache and the
shared runtime cache available; they are not cold-machine timings or evidence of
a compile-time improvement. Native time includes linker time, so do not add them.
Both experimental modes bypass per-function optimization caches while retaining
correctly keyed executable replay.

Raw repetitions and RSS are in [performance.json](performance.json), phase
summaries in [compile-timings.json](compile-timings.json), the complete census in
[results.json](results.json), and the strict audit in
[candidate-audit.json](candidate-audit.json). Raw commands, LLVM and counters are
under `.tmp/zero-rc-20261011/measurements`; raw timing reports are under
`.tmp/zero-rc-20261011/benchmarks-large`. [Stage 1 validation](stage1-validation.json)
records tool/source hashes and gate results.

Validation: 868 Core tests; 247 relevant frontend tests; 11 final focused
ownership/counter tests; 330 census executions; 88 whole-tree Guardian checks.
The focused tests cover ownership errors, overlapping mutations, string indexing,
static literals, Unicode, nested records/fixed arrays, deep copies, early returns,
and startup/teardown counters. The original modes remain covered by the Core suite.

### Try it

From this worktree:

```sh
python3 experiments/zero-rc-20261011/try.py 25_text_snapshot x x x x
# 1227
.tmp/zero-rc-20261011/candidate/bin/mylang run your_program.my --experimental-zero-rc
```

The first command selects the migrated sample automatically. Set `ZIG` to the
pinned toolchain for direct compiler commands. Rebuild with:

```sh
scripts/build-slot.sh build /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig \
  build install --prefix .tmp/zero-rc-20261011/dev
```

Reproduce qualification with `measure.py --compiler COMPILER --before BASELINE
--zig ZIG --output RAW_DIRECTORY`; run the paired benchmarks with `benchmark.py`
and the same arguments (a fresh output directory for cold-cache measurements).
The baseline is `.tmp/shared-snapshot-20261011/candidate/bin/mylang`.

Stage 1 remains deliberately incomplete as a language implementation: no escaping
views, snapshots/Shared, dictionaries/sets, recursive owned boxes, resource/foreign
contracts, or tasks. Some standard-library operations such as text `.upper()` are
also refused until audited. Source errors and unsupported APIs have diagnostics;
there is no RC fallback. Borrowed views are the next planned stage.

## Language contract

- Each dynamic allocation has one owner, possibly an owning container or scope.
  Assignment, insertion, and owned return transfer ownership.
- Ordinary function parameters borrow. `mut` borrows exclusively. Fresh results
  can return normally; callers need not construct empty destination objects.
- An independent owned copy duplicates dynamically owned children, including
  strings and bytes. Immutable dynamic storage has no implicit sharing exception.
- Static literals need no reference counting or destruction. Mutation that starts
  from literal storage materializes owned writable storage. A storage-kind tag or
  other static/owned distinction is not a reference count.
- Borrowed views cannot outlive or be invalidated by their source. Returned views
  have an explicit source relationship at the function boundary.
- A source ownership violation is a compile error. An unimplemented compiler or
  runtime shape is an explicit unsupported diagnostic, never an RC fallback.
- The new mode excludes `.snapshot()` and the proposed `Shared` wrapper. Earlier
  snapshot experiments remain available for comparison.
- Ownership cycles are not representable. Graphs may keep nodes under one owner
  and refer to them with IDs; checked IDs can still require runtime validation.

Borrowing and cleanup are checked per function using signature contracts.
Correctness and the absence of RC must hold without inlining, optimization, or
whole-program alias inference. Moving an allocation does not move its bytes.

## Stages and acceptance criteria

| Stage | Work | Required result |
| --- | --- | --- |
| 0. Baseline and measurement | Preserve the current compiler, sources, and raw counters. Audit the entire execution and record where RC remains. | Reproducible baseline; the audit rejects the current programs as not RC-free. |
| 1. Owned strings, bytes, and buffers | Add a separate experimental zero-RC mode; extend source ownership rules and direct cleanup to these types and their aggregate fields; migrate implicit aliases to explicit copies; remove RC from entry/exit and the runtime helpers these programs use. | All 27 supported census cases preserve their output and have zero RC in complete executions, including unoptimized builds. Unsupported APIs are diagnosed. |
| 2. Borrowed views | Add local views and a simple returned-view contract tied to one input. Reading/slicing can borrow; an independent result explicitly materializes an owned copy. | Borrow-only view creation allocates nothing and uses no RC. Escape, invalidation, and overlapping-mutation cases fail at compile time. Measure copies avoided. |
| 3. Remaining containers | Add dictionaries/sets, unions/options, recursive owned boxes, and necessary extraction/replacement operations. Keys, values, and children follow the same ownership rules. | All 30 original census cases are supported after documented migrations, with zero whole-program RC; new recursive and mixed-type cases also pass. |
| 4. Resources and foreign boundaries | Give files/providers/capabilities explicit owning scopes and borrowed dependent handles. Define borrow/transfer contracts at foreign calls. | Normal return, early return, and recoverable error paths close owned resources exactly once. Borrowed handles cannot escape their backing owner. No language/runtime RC in these paths. |
| 5. Tasks and concurrency | Let scoped task groups own task storage. Captures move or borrow until a mandatory join; results move out or remain borrowed from the group. | Parallel execution, task failure, and scope exit preserve lifetimes without RC. No borrowed capture escapes a join. Synchronization atomics may remain. |
| 6. Runtime and compiler completion | Remove reference-count fields, operations, and COW paths from the zero-RC runtime ABI; cover remaining standard-library helpers; enable correctly keyed caches; evaluate performance. | The emitted program and its language runtime cannot perform RC, rather than merely avoiding it on tested inputs. Performance and compile-time results accompany the supported-feature inventory. |

Stages 4 and 5 extend coverage beyond the original census; passing 30 small
examples is not sufficient evidence of complete language support. Each newly
supported operation needs an ownership contract and corresponding runtime path.

The zero-RC mode may temporarily retain unused header space to keep Stage 1
reviewable. Count initialization, count-dependent literal tests, uniqueness
assertions, and hidden runtime count reads must still be removed from supported
paths. Removing the field/layout compatibility itself is Stage 6 work. Do not
reinterpret reference-count operations as "cleanup" to satisfy the criterion.

Scratch arenas, fixed-capacity lists, automatic stack placement, and global
allocation inference are separate allocation optimizations. They are not needed
to eliminate RC and are outside this implementation sequence.

## Stage 0: baseline ready

The frozen comparison compiler is the snapshot experiment's compiler, used with
`--experimental-single-owner` and the 27 snapshot-free census controls:

`a02b4b1c34b6d52977a544245e832c896f5a00645182987f3fd217d5ee08483c`.

The prior [measurement manifest](../shared-snapshot-20261011/validation.json)
records its source and artifact hashes. Its [results](../shared-snapshot-20261011/results.json)
preserve output checks and the original five configurations. Stage 0 reanalyzes
the 54 existing counted release runs (27 cases at inputs 4 and 11); it does not
claim new compiler executions, new timing measurements, or new memory savings.

The prior workload-only results were 21 cases with no measured RC and six with
RC in strings or buffers. Once startup and teardown are included, none of the
27 programs is free of observed RC at either input. All 54 runs have zero live
managed bytes at exit. The six workload cases are:

| Case | Stage 1 work |
| --- | --- |
| `15_managed_elements` | Own and directly destroy string fields inside records/lists. |
| `24_text_builder` | Grow an owned string without COW or counted cleanup. |
| `25_text_snapshot` | Replace the implicit preserved alias with an explicit owned copy. |
| `26_text_slice` | Return an owned substring and directly destroy it. A borrowed alternative follows in Stage 2. |
| `27_buffer_builder` | Direct buffer cleanup and an RC-free mutation/growth path. |
| `28_buffer_snapshot` | Keep independent bytes and buffer owners. The existing conversion already copies bytes; its counted cleanup still needs replacement. |

[audit.py](audit.py) reads raw `mylang-counters-v1` JSON, including `main` and
`<outside>` events. It validates required fields and consistency between totals
and detailed records; reports emitted retains, counted releases and uniqueness
tests separately from runtime/shared RC; and keeps direct frees separate.
Missing/incompatible reports fail instead of becoming zero counters.

Reproduce the saved [baseline audit](baseline.json), from the worktree root:

```sh
python3 experiments/zero-rc-20261011/audit.py \
  .tmp/shared-snapshot-20261011/measurements/controls/census \
  --output experiments/zero-rc-20261011/baseline.json
```

Use the same input with `--require-zero` to see the expected rejection (exit 1).
For a future candidate, pass its raw counter directory instead. Missing or
invalid evidence exits 2. A directory must contain `counts-*.json` files.

The audit is an observed-event check, not a static proof: today's counters do not
instrument every runtime count read or uniqueness helper, and unexecuted paths
cannot be validated by these measurements alone. Stage 1 therefore also needs
the structural and runtime checks below. Runtime and emitted counts can overlap;
they must not be summed into a supposed total.

## First compiler batch: Stage 1

Use `--experimental-zero-rc` on build, run, check, and dump-ir. The earlier
single-owner and snapshot experiments keep their defined behavior. `check`
validates the source ownership contract; `build` additionally admits backend
shapes and runtime helpers. The guest `test` command does not accept this flag.

1. **Ownership contract and diagnostics.** Generalize the checker in
   `src/core/single_owner.zig` to distinguish owning string/bytes/buffer values
   from borrowed reads and static literals. Cover records, fixed arrays, and list
   elements. Reject snapshot opt-in in the new mode. Add explicit owned-copy
   operations for text/bytes and specify consuming conversions at their API
   boundary; copying must never silently retain a dynamic child. Account for
   self-append, nested expressions, branch joins, loops, and early return.
2. **Lowering and destruction.** Extend `single_owner_copy.zig`, `own.zig`, and
   LLVM emission so ownership transfers and typed destruction do not synthesize
   RC/COW paths. A post-lowering/emission verifier rejects any remaining count
   manipulation or dynamic uniqueness operation. A direct destruction operation
   is allowed; a decrement followed by a zero test is not.
3. **Runtime path and entrypoint.** Add RC-free variants for admitted text/byte
   operations and argument construction/destruction. Audit runtime-internal
   temporary values, formatting, encoding, child cleanup, and failure paths too.
   Metadata records whether each helper borrows/consumes inputs, owns its result,
   and is available to the zero-RC mode. Calls to unaudited helpers fail explicitly.
   Use runtime tripwires for accidentally reached legacy count primitives during
   development, covering count reads/tests as well as increments/decrements.
4. **Source migrations and regression evidence.** Preserve original sample files.
   Add migrated versions with explicit text/byte copies where needed. Verify
   same outputs, leaks, ownership errors, and entire-run counters. No temporary
   exclusion of argument cleanup or printing is allowed to make the numbers pass.

Begin with buffers plus entry/exit as a narrow vertical slice, then string
construction/cleanup, explicit string copies, and owned slicing. Finish mixed
aggregate cleanup and all 27 controls before declaring Stage 1 complete. The
initial buffer slice is only an intermediate result, not completion of the stage.

Primary implementation locations:

- Ownership/copy contract: `src/core/single_owner.zig`,
  `src/core/single_owner_copy.zig`, collection/text method typing and lowering.
- IR/checks/emission: `src/core/ir.zig`, `src/core/own.zig`,
  `src/core/emit_llvm.zig`, `src/core/emit_bytes.zig`, `src/core/emit_text.zig`,
  `src/core/pipeline.zig`.
- Runtime: `src/core/runtime/core_rt.c`, `core_text.c`, `core_bytes.c`,
  `core_values.c`, and `src/core/count_runtime.zig`.
- Mode plumbing and later cache compatibility: CLI/check/build/run/dump-IR
  options, lowering/optimization/emission keys, executable replay identities.

## Validation and measurement for each compiler stage

- Functional equivalence to the frozen source/output baselines at both existing
  inputs, plus empty and larger representative inputs. Record source migrations
  separately from backend-only changes so copying costs remain visible.
- Source-negative tests: use after move, borrowed escape, overlapping mutation,
  duplicate destruction, views invalidated by growth, and errors at API boundaries.
- Whole-execution counters and leak checks in optimized and unoptimized builds;
  verification/debug builds must obey the same ownership rules. An RC-free result
  must not depend on optimization successfully deleting an unsafe sharing path.
- Structural verification of emitted IR/code plus audited runtime helper contracts
  and RC tripwires. Counters alone are insufficient. Remove tripwire dependencies
  when the zero-RC runtime no longer contains legacy count machinery.
- Report allocation/reallocation counts, copied bytes, peak managed bytes, and
  measured RSS separately. Keep direct frees distinct from counted releases.
- Benchmark elapsed execution with counters/leak instrumentation disabled and
  workloads large enough to measure. Use repeated runs and report variability.
  Do not infer a speedup from fewer RC operations or fewer allocated bytes.
- Measure compiler checking/Core time separately from LLVM/link time, as well as
  end-to-end cold and warm builds on fixed hardware/toolchain. Record mode and
  cache differences; the current prototype bypasses some caches. No compile-time
  improvement is claimed before measurement.
- Run relevant Core/frontend checks and applicable repository gates after compiler
  changes. Preserve results/manifests. Guardian feedback entries are not required.

The first comparison is a completed Stage 1 candidate against the frozen
snapshot-free controls. Later stages expand coverage and reduce explicit-copy
costs. Runtime performance wins and compile-time changes remain measurements,
not promises of the ownership model.
