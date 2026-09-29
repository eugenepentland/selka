## Task: add a `%` operator to Lox

`lox/` holds a Lox interpreter (the language from *Crafting Interpreters*) with two
engines, a bytecode VM and a tree-walking interpreter; `lox/SPEC.md` specifies it and the
implementation you maintain is in `lox/ports/LANG/` (read its `NOTES.md` and
`bench.json`). Add a remainder operator `%` to Lox in **both** engines:

- `%` is a binary operator with the same precedence and associativity as `*` and `/`.
- Both operands must be numbers; otherwise it is a runtime error with the same message
  and behaviour as `*` with non-number operands.
- The result is the floating-point remainder with the sign of the left operand (C's
  `fmod`): `7 % 3` is `1`, `-7 % 3` is `-1`, `7 % -3` is `1`, `5.5 % 2` is `1.5`.
  Results print with the existing number formatting.
- Compile errors mention the token as for any other operator (e.g. `print % 3;` reports
  `Error at '%': Expect expression.`).
- Add unit tests for the new behaviour in the port's existing test style.
- The port's existing unit tests and the conformance corpus must still pass:
  `python3 lox/harness/lox_bench.py conformance --binary <your built lox> --engine both`
- `build.sh` in the run directory must build the interpreter into an executable named
  `prog` in the run directory; the grader runs `./prog [--engine=vm|--engine=tree] FILE`.
