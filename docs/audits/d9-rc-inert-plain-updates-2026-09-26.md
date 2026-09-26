# Inert receiver scopes around plain inline record updates

Following terminal read admission `e9cde8d6`, exact `nbody::advance` still emitted
nine receiver scope pins for writes such as `bodies[i].vx = value`. Its capture-to-write
intervals passed the existing stable-root, plain-input and forward-control checks,
but the inert opcode whitelist rejected `UPDATE_RECORD`.

The proof now admits that opcode only when its result has no counted edges or
unique-drop obligations and its record is not managed. Every consumed operand is
already checked as plain, including the original record and all replacement fields.
The update operates on private aggregate result scratch. It cannot overwrite the
captured list local, saved index or pending receiver address. Managed fields,
unique finalizers, unknown effects, callbacks and arena transitions retain the
existing scoped protocol. One final write, the 256-instruction interval bound,
stable live root and closed forward control-flow checks are unchanged.

The ordinary uniqueness check still precedes borrowing. The interval contains no
managed snapshot publication or caller callback, so the removed nested pins and
backing holds are redundant. Source snapshots retain their detach behavior, and
an outer mutable-call pin remains active where applicable. GC emission, semantic
history, region rules, generic uniqueness and runtime ABI are unchanged. As with
the earlier inert-receiver proof, removing internal hold/journal work also removes
its internal allocation or count-limit refusal; no language publication is skipped.

## Isolated diagnostic

Both sides use the same `nbody` source with 10,000 steps, Debug compilers and
ReleaseFast guests. The baseline includes terminal read admission and the private
field-loan correction. Neither side includes the concurrent plain-record native
store/update or `retain_replace` optimizations.

| Backend | Before instructions | After instructions | After / before |
| --- | ---: | ---: | ---: |
| QBE | 2,172,779,312 | 1,512,597,252 | 0.696158 |
| LLVM O3/full LTO | 1,665,551,214 | 1,145,239,817 | 0.687604 |

These are medians of three CPU10 `instructions:u` samples. All runs print exactly
`-169075163` and `-169016441`. Raw samples retain the observed approximately 1%
variation. Both backends remove all nine scope-pin sites from `advance` and reduce
balanced H pairs from **1,520,009 to 20,005**. O acquisitions/releases remain 1/3,
heap allocations/retirements 2/2, clones zero and uniqueness checks 20,007.
These reductions must not be multiplied by other slices as a substitute for a
combined measurement; the parent owns that run and full acceptance remains open.

## Correctness evidence

- Six guest files pass **54/54 assertions** in each GC-stress/RC-counting and
  actual QBE/LLVM combination, **216 total**. They include callback publication,
  record snapshots, iterator identity, nested mutable arguments and private loans.
- Four out-of-bounds record writes preserve `R_LIST_BOUNDS` and cleanup.
- The eight-case unaccounted inert-receiver driver passes on both backends with
  identical balanced counts: heap 154/154, O 72/226, H 233/233 and eight arena
  allocations.
- Structural tests prove plain updates remove pins while index callbacks and
  records containing managed fields retain them. New guest cases cover repeated
  negative-index writes with a snapshot, a snapshot-publishing index callback,
  and nested record writes inside an arena.
- Focused inert-update tests **12/12**, RC tests **69/69**, formatting and
  whole-tree Guardian **88/88** pass.

Before Debug compiler SHA-256:
`11d7a1936e91503c4d84259ff00bd0ded643aa974a6afff5b514b898effab044`.
After Debug compiler SHA-256:
`a438f3bccec1e4c6683b0908feaed1fa78929c4556cf42651d26ad2fc1299f6a`.

[`experiments/d9-rc-inert-plain-updates-20260926`](../../experiments/d9-rc-inert-plain-updates-20260926)
contains full commands, hashes, emitted IL, stdout, count records and instruction
samples. Its `compare.py BEFORE AFTER OUTPUT --cpu 10` rebuilds and measures the
same reduced input through build slots. Permanent behavior tests are in
`tests/lang/rc_inert_receivers.my`. The parent integration owns the combined gate.
