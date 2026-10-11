# Zero-RC closeout: ten-agent execution plan

Prepared 2026-10-11 against `codex/zero-rc-batch-20261011` at `afb81c0f5`.

## Outcome and boundaries

Finish the remaining memory-management performance, qualification, integration,
and rollout work. Priorities, in order, are correct RC-free execution, fast runtime
performance, simple local reasoning, and fast compilation. Ordinary dynamic heap
allocation is allowed. Zero heap allocations is not an acceptance requirement.

This plan has two distinct delivery milestones:

1. **Qualified implementation:** integrate the completed prototype and remaining
   improvements into a tested main-derived branch, then local `main`, with a fresh
   allocation census and application measurements.
2. **Default rollout:** make zero-RC the normal mode for the declared release
   contract after compatibility and command-path checks pass. Prepare this change
   separately so a performance improvement does not silently change language defaults.

Report these milestones separately. A qualified opt-in prototype does not count
as a completed default rollout. Any retained explicit legacy RC mode must be
identified, with a concrete retirement checklist; it must never be an automatic
fallback for programs rejected by zero-RC checking.

Stored or escaping views, detached tasks, general closure captures, arbitrary
retained managed pointers across FFI, arbitrary partial record moves, and a new
arena/scratch language design are outside this closeout. Keep their refusals clear.
If an application in the agreed release contract needs one of these, report a
rollout blocker instead of silently expanding the compiler or shrinking coverage.

## What is already finished

Do not reimplement these items:

- Owned Result/Option `try` payload transfer and fresh-match payload transfer.
- JSON `get`/`at` borrowing the container and copying only the selected result.
- Whole field transfer from immediate named-field patterns on a fresh owned enum.
- Cleanup of ignored fields and recursive box shells without RC.
- Cache hashing that visits a fielded match body once, including the 64-level
  regression against exponential traversal.
- The source-level scoped `parallel.map` API. Its scheduling/allocation efficiency
  remains a separate item; the API itself already exists.

The latest batch passed 1,025 Core tests, 177 selected frontend tests, 11 CLI cache
tests, six cold/warm/uncached executions, and 88 whole-tree Guardian checks.
Its benchmark matrix passed 106 counted executions, including 101 zero-RC runs.
See the [batch report](../../experiments/zero-rc-batch-20261011/README.md) and
[integration evidence](../../experiments/zero-rc-batch-20261011/integration-validation.json).

| Evidence to preserve | Latest measured result |
| --- | --- |
| JSON array lookup with 128 unrelated siblings | 391 → 3 allocations per lookup |
| JSON object lookup with 128 unrelated siblings | 520 → 3 allocations per lookup |
| Failed JSON lookup | Zero additional managed allocations |
| 1,000 migrated record unpacks | 27,000 → 21,000 allocations; 22.6% lower peak managed bytes |
| Standard JSON fixture | 553 → 538 allocations; peak remains 9,952 bytes |
| Original allocation census | **Historical:** 23/30 workloads allocated; this must be rerun |

The ten selected library fixtures passed in the earlier closeout. That is not
qualification of every standard-library export or a representative large application.
Earlier reports describe historical limitations; use the current code and the
newest evidence when deciding what is still missing.

## Remaining work and priority

| Priority | Item | Lead | Closeout evidence |
| --- | --- | --- | --- |
| P0 | Integrate the unmerged prototype follow-ups from the correct main lineage | Coordinator | Pinned base, merge history, clean final checkout |
| P0 | Preserve ownership, cleanup, runtime ABI, and cache correctness | A07, A08 | Positive/negative regressions, RC-free output, cache isolation |
| P1 | Reduce `parallel.map` per-element scheduling storage | A01 | Batched execution, allocations vs input size, concurrency stress |
| P1 | Resolve the retained-list-capacity peak-memory tradeoff | A02 | Growth/peak measurements and an explicit adopt/reject decision |
| P1 | Qualify and migrate more library operations | A04, A05 | Export inventory, executable examples, copying/borrowing contracts |
| P1 | Qualify representative applications | A06 | Original/migrated source pairs and correctness results |
| P1 | Refresh the allocation census and classify remaining costs | A03 | Current denominators, per-case allocation/RC report |
| P1 | Measure runtime, process memory, and compilation on larger inputs | A08, A09 | Paired timings, RSS, compile/cache measurements |
| P2 | Complete support documentation, migration, and default rollout | A10 | Compatibility matrix, separate rollout commit, retirement checklist |

