# D5: Lambdas are noncapturing only

Status: accepted; Wave 1 implementation pending integration.

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
diagnostic points to the name and recommends one of those repairs.
