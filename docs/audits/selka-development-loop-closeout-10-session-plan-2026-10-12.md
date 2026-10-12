# Selka development-loop closeout: coordinator plus ten sessions

Prepared 2026-10-12. This is an execution handoff for one coordinator and ten
worker sessions, S01–S10. It closes the remaining development-loop work in
[DL1–DL8](selka-development-loop-plan-2026-10-11.md). Cache waves 1–11 already
landed; do not restart them or create a competing compiler port.

## Checked baseline and changes since the last pass

This document was prepared after `git fetch origin`, from a clean worktree
updated to local `main` at:

```text
fbfcaa7a923186a8e773c3760f81c10aa345a432
```

At that check, `origin/development` matched local `main` exactly. GitHub's
`origin/main` is a separately published snapshot, not this development lineage.
Follow [remote development](../tooling/remote-development.md) when refreshing a
clone; do not merge the published snapshot into development merely because both
are called main. Recheck these refs before starting execution.

Fourteen commits landed after development-loop qualification `af2fb3e8e`:

- Owned Result/Option and fresh-match payload transfers, whole-record field
  transfers, and narrower JSON container borrowing.
- Linear hashing of owned match bodies in the lowering cache, with its scaling
  regression, and allocation-failure fixture isolation.
- Exclusive timing admission in `scripts/build-slot.sh`, the new
  `scripts/build_admission.py`, and updated benchmark harnesses. Ordinary jobs
  now use all allowed CPUs by default. Timing windows drain cooperating jobs.
- Admission tests added to verification, revised declared inputs, the
  [zero-RC ten-agent closeout plan](zero-rc-closeout-10-agent-plan-2026-10-11.md),
  and remote development setup documentation.

Preserve these changes. This team owns development-loop costs and cache
contracts; the memory-management team owns lifetime/ownership semantics,
allocation algorithms, scoped parallel scheduling, and default-mode rollout.
Their compile/cache and measurement lanes overlap our interests, so exchange
fixtures and manifests through the coordinator instead of implementing both.

The self-hosting branch was inspected at:

```text
codex/selka-bootstrap-20261011
dff9304b9cd7bc72e66f9feb20f1b05281d67333
```

That is a snapshot, not permission to edit its active checkout. Its performance
policy still requires every required workload's median and p95 to be at most
1.5 times the frozen Zig reference. Existing partial component results do not
establish that acceptance or completion of the compiler port.

### Immediate configuration qualification follow-up

The current configuration differs from the reviewed fingerprint in
`scripts/verify_cache.py`:

| Item | SHA-256 |
| --- | --- |
| Checked-in qualification | `7cefed8043b05279aa8960b33ea742e728f91dfc294d08c6e48d7b4a0a8fd6fc` |
| Observed configuration on this worktree | `c696349b2eee64e99a877a424ba3189667d9e2db5da8d04715c351455a360e92` |

The mismatch conservatively disables declarative input-list projection. The
inventory still has group-local membership contracts; this is specifically the
configuration/input-list boundary, not a cache corruption finding. Computing a
new digest does not qualify it. The coordinator and S04 must review all consumers,
update regression evidence, and explicitly qualify the final configuration.
Repeat this review after later build-wiring changes; never auto-refresh the pin.

## Starting point and honest completion criteria

Already implemented and qualified on the previous revision:

- Named action members, invalidation explanations, optional admitted-command
  deadlines, process-tree cleanup and retained verification sessions.
- A pure Juice cohort and an independent native tooling root with 27 named tests
  plus its import-root test; conservative group-local action contracts.
- Bounded advisory calibration, with incompatible, failed and incomplete evidence
  excluded. Hard deadlines are not inferred from descriptive suggestions.
- A complete gate and four unchanged requests: 34 of 45 groups reused, zero warm
  file hashing/enumeration, and roughly 28–37 seconds of warm gate occupancy.

Those counts and durations belong to the
[previous qualification](../../experiments/development-loop-boundaries-20261011/REPORT.md).
Main has since changed build registration and compiler behavior. Re-export the
inventory and measure current main; do not copy old counts or promise the same
latency. The previous run also left a source-stability rejection unexplained;
S01/S08 should make future failures identify the invalidated input or authority.

