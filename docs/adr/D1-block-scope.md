# D1: Keep block-scoped locals

Status: accepted for `bootstrap-v1`; implementation reconciliation required.

## Rule

A local introduced inside `if`, `for`, `while`, `with`, or a match arm belongs
to that lexical block. Code that needs the value after the block declares it
before entering the block. Nested blocks may assign an already-declared outer
local.

## Rejected alternative

Reject function-scoped implicit handoff, where an assignment inside a nested
block introduces a binding that remains visible after the block and definite
assignment is merged across paths. Lexical ownership keeps resolution and
incremental dependencies local.

## Compatibility consequence

The current tree disagrees with this decision. Commit `8420528` implements
function-scoped locals plus `E_UNBOUND` for a read on a path that may not assign
the name. Reconciliation is a separate semantic change: the orchestrator must
choose whether to restore block scope or revise this ADR and `bootstrap-v1` before
the bootstrap grammar is frozen. Existing programs relying on block-to-function
handoff would need to predeclare the local.
