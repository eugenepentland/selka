## Task: fix a bug report in Lox

`lox/` holds a Lox interpreter (the language from *Crafting Interpreters*) with two
engines, a bytecode VM and a tree-walking interpreter; `lox/SPEC.md` specifies it and the
implementation you maintain is in `lox/ports/LANG/` (read its `NOTES.md` and
`bench.json`). A user reports:

> With `--gc-stress`, some programs that use closures misbehave on the VM engine —
> depending on the program they crash or print wrong values. Without `--gc-stress`, and
> on the tree engine, the same programs are fine. For example, this should print `1`
> then `2` under `./lox --engine=vm --gc-stress counter.lox`:
>
> ```lox
> fun counter() { var n = 0; fun inc() { n = n + 1; return n; } return inc; }
> var c = counter();
> var junk = nil;
> for (var i = 0; i < 50; i = i + 1) { junk = "x" + "y"; }
> print c();
> print c();
> ```

Find the root cause and fix it (not the symptom). Add a regression test in the port's
existing test style. The port's existing unit tests and the conformance corpus must pass,
including `python3 lox/harness/lox_bench.py conformance --binary <your built lox> --engine both --stress`.
`build.sh` in the run directory must build the interpreter into an executable named
`prog` in the run directory; the grader runs `./prog [--engine=vm|--engine=tree] [--gc-stress] FILE`.
