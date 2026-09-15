# D1: Keep function-scoped locals with sound definite assignment

Status: accepted for `bootstrap-v1`; implementation landed in the Wave 1.1 stabilization pass.

## Rule

A local introduced by an assignment anywhere in a function body is one
function-scoped binding from its first assignment to the end of the body.
Nested `if`, `elif`, `else`, `with`, `match`, `for`, `while`, `range`,
`reversed` and `zip` blocks reassign that binding rather than introducing a new
one. A `for` loop variable and a `match` payload binding remain scoped to their
own block.

The binding is definitely assigned only on paths that assign it. An assignment
in every continuing branch of an `if`/`elif`/`else` binds the name afterwards.
A `for` or `while` loop may execute zero times, so an assignment made only in
the loop body does not bind the name after the loop. Code that reads the name
after such a loop must assign it before the loop.

## Rejected alternatives

Reject block scope. Function scope is more Python-like, is convenient for
agent-written code, and does not enlarge cross-function incremental
dependencies beyond the function body that already owns the binding.

Reject treating a body assignment as definite after a loop. Native storage for a
local that was never executed is uninitialized; accepting that path would make
checking unsound and could return an arbitrary value.

## Compatibility consequence

Programs that relied on a name first assigned inside a `for` or `while` body
being readable after the loop must predeclare it, for example `last = 0` before
the loop. Reading the name after a zero-iteration loop is `E_UNBOUND`, not an
undefined native read.
