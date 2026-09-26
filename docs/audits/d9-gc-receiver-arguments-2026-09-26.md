# GC receiver scopes across later arguments

The accepted stage-3 compiler incorrectly lets a callback snapshot a selected
nested receiver before its later mutation. The preserved control in
`experiments/d9-rc-receiver-probes-20260926/snapshot_callback.my` fails on accepted
compiler `f6bea5d9` (SHA256 `8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`).
Its original log is retained in the receiver-lowering evidence archive. The GC
benchmark baseline remains immutable.

GC lowering now keeps the existing finite-path scope through the receiver's
consuming mutation when argument evaluation contains a callback. The compiler's
single-assignment place local identifies that operation. Prepared projections
remain bounded by the original fill, so later callback argument projections do
not inherit receiver borrowing. Normal completion releases scopes in reverse
start order and restores the still-active root; early propagation uses existing
frame scope cleanup. RC keeps its independent owner/hold scope lowering.

Validation: 32 focused COW tests pass, including a native normal/stress reduction.
Six permanent guest regressions pass on QBE and LLVM with GC, GC stress, and
counted RC (36 executions). They cover plain nested lists, dictionaries,
recursive boxes, repeated loop scopes, nested callbacks and early propagation.
The existing 19 nested-array callback regressions pass GC stress on QBE;
joined aggregate/runtime fixes also make all 19 pass under RC on both backends.
Guardian passes all 88 checks. Raw guest commands and output are in
`evidence/d9-gc-receiver-arguments.json.gz`.

The separate GC longjmp path bypasses generated cleanup; this change does not
claim to repair pin restoration for host reuse after a trap. The parent received
that follow-up review finding. The shared integration gate remains required.
