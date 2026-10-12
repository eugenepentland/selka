# A01 bounded parallel-map closeout

Base C0: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Worker: `codex/memory-closeout-20261012-A01`.

Implementation commit: `71940901d89f3e9443c364e7c0cf427c0c9fab6c`.

Implementation qualification is in progress; integrated C1 measurements remain required.

Owned production files: `src/core/build_parallel.zig`, `src/core/runtime/core_tasks.c`,
`src/stdlib/parallel.my`. New regression: `src/core/a01_parallel_map_test.zig`.
Coordinator requested/applied its test-root registration. A07 helper contract is
consumed from `9459f4049c93dfe1e2f13b7928ec89306e0b14f2` (local cherry-pick
`f82a23e47`). No other peer changes were merged.

The local and remote branch inventory contained no completed map-efficiency
implementation. Historical commit `3af94c6e1092d2c7d3b0b541b5cac0cc31a9573e`
contains isolated legacy scheduling-policy experiments, not a zero-RC map change;
it is not adopted or used as a paired timing control.

The map worker borrows a source list and one contiguous range, then returns one
owned list of independently owned callback results. Captures, task handles and
result containers are bounded by `min(n, 4 * threads)` (one at one thread).
Result elements still require O(n) storage: the caller output plus temporary
chunk output slots. These are distinct from scheduler wrapper allocations.
The parent moves chunk elements in order, frees their empty list shells, and
joins before returning. A task-item marker preserves exact trap item indices.

Evidence harness `qualify.py` writes exclusively under its `--output` directory.
It covers sizes 0/1/many/uneven, cheap and expensive callbacks, managed records,
nested maps, tagged outcomes, `Result`, and discarded outputs at 1/2/8 workers.
Five counted pipelines and separate ThreadSanitizer binaries have passed on the
private prototype; integrated requalification remains pending.
`scaling.my` accepts `size repetitions cheap|expensive` for controlled allocation
and A09 timing/RSS comparisons; instrumentation stays off timing binaries.

Completed checks on the private prototype compiler
`1efd0c92cc0b98768a9a89961c50f0c1c554b5ae4635dcaa9f218217c50f5275`:

- Full compiler installation build, exit 0; diff Guardian 88 passed.
- `zig build test-core -Dtest-filter='zero RC' -Dtest-filter=scheduler` through
  shared admission: 72 passed, command exit 0. Includes the new chunk regression,
  zero-RC ABI/ownership regressions, 1/2/8-worker million-submit/deep nested stress,
  and supported ThreadSanitizer million-submit stress at eight workers.