## Concurrency and workspace setup

The intended team is **one coordinator plus ten workers**. Ten workers can read,
implement, and prepare tests concurrently; ten native builds should not run together.

The session that produced this plan exposes **four total agent slots**, including
the coordinator. Actual ten-worker concurrency requires an orchestration environment
with at least eleven total slots. If that capacity is unavailable, preserve the ten
assignments and run up to three workers at a time. Do not claim ten simultaneous
workers or bypass a configured slot limit.

Use an isolated worktree and branch for each worker. All workers start from the same
coordinator-pinned commit, called `C0` below. Never share a writable checkout.

### Coordinator bootstrap

1. Read applicable `AGENTS.md` instructions and inspect working-tree status.
2. Verify the actual `main` checkout and current commit. At plan creation:
   - main checkout: `/home/epentland/ai/canopy/mylang-debug-speedup-main`;
   - local main: `9225adeb06cca3ab19a0f4437ec2065fbea34e2e`;
   - completed batch: `afb81c0f5` on `codex/zero-rc-batch-20261011`.
3. Create a new integration worktree **from current main**, then integrate the
   completed batch history. Resolve any newer-main conflicts there. The batch
   already contains the owned-try and fresh-match follow-ups; do not apply them twice.
4. Find the separately assigned `parallel.map` work and its owner/commit. A01
   adopts and qualifies that work; it must not start a competing implementation
   while the existing owner is still changing it.
5. Run integration smoke checks, freeze `C0`, and record its full SHA. If main has
   changed compiler behavior since the batch, build a new baseline and measure that
   integration separately before attributing later gains to these workers.
6. Create ten worker worktrees at `C0`; publish the ownership table below and
   agreed release applications/APIs. Agents may prepare inventories immediately,
   but final qualification uses the frozen integrated candidate.

The default workspace `/home/epentland/ai/canopy/mylang` is a different branch.
Do not use it merely because it is the shell's initial directory. This work uses
the current Core/LLVM backend; historical QBE benchmark drivers are not the baseline.

Preserve the existing frozen compiler:

```text
/home/epentland/ai/canopy/mylang-zero-rc-batch-20261011/.tmp/zero-rc-batch/candidate-v2/bin/mylang
SHA-256: 76ef3ab199bfed73ad6e5ffb1e0ef8c11eb65afd65ac7826307d83e713b8d2d3
Compiler source: d57510b466ff798ec38b3719e44ee84b40f68e02
```

Use the repository-pinned Zig toolchain; at plan creation it is:

```text
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig
```

## Shared working contract

- Run significant compiler/native builds through `scripts/build-slot.sh build`.
  Run the full project gate through `scripts/build-slot.sh gate`. Current defaults
  admit three builds and one gate. Do not raise limits or use private slot directories
  to defeat the shared queue. See [many-agent tooling](../tooling/many-agents.md).
- Use a dedicated `.tmp/zero-rc-closeout/Axx/` build prefix, cache, and output area
  inside each worker's worktree. Never overwrite a frozen compiler or prior report.
- Do not edit compiler/test inputs while a build in that worktree is running.
- A09 schedules all timing windows. A08 coordinates compile timing with A09.
  Use `scripts/build-slot.sh timing …` for measurements and pin serial guests to
  CPU 2 inside that command. Timing admission drains cooperating builds/gates;
  ordinary jobs use all allowed CPUs outside timing windows. Harnesses that own
  admission run directly. Do not run competing benchmark timers.
