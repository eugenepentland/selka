# A01 retirement patches against integration 44947

Prepared only. No production file is changed and no default or retirement milestone
is claimed. The exact base is `44947e6967d8eb0deeaa86b25ca2bb44bc58803d`.
Apply only after the coordinator records actual C2 qualification and authorizes C3.

`owned-runtime.patch` removes every RC conditional in `core_tasks.c`, including
capture sharing/retaining, result retaining, and RC release alternatives. It keeps
owned capture destruction, take-once independent results, and destruction of untaken
results. Former externally named submit/result/close helpers become private C
implementation details; generated callers must use the existing owned task ABI.
The parallel library comment describes the single behavior after retirement.

`build_parallel.zig` is unchanged. It already contains only owned chunk lowering.
`shared-selector-request.patch` is for A07/coordinator's `core/build.zig`: remove the
mode condition around the existing `parallel.matches` dispatch. The file has other
retirement work outside A01's reservation. Do not apply this request independently
while the legacy mode remains selectable.

`fixture-migration.patch` preserves the registered scheduler and emitted-task
coverage while replacing unsupported legacy task handle sharing with owned group
contracts. It is separate so reviewers can inspect source removal and evidence
migration independently. It must land with the ABI removal, not afterward.

| Existing contract or check | Prepared replacement |
| --- | --- |
| Million submissions, tree depth12, chain2048, own-deque waiting | Same stress shapes with one independent capture per submission and take-once results. |
| Lazy pool, budget/frame sequential limits, forbidden batch/fork | Existing guards and output assertions retained. |
| Repeated result retrieval / task handle survives group | Legacy ownership contract explicitly retired. A transferred result survives group destruction; a second take refuses R_TASK_GROUP. |
| Group dropped with pending/untaken work | Join and exact direct cleanup remain, including separate untaken results. |
| Mixed list/nested-list/dict/text capture snapshots | Explicit independent copies preserve values while the parent mutates. No shared capture or RC fallback. |
| Emitted fastcc bridge, item17 trap and captured source location | Existing assertions retained under owned submit/take/end helpers. |

The runtime patch deliberately preserves both `_Atomic uint64_t pending` fields.
They count outstanding work, not references. `static-review.json` proves the queue,
join, quiesce and owned-map function bodies are identical, and every atomic/futex
line is unchanged. The owned-map source borrow stays valid through its mandatory
join; result order and list-shell-only destruction are unchanged.

## Dependencies and application boundary

1. C2 must qualify ordinary commands and all supported library/application paths.
2. A10 removes legacy CLI selection and aligns installed package/components. A07
   removes Core mode branches, legacy emission paths and generated declarations;
   A02/root removes counted block layout, RC/COW helpers and conditional runtime
   plumbing. This patch alone cannot establish a package-wide count-free ABI.
3. A07's checked helper contract remains: submit consumes argument2, group end
   consumes argument0, take/open return fresh owners, map consumes only output
   argument6, and scalar task-item/chunk/thread helpers retain no memory.
4. The legacy generated callers are in `task_ir_program.zig`; migrate them with
   the supplied test patch. The native scheduler fixture is the other active
   caller. There are no shared runtime header prototypes for these three legacy
   names at the pinned base; C runtime fragments share one translation unit.
5. The dependent fixture patch still spells `.single_owner=true,.zero_rc=true`
   in hand-built IR. Reconcile those fields with A07's final IR schema deletion;
   they are explicit ownership evidence until that shared schema changes. The
   final C3 source audit must not leave a compatibility selector behind.
6. Keep direct destruction and synchronization. Do not remove every identifier
   containing `count`, `release`, or `owned` during lexical cleanup.

A10 confirmed the shared declaration boundary is `zero_rc.zig`, `emit_llvm.zig`
and generated runtime declarations under A07/root. The owned submit/take/end
names remain. Former aliases may be private only after no generated caller uses
them. `manifest.json` records exact before/prepared hashes; originals are immutable
gzip snapshots under `originals/`.

## Required reruns after application

Source inputs must be frozen. Re-source the shared development environment and
use the shared admission queue; A09 schedules timing. Run the registered scheduler,
emitted-task, zero-RC task and A01 map suites, including supported ThreadSanitizer.
Run native stress at1/2/8 workers (1,010,002 counted increment callbacks including
discarded output, plus the nested tree/chain), take-twice refusal, and all
pool/fork/budget guards.

Run A01 `qualify.py --ordinary` on the exact installed C3 compiler with release,
unoptimized debug, verified release, optimized debug and no-facts release, plus
TSan for task/map paths. Include combined map, direct Results, Result lists, empty/
uneven ranges and trap item17. Preserve all output, zero-RC counters, exit-live,
LLVM and symbol checks. Managed tuple/DictItem/fresh-field tests also have CLI
selectors listed in the parent `additional-command-paths.json` inventory.

Preprocess the final runtime, inspect generated LLVM and linked symbols, and
require the legacy submit/result/close names plus all retain/release/share/COW
operations to be absent at their respective runtime/guest layers. Atomics for
pending/ready/state remain. Requalify A03 census and A08 cache identities; A09
reruns affected paired runtime/RSS/allocation evidence on exact final artifacts.
The coordinator runs the complete verification/Guardian gates and accounts for
installed bootstrap/component artifacts separately.

Only patch applicability and static preservation checks have run here. No native,
TSan, allocation, runtime, RSS, compilation or package result is claimed for this
prepared retirement patch.
