# Memory-management closeout: ten-agent session handoff

Prepared 2026-10-12 against GitHub `eugenepentland/selka` branch `development`,
commit `fbfcaa7a923186a8e773c3760f81c10aa345a432`. This is an execution plan,
not a claim that the remaining work has passed qualification.

This supersedes the [11 October plan](zero-rc-closeout-10-agent-plan-2026-10-11.md).
The previous plan's initial merge is already complete. Use this document for a
new session, including on another machine.

## Intended result

Finish the move to compiler-checked memory management with no language/runtime
reference counting. Preserve fast runtime performance, simple local reasoning,
and bounded compilation work. Keep ownership and lifetime names out of the syntax.
Assignments and returns can move, ordinary parameters can borrow, `.copy()` makes
independent storage, views borrow, and scoped work joins before owners are destroyed.

Dynamic heap allocation, container growth, direct destruction, and task
synchronization remain valid. Zero heap allocations is not the goal. A task's
pending-work counter is not a memory reference count.

Deliver and report three milestones separately:

1. **Qualified implementation:** remaining improvements and coverage are integrated
   and measured on one reproducible compiler revision.
2. **Zero-RC default:** ordinary supported commands use checked ownership without
   an experimental flag; supported applications and libraries work through them.
3. **Legacy RC retirement:** current guest compilation/runtime paths no longer offer
   RC or copy-on-write sharing. A temporary compatibility mode is unfinished work,
   even when zero-RC is already the default.

The intended endpoint includes milestone 3. If a milestone is blocked, finish
independent work and report the specific reproducer and owner. Do not mark a
checklist or a prepared rollout patch as a completed implementation.

## Current state: preserve what already works

The prototype merged at `9225adeb0`; follow-up transfers, JSON borrowing and
timing admission merged at `441a96465`. Both are ancestors of the published base.
Do not merge their old branches again.

| Area | Current evidence / remaining distinction |
| --- | --- |
| Ownership | Checked moves/borrows, explicit deep copies, count-free guest ABI and direct destruction exist. Unsupported ownership shapes refuse compilation. |
| Allocation avoidance | Bounded caller construction, borrowing readers, repeated list replacement, and text/byte views exist. Preserve their positive and negative regressions. |
| Managed results | Owned `try`, fresh-match payload transfer, immediate whole-field unpack, ignored-field cleanup and recursive box-shell cleanup exist. |
| JSON | Lookup borrows the container and copies only the selected result. Misses add no managed allocations in the measured fixtures. |
| Parallel work | Source `parallel.map` exists and joins before returning. Current lowering/runtime still allocate capture, task and result storage per element. Optimize this; do not rebuild its API. |
| Libraries | Ten selected library fixtures pass after migration. That is not a complete public-export survey. |
| Compiler scaling | The repeated traversal of nested owned-match bodies was fixed; preserve the 64-level cache-key regression. Larger compile workloads remain to measure. |
| CLI rollout | Zero-RC is opt-in. Ownership docs list `build`, `run`, `check`, `dump-ir`; guest `test` does not accept the prototype flag. Audit dispatch and implementation, not just help text. |
| Census | The historical original corpus had 30 workloads: 23 allocating and 7 workload-allocation-free. These are not current post-batch counts. |
| Build scheduling | Shared build/gate admission and exclusive `timing` admission are implemented. Ordinary jobs can use allowed cores outside timing windows. |

Read these evidence sources in order; older reports describe earlier limitations:

- [Prototype and original 30-case results](../../experiments/zero-rc-final-20261011/README.md).
- [Library migrations and source parallel map](../../experiments/zero-rc-closeout-20261011/README.md).
- [Owned payloads and capacity tradeoff](../../experiments/owned-payload-20261011/README.md).
- [Latest JSON/field transfer batch](../../experiments/zero-rc-batch-20261011/README.md)
  and [integration evidence](../../experiments/zero-rc-batch-20261011/integration-validation.json).
- [Current ownership rules](../tooling/ownership.md),
  [runtime boundary](../../src/core/zero_rc.zig), and
  [parallel lowering](../../src/core/build_parallel.zig).

