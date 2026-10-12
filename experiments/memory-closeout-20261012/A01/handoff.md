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
Five counted pipelines and separate ThreadSanitizer binaries are planned.
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

Pending: remaining five-pipeline source/ThreadSanitizer matrix, A09 runtime/RSS
measurement on frozen integrated revision, integrated C1 requalification, and
final retirement edits coordinated by A10.