- Each agent owns its listed production files, a new uniquely named test file,
  and `experiments/zero-rc-closeout-10-20261011/Axx/`. A10 also owns release docs.
  A worker may inspect any file, but requests changes outside its ownership.
- The coordinator owns shared registration files: `SPEC.md`, `build.zig`, test-root
  imports, `src/typed.zig`, `src/sema_statements.zig`, shared runtime declarations,
  helper-contract registration, and `src/features.json`. Submit a small patch
  request describing the dependency instead of editing these concurrently.
- Prefer existing borrowing, fresh-result transfer, caller destinations, and explicit
  independent copies. Add no general lifetime inference, new ownership syntax,
  partial-move tracking, or silent RC fallback as a shortcut.
- Keep correctness tests focused on observable contracts. Optimization changes need
  a reproducer and measured before/after evidence; avoid tests that merely mirror code.
- Run formatting, appropriate focused tests, and required Guardian checks. Use normal
  commit hooks. Guardian feedback-log entries are not required; do not write
  `~/ai/canopy/guardian-zig/FEEDBACK.md` unless the user explicitly requests it.
- Commit worker changes in coherent units. Never merge into main, push, clean another
  worktree, reset shared caches, or cherry-pick a moving peer branch independently.

### Common handoff format

Each worker supplies `handoff.md` in its experiment directory containing:

1. Base SHA and proposed commit SHA(s), file list, and any shared-file patch request.
2. What changed, with one concrete before/after source example where relevant.
3. Exact test commands, exit statuses, compiler/source hashes, and evidence paths.
4. Allocations, cumulative bytes, peak managed bytes, and performance effects when applicable.
5. Unresolved failures and scope limits. Distinguish a shipped fix from a measured
   decision to retain current behavior.
6. The next agent that consumes the result and whether a final-candidate rerun is needed.

Each measurement manifest identifies source path/hash, compiler path/hash, flags,
input size or seed, worker count, expected output/exit status, migration status,
and instrumentation. Keep refused cases in the inventory with their diagnostics.

## The ten assignments

### A01 — Scoped parallel-map efficiency

**Own:** `src/core/build_parallel.zig`, `src/core/runtime/core_tasks.c`,
`src/stdlib/parallel.my`, and new A01 tests/fixtures.

Adopt the separately assigned map work first. Replace avoidable per-item capture,
task, and result wrappers with bounded batches or worker chunks while preserving
input borrowing, result order, independent owned outputs, and join-before-return.
Keep synchronization required for scheduling; it is not reference counting.

Test empty and single-item inputs, non-divisible chunk sizes, managed results,
Result-valued callbacks, nested maps, discarded outputs, and 1/2/8 workers. Run
ThreadSanitizer stress through the existing supported harness. Include cheap and
expensive callbacks and show scheduling allocation growth separately from output
allocation growth. Ordinary RC's sequential map is a correctness control, not an
isolated performance comparison for the effect of RC removal.

**Done:** the adopted implementation is integrated and race/cleanup clean, ordering
is unchanged, and scheduling overhead is demonstrably reduced at larger input sizes.
No detached work or new capture semantics. Hand results to A06, A07, and A09.

### A02 — List capacity and peak live storage

**Own:** capacity/allocation changes in `src/core/runtime/core_rt.c` and
`src/core/runtime/core_bytes.c`, plus new A02 tests. Other edits to these files
must be coordinated through A02.

Reproduce the retained-capacity effect from the
[owned-payload report](../../experiments/owned-payload-20261011/README.md).
Measure tiny nested lists, long append-heavy lists, repeated replacement, clearing
and reuse, and large buffers. Start with small bounded growth-policy alternatives
and existing reserve hints. Avoid reintroducing deep copies to make peaks look smaller.

Report actual capacity, logical length, reallocations, cumulative allocated bytes,
peak managed bytes, and runtime. Check overflow/OOM handling and ordinary RC behavior.
Do not add automatic shrinking at every return or an unrequested compaction syntax.

