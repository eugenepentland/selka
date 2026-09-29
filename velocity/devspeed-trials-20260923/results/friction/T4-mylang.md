# FRICTION.md — adding `%` to the mylang Lox port

Overall this went smoothly: the port's own `NOTES.md` (in
`lox/ports/mylang/NOTES.md`) is unusually thorough about *why* the code is
shaped the way it is, and every mechanical touch point for a new binary
operator — scanner token, opcode, Pratt-parser precedence table, VM handler,
tree-walker handler — was a small, grep-able, single-purpose edit that built
correctly the first time. The two things below are the only real slowdowns.

## 1. Could not write an end-to-end unit test that runs the interpreter

**What I tried.** Following the existing test style exactly (`compiler_test.my`
calls `compiler.compile` directly; `parser_test.my` calls `parser.parse`
directly), I wrote `vm_test.my` and `interpreter_test.my` calling
`vm.interpret(mut rt, mut o, source)` and `interpreter.interpret(mut rt, mut o,
source)` on small `%`-using programs, capturing `o.stdout`/`o.stderr` the same
way `compiler_test.my` captures `o.stderr`.

**What the tool said.** `mylang test .` refused both files, one error per
test function, e.g.:

```
vm_test.my:18:9: error[E_EFFECT_BOUND]: effect `clock` exceeds this signature's
ceiling: vm_test::run -> vm::interpret -> vm::run -> vm::call_value ->
natives::call_native -> natives::clock_native -> time::now, which no parameter
permits; add `clock: Clock` to the parameters
```

and the same shape for `interpreter_test.my`, through
`interpreter::evaluate -> interpreter::call_expr -> interpreter::call_value ->
natives::call_native -> natives::clock_native -> time::now`.

**How I resolved it.** `vm.interpret`/`vm.run` and `interpreter.interpret`/
`interpreter.evaluate` can, in principle, execute a Lox program that calls the
`clock` native, so the effect checker charges the whole function with `clock`
— unconditionally, for every program, not just ones that call `clock()`. A
`mylang test` function is only ever given `out: Stream` by the runner (per
`NOTES.md`'s own account of `--cases`, a case file "cannot make a capability"),
so no test can call either `interpret` entry point at all, regardless of what
the test program does. I fixed this by marking the two per-operator numeric
helpers `public` — `vm.numeric` and `interpreter.arithmetic` — since neither
one reaches a native, and testing *those* directly with a hand-built
`heap.Runtime` and pushed operands, the same way `compiler_test.my` reaches
into `heap.function_obj(...)` rather than reading stdout.

**Attempts / cost.** One failed attempt (8 compile errors across the two
files, one full `mylang test .` cycle to see them all at once), one fix
(exporting the two helpers and rewriting the tests around them, verified
green immediately). Call it 2 attempts, maybe 20 minutes.

**Documentation.** `lox/ports/mylang/NOTES.md`'s "Language and toolchain
friction" item 1 *does* describe this exact mechanism (it's why
`driver_tests.my` existed as a separate `--cases`-fed invocation with a
substituted `natives.my`, before this trial copy removed that file for not
compiling on the installed compiler). It helped me understand the cause
quickly once I hit the error, but reading it beforehand did not make me
predict that it blocks *any* call into either `interpret` function from a
test, not just ones that read the clock's value — I had assumed a program
that never calls `clock()` would be fine. So: accurate, but I under-read its
scope on first pass. No file in `/home/epentland/ai/trials/devspeed-20260923/kit/docs/`
covers this (it's a port-specific consequence of `effects.md`'s design, not
something the effects doc itself calls out with this consequence).

## 2. mylang's own `%` is not C's `fmod`

The task wants "the floating-point remainder with the sign of the left
operand (C's `fmod`)". mylang has a native `%` for floats, but
`floating-point.md` and `python-syntax.md` both say plainly that it "follows"
`//`'s floor-rounded quotient — i.e. Python's modulo, sign of the *right*
operand. Worked example in `floating-point.md`: `negative % 2.0 == 1.0` where
`negative = -5.0`, which is floor-mod, not fmod (fmod(-5, 2) is -1). There is
no `math.fmod` and no transcendental-function-style helper for it; `math`
only has `sqrt`/`pow`/rounding. I derived the standard `a - trunc(a / b) * b`
identity (trunc rounds toward zero, giving the dividend's sign) and checked it
against the task's four examples with a two-line throwaway script run via
`mylang run` before touching the port — all four matched exactly on the first
try, so no rework was needed once the formula was in.

**Cost.** One attempt, a few minutes, entirely because the docs were precise
enough (worked examples, not just prose) to derive and check the formula
without touching the actual port code.

**Documentation.** `docs/floating-point.md` helped, correctly and
unambiguously — it just answers a different question than "how do I get C's
fmod" than I first assumed `%` would. Nothing misled me; I just had to notice
the semantics on my own rather than being told them.

## No other friction

Adding the token (`scanner.my`), the opcode (`chunk.my`), the tree-parser's
`factor()` and the bytecode compiler's `binary()`/`precedence_of()`
(`parser.my`, `compiler.my`), and the two runtime handlers
(`vm.my`'s `numeric`, `interpreter.my`'s `arithmetic`) were each a one- or
two-line addition next to the existing `*`/`/` cases, and the whole project
(`mylang build lox/ports/mylang/main.my --project -o prog`) built clean on the
first try, on both the default LLVM/ReleaseFast backend and `--backend qbe`
(relevant because `NOTES.md` documents a real QBE regression, "no more pm
slots", on a large inline VM dispatch loop — extending the existing
`numeric` handler rather than inlining a new case avoided re-triggering it).
`mylang test .` picked up the two new `*_test.my` files with no extra
configuration, exactly as `NOTES.md` describes. The conformance corpus
(`python3 lox/harness/lox_bench.py conformance --binary ./prog --engine both
--stress`) is unaffected: 246/246 (vm) and 241/241 (tree), normal and
gc-stress, unchanged from the port's documented baseline.

## Ranked changes that would have saved the most time

1. **Effect inference should be scoped to what a specific run can reach, not
   what the interpreter function could ever reach.** Charging `vm.interpret`
   and `interpreter.interpret` with `clock` unconditionally makes it
   impossible to unit-test *any* interpreter behavior end-to-end from
   `mylang test` — not just clock-touching behavior — which is why this port
   has no `vm_test.my`/`interpreter_test.my` at all upstream and had to grow a
   whole second test-invocation mechanism (`--cases` plus a hand-substituted
   `natives.my`) just to cover 11 tests. A capability-carrying interpreter
   entry point is a very common shape (any embedded scripting language), so
   this hits more than just this port.
2. **Let a test see the private items of the module it tests.** I had to
   widen `vm.numeric` and `interpreter.arithmetic` from module-private to
   `public` purely so a `*_test.my` file could call them, permanently growing
   each module's public surface for a test-only need. A `mylang test`-only
   visibility (or letting `<module>_test.my` specifically see `<module>`'s
   private declarations) would keep the production interface as narrow as the
   author intended.
3. **A `math.fmod` (or an explicit worked example of the `a - trunc(a/b)*b`
   idiom next to the `%`/`//` semantics).** Small compared to the above, but
   C's remainder convention is common enough (hashing, wrapping arithmetic,
   porting any C-family language) that every program wanting it currently has
   to re-derive the identity from `trunc` by hand.