Preserve the measured JSON lookup improvements (391 to 3 allocations for the
128-sibling array and 520 to 3 for the object) and the migrated record-unpack
reduction (27,000 to 21,000 allocations per 1,000 unpacks). These are historical
workload-specific results. Do not reuse them as new measurements or infer RSS
savings from managed-memory counters.

## Scope and release contract

Keep the current source rules. Do not add Rust-style lifetime parameters, general
ownership inference across the whole program, or implicit RC fallback. New arenas,
shared/snapshot types, detached tasks, escaping task handles, general captured
closures, stored/escaping views, arbitrary partial record moves, and arbitrary
retained managed pointers through FFI are outside this closeout.

At kickoff, enumerate current public standard-library exports and relevant CLI
entrypoints from source. Classify each supported contract and each explicit
unsupported boundary. All previously qualified zero-RC examples, the original
30 census cases, ten migrated library fixtures, and four application shapes below
are mandatory regression coverage. Extend coverage to public APIs; do not silently
drop a failing export or application to make default rollout pass.

The RC-removal claim must identify its layer: generated guest programs, their
runtime, and installed language components. The compiler's Zig allocator is not
guest RC. Historical Git commits and immutable bootstrap seeds are historical
inputs, not code to rewrite. However, if installed Selka components are still
built with an RC seed/runtime, report that explicitly and resolve their packaging
or qualification before claiming the entire installed package is RC-free.
Coordinate that boundary with self-hosting work; do not silently repin its seed.

## Start from the right branch on any machine

Use the [new-machine setup guide](../tooling/remote-development.md) for the pinned
Zig distribution, sibling Guardian repository, environment, Git hooks and full
clone. The compiler on this line is still `mylang` and sources use `.my`.

GitHub `main` is an independently published Selka-branded snapshot. The separate
`codex/selka-bootstrap-20261011` and `codex/selka-entry-semantics-20261011` branches
are self-hosting work, not this memory-management base. Do not mix their pending
changes into this closeout merely because they are also on GitHub.

From a clean, configured clone, inspect status and create the integration branch:

```bash
git status --short --branch
git fetch origin
git switch -c codex/memory-closeout-20261012 origin/development
git merge-base --is-ancestor fbfcaa7a923186a8e773c3760f81c10aa345a432 HEAD
git merge-base --is-ancestor 441a96465 HEAD
git rev-parse HEAD
```

If that branch already exists or the checkout has edits, inspect it and choose
an unused branch/worktree name. Do not reset it. Record the resulting full SHA as
`C0`; if development advanced, summarize relevant differences before measuring.
Use explicit workdirs: the original machine's default `mylang` checkout was a
different branch from its local `main` worktree.

Create ten worker branches at exactly `C0`, with worktrees beside the integration
checkout so every tree resolves `../guardian-zig`. Example after recording `C0`:

```bash
MM_C0=$(git rev-parse HEAD)
MM_PARENT=$(dirname "$(git rev-parse --show-toplevel)")
for MM_AGENT in A01 A02 A03 A04 A05 A06 A07 A08 A09 A10; do
  git worktree add -b "codex/memory-closeout-20261012-$MM_AGENT" \
    "$MM_PARENT/mylang-memory-20261012-$MM_AGENT" "$MM_C0"
done
```

Source the setup guide's environment file separately inside each worktree. Keep
private `TMPDIR`, local Zig cache, output prefix and experiment directory per worker.
Keep installed `bin/`, `libexec/` and `tools/` together. Build a fresh baseline from
`C0` on the measurement machine; old absolute `.tmp` compiler paths are not portable
and old-machine timings are not paired controls for a new PC.

## Ten workers, one coordinator

The new session needs **eleven total agent slots: one coordinator and ten workers**.
A Markdown plan cannot raise the session's configured capacity. Check capacity
before launching. If fewer slots are available, report the limit and preserve these
ten assignments in waves; do not claim ten simultaneous workers.

The coordinator owns the integration tree, base/candidate identities, task dispatch,
shared-file reservations, conflict resolution and final verification. Each worker
gets its ID, this document, `C0`, worktree, owned files and evidence directory.
All ten can start immediately; final measurements depend on the integrated candidate.
Workers must not spawn additional agents, merge peer branches, push, or change
another worker's checkout. Give cross-owner requests to the coordinator.

