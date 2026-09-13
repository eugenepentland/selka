# Concrete results in generic bodies

Generic bodies now accept concrete result-bearing data graphs while keeping type
parameters symbolic. `examples/generic-results.my` combines success/error
propagation, exhaustive matching, early-return branches and a result-replenishing
loop; it returns 9.

A result-valued parameter, binding or payload has one handling obligation.
Reading it by value transfers that obligation; subsequent reads reject. Returning,
passing, matching and explicitly acknowledging results preserve this rule.
Scope exit and return reject outstanding obligations. Assignment requires handling
the old result first, while self-transfer assignment remains valid. Ordinary
`discard` cannot acknowledge a result, and acknowledgement evaluates its operand,
including traps.

Each branch and match arm starts from the same incoming state. Only continuing
paths participate in the merge; returning paths must independently discharge
obligations. Loops preserve incoming availability through their condition and
continuing body. Short-circuit operands must agree with the skipped path. These
checks run on uncalled templates as well as instantiated ones.

Nested record, array and union payloads retain result obligations. A payload
pattern cannot use `(discard)` for a nested result. Projection cannot erase a
sibling result; array indexing cannot erase other result elements. Length,
replacement and record update reject operations that would silently drop a
result-bearing value. Whole-value transfers and preserving updates of unrelated
ordinary fields work.

`try` requires concrete result input/output shapes with matching error types.
It checks outstanding local obligations on its early-return path and also rejects
previously evaluated result temporaries in enclosing calls, arrays or records.
The recursive checker counts live result temporaries across child expressions
and releases that count when their containing expression consumes them. Successful
nested result payloads become new obligations. References to result-bearing
parameters remain rejected consistently with the ordinary checker.

## Acceptance

`src/generic_results_test.zig` covers uncalled invalid templates, aliases,
acknowledgement traps, overwrite/self-transfer, branch/match continuation merges,
loop and short-circuit mismatches, nested payloads, aggregate restrictions,
propagation success/error paths, incompatible error types and live temporaries.
Allocation sweeps exercise checking, execution and native emission with branches,
loops, short-circuit calls and propagation. Native parity fixtures exercise the
source example, imported result schemas/helpers with aliases, both result paths,
and a located trap during acknowledgement.

## Remaining work

This is concrete result support, not generic type constructors. Symbolic
success/error shapes and associated constraints remain pending. [Partial field moves](generic-fields.md) now preserve remaining obligations and
field-aware path merges. [Concrete owned flow](../legacy/experiments/generic-owned.md) now preserves cleanup and transfer.
Runtime operations/regions, generic codec constraints and public generic tooling
remain open.
