# Implemented semantics

Status: M0–M3, 2026-09-05. This file describes implemented behavior, while
[plan.md](plan.md) describes the complete target and future experiments.

- A source file contains exactly one `fn main() -> i64` with a block body.
  Statements include `let`, `let mut`, assignment (`=`, `+=`, `-=`), nested
  blocks, `if`/`else`, `while`, `discard`, and explicit `return`. A function must structurally return; statements after
  a terminating return or block are rejected.
- Expressions contain decimal `i64` literals, booleans, local references,
  parentheses, unary negation/not, arithmetic `+ - * / %`, short-circuit `&& ||`, and comparisons
  `== != < <= > >=`. Unary operators bind above multiplication, then
  addition/subtraction, ordering, equality, conjunction, and disjunction. Binary operators associate left;
  operands evaluate left to right. Booleans are distinct from integers; ordering
  requires integers and equality requires matching primitive types.
- Literal magnitudes ordinarily range from `0` through `9223372036854775807`.
  Magnitude `9223372036854775808` is allowed only under direct unary negation,
  ignoring parentheses. Negating the resulting minimum again traps.
- Addition, subtraction, multiplication, negation, and division trap on overflow, with a diagnostic at the
  responsible operator. This is independent of the Zig optimization mode.
- `check` parses and type-checks without lowering or execution; an expression
  that would overflow still passes checking. Out-of-range literals do not.
- Whitespace and `//` line comments are accepted. Identifiers are ASCII.
  LF and CRLF produce correct one-based line/byte-column locations.
- The parser limits combined recursive syntax nesting to 256 levels. Semantic conversion
  and lowering do not recursively traverse the potentially deep left-associative
  expression tree. Lowering uses an explicit work stack.
- The instruction stream is an in-memory tagged union with source spans.
  Local slots retain their types and carry an uninitialized sentinel in the VM.
  Arithmetic pops the right operand before the left operand. Validation rejects
  malformed internal stack shapes as host/internal failures rather than guest traps.
- One compilation request owns its copied source/path, line index, AST, typed
  program, and instructions. Runtime operand storage is separately allocated
  and released on both successful execution and traps.
- `run` prints the integer result followed by a newline and exits 0. A source
  error or runtime trap prints no stdout result and exits 1. Usage, file I/O,
  allocation failure, and internal failures exit 2.
- `dump-bytecode` prints functions and instructions in deterministic order with
  source locations. It does not execute arithmetic.

- Every binding is initialized; an annotation must match the initializer's type.
  `let` is immutable. A name becomes visible after its initializer, and ceases
  to be visible at block exit. Active local/function names cannot be shadowed;
  sibling scopes can reuse names with independent identities.
- `W_UNUSED_BINDING` reports a binding with no resolved read. Plain assignment
  writes but does not read its target. `W_UNNECESSARY_MUT` reports a mutable
  binding with no assignment after initialization. Warnings sort by source
  position then code, appear only after successful checking, and do not change
  exit status or stdout. Initializers still run and can trap.

- Conditions and logical operands require booleans. Logical operators evaluate
  their right operand only when needed, including within `discard`. Bare
  expression statements are rejected; discard evaluates its operand and keeps
  its traps. Compound assignment counts as both a read and a write.
- Division truncates toward zero; remainder has the dividend's sign. Zero
  divisors trap. Minimum integer divided by `-1` traps; its remainder is zero.
- An `if` terminates only when both branches terminate. Loops always may fall
  through for return analysis, even `while true`. All branches are checked and
  counted for binding warnings regardless of constant conditions.
- `run --max-steps=N` accepts a positive decimal u64 budget, default 10,000,000.
  The VM checks the limit before each instruction dispatch. Budget exhaustion
  is a guest trap at the next instruction's source location. Other commands
  reject execution options. Jump validation checks target bounds and matching
  stack heights at control-flow joins.

Helper functions and call frames are not implemented yet. No future-feature
syntax is accepted as a placeholder with invented semantics.