**Done:** either adopt a simple policy that improves relevant peaks without a
repeatable material throughput regression, or retain the policy with measured
tradeoffs and a specific follow-up. A retained tradeoff is not a claimed memory fix.
Hand the alternatives and decision to A09/A10; coordinate any library reserve edits
with A04/A05 rather than changing their files.

### A03 — Current allocation and RC census

**Own:** A03 harnesses, manifests, generated fixtures, and reports only.

Rebuild the original 30-case census and the expanded program matrix against `C0`
and the final candidate. Read the corpus and migration mappings from
`experiments/rc-census-20261010/`, `zero-rc-containers-20261011/`, and
`zero-rc-final-20261011/`. Preserve the original 30-case denominator even when
adding new cases. List admitted, refused, workload-allocation-free, allocating,
and RC-observed cases separately.

For every remaining allocation family, distinguish required independent storage,
container growth, explicit copies, avoidable library copies, task infrastructure,
and other runtime storage. Separate startup/teardown from workload counters; include
both whole-program totals and any carefully derived operation-only deltas.

Historical harness entrypoints can write into their own report directory even when
given `--output`. Import reusable helpers or adapt a new harness with all writes
redirected into A03. Never overwrite historical reports.

**Done:** answer “how many examples still allocate?” with current exact counts and
source/compiler hashes, and produce a ranked residual-allocation list. Send actionable
findings to the owning agent; the census itself does not own production fixes.

### A04 — Text, parsing, and navigation library coverage

**Own:** `src/stdlib/{json,strings,path,base64,hex,byte_builder}.my`,
`src/core/runtime/core_text.c`, and corresponding new A04 tests.

Inventory public exports and ownership behavior, extending beyond the ten existing
fixture programs. Exercise valid and invalid parsing, dynamic strings, nested JSON,
formatting, split/join, codecs, path processing, empty values, and repeated calls.
Remove demonstrated intermediate copies using current source rules. Preserve copies
required for independently returned borrowed input; `.copy()` remains meaningful.

For APIs returning an owned result, check use after input replacement/destruction.
For borrowing APIs, check invalidation and escape diagnostics. Coordinate byte-runtime
changes with A02 and new helper contracts with the coordinator/A07.

**Done:** every export in this group is classified and every in-scope supported
contract has runnable evidence. Fix encountered bugs; identify genuinely unsupported
APIs explicitly. Supply same-source controls and migrated-source comparisons to A09.

### A05 — Remaining library coverage and ownership migration

**Own:** the remaining `src/stdlib/*.my` modules, excluding A01/A04 ownership;
`src/core/runtime/core_dict.c`, `src/core/runtime/core_sort.c`, and new A05 tests.

Audit collections, sorting, pools, random state, memoization/persistence helpers,
numeric helpers, and provider-facing library wrappers. Start with hot paths and
operations whose results retain managed children. Classify all remaining public
exports, rather than treating a passing module fixture as complete API coverage.

Preserve explicit generator-state copies, borrowed sort inputs, owned sort results,
pool-handle validity, dictionary/set replacement and extraction, and exactly-once
provider cleanup. Exercise independent copies and repeated mutation. Do not admit
unaudited native helpers merely to make a fixture compile; send the contract and
reproducer to A07/coordinator.

**Done:** owned/borrowed contracts and support status are documented for this group,
all agreed release APIs pass, and any unnecessary copies removed have measurements.
Unresolved in-scope resource or persistence failures block rollout, even if other
library fixtures pass. Hand the inventory and migrations to A06/A10.

### A06 — Representative applications and migration ergonomics

**Own:** new A06 application fixtures and migrations in
`examples/python-word-count/`, `examples/domain-codecs/`,
`examples/external-capabilities/`, and `examples/generic-resources.my`.

