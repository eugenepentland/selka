# Generic result-handling requirements

Concrete whole-value result handling is now implemented; see
[the implementation and acceptance record](generic-results.md). The requirements
below remain the acceptance contract. Partial field moves are now covered by
[generic fields](generic-fields.md). Runtime operations/regions, generic result declarations
and associated success/error constraints are still pending; whole-value acceptance
does not establish those capabilities.

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
paths through the VM with checked source traces. Native parity is outside the
active interpreter-first roadmap. Allocation sweeps
must cover checking and execution; no baseline or suppression can stand in for
these missing abstract rules.

## Partial field acceptance and remaining ownership work

`take_field` and `read_field` now maintain immutable partial field state through
snapshots, restoration and continuing-path comparisons. Remaining result-bearing
fields keep their obligations; whole-record access after a partial move rejects.
Reassignment replenishes a binding only after remaining result obligations are
handled. [The partial-field record](generic-fields.md) documents executable and
allocation-failure acceptance.

[Concrete owned fields](generic-owned.md) now participate in whole/partial move
state, cleanup and transitive cleanup-effect bounds. [Buffer/pool acquisition and mutation](generic-runtime.md) now check explicit
authority and effects. [Provider operations](generic-providers.md) now enforce capability/result/effect
contracts. [Concrete local array/buffer views](generic-local-views.md) now preserve
owner access and input provenance. [Generic arena/reset scopes](generic-regions.md)
now track allocator origins and reject escapes. Generic result constructors and
associated success/error constraints remain pending independently.
