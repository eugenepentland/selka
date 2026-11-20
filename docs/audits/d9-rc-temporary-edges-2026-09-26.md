# RC collection temporary edge cleanup

The matrix multiplication RHS retained hidden root and row snapshots until frame
cleanup. Each subsequent nested write therefore detached both levels. The emitter
now discharges a conservative subset of the existing finalized RC edge plan:
dead compiler collection temporaries after an empty-stack fallthrough local store.
The initialized guard controls the release, including any non-sharing hold token.

This excludes parameters, named locals, address aliases, unique resources,
recursive boxes, inline aggregates and certified borrowed entries. RC already
disables nonparameter address borrowing. Captured receivers have independent
lifetime holds; the plan uses liveness after implicit COW parent/key uses are
included. Owned derived results are published before these releases. Other CFG
edges retain the existing frame-cleanup fallback; this is not complete general
borrow-anchor or edge-release lowering.

On the diagnostic matrix size 12, QBE and LLVM produce exactly `41383` and `485891`.
Both backends have identical counted traffic: one clone, 132 allocations and
retirements, 9,345 owner acquisitions, 9,477 releases and 10,368 balanced holds.
The earlier joined diagnostic recorded 3,482 clones, 7,068 allocations/retirements
and 30,081 acquisitions. That earlier comparison includes intervening integration
changes; it is diagnostic evidence, not a matched performance acceptance run.
The required size 500 and complete acceptance corpus remain integration work.

Validation uses the Debug compiler SHA256
`91b7ff893aff4133f7f921c174a7e509a879f2d6e8103f2b854260565d0fbb18`:

- Four new snapshot, derived-child, pending callback and branch/zero-loop cases
  pass both backends with identical balanced counts, and all four pass newly
  executed default-GC guest tests with explicit native GC stress.
- Existing pending-receiver and nested-array callback cases: 25 per backend.
- Live views, aggregate ownership, borrowed results and the new cases: 23 per backend.
- The original indirect recursive unique-argument admission reproducer now passes
  both Debug backends after the LLVM self-address fix: expected `R_FRAME_LIMIT`,
  exactly two heap allocations and two retirements.
- Whole-tree Guardian passes all 88 checks. The planner selection passes 32/33;
  its one failure is the independently identified stale ABI-negative fixture
  using the now-valid `rc-v2`, being corrected by integration.

Raw commands, sources, compiler/binary identities, stdout, counters and diagnostics
are in [compressed evidence](evidence/d9-rc-temporary-edges.json.gz). This component
has not run a separate full gate; integration owns the serialized joined gate.
