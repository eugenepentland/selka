# Cumulative ABI3 gate and remaining augmented-field regression

Source `19e16e1d96112e9ccc741fa0c430ea97173a1032` joins the experimental
ABI3 semantic-history and private-loan compiler with indexed mutable places,
boxed write-back, the GC rebox-root correction, compact journals, inert returns,
and single-element flat destruction. GC remains the default.

The frozen Debug compiler SHA-256 is
`1b705d90e58c6b2b3799c5cbe79da9adbc57913e4c72ebbfa2b54dad044c1bbe`.
The ordinary full gate passes: main 94/94 steps and 2,260 executed tests;
QBE 51/51 and 438 tests; native build 29/29; formatting 2/2.

The separate uncached RC sweep exposes one remaining regression on both actual
backends: 841 of 842 assertions pass across 145 programs, and
`field_augmented::test_augmented_list_field_writeback_preserves_record_snapshot`
aborts. There are no cached verdicts, skipped assertions, dropped tests or
unloaded programs. A hidden containing record still has a physical loan when
field detachment treats its child slot as ordinary ownership; replacing that
child invalidates the loan's later cleanup. The compiler agent is correcting
that transition. The original expected result is retained.

[Raw receipts and exact commands](../../experiments/d9-rc-history-flat-gate-20260926/README.md)
keep this failed RC result separate from the passing default-runtime gate.
Supplemental native golden replay and the complete 43-program-per-backend
performance corpus are in progress on this immutable compiler. No RC correctness
or performance acceptance is claimed; the instruction/RSS gate remains open.
