# Next generic result-handling implementation

Concrete result-bearing signatures currently reject during abstract generic type
validation. Enabling them requires checking the same handling obligations as an
ordinary function before any template is instantiated. Removing that rejection
alone would let an uncalled template silently drop or duplicate a result.

The next implementation should cover concrete result shapes while keeping type
parameters symbolic. Generic result type declarations and associated success/error
type constraints remain separate requirements.

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

Use the existing concrete checker (`sema.zig`'s pending-state operations,
result operations and temporary checks) as the behavioral reference. Share state
comparison/transition helpers where the concrete and symbolic representations
permit it, while retaining distinct type resolution. Extend abstract locals with
result availability and make scope/branch/loop checking explicit before allowing
result-bearing types in `concreteType`.

Acceptance must include uncalled invalid templates, consumed aliases, discarded
results, missing handling on one branch, returning/fallthrough match arms,
loop/short-circuit mismatches, overwrites, nested aggregate obligations and early
propagation with live temporaries. Valid examples must execute both success/error
paths through VM/native backends with matching source traces. Allocation sweeps
must cover checking and execution; no baseline or suppression can stand in for
these missing abstract rules.

This document records pending implementation and acceptance requirements. None of
these new generic result behaviors is marked implemented by this plan.


## Current implementation seams

At commit `27f4eec`, `generic_bodies.zig` has no obligation state in `Local`.
`namedValue` only checks borrowing access; `endScope` removes bindings without a
handling check. The branch checker visits both branches sequentially, and the
loop checker visits its condition/body once without a state comparison.
`matchValue` restores lexical scope per arm but has no incoming obligation
snapshot. These are the points that must change together before result-bearing
concrete types can be enabled.

The ordinary checker in `sema.zig` already exposes the behavior to preserve:
`pendingState`, `restorePending`, `samePending`, `pendingObligation` and
`requireHandled`. Its snapshots include both whole-value availability and partial
field moves. A boolean-only abstract ledger must not accidentally erase the
partial-move requirement for result-bearing records. Keep the concrete type
rejection in place until the corresponding acceptance cases prove these
transitions, including early-return paths with evaluated temporaries.
