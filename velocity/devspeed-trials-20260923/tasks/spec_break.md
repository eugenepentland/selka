## Task: add `break` to Lox

`lox/` holds a Lox interpreter (the language from *Crafting Interpreters*) with two
engines, a bytecode VM and a tree-walking interpreter; `lox/SPEC.md` specifies it and the
implementation you maintain is in `lox/ports/LANG/` (read its `NOTES.md` and
`bench.json`). Add a `break` statement to Lox in **both** engines:

- `break;` exits the innermost enclosing `while` or `for` loop immediately. In a `for`
  loop the increment clause does not run. Execution continues after the loop.
- Locals declared inside the loop body go out of scope as usual; a closure that captured
  one of them keeps seeing the value it had when the loop was left.
- `break` is a reserved word. `break` outside any loop — including inside a function
  body that is itself inside a loop — is a compile error reported like the port's other
  compile errors: `[line N] Error at 'break': Can't use 'break' outside of a loop.`
  (exit status 65).
- Add unit tests in the port's existing test style.
- The port's existing unit tests and the conformance corpus must still pass:
  `python3 lox/harness/lox_bench.py conformance --binary <your built lox> --engine both --stress`
- `build.sh` in the run directory must build the interpreter into an executable named
  `prog` in the run directory; the grader runs `./prog [--engine=vm|--engine=tree] [--gc-stress] FILE`.
