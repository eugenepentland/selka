# C/D: explicit result propagation

Status: postfix `?` propagation is implemented, including result-obligation checks
on its early-return path. Typed result handling, propagation, and explicit release
now cover the plan's fallible-result acceptance cases. This page was written when the
operator was spelled `try expression`; the spelling changed on 2026-09-13 and the
rules below are unchanged.

## Syntax and typing

```text
result Quotient { ok: i64, err: i64 }
result Positive { err: i64, ok: bool }

fn positive(outcome: Quotient) -> Positive {
    return new Positive.ok(outcome? > 0);
}
```

`expression?` evaluates its operand exactly once. An `ok` result yields its
success payload and continues the surrounding expression. An `err` result returns
from the current function, constructing that function's declared result type with
the same error payload. Input and output result types may differ, including their
success payload types and variant declaration order. Their error payload types
must match exactly, including nominal identities. No implicit error conversion
or representation access is introduced.

The operand and enclosing function return type must both be declared `result`
types. An ordinary union with cases named `ok` and `err` is insufficient. `main`
returns i64, unit, or a result, so a i64 entry handles fallible results explicitly
instead of propagating them to the CLI.

`?` binds tighter than any binary operator. Thus `2 * operation()? + 1` unwraps
the call before the surrounding arithmetic. Parentheses can delimit a larger
operand. Repeated `?` can unwrap nested results when each error payload matches
the enclosing function's error type. A success payload that itself carries a
result obligation still requires handling, transfer, or an explicit `_ =` release.

`?` may appear in arguments, constructors, conditions, and ordinary expressions.
Failure skips the rest of the current expression and function. Short-circuit
operators retain their existing evaluation rules: a skipped `?` does not execute.
Success does not establish that the function returns on every path, so ordinary
missing-return checks still apply. Arithmetic traps and host failures are not
converted into error payloads or caught by `?`.

## Obligations on the early-return path

At every `?`, all other active result-bearing bindings must already have been
handled or transferred. Releasing them only after a successful `?` would
leave its error path incomplete and is rejected. These checks are conservative
even when a literal operand happens to construct `ok`.

The checker also tracks unfinished value operands inside the surrounding
expression. For example, `consume(first_result, operation()?)` cannot silently
drop the already-evaluated `first_result` on failure. Result-bearing constructor
fields and wrappers receive the same check. Move/handle those values in an order
that discharges their obligations, or explicitly match failure and make the
required handling decisions. Merely moving a result out of its local into a
pending argument does not erase it.

Ordinary value temporaries may be abandoned when failure returns; they are released
by the VM. The existing branch, loop, and short-circuit rules still check result
obligations on every continuing path. Propagation does not permit conditional use
of a result slot that another continuing path leaves pending.

## Lowering and cleanup

`TRY_RESULT` carries resolved input/output result identities and a failure target.
On success it replaces the input result with its retained success payload. On
failure it builds the output error value, releases unfinished operands belonging
to the current frame, leaves the caller's operands intact, and branches to an
explicit cleanup-and-return sequence. Variant mapping uses resolved named `ok` and
`err` cases, not an assumed declaration order.

The cleanup sequence uses the ordinary value-return instruction, which releases
locals and restores caller access. No exception handler stack or host
recursion is introduced.

Instruction validation checks result identities, error payload compatibility,
function return type, targets, and both stack shapes: success preserves the current
operand height; failure carries exactly one result after discarding unfinished
operands. Allocation failures and instruction-budget traps release execution
storage, including partial ordinary aggregate constructions and error payloads.

## Evidence

199/199 tests pass in Debug and ReleaseFast (174 core, 25 actual CLI) on Guardian's
`0.17.0-dev.1683+5ceec001b` snapshot. Tests cover:

- success payloads, nominal input/output remapping, named tags in reversed order,
  and exact error identity;
- invalid operands/return types and missing returns;
- pending locals/parameters and unfinished result-bearing argument/field/wrapper values;
- single evaluation, skipped later arguments, preserved caller operands, loop conditions,
  and short-circuit behavior;
- recursive propagation, nested result unwrapping, and explicit release;
- partial aggregate operands and nested aggregate error payloads under allocation failures;
- every instruction-budget boundary of a nested propagation/cleanup program;
- 10,000 propagated failures within 16 KiB live runtime allocation, with no storage
  remaining after success or each tested trap;
- malformed result/target metadata, duplicate identity, and actual CLI diagnostics/dumps.

`examples/propagation.my` returns 20. Exact discovery is `exact-v13`, retaining
propagation and its output result identity. Formatting and whitespace checks pass.
Guardian gates were not exercised; hosted CI has not run.
