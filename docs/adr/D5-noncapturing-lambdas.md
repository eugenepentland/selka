# D5: Lambdas are noncapturing only

Status: accepted; Wave 1 implemented, with project-merge and cache-copy coverage completed in the Wave 1.1 stabilization pass.

## Rule

`lambda parameters: expression` is expression-bodied and contextually typed by
an expected callback type. It may use its parameters and module constants. It has
no defaults or statements, and its effects must fit the callback's exact bound.

## Rejected alternative

Reject local capture and inferred closure environments. A lambda without an
expected callback type is also rejected. Captures would introduce hidden state,
allocation, and invalidation edges outside the existing function-value model.

## Compatibility consequence

Named top-level callbacks remain valid. Concise callback sites may migrate to
lambdas, but state is passed as an explicit parameter or managed `Cell`. A capture
diagnostic points to the name and recommends one of those repairs. Module
projects, the persistent frontend cache and the in-memory syntax cache all carry
`Program.lambdas`, so a warm path checks the same lambda program a cold parse
would.