At kickoff, select at least four application shapes: text/word counting,
JSON or domain-codec transformation, resource-backed file processing, and useful
parallel computation. Reuse existing examples where they fit; add a multi-module
workload combining these features. Fix input datasets and observable checksums.

Capture original source behavior, make the smallest ownership-compatible migration,
and measure the source burden: changed lines, copies introduced/removed, rejected
patterns, and diagnostics that obstruct local reasoning. Include early/error paths
and realistic larger inputs. Keep synthetic stress cases separately labelled.

**Done:** agreed applications run correctly in zero-RC mode with no RC fallback or
managed leaks; migration requirements are explicit. Library/compiler defects are
routed to A04/A05/A07 and retested after integration. Supply stable workloads to A09.

### A07 — Ownership and cleanup soundness

**Own:** `src/core/single_owner.zig`, `single_owner_copy.zig`, `build.zig`,
`own.zig`, `emit_llvm.zig`, `emit_homes.zig`, `verify_ir.zig`, `zero_rc.zig`,
`src/core/runtime/core_owned_copy.c`, and new A07 regressions.
The `build.zig` here is **`src/core/build.zig`**, not the coordinator-owned root file.

Audit the integrated transfer boundaries: `try`, fresh match, whole-field unpack,
ignored fields, wide/recursive boxed values, mutable writebacks, views, resource
scopes, and task input/result lifetimes. Extend positive and negative coverage for
early return, propagation, break/continue, owner replacement, duplicate moves,
borrow escape, and wrong-ABI extraction. Verify task changes with A01.

Use small reproductions and supported sanitizer/runtime probes where useful.
Preserve the explicit source rules. Fix concrete bugs within those rules; do not
extend nested-pattern movement or general field movement to paper over a failure.
Coordinate changes to shared runtime contracts with their file owner/coordinator.

**Done:** every identified safety defect has a regression and fix, RC-free builds
reject surviving count operations, and emitted code/native symbol/runtime audits
agree. Unsupported programs fail clearly at compile time. No untriaged cleanup or
ownership failures may be deferred while declaring the release contract complete.

### A08 — Compile time and cache behavior

**Own:** `src/core/lowering_cache.zig`, `optimization_cache.zig`,
`emission_cache.zig`, `src/semantic_store.zig`, `src/semantic_copy.zig`, and new
A08 cache tests and measurement harnesses.

Measure cold builds with isolated caches, warm stage reuse, whole-build replay,
and small edits to large projects. Include increasing nested-match depth, field
counts, recursive types, module counts, and generic instantiations. Pin the
64-level hashing regression and test source relocation, changed binding metadata,
cache-format invalidation, and alternating ordinary RC/zero-RC mode requests.

Separate checking, lowering, optimization, emission, and native compilation when
available. Record wall time and compiler process memory. Serialize timing with A09;
exclude queue wait and do not compare a cold baseline with a warm candidate.
Fix demonstrated superlinear behavior or incorrect reuse. Preserve eager ownership
checks; do not add speculative whole-program lifetime analysis.

**Done:** cache correctness passes and compilation scaling is measured, with any
repeatable regression explained or fixed. Report compile-time results independently
of guest runtime improvements. Hand measurements to A09/A10.

### A09 — Performance, RSS, and evidence coordination

**Own:** A09 benchmark orchestration and final performance report. Production files
belong to the implementation agents. A09 owns the timing schedule for the whole team.

Combine A01/A02/A03/A06 workloads and A08 compile-time measurements. Use two controls
where useful: the frozen prior zero-RC compiler to isolate these improvements, and
ordinary RC for compatibility/context. Record source migrations separately; a
different source or parallelism strategy is not an isolated compiler comparison.

Measure allocation counts, reallocations, cumulative managed bytes, peak live managed
bytes, exit-live bytes, uninstrumented runtime, total process peak RSS, and compile
times. Managed counters exclude some raw buffers, task stacks, and native storage;
RSS is a separate measurement. Use a process-tree/cgroup measurement for builds
that spawn child processes, and document exactly what the reported peak includes.