There are two separately reported delivery milestones:

1. **Development-loop closeout:** finish DL1–DL6 and qualify them with DL8 on the
   current compiler. Ordinary named edits should receive useful checked feedback
   within 5 seconds and meet the proposed 15-second p95 target, or remain visibly
   unmet with a concrete follow-up. These targets are not automatic watchdogs.
2. **Self-hosting integration closeout:** finish DL7 as qualified milestones arrive,
   repeat DL8, and preserve the port's full correctness/bootstrap/performance
   requirements. If the other branch is not ready, this milestone remains open.

A scaffolding-only producer API, an unmeasured optimization, or a quick profile
that omits required tests cannot close its wave. Report requirements as passed,
failed, or not qualified. Do not label the entire roadmap complete while a
required milestone is still open or a target has merely been deferred.

## Coordinator startup

1. Read applicable `AGENTS.md`, `CLAUDE.md`, this plan, the DL roadmap, and the
   latest memory-management and bootstrap ownership documents. Inspect worktree
   status before switching or merging anything.
2. Fetch configured remotes. Reconcile the development tracking ref and local
   `main` without resetting either. Pin the actual integration base as `C0`,
   record its full SHA, and preserve a baseline build and its source/tool hashes.
3. Use a clean merged worktree or a separate integration worktree. The usual
   main checkout is `/home/epentland/ai/canopy/mylang-debug-speedup-main`;
   `/home/epentland/ai/canopy/mylang` is another branch. Discover the live worktree
   mapping rather than assuming either path is free to edit.
4. Refresh the bootstrap branch and identify the active memory-management owner.
   Record file ownership, current mode/ABI contracts and pending changes. If an
   owner is unavailable, continue on independent work and prepare patch requests
   for shared files; do not silently take over their branch.
5. Ask S10 to freeze baseline workloads/cache conditions and arrange baseline
   qualification. Export the real action inventory; account for every required
   action and label. Establish exact producer, telemetry and profile contracts
   with S01/S02/S04/S05 before editing shared integration points.
6. Create one branch/worktree per worker at `C0`, named for its Sxx assignment.
   Maintain a coordinator-owned `status.md` in
   `experiments/development-loop-closeout-20261012/`, with base, owner, claimed
   files, proposed commits, dependencies, evidence, and outstanding requirements.
7. Keep a qualification candidate frozen while tests or measurements use it.
   Workers continue in their own worktrees; later changes create a new candidate.

### Actual parallel capacity

Use **one coordinator plus ten worker sessions**, preferably Sol 6.1 as requested.
Ten workers may read, implement and prepare evidence concurrently. Native builds,
gates and measurements still follow the machine's admission limits.

This authoring session has four total agent slots, including the coordinator.
Ten concurrent workers require eleven available slots, or ten independently
opened worker sessions plus the coordinator with this shared ownership ledger.
If capacity is smaller, keep the ten assignments and execute them in batches.
Do not claim ten-way concurrency or bypass an orchestrator limit. Nested workers
count against the same total; workers should not create untracked subteams.

A useful three-worker fallback is S01/S03/S08, then S02/S04/S07, then
S05/S06/S09, followed by S10 and implementation follow-ups. S10's baseline
specification can be prepared by the coordinator before the first batch.

## Shared ownership and operating rules

The coordinator is the sole writer for:

- `build.zig`, `build_test_inputs.zig`, `build_verification.zig`,
  `build_identity.zig`, `guardian.toml`, `SPEC.md`, and existing test-root imports.
- `scripts/verify_cache.py`, `scripts/verify_cache_test.py`,
  `scripts/cache_session.py`, and `scripts/cache_session_test.py`.
- Final inventory/schema changes, common CLI wiring, source/configuration pins,
  final roadmap/user documentation, and the integration ledger.

Workers own the files below plus uniquely named tests and
`experiments/development-loop-closeout-20261012/Sxx/`. A proposed filename is a
new module, not a claim that the module exists today. S03 publishes its exact
existing-test file claims before moving them; S07 and S09 similarly confirm
component harness ownership. Read access is unrestricted. Shared-file changes
are small patch requests with a caller contract, dependencies and tests; the
coordinator applies them serially. A worker may own an integration file later
only after the ledger transfers exclusive ownership.

