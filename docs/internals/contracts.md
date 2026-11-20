# Contracts: how it works

Implementation detail moved out of `docs/contracts.md`. The guide keeps the user-visible rule.

## What the compiler proved

A clause becomes a test and a trap in the compiled code: Core folds a decided comparison to a constant branch, and LLVM removes the dead trap.

The status is not a count of trap blocks. A decided check keeps its trap block in
`selka dump-ir` and `--emit-llvm` (a `br i1 true` to the passing side, the dead
trap behind it), and a branch that folds to the trap is not a refutation by
itself: in `a or b` with `b` false, the trap is reached only when `a` fails at run
time, so the clause is kept. A copy is refuted only when the block its check
passes to is unreachable. Core folds a decided comparison of an `and`, `or` or
`not` chain to a constant branch; a chained comparison such as
`0 <= value <= 255` is one boolean, which the facts decide but Core does not
fold, so its branch stays in Core's output for LLVM's optimizer to remove. Its
status is still proved: the facts state its trap unreachable.

A proved clause rests on the fact certificate: the facts state the clause's trap
unreachable, a Debug compiler validates that statement before it emits the
program, and a `--verify-facts` build keeps a fact assertion in every block the
facts call unreachable, so a wrong proof traps `R_CORE_FACT` instead of passing.
