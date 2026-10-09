# C/D foundation: typed recoverable results and handling obligations

Status: nominal result types, exhaustive handling, explicit acknowledgement, and
transfer of result obligations and [explicit propagation](propagation.md) are
implemented. Resource ownership, partial-construction cleanup, generics, and typed handles
remain pending. This is a foundation for C/D, not completion of either track.

## Result declarations and explicit handling

```text
enum DivisionError { zero }
result Quotient { ok: i64, err: DivisionError }

fn divide(n: i64, d: i64) -> Quotient {
    if d == 0 { return new Quotient.err(new DivisionError.zero); }
    return new Quotient.ok(n / d);
}

fn value_or_zero(outcome: Quotient) -> i64 {
    match outcome {
        Quotient.ok(value) => { return value; },
        Quotient.err(_) => { return 0; }
    }
}
```

A `result` declaration has exactly two named payload cases, `ok` and `err`, in
either declaration order. Both payload types are explicit. Error payloads may be
existing value types, including closed enums, records, or nominal domains. Result
types are nominal: equal payload layouts do not make two result types substitutable.
`result` is contextual at type declarations, so ordinary variables/functions may
still use that name.

Construction uses the existing checked variant syntax. Exhaustive matching handles
both outcomes and is an explicit decision about failure. An error arm may convert
failure to a default or absence; the compiler does not infer that such a policy is
correct. Returning a result forwards its obligation to the caller. Manual
propagation can match an input and construct a declared error result on that path.
`try` now propagates compatible error payloads into the enclosing result type;
see [propagation semantics](propagation.md). There is no implicit error coercion.

`acknowledge expression;` explicitly accepts that the value may contain failure and
discharges all result obligations carried by it. It evaluates its entire expression
and then releases the value. It does not suppress arithmetic traps, host failures,
or side effects. Ordinary `discard` rejects result-bearing values. Acknowledgement
of a value with no result obligation is also rejected.

## Transfer and control flow

A result-bearing binding or value parameter starts with a pending obligation.
Reading that binding by value transfers the obligation; it does not create a
second independently usable result. `let next = previous;` transfers it to `next`,
passing it to a helper transfers it to a parameter, and returning it transfers it
to the caller. Subsequent use of the consumed binding is rejected. All helper
bodies are checked, including unused functions, so forwarding to a helper that
ignores its parameter does not erase the obligation.

Every ordinary scope exit and return must have discharged or transferred all
active local obligations. Binding an unused result is an error, not an advisory
unused-binding warning. Replacing a result-bearing variable requires the previous
value to have been transferred or handled first. Reinitializing a consumed mutable
slot creates a new obligation. Self-assignment transfers the existing obligation
back into the same slot.

At a branch or match join, every continuing path must have the same obligation
state for outer bindings. A terminating branch checks its own exits and does not
constrain the surviving path. Loops require the same outer obligation state at
entry and the back edge; consuming and replacing a mutable result slot inside
an iteration is allowed. Loop conditions cannot consume an outer result slot.
Short-circuit right operands also cannot conditionally consume an outer result.
These are conservative rules; constant conditions do not bypass the path checks.

## Wrappers and current limits

Schema collection derives result obligations transitively through record fields,
union payloads, and nonempty arrays/tables. A wrapper therefore retains the
obligation even when it is bound or passed through another API. Empty arrays carry
no element obligations. Types with alternative payloads are conservative: a union
that can contain a result remains result-bearing even when its current variant
has no payload.

Whole wrappers can be transferred, returned, acknowledged, or exhaustively matched
when they are variants. Matching a result-bearing payload requires a binding;
`(_)` cannot silently drop a nested result. A record projection may extract
its sole result-bearing field when every omitted field is ordinary. Selecting an
ordinary field while dropping a result-bearing sibling is rejected. Single-element
arrays permit consuming extraction; indexing larger result-bearing arrays is
rejected because it would drop the other elements. Length queries, replacements,
and record updates that would drop obligations are likewise rejected. Preserving
updates of ordinary fields can carry result-bearing fields forward.

This first obligation model transfers whole bindings. It does not yet support
partial moves from multiple result-bearing fields, borrowing result-bearing
values, or result-bearing slice parameters. Use whole-value transfer or explicit
acknowledgement where appropriate. General owned-resource moves and borrowing
require the C ownership work; these restrictions are not its final design.

The VM still uses immutable, reference-counted aggregate values. Static result
transfer enforces a handling contract, not unique ownership of a guest resource.
No external resource or allocator capability is introduced by a result declaration.
Existing arithmetic traps remain distinct from recoverable error values; the
example division API models zero explicitly but does not convert arithmetic
overflow or host out-of-memory into its declared error payload.

## Evidence

199/199 tests pass in Debug and ReleaseFast (174 core, 25 actual CLI) on Guardian's
`0.17.0-dev.1683+5ceec001b` snapshot. The result tests cover:

- success/failure payloads, nominal identity, schema errors, and exhaustive handling;
- binding/parameter/return transfer, explicit acknowledgement, repeated-use rejection,
  overwrite rejection, and unchanged expression evaluation;
- continuing and terminating branch/match paths, loop back edges, and short-circuit use;
- records, arrays, union wrappers, nested results, preserving updates, and rejected erasure;
- recoverable returns through active borrow scopes, with aggregate snapshots preserved;
- allocation failures through checking, execution, disassembly, and duplicate discovery;
- every instruction-budget boundary of a nested aggregate/result/borrow program;
- 10,000 acknowledged results within 16 KiB live runtime allocation and zero bytes
  live after success or each tested trap;
- actual CLI handling, related unhandled-result diagnostics, and `ACKNOWLEDGE` dumps.

`examples/results.selka` returns 7. Exact duplicate discovery is `exact-v13`, retaining
result-bearing expression types and explicit acknowledgement. Formatting and
whitespace checks pass. Guardian gates were not exercised; hosted CI has not run.

Explicit propagation now checks obligations on its early-return path. Next: owned
resources and partial-construction cleanup. C/D and the full roadmap remain
in progress.