Compiler driver, test receipt, runtime/ABI, frontend and self-hosting manifest
changes need a joint ownership decision with the existing workstream. No worker
changes language ownership rules, default memory mode, Zig pin, or Guardian
implementation as an incidental speed optimization. Request necessary upstream
runner instrumentation through the coordinator.

Operational requirements:

- Use the repository-pinned Zig, a private `ZIG_LOCAL_CACHE_DIR` per worktree,
  a worktree-local on-disk `TMPDIR`, and the shared Zig global cache. Never share
  mutable local compiler caches across different compiler generations.
- Significant builds and focused native tests use `scripts/build-slot.sh build`;
  complete native gates use `gate`. The verification coordinator owns admission:
  run `scripts/verify_cache.py` directly, without a wrapping slot.
- S10 schedules bounded timing windows through `build-slot.sh timing`. Prepare
  binaries under build admission first; put measured compiler invocations inside
  timing admission. Harnesses that already own admission run directly. Do not
  request timing while holding build/gate admission, reserve raw lock files,
  raise slot limits, or create a private production slot directory.
- The current default is all allowed CPUs for ordinary jobs. Do not restore the
  old permanent CPU reservation accidentally. Record any explicit CPU pinning.
- Use cache leases/pins for frozen artifacts and private cold experiment stores.
  Do not clear shared caches to manufacture a cold result or stop other jobs.
- Keep timeouts, crashes, source mutation, missing inputs and incomplete coverage
  fail-closed. Preserve effect eligibility, negative dependencies, transitive
  imports, directory membership, seed authentication and publication checks.
- Keep installed commands and ordinary source builds Python-free. Python developer
  telemetry and qualification tools may remain Python.
- Run meaningful focused checks and normal commit hooks. Required complete
  verification belongs to each frozen integrated candidate; do not launch ten
  redundant full gates for one candidate. Do not treat a filtered pass as a gate.
- Guardian feedback entries/commits are not required. Do not modify
  `~/ai/canopy/guardian-zig/FEEDBACK.md` without an explicit user request.
- Workers commit their changes and report exact SHAs. Only the coordinator
  integrates them; no worker merges main, pushes, rewrites peer history, or
  changes another worktree. Publishing or updating main follows the user's
  authorization for that execution session.

## Ten worker assignments

| Session | Main responsibility | Waves | First independent deliverable |
| --- | --- | --- | --- |
| S01 | Test/action telemetry and failure explanations | DL1 | Event schema, coverage audit, failing-input diagnostic contract |
| S02 | Calibrated limits and cancellation | DL2 | Policy schema and process-lifecycle adversarial cases |
| S03 | Independent native test boundaries | DL3 | Import/fixture closure inventory and proposed executable split |
| S04 | Qualified producer identities | DL4 | One concrete independent producer and dependency contract |
| S05 | Quick/complete/qualification profiles and work budgets | DL6 | Coverage-preserving profile plan and report contract |
| S06 | Fresh language-test execution cost | DL5 | Profile of startup, discovery, compilation and execution |
| S07 | Expensive fixture and component/golden setup | DL3, DL5 | Repeated-work inventory and immutable fixture design |
| S08 | Retained snapshot validation overhead | DL1, DL5 | Metadata/watch cost breakdown and rejection diagnostics |
| S09 | Self-hosting integration and ownership handoff | DL7 | Refreshed stage/ABI/seed matrix and overlap ledger |
| S10 | Independent correctness/performance qualification | DL8 | Frozen edit matrix, baseline harness and timing schedule |

All ten can begin their first deliverable at `C0`. Final integration and acceptance
follow dependencies; the table is not an instruction to run ten full gates at once.

### S01 — Complete observability

**Own:** `scripts/verification_report.py`, its tests, and new telemetry/collector
helpers and fixtures. Coordinate process hooks with S02 and snapshot diagnostics
with S08; request coordinator/report wiring rather than editing their files.

