# Private semantic-history guest matrix — 2026-09-26

`tests/lang/rc_semantic_history.my` adds 13 permanent language regressions for
the private ABI3 history work. All 13 pass under GC stress on both actual QBE
and LLVM O3/full LTO. The current private RC compiler passes six and fails seven
on each backend. These are retained negative controls, not an accepted RC slice.

| Cases | GC stress | Current RC |
|---|---:|---:|
| Snapshot first, owner first, sharing before view creation | 3/3 | 0/3 |
| Nested record, fixed array, list element | 3/3 | 0/3 |
| Fresh dictionary appended to an arena list | 1/1 | 0/1 |
| Already-detached owner and whole-view copies | 2/2 | 2/2 |
| Heap/arena read-only mapping projection | 2/2 | 2/2 |
| Boxed variant materialization and arena snapshot | 2/2 | 2/2 |

The append case was identified by the independent collection-helper audit:
physically copying a fresh child into an arena list leaves a sticky shared mark
with no equivalent GC semantic share. A later live view consequently observes
different dictionary identity. The other negative controls preserve the earlier
snapshot/history divergences through multiple aggregate layouts.

A standalone driver executes all 13 scenarios and prints each result. Both
counted backends agree on balanced physical traffic despite the seven semantic
failures: 175 heap allocations/retirements, 41 owner acquisitions, 216 releases,
131 held acquisitions/releases, 41 arena allocations, 14 clones and 98 uniqueness
checks. No counters saturate. Balance alone therefore cannot establish parity.

[Drivers, raw guest verdicts, standalone outputs and counters](../../experiments/d9-rc-semantic-history-guests-20260926/results.json.gz)
record the exact compiler and source hashes. The compiler is a Debug build from
private base `6740f53f` plus the guest/spec additions. Loan infrastructure is
present, but compiler loan emission and semantic publication are not yet active.
Keep this commit on the private history branch until all RC cases pass.