Evidence root for this run: `experiments/memory-closeout-20261012/Axx/`.
Use `.tmp/memory-closeout/Axx/` for disposable build outputs. If these already
contain a different run, use a new run suffix rather than overwriting evidence.

| Agent | Primary assignment | Useful first work | Final dependency |
| --- | --- | --- | --- |
| A01 | Parallel-map scheduling/storage | Capture current allocation scaling; prepare chunked prototype | A07 review; A09 timings |
| A02 | Capacity and peak live memory | Reproduce retained-capacity peaks; compare bounded policies | A09 throughput/peak comparison |
| A03 | Allocation and RC census | Pin original 30 cases and migrations; capture C0 | Frozen integrated compiler |
| A04 | Text/JSON/codec/path library coverage | Enumerate owned exports; add executable contracts | A07 helper contracts if needed |
| A05 | Collections/resources/remaining library coverage | Enumerate remaining exports and ownership paths | A07 contracts; A10 command support |
| A06 | Applications and migration ergonomics | Fix datasets/checksums and baseline sources | A01/A04/A05 fixes |
| A07 | Ownership, cleanup and ABI correctness | Audit transfer/borrow boundaries; reproduce defects | Reviews A01/A02 and retirement |
| A08 | Compile time and cache correctness | Prepare cold/warm/edit cases and mode isolation tests | A10 mode plumbing; final compiler |
| A09 | Runtime/RSS measurements | Freeze methodology and baseline binaries | A01-A08 final artifacts |
| A10 | Command coverage, default rollout and RC retirement | Inventory flags/dispatch/test/package paths; start mode plumbing | Integrated coverage and qualification |

### Shared files and admission

Only the coordinator edits root `build.zig`, `build_test_inputs.zig`,
`build_verification.zig`, test-root registrations, `SPEC.md`, `src/features.json`,
`src/typed.zig`, `src/sema_statements.zig`, shared runtime headers and shared helper
declarations. Workers submit small patch requests with the exact contract and test.
Other files have one owner below. Unlisted files require a coordinator reservation.
Transfer a reservation explicitly when a later stage needs an existing owner's file.

All workers on one host use the same `MYLANG_SLOT_DIR`. Native concurrency follows
the host budget, not the number of agents. Start with the remote setup's conservative
build/job limits; the coordinator can tune one shared budget using measured memory.
Do not change slot counts independently or create private admission directories.

```bash
scripts/build-slot.sh build "$ZIG" build \
  -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
scripts/build-slot.sh build "$ZIG" build test-core -Dtest-filter='zero RC' \
  -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
python3 -B scripts/verify_cache.py --zig "$ZIG" -- \
  -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
```

The verification coordinator owns admission; **do not wrap `verify_cache.py` in
another build-slot command**. Use `gate` only for a direct full-gate command that
does not already own admission. Freeze inputs during verification.

A09 schedules timing windows with `scripts/build-slot.sh timing COMMAND...`.
Admission drains cooperating builds/gates and blocks new ones while measuring.
Pick an allowed CPU on the actual machine for serial tests; do not assume CPU 2
exists. Parallel tests retain enough CPUs for their worker matrix. Ordinary work
uses available cores outside these windows; `MYLANG_TIMING_CPUS` is optional.
Do not nest admission inside a harness that already owns it. Queue wait is not
compiler or guest runtime. See [many-agent tooling](../tooling/many-agents.md).

Run required hooks and Guardian checks. Do not append to or commit Guardian's
`FEEDBACK.md` unless the user explicitly requests it.

## Detailed assignments

### A01 — Parallel-map allocation and scheduling

Own `src/core/build_parallel.zig`, `src/core/runtime/core_tasks.c`,
`src/stdlib/parallel.my`, and new uniquely named A01 tests.

Check for an already completed external map-efficiency branch before implementing;
adopt its pinned commits if appropriate instead of duplicating active work. The
API already exists. Replace avoidable per-element capture/task/result wrappers
with bounded chunks or batches. Target scheduling storage proportional to workers
or bounded chunks; output storage and independently owned callback results can
still scale with input size. Preserve result order and mandatory joins.