Deliver stable action/member/test identifiers, phase boundaries, selected/reused
counts, and available process CPU/RSS observations. Capture individual test times
through a supported runner contract, not by treating only slow-test messages as
complete coverage. Distinguish per-process peak RSS from aggregate concurrent
memory. Unsupported observations remain explicitly unknown.

Define bounded events for invalidation and failed stability checks: snapshot role,
path or host facet, event/metadata reason, and truncation/unknown status. A file
restored to its old bytes must still invalidate authority. Diagnostic generation
must neither clear dirty state nor turn an incomplete result into a pass.

**Accept:** every current action is represented; selected test timing coverage is
explicit; nested durations are not summed as wall time; malformed/truncated output
and absent telemetry are tested; enabling diagnostics preserves selection, output
and reuse. Deliver the schema to S02/S05/S10 before those consumers stabilize.

### S02 — Qualified budgets and reliable cancellation

**Own:** `scripts/verification_budgets.py`, `scripts/verification_process.py`, their
tests, and a proposed versioned policy module/data file. Common CLI/build adapters
remain coordinator-owned; timing admission changes also need coordinator review.

Keep expected cost, regression threshold, hard deadline, memory ceiling and work
ceiling separate. Build/setup, whole action and individual test scopes need
unambiguous clocks. Start enforced execution limits after admission; represent
queue/user cancellation separately. Preserve ownership of child/grandchild trees,
cleanup, reaping, claim release and another subscriber's still-needed work.

Use S01 events and S10's current compatible samples. The old five-sample advisory
suggestions are not calibrated hard deadlines. Retain report-only rollout until
normal and adverse cases justify an explicit policy. Legacy expensive actions
need named exceptions and review points; never relabel a slow test automatically.
Implement justified per-action controls without serializing the entire existing
build graph or starting a separate full build for every member.

**Accept:** CPU loop, blocked child, detached grandchild, interrupted build,
timeout during publication and concurrent subscriber cases recover correctly.
Incomplete work publishes no success. Limit changes affect execution identity;
advisory-only changes reuse compatible captures. Enforced policies have archived
headroom evidence and do not hide regressions by raising ceilings.

### S03 — Split the remaining broad native test roots

**Own:** new native test roots and their exact claimed test modules; pure helper
extraction only where its complete dependency closure is established. Existing
root imports, build registration, input recipes and Guardian roots go through
the coordinator. Share fixture/helper changes with S07 before claiming them.

Inventory `src/root_test.zig`, `src/core/root_test.zig` and `test/integration.zig`.
Select the next expensive independent boundaries from actual imports and files
read: pure units, compiler integration, CLI packaging and cold qualification.
A new shard of the same executable is not an independent implementation identity.
Do not split into hundreds of tiny binaries that duplicate compiler compilation.

Remove unnecessary broad recipe inheritance only after proving the narrower
closure, including generated and embedded inputs. Coordinate migrations of
eligible guest-behavior tests with the active port; retain host/trap/diagnostic
assertions. Preserve the existing pure tooling root and no-match filter behavior.

**Accept:** exact named-test inventory parity, added/deleted/renamed fixture
coverage, and responsible-only invalidation for qualified test/fixture edits.
Show unrelated compiler edits preserve independent pure roots. Measure both warm
edit benefit and cold compile/link/RSS cost with S10; reject harmful oversplitting.

### S04 — Narrow producer identity with a real adopted boundary

**Own:** `scripts/verification_artifacts.py`, new producer-manifest/identity helpers
and tests, and candidate producer contracts. `build_identity.zig`, coordinator
identity code and component manifests are shared integration changes.

Start with one independently built tool/component with a complete source/import,
generated-input, seed/build-recipe, runtime/ABI, flag, tool and protocol closure.
Use S03's boundaries and S09's authenticated component inventory. Preserve the
whole-compiler fallback for everything not proven independent.

Distinguish producer implementation, interface/schema and consumed input data.
An unchanged wire format does not make a changed checker interchangeable. Carry
qualified identities into compiler artifacts, test evidence, fuzz campaigns and
performance captures through their existing stores; coordinate adapters with S05.
Preserve main's owned-match hashing and all ownership/ABI invalidation inputs.

