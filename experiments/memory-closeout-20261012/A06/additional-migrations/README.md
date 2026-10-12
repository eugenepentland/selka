# Additional 23 registered guest fixtures

The coordinator reserved these files after the initial 64-source survey.
`before.json` preserves A10's support3 source survey; `original-sources/` contains
the exact C0 source bytes as deterministic gzip archives. `ledger.json` reports
current identities, explicit-copy burden and every unresolved source refusal.
No failure is removed from the denominator. Original assertions and public test
function names/order are mechanically preserved.

Copies make independent storage explicit for retained parameters, fields, list
elements, repeated construction and snapshots. The source changes alter
allocation contracts and cannot be presented as compiler-only savings. Registered
native RC/COW allocation and IR expectations need review during retirement; these
source checks do not replace those gates.

The intermediate Support4 source survey admits 18 of 23 sources. The five refusals are
`ce_elements.my:70`, `m_recursive_values.my:181`, `row_cow.my:145`,
`v_nested.my:20` and `v_wide_managed.my:61`, each at a nested list-slot write.
A07 owns the checker and lowering repair; these fixtures retain their original
write shapes as positive regressions. Across all 23 sources the migration adds
165 explicit copy sites and changes 203 added/173 removed lines.

Source admission is insufficient for native qualification. A09's Support4
`dump-ir` probe of the admitted `ce_cow.my` still panics in `build.providerStore`
while resolving a missing IR value. Its source hash is
`3cacf6b0c40e8ddf85488fb8914f5c6ef1610d021a4bd522f950eedb96647a52`;
A07 and the coordinator have the reproducer. Support5 fixes that lowering panic and passes the exact three native output lines, with zero RC events and zero exit-live bytes (A09 evidence). Final integrated qualification remains required. The two `ce2_effects` bounds-error locations
move to 239:30 and 247:9; the expected error, indices, lengths and preceding
output are unchanged, and the coordinator owns updating those registrations.

Evaluation-order changes preserve specific observed behavior:

- `ce2_effects.read_const` copies the receiver before advancing its mutable frame.
- `v_snapshot` captures each original indexed receiver before the callback that
  changes, grows or replaces it. The callback and later observations retain their
  original order.
- `u1_state` captures a scalar target before the call mutates its frame;
  `v_mut_window` completes the nested call before the outer call.
- `m_recursive_values` preserves ancestor-write cancellation with a captured row
  copy: the inner write and outer append both execute, but only the branch without
  an ancestor write publishes the captured row. Sibling and same-place callbacks
  use explicit evaluation temporaries; existing assertions retain their original
  expected rows and tick counts. The original overlapping form remains a negative
  regression in `a06_nested_write_test.zig`.

The original depth-40 equality fixture duplicated both children from the previous
tree at every level. RC represented that as a shared DAG; independent deep copies
would materialize roughly 2^40 nodes. With coordinator approval, the current
fixture keeps depth 40 but adds a fresh leaf alongside the previous tree at each
level. NaN non-reflexivity and signed-zero equality remain tested, and a different
leaf adds an inequality check. This is a changed workload shape with bounded owned
storage, not an equivalent allocation/performance comparison. The original DAG
source is frozen, and its duplicate move is retained as an expected refusal.


The approved `ce_cow` followup removes three explicit Runtime copy sites using
`mut it.rt` projections, with no intervening outer-owner observation omitted.
`../evidence/ce-cow-projection/` preserves both migrated source identities and the
controlled same-Support5 native allocation comparison. Both retain the exact
registered output, all iterations, required callable/Builder/snapshot copies,
zero RC events and zero managed exit-live bytes. Managed peak is unchanged.
The current ledger measures total burden from the C0 original; this followup is a
source migration optimization and is never counted as a compiler-only saving.