Cover 0/1/many inputs, uneven chunks, 1/2/8 workers, cheap and expensive callbacks,
managed results, Results, nested maps and discarded output. Check borrow validity
through join and cleanup exactly once, including untaken results. Run the supported
ThreadSanitizer/task stress harness; report unavailable instrumentation explicitly.

Done when correctness and stress checks pass and scheduling allocation growth is
measurably lower. Separate output allocation costs from scheduler costs. Compare
before/after zero-RC with identical worker counts; ordinary RC's sequential map
is a correctness control, not proof of a memory-mode speedup.

### A02 — List/buffer capacity and retained storage

Own `src/core/runtime/core_rt.c`, `src/core/runtime/core_bytes.c`, and A02 tests.
Other runtime-header changes go through the coordinator.

Reproduce the owned-payload result where fewer copies retained spare capacity and
raised peak managed bytes. Compare small bounded growth-policy alternatives and
existing reserve hints on nested small lists, long append loops, repeated replacement,
clear/reuse and large buffers. Preserve the caller-destination/replacement wins.

Record length/capacity, allocation/reallocation counts, cumulative bytes, managed
peak, RSS and runtime. Test overflow/OOM boundaries through existing facilities.
Do not reintroduce deep copies or shrink every return merely to lower a peak.

Done when a policy is adopted with measured benefits and acceptable throughput, or
the current policy is retained with evidence and a concrete tradeoff decision.
Rejecting a performance experiment can close this item; it is not a claimed saving.

### A03 — Fresh allocation and RC census

Own A03 fixtures, adapters, manifests and reports; no production files.

Start from `experiments/rc-census-20261010/{REPORT.md,census.py,results.json}` and
the container/final/closeout migration maps. Preserve all 30 original case IDs.
Record original and migrated source identities separately. Add a distinct expanded
set for newer results, tasks, views, resources and the batch regressions.

For C0 and the final compiler, record admitted/refused status, output, workload
and whole-program allocations, bytes, managed peak/exit-live bytes, RC events and
structural audits. Classify remaining allocations as independent result storage,
growth, explicit copy, avoidable intermediate copy, task infrastructure or other
native storage. Do not subtract peak-memory observations as if they were traffic.

Adapt historical harnesses into A03: some write into historical directories even
with `--output`. Inspect writes before running; never overwrite old reports.

Done when the report answers separately: how many of the original 30 still allocate,
how many execute RC, how many are refused, and what residual costs are actionable.
Do not exclude failures from the denominator. Send production reproducers to owners.

### A04 — Text, JSON and codec APIs

Own `src/stdlib/{json,strings,path,base64,hex,byte_builder}.my`,
`src/core/runtime/core_text.c`, corresponding fixtures, and A04 tests/docs evidence.

Inventory every public export in these modules and its owned/borrowed contract.
Test dynamic inputs, Unicode/invalid encoding, empty values, nested parsing,
formatting, split/join, codecs, path operations and repeated calls. Preserve copies
needed for independent returns; remove only demonstrated intermediate copies.
Returned owners must survive input destruction/replacement; view invalidation and
escape must refuse. Coordinate byte storage with A02 and helper contracts with A07.

Done when every export is classified, in-scope contracts have runnable evidence,
encountered bugs are fixed, and each allocation change has a controlled comparison.

### A05 — Remaining libraries, containers and resources

Own remaining `src/stdlib/*.my` and fixtures except A01/A04 files;
`src/core/runtime/{core_dict.c,core_sort.c,core_io.c,core_host.c,core_durable.c}`;
and A05 tests/evidence. Reserve any additional provider files before editing.

Inventory collections/sorting, pools, random state, memo/persistent/durable storage,
numeric helpers and environment/filesystem/network wrappers. Exercise managed
children, dictionary/set extraction and replacement, explicit generator copies,
borrowed sort input, independent output, valid pool handles, provider cleanup and
resource early/error exits. Use deterministic injected/local providers for tests.

Do not whitelist a native helper merely because a fixture needs it: audit the
complete ownership path with A07. Preserve persistence semantics and snapshot
independence using explicit owned copies where the existing contract requires them.