Audit the configuration projection with the coordinator now and after final
wiring. Recompute only after reviewing its consumers; arbitrary build code must
continue to invalidate broadly. Never replace dependency proof with a hand-edited
version, directory name, heuristic test selector, or function-name match.

**Accept:** adopt at least one real boundary end to end, not just a manifest API.
Independent edits preserve unrelated results; a transitive semantic change that
turns a pass into failure executes and fails. Test mode/ABI/seed replacement,
mutation during lookup/publication, schema change, missing metadata, revert and
second-worktree reuse. Version changed identity contracts and retain fallback.

### S05 — Supported feedback profiles, fuzz and performance work budgets

**Own:** proposed `scripts/verification_profiles.py` and tests;
`scripts/fuzz_campaign.py`, `scripts/juice_cache.py` and their adapter tests where
needed. Do not rewrite existing claim/retention stores. Common verification and
session dispatch remain coordinator-owned.

Define explicit quick, complete and long-qualification profiles over one action
inventory and one dependency model. Quick mode schedules relevant inexpensive
checks first and reports required work still outstanding. Heuristic selection
must be visibly partial. Complete mode accounts for every current required action
through valid evidence or execution; long qualification never waives that gate.

Use S02's controls and S04's identities. Add representative compiler/test-driver
workloads to existing Juice handling with output, completed-work and repeatability
checks. Preserve threshold-only reevaluation of compatible evidence. Fresh timing
requests remain fresh; instruction counts cannot satisfy a wall-clock ratio gate.
Extend existing fuzz case/work/time controls only where gaps remain. Exhaustion
reports partial coverage, never a completed full campaign.

**Accept:** cold/warm/edited sessions and equivalent one-shot commands agree on
coverage and results. Quick mode cannot issue a complete-verification success.
Broad semantic edits get a visible larger plan. Corrupt/missing/insufficient
perf or fuzz evidence is handled conservatively; defaults and CLI docs match
actual behavior and regression enforcement has a report-only qualification phase.

### S06 — Reduce work in fresh guest-test actions

**Own after overlap review:** `src/core/test_runner_directory.zig`,
`test_runner_batch.zig`, `test_runner_discover.zig`, `test_runner_work.zig`, and
uniquely named runner tests/fixtures. Receipt semantics, frontend selection,
`src/core/test_runner.zig` and bootstrap-touched entry points remain joint changes
through S09 and the coordinator. Memory/runtime/IR files stay with their owners.

Profile mandatory language actions by discovery, startup, frontend work, native
build/link and execution. The earlier release/fact/leak member had an observed
12-second median; that is a lead to remeasure, not the new baseline or a promised
saving. Batch or reuse immutable preparation where safe, avoiding per-test
process/compilation work that the current contracts do not require.

Keep external effects and qualified-seed checks fresh. Fact/leak and forced runs
must really execute as specified. Preserve test identity, exact mode/count
accounting, source mutation checks, no-cache controls, isolation and crash cases.
Do not optimize away the assertions that make this group expensive.

**Accept:** selected fresh actions perform less measured work with identical
results, fact/leak coverage and failure behavior. Compare cold, warm and edited
projects, with no startup costs hidden outside the reported developer loop.
S10 supplies isolated latency results. If bootstrap owns a needed file, prepare
the measured reproducer and patch request while continuing independent changes.

### S07 — Reduce repeated golden/component fixture preparation

**Own:** `test/golden_parity.zig`, new uniquely named fixture helpers/tests, and
component-harness patches only after S09/coordinator assigns those files. Audit
`selfhost/test_components.py`, `selfhost/test_component_native.py` and related
qualification drivers; the port may already be changing them.

Separate pure corpus/codec/report work from live qualification where declarations
prove independence. Investigate duplicate compiler launches, identical fixture
preparation, small compile/link calls and serialization. Share immutable prepared
inputs; keep fresh mutable state for corruption, bootstrap, cold-cache, allocation
failure and recovery tests. Preserve main's allocation-failure fixture isolation.

