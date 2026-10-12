# A07 ownership, cleanup, and ABI handoff

C0 is `fbfcaa7a923186a8e773c3760f81c10aa345a432`. Original worktree/branch:
`mylang-memory-20261012-A07` / `codex/memory-closeout-20261012-A07`.
Current integrated validation tree/branch:
`mylang-memory-20261012-A07-validation` /
`codex/memory-closeout-20261012-A07-integrated`, created at `07f16c654`.
The coordinator integrates shared files and worker commits; no publication occurred.

This supersedes the initial narrow-fix status below. Earlier experiment JSON
continues to describe its own exact frozen compiler, including then-pending work.
C1 complete qualification, C2 default promotion, and C3 retirement are separate
coordinator gates and are not claimed by this handoff.

## Implementation ledger

These are A07 feature commit identities, not a suggestion to re-merge dependency
commits or branches. Integration may contain equivalent cherry-pick identities.

| Feature | A07 commit | Evidence / owner of integrated rerun |
| --- | --- | --- |
| Existing task diagnostic helper contract | `9459f4049` | Focused 1/1; A01 map/scheduler matrices |
| Direct Result entry cleanup, immediate dict snapshots, test adapters, scoped try | `afce73104` | `narrow-fixes/`; earlier 72/73 plus corrected focused rerun |
| Fresh text/character origins and audited helper contracts | `0c86f3470` | `borrow-support/`; library and component reruns |
| Bounded affine resource origins/provider keepalive | `23f7d49c7` | `resources/`; A05 network/denied/durable native fixtures |
| Builtin file result forwarding | `f50045ce7` | `file-forward/`; original rc_contract_results A05 pass |
| Conditional owner and optional impossible-arm handling | `41660cb3f`, `f3a021f53` | `conditional/`, `narrowing-defaults/`; A03 v_narrow five modes |
| Prepared parent identity and shallow managed-copy rejection | `eb9dd1f8d` | A02 nested extension before/after and A06 writeback regressions |
| Exact list/fixed-array slot reconstruction | `e597dbb26` | A06 nested/dynamic index/alias controls, A03 array and mut-place reruns |
| Explicit copy of managed dict defaults | `0f8dbd04f` | A05 defaults hit/miss/independence matrices |
| Recursive ancestor-source extension refusal | `f88116064` | A02 exact/dynamic negatives and explicit-copy five-mode positives |
| Record-home preservation across sibling versions | `4fd7c900d` | A06 original/reduced ce2 abort, no-update and dynamic-branch controls |
| Scalar snapshots across mutable record loops | `a0f244b07` | A08 minimal marks loop and actual cache-plan 560 protocol executions |
| Borrowed compiler-generated dictionary item pairs | `385ed7b1f` | Dictionary-item source/IR and migration fixtures; A01 two-name lowering is separate |
| Managed readonly dict.get with both roots live | `ba273f041` | `borrow-selection/`, focused 6/6 including native debug/verified release |
| Complete tuple staging and strict live shape validation | `9bfc52809` | `tuple-staging/`, focused 5/5; integrated matrix below |
| Always-on marker dominance validation/cache rejection | `2cb87014c` | `borrow-selection/dominance-validation.json`; A08 corrupted artifact suite |
| Release verifier scratch with backing allocators | `522e66671` (integrated validation `fb8c240e0`) | `borrow-selection/scratch-validation.json`; A08 final 4/4 without leaks |
| Aggregate pin declaration/call/table/type hardening | `157901e5c` | `aggregate-markers/`, focused 5/5 including cache replay and malformed IR |

A07's source checker and exact marker extension for managed text min/max and
Optional defaults was delivered as an isolated coordinator-applied patch to A04.
A04 owns combined feature commit `44ca315ee` and its frontend/native evidence;
A07 did not edit the peer checkout. It preserves eager evaluation, both-owner
loans, fresh temporary cleanup, logical type validation and stored-view refusal.

## Latest integrated tuple qualification

Evidence commit `9accc895f`, source `157901e5c6e35447bd32df825147d56074fcedaf`,
compiler SHA256 `4a554651e57ffb569c0971da569e85eac3e57d9179a98cf2bd0032af84f7f8cd`.
The complete A01 fixture includes the authorized helper rename and meaningful
provider checksum from `01c00de44` (local equivalent `1aa8e42c5`).