Done when all remaining public exports are classified and the release contracts
pass. Unresolved resource/persistence correctness failures block rollout.

### A06 — Realistic programs and local reasoning

Own new A06 programs/datasets and migrations in `examples/python-word-count/`,
`examples/domain-codecs/`, `examples/external-capabilities/`, and
`examples/generic-resources.my`. Reserve any other existing example first.

Qualify at least four shapes: text/word counting, nested JSON or domain-codec
transformation, resource-backed file processing, and useful parallel computation.
Include a multi-module combination. Freeze generated data seeds, sizes and expected
checksums; use both small correctness cases and larger performance inputs.

Keep original/migrated source pairs. Count changed lines, explicit copies and
surprising diagnostics. Exercise early/error paths and repeated use. Prefer the
smallest locally understandable migration; route language/library defects to owners.

Done when programs pass without RC fallback or managed leaks and source burden is
documented. Different source semantics must not be presented as a compiler-only win.

### A07 — Ownership soundness, cleanup and runtime ABI

Own `src/core/{single_owner.zig,single_owner_copy.zig,build.zig,own.zig,emit_llvm.zig,emit_homes.zig,verify_ir.zig,zero_rc.zig}`,
`src/core/runtime/core_owned_copy.c`, and A07 regressions. This is the Core
`build.zig`, not the coordinator-owned root build file.

Audit moves, mutable writebacks, borrowed views, `try`, fresh match, whole-field
unpack, ignored fields, recursive/wide boxes, resources and task results. Regress
concrete defects at early return, propagation, break/continue, owner replacement,
duplicate move and wrong-ABI boundaries. Cover negative escape/invalidation cases.

Review A01/A02 changes and all new runtime helper contracts. Require agreement
between source checks, IR, emitted LLVM, runtime layout and linked-symbol audits.
Zero runtime RC events alone is insufficient: count operations/fields and legacy
helpers must be structurally absent from the selected runtime.

Done when reported safety defects are fixed with regressions and unsupported shapes
fail clearly. During retirement, remove legacy ownership/emission paths in owned
files and audit the final ABI with A10 and runtime file owners.

### A08 — Compilation and cache correctness

Own `src/core/{lowering_cache.zig,optimization_cache.zig,emission_cache.zig}`,
`src/semantic_store.zig`, `src/semantic_copy.zig`, and A08 cache/scaling tests.
Coordinate test-runner receipt changes with A10.

Test cold caches, warm stages, whole-build replay, source relocation, small valid
and invalid ownership edits, dependency changes and runtime/ABI invalidation.
Alternate RC/zero-RC requests while both modes exist. After retirement, old RC
artifacts and receipts must be invalidated or refused, never adopted as zero-RC.

Measure increasing match depth/field counts, recursive types, modules and generic
instantiations. Preserve the 64-level regression. Separate checking, lowering,
optimization, emission and native compilation where supported; keep eager ownership
checks. Run timings under A09's schedule with matched cache states.

Done when cache safety passes and cold/warm/edit scaling is measured. Fix concrete
superlinear behavior; do not add speculative lifetime analysis for hypothetical wins.

### A09 — Performance and memory evidence

Own A09 measurement harnesses and the combined report; no production changes.
Own the team's measurement schedule. Freeze a complete C0 compiler installation
and build a separate candidate; record source and binary hashes for each.

Measure allocation traffic/reallocations, cumulative bytes, peak live managed bytes,
exit-live bytes, uninstrumented guest wall time, process RSS and compile time.
Managed counters omit some metadata, provider buffers, task stacks and allocator
overhead. Identify whether RSS includes child processes; use process-tree/cgroup
measurement where needed for builds, and document availability/limitations.

Use at least two warmup pairs and nine alternating measured pairs for runtime.
Keep instrumentation off timing binaries. Lengthen tiny workloads, publish all
samples/ranges and input sizes, and report noisy results without a speedup claim.
Investigate repeatable slowdowns over 5%; this is a review trigger, not an automatic
failure threshold when noise exceeds the difference. Do not compare old-host
baselines with new-host candidates or C0 cold builds with candidate warm builds.