Use at least two warmup pairs and nine alternating measured pairs for runtime.
Lengthen tiny workloads to make startup less dominant. Publish all samples/ranges,
not only the best run. Treat repeatable slowdowns above 5% as review triggers,
not automatic proof of a regression when the noise range is larger.

**Done:** a reproducible final-candidate report distinguishes allocation traffic,
live storage, RSS, runtime, and compilation; it includes regressions and rejected
optimizations. Compiler hashes match the exact binaries tested. No broad speedup
claim is inferred solely from JSON microbenchmarks.

### A10 — Support contract, documentation, and rollout

**Own:** `docs/managed-memory.md`, `docs/tooling/ownership.md`, new migration/release
documentation, and A10 compatibility/CLI fixtures. Reserve any CLI mode-selection
files with the coordinator before preparing their separate rollout commit.

Merge A04/A05 API inventories and A06 application findings into one support matrix.
Explain ownership in ordinary code: moves on assignment/return, borrowing parameters,
explicit independent copies, fresh-match transfer, and scoped parallel work. Show
diagnostic-driven migrations and preserve clear unsupported-feature boundaries.

Prepare a separate default-mode change with tests for build/run/check/dump/test and
other relevant entrypoints. Inventory which commands currently accept the prototype
flag; for example, the guest `test` command's current limitation must be resolved or
explicitly block full default rollout. Ensure caches and installed packages select
the intended ABI consistently. Preserve an explicit, tested migration/rollback route
during transition, without silently compiling rejected code under RC.

Also inventory legacy RC retirement: CLI flags, runtime selection, helpers/symbols,
tests, packaging, docs, and persisted caches. Distinguish “default is zero-RC” from
“legacy RC support has been removed”; specify the remaining commits and compatibility
conditions for the latter. Do not describe a dormant compatibility mode as RC removal.

**Done:** the release contract and migration guide are complete, the default-change
commit is reviewable and tested, and its blockers are explicit. Landing default
promotion requires the integration criteria below; a documentation-only handoff
does not count as having changed the default.

## Integration stages and dependencies

### Stage 0 — One base and one release contract

The coordinator completes bootstrap, agrees the initial API/application inventory,
records external map ownership, and publishes `C0`. Pin baseline compiler/source
hashes and allocate file ownership before production edits start.

### Stage 1 — All ten workers proceed independently

- A01/A02 implement bounded runtime improvements.
- A04/A05 expand library coverage and make source migrations.
- A07 audits/fixes ownership; A08 validates cache scaling and prepares compile timing.
- A03 captures the baseline census; A06 prepares applications; A09 prepares measurement;
  A10 drafts the support matrix and rollout change.

The measurement/documentation agents have useful work immediately; they do not wait
for implementations before collecting baselines and fixing the input manifests.

### Stage 2 — Integrate by dependency, then freeze

1. The coordinator lands shared contract/registration prerequisites and A07 correctness
   fixes, followed by A08 cache fixes as needed.
2. Integrate A01 task work and A02 capacity changes independently. Integrate A04/A05
   library changes once their contracts are present, then A06 application migrations.
3. Review overlapping dependencies with the assigned file owner. Use small commits;
   preserve an easy revert of a capacity or batching experiment that does not pay off.
4. Build a new immutable candidate. Run focused regression tests and the combined
   correctness checks. A03/A06/A08/A09 run their final qualification against that
   exact binary; A10 finalizes the support contract from those results.
5. Route failures back to their owner. A compiler/runtime change creates a new
   candidate/hash and requires affected qualification to run again. Keep old results
   rather than relabelling them as evidence for the new candidate.

### Stage 3 — Close the qualified implementation

Run the final required project gate once the combined source is stable, through the
shared gate queue. Include the full Core suite, relevant frontend/CLI regressions,
whole-tree Guardian checks, task stress, and the matrices below. Integrate the
qualified changes into local main and verify the resulting revision; do not publish
or push as an incidental part of measurement.

