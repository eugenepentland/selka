# D9 RC scopes, arena cleanup and counters: joined regression gate

Frozen `a9361b46` passes all four required commands with GC still the default.
This is implementation regression evidence; RC guest correctness, physical
borrow-traffic reduction and the WP-4 performance/RSS gate remain incomplete.

| Command | Result |
| --- | --- |
| `zig build test --summary all` | 94/94 steps; 2,167 executed tests, 21,980 shard exclusions |
| `zig build test-qbe --summary all` | 51/51 steps; 436 tests |
| `zig build test-qbe-build --summary all` | 29/29 steps |
| `zig build fmt-check --summary all` | 2/2 steps |

The Debug compiler SHA-256 is
`15d4d085bf2ef132092377fcf24ae372f7d0a67585d6d2d855623c1c4c53ec10`.
The [machine-readable record](evidence/d9-rc-arena-stats-gate-2026-09-26.json)
retains compressed exact logs and raw hashes. Source stayed frozen, the gate
held the shared serialization lock, and scratch remained in the worktree.
Whole-tree commit Guardian passed all 88 checks without ratchet changes.

The join includes scope restoration and transactional multi-value copy
(`9a987374`, `6463697b`), live-frame trap cleanup (`3a53dad6`), stable pinned
sparse dictionary readers (`4eb5e1dd`), physical counters (`f316523c`), and
charged arena cleanup plus execution-report hooks (`9dae3b1f`). Integration
wiring and a nested-scope regression are in `70d28dc7` and `a9361b46`. Every
branch join is a real two-parent merge.

The joined focused RC run passes 26/26 tests, including production C fixtures.
Five arena scenarios pass ASan/UBSan, including preservation of an older outer
hold when an inner arena closes with zero ordinary owners. Counter evidence
separately verifies exact traffic, saturation/isolation, silent ordinary
artifacts, and unchanged ordinary core/transfer machine code:
[statistics report](d9-rc-statistics-2026-09-26.md).

Review identified an additional arena-finalizer ordering case after this
snapshot was frozen: a parent finalizer could inspect an earlier arena child's
already-cleared fields. The runtime agent is adding an all-finalizers pass and
a regression before RC acceptance. Fresh arena text-split rollback
`706c527d` and actual compiler ownership lowering are also still on agent
branches at this checkpoint. This report does not claim those pending changes
were included in this gate. The first basic RC CLI guest ran in the compiler
worktree, but broader guest and performance acceptance has not run.

`main` remains `b292660a`; no push, main merge, or devspeed landing occurred.
WP-5 remains dependent on completing WP-4.