Done when the final report distinguishes all metrics, explains regressions and
rejected experiments, and uses exact final artifact identities. Requalify affected
cases after default/retirement changes; do not relabel an earlier binary's results.

### A10 — Command paths, migration, default and legacy retirement

Own `src/core/{cli.zig,cli_args.zig,main.zig,check_command.zig,cli_run.zig,test_runner*.zig}`,
`docs/managed-memory.md`, `docs/tooling/ownership.md`, new migration docs and A10
command fixtures. Reserve additional top-level dispatch/config/package files with
the coordinator. Source mode selection crosses more than one command parser.

Start immediately with a command matrix: build/run/run-project/check/dump-ir/test,
directory and cached tests, doctest/example execution, installed invocation, and
other paths that compile or execute guests. Add explicit zero-RC guest-test support
and propagate ownership/ABI selection through discovery, workers, execution and
receipts. Verify source refusal and cleanup in cold and cached commands.

Prepare separate commits for command support, default promotion, and retirement.
Use A04/A05 exports and A06 applications for the support/migration matrix. Explain
moves, borrows, explicit copies and scoped parallelism with runnable examples.
Keep normal compiler development and component builds working through the change.

Inventory active RC selection, retains/releases, count fields, uniqueness/COW paths,
generated helpers, flags, tests and package contents. A07 and runtime owners remove
their portions after the default qualifies; A08 changes persisted identities.
Migrate current tests/examples; preserve frozen historical comparisons. Retire any
temporary compatibility selector and reject retired flags clearly. Rollback uses
a prior commit/release, not a hidden fallback on an ownership error.

Coordinate seed/component packaging with its existing owner. Do not merge the
separate bootstrap branch or change immutable seed history as an incidental fix.

Done when ordinary commands use zero-RC, installed artifacts and caches agree,
legacy guest RC selection/implementation is retired, migration docs match tested
behavior, and any RC retained in bootstrap tooling is precisely accounted for.

## Integration stages

### Stage 0 — Baseline and dispatch

Verify the published base and ancestor checks, tools, Guardian pin and actual agent
capacity. Freeze C0 and the release inventory. Create the coordinator/worker trees.
A09 builds the frozen C0 installation; A03/A06 prepare baseline workloads. Launch
all ten assignments once worktree and file ownership are recorded.

### Stage 1 — Parallel implementation and early feedback

A01/A02 prototype the bounded performance changes. A04/A05 migrate APIs while
A06 prepares applications. A07 audits/fixes soundness. A08 tests cache/scaling.
A03/A09 collect controlled baselines. A10 fixes command coverage and drafts rollout.
Send reproducers early; do not wait until final measurement to reveal unsupported APIs.

### Stage 2 — Integrate a qualified opt-in candidate

The coordinator integrates shared contracts/A07 safety fixes, A08 correctness fixes
and A10 command support first, then A01/A02 and A04/A05 changes, followed by A06
migrations. Respect actual dependencies; independent small commits can land earlier.
Workers rebase or test integration conflicts only under coordinator direction.

Freeze candidate C1. Run the combined focused checks, then the complete verification
coordinator and Guardian requirements. A03/A06/A08/A09 run final qualification on
that compiler. A performance policy can be rejected with evidence; a safety or
in-scope support failure remains a blocker. Record milestone 1 separately.

### Stage 3 — Promote the normal command behavior

Apply A10's isolated default change after the release inventory passes. Verify
normal commands without the experimental flag, installed layout, ABI choice,
negative diagnostics and cache isolation. Rerun affected applications and evidence
against C2. Record milestone 2 only after the actual default changed and passed.

### Stage 4 — Retire active RC implementation and close out

A10 coordinates deletions with A07 and each runtime owner; A08 handles artifact
invalidation. Preserve required direct-destruction and task synchronization code.
Audit active sources, generated LLVM, preprocessed runtime, symbols and installed
artifacts. Searches are an inventory aid: classify matches instead of deleting
every occurrence of words such as `count`, `release` or `snapshot`.