Golden corpus filenames containing `qbe` are historical data names; execution
still uses the current Core/LLVM backend. Do not restore the retired backend.
Compare exact selected cases, outputs and diagnostic assertions before/after.
Hand narrowed recipes to S03 and authenticated producer needs to S04/S09.

**Accept:** measured preparation/startup work decreases for identified expensive
actions without shrinking case inventories. Cold controls remain cold at the
specified cache tiers; live component authentication stays fresh. Document and
measure additional artifact size, cold cost and RSS if fixtures are retained.

### S08 — Reduce retained-session validation cost safely

**Own:** `scripts/verification_snapshot.py`, its tests, and new snapshot profiling
fixtures. Session runtime guard/protocol and coordinator changes are patch requests.

Explain the retained session's metadata work. The prior warm request performed
175,677 metadata observations despite zero hashing/enumeration; quantify the new
baseline before optimizing. Review repeated validation, equivalent live snapshots,
provider resolution and bounded inventory reuse. Preserve one-shot correctness.

Implement S01's dirty-reason contract with bounded records for watcher events,
metadata differences, missing-path changes and unavailable authority. Consider
consolidating proven redundant checks or live watches without persisting
metadata-only proof or extending authority after a watch is lost. No daemon is
required; a compiler AST service is outside this lane's remit.

**Accept:** deterministic counter reductions on selected warm/edited workloads;
unchanged hashing/enumeration remain zero where qualified. ABA edits, symlink
retargeting, membership changes, PATH shadowing, event overflow, reset, fork,
eviction and active borrowers remain safe. Keep memory/watch/fd bounds, exercise
host changes, and report unsupported causes as unknown instead of accepting them.

### S09 — Integrate the existing self-hosting work

**Own:** the refreshed bootstrap handoff, new bridge qualification fixtures,
producer/seed contract documents, and accepted stage integration patches. The
other workstream continues to own its compiler port and active worktree. Existing
selfhost source/manifests and core runner identity changes need an explicit
coordinator ownership transfer before either side edits them.

Refresh the branch from the SHA above and inventory qualified versus incomplete
stages, mode flags, ABI/schema versions, embedded inputs and external seed receipts.
Bring S04's producer contracts and S01/S02 telemetry/budgets to each adopted stage.
Use existing parity/bootstrap harnesses; do not start a second lexer/checker/backend.

Reconcile admission before measuring: the inspected bootstrap performance guide
still describes a legacy gate-FD/reserved-CPU launcher, while main now has exclusive
timing windows. Arrange one compatible launcher migration with the port owner,
preserving authentication and measurement provenance. Do not nest old gate locks
inside new timing admission or silently waive the harness's required controls.

**Accept:** qualified adopted stages demonstrate source edits rebuilding the
responsible work with a valid seed, correct diagnostics/behavior/facts/leaks,
stale-result rejection and no silent native fallback. Preserve Python-free source
builds/installed commands. Full compiler acceptance still needs complete ownership,
seed→stage1→stage2→stage3 qualification and per-workload median **and** p95 ≤1.5×
the frozen Zig reference. Report unsupported stages or failed ratios explicitly;
a tooling milestone can land while DL7 remains open.

### S10 — Independent qualification and the timing schedule

**Own:** the baseline/final experiment harnesses, edit/failure matrix, timing
schedule, raw evidence and final acceptance report. Production fixes go to their
owners. S10 reviews coverage independently and is not a substitute implementation
owner for missing compiler functionality.

Freeze paired controls from `C0` and the final candidate: Debug developer loops,
ReleaseFast compiler timing, guest release runtime, exact flags, CPU placement,
mode/ABI, inputs, tools and cache tiers. Rebuild a matched baseline when a merge
changes semantics; preserve the frozen self-hosting reference separately. Never
attribute a lifetime/runtime optimization to a tooling-only change.

Coordinate bounded exclusive timing windows with the memory-management team's
measurement owner. Obtain enough repetitions and a declared estimator for latency
claims; five operational samples alone do not establish a stable p95. Include
planning, validation, preparation, execution and reporting. Record queue time
separately, and keep wall time, aggregate work and memory meanings distinct.