- Whole-tree Guardian 88 passed in implementation precommit.
- A07 final static ownership/ABI review passed, conditional on remaining native matrix.
- 18 C0 and 18 candidate counted scaling runs: all checksums match, all zero RC,
  and all exit-live managed bytes zero. The compiler installation is complete;
  C0 binary SHA256 is `324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.
- 100 repeated eight-worker managed/nested/source-clear map runs passed.

For 4,097 cheap callback elements, total allocations change from 12,308 at C0
(each worker count) to 16/37/111 at 1/2/8 workers. Candidate counts at 257
items are also 16/37/111. One item stays at 12 allocations and 832 allocated
bytes. At eight workers, parent-map allocations change 8,201 to 69 and worker
result-container allocations change 4,097 to 32; callback allocations are zero.
This separates wrappers from independent output storage: 32 chunk arrays still
hold 4,097 result elements temporarily before parent transfer. Managed peak at
4,097/eight workers changes from 819,832 to 116,120 bytes in these single observed
runs. These are managed metrics, not RSS or runtime claims.

The local compiler was built from C0 plus A07 and the A01 prototype before the
implementation commit existed. It is identified by its binary hash, not relabeled
as C1. Final C1 must rerun the checked-in harnesses with its exact revision.

Raw work-in-progress evidence: `.tmp/memory-closeout/A01/{C0-allocations,
prototype-allocations,prototype-smoke,prototype-matrix,prototype-repeat-managed}`
and `core-tests.log`, `build.log`, `commit.log`. Reports and compressed raw counters
will be retained under A01 before handoff.

The later prototype matrix passed all eighteen combined-source executions. Its
trap executions were correctly tagged `(item 17)`, but an incorrect old oracle
recorded failures. Those raw failures are preserved; the corrected oracle will
be rerun on the final candidate. Fatal trap exits are excluded from normal-exit
managed-leak assertions.

## Expanded Result-list implementation

Implementation commit: `3c8c494758221d8d1f3dce6f65a05dce3ada5868`.

The user explicitly expanded scope to include stored Results and `parallel.map`
callbacks returning Results. The complete source contract is in
`result-list-contract.md`; the implementation separates storage eligibility from
pending handling obligations. Explicit acknowledgment, whole-list transfer,
independent copies, borrowed inspection, and per-element handling are checked
locally. Resource/capability, dictionary/set, boxed pending and copy-trait
boundaries remain rejected. Nested ordinary Result payloads are supported.

Additional coordinator reservations cover `generic_bodies.zig`,
`nominal_templates.zig`, `record_layouts.zig`, `symbolic_shapes.zig`,
`symbolic_types.zig`, `type_catalog.zig`, `sema_calls.zig`,
`sema_collections.zig`, `sema_expressions.zig`, `sema_gathers.zig`,
`sema_loops.zig`, and the precise existing `managed_lists_test.zig` update.
Coordinator authored shared changes in `SPEC.md`, `typed.zig`, `sema_shared.zig`,
and the `src/root_test.zig` registration for `a01_result_shapes_test.zig`.
A06 requested the narrow tuple `.copy()` parser exception included here and owns
its independent counted native regression. A08's comprehension iteration origin
fix is preserved; the coordinator resolves that already-integrated three-line
overlap.

Native compiler v3 SHA256
`a6795771960a0540e9c573b99dc5117d8450b8010e242ed485744eb725edf320`
passed eighteen Result-list executions (six modes, 1/2/8 workers), with zero RC
events and managed leaks in all counted runs, plus 100 release and 100 TSan
eight-worker repetitions. Raw results, reproducible compressed counters, exact
harness and identities are in `result-evidence-v3/`. Five Core and twenty-one
frontend checks also passed, including public cross-module obligations.

The final symbolic cycle correction follows that v3 compiler: incomplete active
cycle results are never memoized, while complete acyclic results remain cached.
A07 approved this within the existing 100,000-work refusal bound. The final focused
run passed five Core and eight frontend checks, including 64 repeated queries of
mutually recursive generic list types with a pending field after the back edge.
A controlled mutation proves the cycle regression fails with incomplete memoization
restored and passes with the committed fix. The rebuilt v4 compiler at the exact
feature commit passed all 54 combined/Result/trap executions, all 30 normal counted
runs with zero RC/leaks, all 18 structural audits and all 9 TSan runs. Its SHA256 is
`a0840db3f813f2bb4dd37447fd3778435ba826ea3d24101c4351c1e73f1beb7f`; raw evidence
and identities are in `result-evidence-v4/`. A03's expanded census and A08's
cross-compiler cache probe pin the Result source hash and await integrated C1.

The A03 supplemental fixture SHA256 is
`6c5ad78bda5b1908889e1a32956456bacbf615ecbc5d36b2fbc7100875865cf6`;
expected output is `27 4 5 4 5\n3889\n`. C0 refuses it with
`E_GENERIC_REQUIREMENT`. The independent unhandled-list fixture refuses with
`E_RESULT_UNHANDLED`.

## Independent native driver repair

Commit `38dc781a897182ffbf1fff0906ec319a007a9154` keeps uncached per-unit objects
alive until native linking finishes. Two focused fallback checks passed, including
two units, repeated unproved-tool builds and success/failure cleanup. Evidence is
in `native-driver/`. A08 found this machine's loader-cache digest differs from the
approved runtime profile; no trust configuration was changed. Native cache-reuse
qualification remains a separate machine boundary.

## Remaining integration work

A09 runtime/RSS measurements, exact integrated C1 requalification, normal-command
C2 checks, and active RC retirement remain pending. `qualify.py --ordinary` omits
the prototype selector for C2/C3 and records that choice. No default or retirement
milestone is claimed. Guest test migrations were explicitly transferred to A03;
remaining local `tests/lang` diffs are excluded from A01 commits.

The additional count-free native scheduler fixture passed counted million-submit
stress at 1/2/8 workers and separate TSan at 8 workers stress. Each run executes 1,010,002 increment
callbacks plus nested tasks (tree depth 12, chain2048), destroys discarded results,
checks transferred result survival and refuses repeated take. All counted runs are
RC-free and leak-free; native symbols are RC-free. `owned-scheduler-evidence/`
records exact fixture/runtime/binary identities and raw counters. This adds direct
owned-runtime stress without confusing the earlier legacy scheduler control with
count-free evidence. Retirement edits remain unapplied pending C2 authorization.

The intermediate Support5 installation at source
`a1f19edf255c8c0886731d8d7cce450d5f657720` passed targeted Result-map release/TSan
checks at 1/2/8 workers (6/6), three counted runs RC0/live0, both structural
LLVM/symbol audits and the required unhandled-list refusal. Exact identities,
commands and raw counters are in `support5-result-map/`. Historical Support4 RC
libexec components remain in that installation; this does not qualify C1 or the
installed package.

The two-name dictionary items lowering now borrows key/value projections directly.
`dict-items/` records 2/2 focused checks and five native modes with exact outputs,
RC0/live0 and structural audits. Root-rebinding preserves the existing D1 independent
entry snapshot; clearing/entry mutation and borrowed escape remain refusals. The
exact `dictionary_views.zig` prerequisite is already integrated by the coordinator
and excluded from this worker's feature commit. Single-item record borrowing remains
A07's separate work. `qualify.py --cases dict_items` supports later final-artifact
qualification, including ordinary command mode.

The fresh whole-result field receiver repair in `fresh-field/` passed five native
modes and six negative controls. A hidden whole-result owner now lives through
immediate read/copy receiver operations, including nested fields and function
invocation, with single evaluation and exact ignored-child/early/error cleanup.
Arbitrary partial moves, borrowed escapes, invalidated views, temporary mutation
and pending-sibling operations remain refused. The 64-field bounded helper does
not change the ABI or lifetime inference. Frozen `samples/fresh_field.my` and
`qualify.py --cases fresh_field` support later integrated/ordinary qualification.
Root's Core test import is included; the old dictionary_views dependency overlay
and transferred guest migration edits remain excluded. Complete tuple unpacking is
separate work and is not claimed by this fix.


Retirement preparation was refreshed against integration
`44947e6967d8eb0deeaa86b25ca2bb44bc58803d` under
`retirement/integration-44947/`. Three isolated patches cover task runtime removal,
dependent scheduler/emitted-IR fixture migration, and the shared Core map-selector
request. All three dry-run applications pass against exact archived inputs. Static
checks preserve every synchronization/pending line and seven queue/join/map bodies.
No production retirement is applied, and no native retirement result is claimed.
The directory records ownership boundaries, exact hashes, C2 authorization and
shared ABI dependencies, and the required final reruns. Evidence is committed from
the coordinator-created clean A01 validation checkout at `67348fc8c`; the old
worker's validation overlays and transferred guest migrations remain untouched.