Registered `test-core -Dtest-filter='complete tuple staging'` passed **3/3**.
Its native fixture passed release, unoptimized debug, verified release, optimized
debug and release without facts, with exact output:

```text
tuple-unpack 3
tuple-results 28
tuple-providers 56
```

Every checked native lane asserted zero runtime RC events, zero managed exit-live
bytes, and clean LLVM/symbols. The fixture covers complete RHS staging before
ordered destination effects, managed swaps, ignored cleanup, early/error exits,
optional tuple copies, named Result obligations, and moved/returned/swapped
providers with independent file contents. The earlier ordinary borrowed-tuple
control remains in `tuple-staging/`.

Exact command, source/compiler/fixture/component hashes and limitations are in
`tuple-integrated/validation.json` and `full-tuple-test1.log`. This normal test
command used A10's owned component pin. An earlier aggregate-marker test attempt
failed legacy default seed provisioning and is preserved in its evidence; the
same registered five tests then passed through `core-test-binary`. The legacy
seed failure was not silently reclassified as a pass or repaired by repinning
immutable history.

Per-run counter files in the registered tuple test are temporary and cleaned by
that test. This is assertion evidence, not the final raw census or new allocation,
runtime/RSS/compile comparison. A03/A09 must rerun the final frozen candidate.

## Soundness reviews and file coordination

Owned or coordinator-reserved source work included single_owner/copy/resource,
build/build_cap/build_dict, own/borrow_fields, emit_llvm/emit_homes, verify_ir,
zero_rc, marker_validation/borrow_selection/tuple_unpack, typed_dump and explicit
zero_rc regressions. Narrow error propagation touched passes/allocation_contract
and the central decoded optimization-cache boundary with owner authorization.
`dictionary_views.zig` returned to the coordinator after the immediate snapshot
fix. Other worker prerequisites were cherry-picked only after coordinator approval.

A07 reviewed A01 chunk ownership/join/cleanup and Result handling, A02 capacity
arithmetic and consuming list methods, A04 copying repetition/rendering/slice and
borrowed selection contracts, A05 resource/runtime/borrowed-provider paths, A06
exact nested writes/home-alias controls, and A08 bounded phi/marker/cache work.
Native qualifications remain attributable to those workers and their exact inputs.
No arbitrary partial moves, retained managed FFI pointers, escaping views/tasks,
new lifetime syntax or fallback RC was admitted.

## C3 retirement draft, not implementation

Evidence-only commit `78a799fd4` contains `retirement-C3-67348/retirement.patch`,
pinned to integration `67348fc8ca14578af999c056891d3d318d311e12`.
It removes active Core RC/COW paths and old mode APIs in 16 files (230 additions,
1,154 deletions), supplies fixed OWN1 ABI provenance, and keeps direct destruction,
independent copies, provider lifetimes and diagnostics. It applies to the exact
base and passes pinned Zig formatting. It is **unapplied and unqualified**.

The draft README lists the atomic A08/A10/runtime/count-template dependencies,
pending feature rebases and required tests. Do not apply the overlapping
`abi-schema.patch` again after the full patch. A prepared deletion patch is not
legacy retirement; active production RC still exists until C3 is applied and
qualified. Historical commits/seeds remain historical inputs.

## Remaining owners and next actions

- Coordinator: integrate ready evidence, freeze one C1 compiler, run complete
  registered verification/fmt and Guardian; then qualify actual default C2.
- A01/A03/A05/A08: final installed-command tuple/Result, public library, application,
  borrowed selection/provider and component/cache reruns on that exact compiler.
- A03/A09: fresh original-30 and expanded census, zero-RC/cleanup counts, independent
  runtime/managed-peak/RSS/allocation/compile evidence and controlled timings.
- A07 with A08/A10/runtime owners: rebase and apply actual retirement only after C2,
  migrate active internal tests/callers, prove old/foreign/mixed artifacts refuse,
  and run final structural/native/package checks before milestone 3.

All actual A07 feature commits above passed the normal 88-check Guardian gate.
No Guardian FEEDBACK entry was appended because the user did not request one.