**Accept:** forced independent executions agree with cached/selected paths;
required action/test inventories match; failure injection cannot publish stale
success; paired cold/warm/edit data covers regressions as well as improvements.
Run required complete verification on the exact final candidate and archive all
commands, statuses, hashes and raw measurements. Convert demonstrated work and
latency targets into appropriate regressions without silently scheduling new jobs.

## Integration order and contracts

Publish these contracts first: S01 event/measurement IDs, S02 policy and clock
scope, S04 producer manifest and fallback, S05 profile completeness, and S08
stability diagnostics. They extend existing schemas with explicit compatibility
behavior; do not introduce ten parallel schedulers or evidence formats.

1. **R0: baseline and ownership.** Coordinator/S10 pin `C0`, refresh inventories,
   inspect current-main configuration qualification and record both external
   workstreams. All workers begin independent audits, reproducers and fixtures.
2. **R1: measurements and lifecycle.** Integrate S01 telemetry and S08 diagnostics;
   merge independently qualified S02 lifecycle changes. Budget enforcement waits
   for calibrated scopes and data. Capture the expanded edit matrix.
3. **R2: dependency and producer boundaries.** Integrate S03 splits, S04's first
   real producer and S07's declared fixture changes. Preserve all registration
   and mode/ABI inputs. Re-audit configuration projection after shared wiring.
4. **R3: executed-work and profiles.** Integrate S06/S07 optimizations and S08
   counter reductions as qualified; then S05 profiles and work-budget adapters.
   S02/S10 qualify enforcement against the actual integrated action graph.
5. **R4: bootstrap adoption.** S09 integrates ready stages throughout R1–R3 using
   the same contracts. Refresh tests/performance for each adopted boundary.
   Port readiness never blocks independent tooling work, and cannot be invented.
6. **R5: final freeze.** Reconcile current development main in the integration
   branch, resolve shared-file conflicts, re-audit any changed fingerprint,
   freeze the candidate, and run S10's complete correctness/performance matrix.
   Changes after the freeze invalidate affected evidence and require revalidation.
7. **Delivery.** Commit the acceptance report and updated developer commands,
   mark each DL requirement honestly, and present the exact candidate for the
   user's integration/publishing workflow. Keep DL7/performance blockers visible.

Workers hand off fixed commit SHAs, never a moving branch tip. Integrate small
coherent changes with focused checks between dependency layers. If a plan proves
unsafe or slower, retain the conservative implementation and return the measured
rejection plus the next candidate; the original requirement stays open.

## Required final matrix

| Case | Proof required |
| --- | --- |
| Unchanged retained and one-shot requests | Same complete verdict; eligible reuse; no new hashing/enumeration where qualified; explicit remaining fresh work |
| Test-only and fixture edits | Responsible groups execute; proven unrelated groups reuse; additions/deletions/renames are discovered |
| Documentation, tooling and pure-helper edits | Exact dependency-driven selection, independent executable boundaries and no missing embedded inputs |
| Semantic rule, runtime, lifetime/mode and ABI edits | Every affected producer/consumer invalidates; no reuse inferred solely from matching schema |
| Component implementation, seed and protocol edits | Authenticated producer changes propagate; missing/replaced/changed-during-use artifacts fail safely |
| Revert and compatible second worktree | Qualified older evidence may reuse; paths, flags, effect and producer differences stay distinct |
| Cold verification versus cold compilation/bootstrap | Cache tiers explicitly isolated; no borrowed warm result passed off as cold generation |
| Concurrent requests and subscribers | Matching work coalesces; cancellation retains work owned by another request; claims recover |
| Timeout, crash, publication interruption | No success from incomplete work; cleanup and subsequent retry work |
| Corruption, eviction and watch failure | Recompute or explicit failure; never stale success; retention respects active leases |
| Source ABA, symlink/PATH and negative lookup changes | Mutation rejected even if final bytes match; bounded diagnostic names the cause where available |
| Quick/complete/long profiles, fuzz and Juice | Exact coverage/partial status; thresholds do not fabricate measurements; fresh timing remains fresh |
| Large inputs and cold preparation | No unexplained cold-build, compiler RSS, watch/fd or artifact-size regression |
| Adopted self-hosted compiler stages | Reference parity and independently reported full bootstrap/per-workload timing acceptance |