Freeze C3 and run required final checks. Publish fresh allocation/runtime/RSS/compile
results for affected paths and a clear package/bootstrap boundary. Milestone 3
requires the removal itself, not only a retirement checklist. Keep blockers visible
if self-hosted installed components or language coverage prevent completion.

The coordinator prepares final reviewable commits on the integration branch.
This handoff does not by itself authorize pushing, changing GitHub `main`, or
merging the independent self-hosting branch. Existing session authorization still
applies; otherwise request publication approval only after the tested result exists.

## Required evidence and completion checks

Each Axx directory must include `handoff.md` with base/proposed commits, owned files,
change/reproducer, test commands and statuses, source/compiler hashes, raw evidence
paths, shared-file requests and unresolved issues. Include applicable before/after
metrics and the exact candidate that must consume or rerun the evidence.

The coordinator maintains an item ledger and final `README.md` plus machine-readable
results under `experiments/memory-closeout-20261012/`. Each item is shipped,
measured tradeoff, or blocked with an owner and reproducer. Never count a correctness
blocker as a measured tradeoff.

- [ ] Correct development lineage, clean integration checkout and exact final SHAs.
- [ ] Existing transfer, borrowing, explicit-copy and stack/replacement regressions pass.
- [ ] Map overhead reduced or a concrete measured blocker remains; race/cleanup checks pass.
- [ ] Capacity policy has a measured adopt/reject decision.
- [ ] Original 30-case denominator, expanded corpus and current allocation/RC counts recorded.
- [ ] All public exports classified; mandatory APIs and four application shapes qualified.
- [ ] Release, unoptimized debug, verified release, optimized debug and release without
      facts covered by the affected zero-RC matrices.
- [ ] Counted admitted runs preserve results, have zero RC events and no managed leaks;
      structural ABI/LLVM/symbol checks also pass. Refusals remain in the inventory.
- [ ] Cold/warm/replay/edit and old-artifact invalidation checks pass; scaling is measured.
- [ ] Runtime, managed peak, RSS, allocation traffic and compilation reported separately.
- [ ] Complete registered test/fmt verification and required Guardian checks pass on
      final inputs. Record reused/fresh actions; focused tests do not replace this gate.
- [ ] Normal command paths and guest tests select checked ownership without opt-in.
- [ ] Active guest RC/COW implementation and selectors retired; package/bootstrap
      exceptions or blockers stated explicitly.
- [ ] Migration guide, support matrix and final report reflect the actual implementation.

If only three workers can run alongside the coordinator, use A01/A02/A03 first,
A04/A05/A06 second, A07/A08/A10 third, then A09 with A03/A06 follow-ups. Revisit
the original owner for failures. This is a capacity fallback, not ten-way execution.

## Paste this into the new session

```text
Execute docs/audits/zero-rc-closeout-10-agent-plan-2026-10-12.md.

Use one coordinator plus ten parallel sub-agents A01-A10 if this session provides
at least eleven total slots. Check actual capacity and report any limitation.
Do not spawn extra nested agents. Use a separate worktree for each worker.

Start from origin/development in eugenepentland/selka and verify the documented
ancestor checks. The earlier zero-RC batch is already merged. Do not start from
GitHub main or the independent self-hosting branches. Freeze a shared C0 and
rebuild the baseline on this machine using the published pinned tools.

Give every worker the plan, its assignment, base SHA, worktree, file reservations
and evidence path. Start all ten on their independent first tasks. Keep native
builds in the shared admission queue; let A09 schedule exclusive timing windows.
Run verify_cache.py directly because it owns admission. Only the coordinator
integrates shared files and worker commits.

Carry the work through qualified implementation, zero-RC default and active legacy
RC retirement. Report those milestones separately. Keep ordinary heap allocation
allowed, ownership/lifetime annotations out of syntax, and unsupported ownership
shapes explicitly rejected. Do not introduce an RC fallback or shrink coverage
to make a gate pass. Preserve local reasoning and bounded compile work.

Return tested commits, the fresh 30-case census and expanded results, library and
application coverage, allocation/runtime/RSS/compile-time comparisons, migration
instructions and precise blockers. Do not claim completion while active legacy
guest RC remains. Follow the plan's package/bootstrap boundary and publication rules.
```