Every original remaining item must be marked shipped, measured tradeoff, or blocked
with an owner and reproduction. A performance idea may be rejected with evidence;
an in-scope correctness or support blocker cannot be reclassified as “done.”

### Stage 4 — Promote the default and track legacy retirement

Apply A10's separately tested default change only after the declared release
contract passes. Recheck normal command paths without the experimental flag,
package/runtime ABI selection, cache isolation, and representative applications.
Publish the migration and rollback instructions alongside the change.

If the compatibility contract cannot yet pass, finish Stage 3 and name the exact
Stage 4 blockers. Leave the default unchanged and report the rollout milestone as
unfinished. Physical retirement of an explicit legacy RC mode follows A10's checklist;
it is not demonstrated merely by zero-RC benchmark counters.

## Final acceptance checklist

- [ ] Correct main-derived lineage; all intended commits integrated; clean checkout.
- [ ] Existing transfer/lookup improvements preserved; no accidental explicit-copy removal.
- [ ] Separate parallel-map work adopted, with measured overhead and race/cleanup checks.
- [ ] Capacity tradeoff resolved by a measured decision, with peak and throughput evidence.
- [ ] Current 30-case census and expanded matrix published with stable denominators.
- [ ] Public library exports classified; all declared release APIs and applications pass.
- [ ] Five zero-RC pipelines covered: release, unoptimized debug, verified release,
      optimized debug, and release without facts. Ordinary RC controls remain distinct.
- [ ] Every admitted counted zero-RC run has no RC events and zero live managed bytes
      at exit; LLVM/native symbol/runtime ABI audits agree.
- [ ] Negative ownership cases refuse compilation; no fallback to RC.
- [ ] Cold, warm-stage, replay, invalidation, and nested-pattern scaling checks pass.
- [ ] Runtime, allocation traffic, peak managed memory, RSS, and compilation reported separately.
- [ ] Full required integration checks pass on the final source revision.
- [ ] Support/migration documentation matches the tested implementation.
- [ ] Default rollout status is explicit; normal command paths pass before promotion.
- [ ] Any remaining legacy RC mode and retirement work are explicitly identified.

## Reduced-slot execution order

If only three workers can run beside the coordinator, use these waves while keeping
the same responsibilities and handoffs:

| Wave | Workers | Purpose |
| --- | --- | --- |
| 1 | A01, A02, A03 | Parallel/capacity prototypes and baseline census |
| 2 | A04, A05, A06 | Library coverage and application migration |
| 3 | A07, A08, A09 | Combined soundness, cache/compile scaling, runtime/RSS measurement |
| 4 | A10, A03 follow-up, A09 follow-up | Rollout/docs and final-candidate evidence |

A failed check returns to its original owner. Waves are a capacity fallback, not a
claim of ten-way concurrency. Native build admission remains capped in either model.

## Copy-and-paste coordinator instruction

```text
Execute docs/audits/zero-rc-closeout-10-agent-plan-2026-10-11.md.

Start by verifying current main and integrating the already completed zero-RC
batch into a new isolated integration worktree. Freeze a common C0 revision.
Preserve the existing frozen compiler and historical reports.

Use one coordinator and ten workers A01-A10 when at least eleven total agent
slots are available. Otherwise report the actual limit and use the prescribed
three-worker waves. Give each worker its assignment, shared working contract,
exact base SHA, dedicated worktree, file ownership, and handoff requirements.

Adopt the existing separately assigned parallel.map work before replacing it.
Keep builds in the shared build-slot queue and serialize timing through A09.
Only the coordinator edits shared registration files and performs integration.

Carry the implementation through qualification and report default rollout as a
separate milestone. Preserve zero-RC checking and reject unsupported programs;
do not introduce lifetime syntax, silent RC fallbacks, or a zero-heap requirement.
Return the final commits, allocation census, runtime/RSS/compile-time results,
tests, migration guide, and any precise rollout or legacy-retirement blockers.
```