Snapshot counters and other deterministic work counts belong in ordinary
regressions. Absolute latency and the self-hosting ratio use qualified timing
runs. Apply the roadmap's existing targets to the agreed workloads; leave an
unmet target open instead of excluding its slow row or changing the denominator.

## Handoff format and closeout checklist

Each Sxx commits `handoff.md` in its experiment directory with:

1. `C0`, implementation commit SHAs, owned files and shared-file patch requests.
2. Concrete behavior/work changed, producer and schema contracts, dependencies.
3. Exact commands, exit statuses, modes, tool/source/artifact hashes and raw logs.
4. Test/action inventories; executed/reused/partial counts; counter reductions.
5. Cold/warm/edit timing and memory evidence, or explicit unavailable/unqualified
   fields. Separate operational observations from isolated comparisons.
6. Required follow-ups, failed alternatives, external-owner dependencies and
   integration order. No claim of completion based solely on a stub or fixture.

The coordinator's final report must satisfy:

- [ ] Current development lineage, clean candidate and complete ownership ledger.
- [ ] Updated action/test inventory; forced independent execution agrees.
- [ ] Per-test/action observability and bounded input-stability explanations.
- [ ] Qualified limits/cancellation and preserved evidence/claim safety.
- [ ] Useful independent test and producer boundaries, with measured cold costs.
- [ ] Reduced selected fresh-work and retained-validation overhead, with evidence.
- [ ] Supported quick/complete/qualification profiles with honest coverage.
- [ ] Fuzz/Juice work budgets and compatible evidence reevaluation qualified.
- [ ] Final configuration fingerprint explicitly reviewed; no automatic bypass.
- [ ] Required full gate and formatting pass on the final source candidate.
- [ ] Named edit-loop and unchanged-run targets achieved or explicitly still open.
- [ ] DL7 status, seed/bootstrap parity and strict self-hosting ratios separate.
- [ ] Memory-management changes preserved; no competing lifetime/default rollout.
- [ ] Raw evidence and user docs committed; no missing work hidden as an exception.

## Copy-and-paste instruction for the coordinator session

```text
Use docs/audits/selka-development-loop-closeout-10-session-plan-2026-10-12.md
as the execution plan. Implement the remaining development-loop closeout with
one coordinator and ten worker sessions S01–S10, using Sol 6.1 workers where
available. Refresh the development main lineage first: at plan creation local
main and origin/development were fbfcaa7a923186a8e773c3760f81c10aa345a432;
origin/main is a separate published snapshot. Pin the actual base as C0.

Give every worker an isolated worktree and its assignment from the document.
Enforce the shared-file ownership ledger, publish the schema contracts early,
and integrate fixed commits in the stated dependency order. If only four total
agent slots are available, run three workers at a time and preserve all ten
assignments; do not claim ten concurrent workers.

Coordinate with the existing self-hosting and memory-management workstreams.
Do not duplicate their port or ownership/runtime work. Preserve all correctness,
mode/ABI, seed and cache contracts. Re-audit the changed configuration fingerprint;
do not update its digest automatically.

Use shared admission for builds and complete gates. S10 schedules exclusive
bounded timing windows under the current timing policy. Coordinators that own
admission run directly. Keep private local caches and frozen qualification
candidates; do not clear other sessions' caches or edit their source trees.

Continue through implementation, focused checks, integration and final required
qualification. Produce an acceptance report and committed reviewable candidate,
with exact evidence and any unmet targets. Report development-loop completion
separately from full self-hosting acceptance. A blocked external port leaves DL7
open; it does not prevent finishing independent tooling work. Worker sessions
must not independently merge main or push. Guardian feedback entries are not
required. Do not start scheduled jobs or change rollout defaults as part of this
work.
```

For manually opened worker sessions, provide this plan, the coordinator's `C0`,
the assigned worktree and the instruction: “Execute Sxx only; follow its ownership
and acceptance contract; commit fixed SHAs and return the required handoff.”
