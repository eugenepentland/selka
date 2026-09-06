# Generic result-handling requirements

Concrete whole-value result handling is now implemented; see
[the implementation and acceptance record](generic-results.md). The requirements
below remain the acceptance contract. Partial field moves, runtime ownership,
generic result declarations and associated success/error constraints are still
pending; whole-value acceptance does not establish those capabilities.

## Required behavior

- A result parameter or result-valued binding starts with a handling obligation.
  Returning it, passing it by value, matching it, propagating it or explicitly
  acknowledging it transfers/discharges that obligation exactly once.
- Reading a transferred binding rejects. Returning or leaving a scope with an
  outstanding result rejects; replacing an outstanding result also rejects.
  Ordinary `discard` cannot acknowledge a result.
- Acknowledgement evaluates its operand and preserves traps and side effects.
  Match payloads inherit nested handling obligations, including when wrapped in
  records, arrays or unions. A `(discard)` payload pattern cannot drop one.
- Every branch and match arm starts from the same incoming obligation state.
  Paths that continue must agree on which outer bindings remain available.
  Returning paths must discharge their outstanding obligations independently.
- A loop must preserve the incoming obligation state on its continuing path.
  Short-circuit Boolean expressions require the same agreement between executed
  and skipped paths. Scope exit must inspect obligations before removing locals.
- Projection/update/length/replacement rules must prevent silently dropping
  sibling or replaced result-bearing values. Partial moves need explicit rules;
  they cannot be inferred from ordinary copyable record projection.
- `try` requires a compatible declared result return shape, preserves the success
  value, transfers the error result, and checks obligations on its early-return
  path, including already-evaluated temporary arguments and aggregate fields.

## Implementation and acceptance

The ordinary checker (`sema.zig`) supplies the behavioral reference. The symbolic
checker now maintains whole-value availability, checks scope/return exits, restores
incoming branch/match states and compares continuing paths. Expression-local
temporary counts protect propagation. Shared result diagnostic codes are declared
in `diagnostic.zig`.

Acceptance must include uncalled invalid templates, consumed aliases, discarded
results, missing handling on one branch, returning/fallthrough match arms,
loop/short-circuit mismatches, overwrites, nested aggregate obligations and early
propagation with live temporaries. Valid examples must execute both success/error
paths through VM/native backends with matching source traces. Allocation sweeps
must cover checking and execution; no baseline or suppression can stand in for
these missing abstract rules.

## Next implementation: partial field obligations

`take_field` and `read_field` still reject during abstract checking. Extend local
state with partial field availability and preserve it in every snapshot/restore
and continuing-path comparison before enabling those operations. Follow the
ordinary checker's `pendingObligation` rules: only remaining result-bearing fields
keep a handling obligation; whole-record access after a partial move rejects.
Reassignment may replenish a binding only after remaining obligations are handled.

Acceptance must include repeated moves, reads after moves, remaining ordinary
field reads, multiple result fields, branch/loop disagreement about which field
moved, whole-record use after a move, replenishment, early propagation with
remaining fields and allocation-failure cleanup. Runtime-owned field support also
requires the separate generic ownership/region rules and must not be inferred
from this concrete result ledger.
