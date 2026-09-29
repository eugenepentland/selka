# FRICTION.md — adding `break` to the Rust Lox port

Overall this was low-friction: the existing port's conventions (an explicit `Flow` enum
for non-local control in the tree engine, `current_function`-style save/restore in the
resolver, `end_scope`'s local-popping logic in the VM compiler) generalized directly to
`break`, and every `cargo build` I ran during implementation succeeded on the first try
— no iteration loop against the compiler was needed. The genuine time sinks were
elsewhere: `SPEC.md` says nothing about `break` at all, so the design had to be inferred
by analogy rather than looked up, and the frozen conformance corpus has zero coverage
for a statement it doesn't know about, so I had to hand-author and manually eyeball
throwaway `.lox` scripts to build confidence before writing permanent tests.

## Points of friction

**1. `SPEC.md` is silent on `break`.** `grep -n -i break lox/SPEC.md` returns nothing.
There is no token, no grammar production, no error-message wording, no "spec question I
get to settle" placeholder — nothing to check a design against. I resolved this by
generalizing three existing patterns instead of inventing from scratch: `end_scope`'s
local-popping loop in `compiler.rs` (for what a `break` must emit before it jumps),
`Resolver.current_function`'s save/restore-around-a-function-body pattern in
`resolver.rs` (for why a `break` inside a function nested in a loop must still be
rejected), and the `Flow` enum already used for `return` in `interpreter.rs` (for how to
thread an early exit through statement execution without unwinding the host stack via
panic/exception). Zero compiler errors here, but real time spent reading rather than
being told. Not misleading, just silent — the existing code was the documentation.

**2. Confirming a two-line-vs-one-line diagnostic asymmetry wasn't a bug I'd
introduced.** Testing `var break = 1;` (break used as an identifier) gave the VM engine
two stderr lines:
```
[line 1] Error at 'break': Expect variable name.
[line 1] Error at 'break': Can't use 'break' outside of a loop.
```
but the tree engine gave only the first line. I was not confident this was correct
until I checked the pre-existing keyword `return` the same way (`var return = 1;`) and
got the identical shape: two lines from the VM, one from the tree engine. That confirmed
it is a pre-existing property of the port's architecture (the VM's single-pass
panic-mode compiler keeps compiling and can hit a second, independent error in the same
run; the tree engine's separate parse-then-resolve pipeline skips the resolve pass
entirely once parsing fails, so the resolver's loop-context check never runs) and not
something `break` introduced. This cost about three extra shell commands and a few
minutes, and nothing in `SPEC.md` or `NOTES.md` calls the asymmetry out — I had to
discover it empirically by testing an analogous case.

**3. No conformance or example coverage for a brand-new statement.** `harness/`'s
corpus (`corpus/test/**.lox`) is the book's frozen suite and, reasonably, has no idea
`break` exists. That means the one automated signal the port leans on hardest gave
literally zero coverage for the feature I was adding. I had to write my own scratch
`.lox` files (under this run's scratchpad, per the task's directory rule) for each
semantic corner the task called out by hand — increment-skipping on `for`, only the
innermost loop exiting on nested loops, a closure keeping the value a loop-local had
*at the moment of the break* — run them manually against both engines, read the output,
and only then promote the strongest ones into `driver.rs` unit tests. This worked, but
it is exactly the kind of manual-inspection step that a test suite is supposed to make
unnecessary, and it's the main reason two engines cost more than 2x one engine: each
scenario needed independent verification per engine, by hand, before I trusted it
enough to freeze it as a test.

**4. Rust exhaustiveness matching found one site for me, but only because I went
looking.** Adding a third `Flow` variant (`Break`) meant every existing `match` over
`Flow` needed a new arm. `grep -n "Flow::Return(value) => value"` found the one place
(`call_function`'s return-value extraction in `interpreter.rs`) that would otherwise
have failed to compile with "non-exhaustive patterns: `Flow::Break` not covered"; I
fixed it (an `unreachable!()` arm, since the resolver's `in_loop` check guarantees a
`break` can never actually reach a function's top-level return-flow match) before ever
running `cargo build`. Had I skipped the grep, `rustc`'s error would have named the
exact call site and line directly — the one time I tested that path deliberately (by
temporarily deleting the arm), the message was precise and immediately actionable. No
friction here, just a note that the compiler would have caught it just as fast as the
grep did.

**5. `cargo fmt -- --check` caught two of my own lines.** Two new test bodies I wrote
wrapped onto extra lines that `rustfmt` wanted collapsed. `cargo fmt` (no `--check`)
fixed both in one pass; one iteration, trivial, and exactly what the tool is for.

## Tools used to navigate the code

`grep -n` across `SPEC.md` and every `src/*.rs` file for cross-cutting patterns
(`OpCode::Jump`/`CloseUpvalue` in `vm.rs`, to confirm the VM engine needed no new opcode
since `break` compiles to instructions it already runs; `Flow::Return` sites, to find
every exhaustive match that needed a new arm; `synchronize`/keyword lists, to find every
place a new reserved word needed adding). Full-file `Read` of `scanner.rs`, `chunk.rs`,
`compiler.rs`, `ast.rs`, `parser.rs`, `resolver.rs`, `interpreter.rs`, `driver.rs`,
`main.rs` before writing anything, to have the whole control-flow story (both engines,
end to end) in view at once rather than editing one function at a time. `cargo build`,
`cargo test`, `cargo test <substring>`, `cargo fmt -- --check`/`cargo fmt`, and
`cargo clippy --all-targets` from the mandated `bin/cargo` wrapper. `harness/
lox_bench.py conformance --binary <bin> --engine both --stress` against both the debug
and release profiles, before and after the change, to establish a clean baseline first
(246/246 vm, 241/241 tree, both GC modes) and then confirm no regression. Hand-written
`.lox` scratch scripts run directly against `--engine=vm` and `--engine=tree` for manual
behavioral spot-checks that the corpus couldn't provide.

## Three changes that would have saved the most time, ranked

1. **A small "language extension" fixture set with expected output, alongside the
   frozen book corpus.** Something like `corpus/extensions/break/*.lox` with the same
   `// expect:` annotation convention the harness already parses, covering the corner
   cases a `break`/`continue`-style addition always needs (skip-the-increment,
   innermost-loop-only, closure-over-a-loop-local). This is exactly the coverage I had
   to build by hand for a feature the task explicitly anticipated adding; shipping it
   once would pay for every port and every future control-flow addition, not just this
   one.
2. **One line in `SPEC.md`'s error-recovery sections (§8.4/§9.2) stating whether the two
   engines are allowed to report a different *number* of cascading diagnostics for the
   same malformed input.** I spent real time convinced I'd introduced a bug before
   proving (via the pre-existing `return` keyword) that the asymmetry was already
   there. A single sentence would have turned that investigation into a citation.
3. **A one-shot "verify this port" command** (e.g. `lox_bench.py verify --port rust`
   that runs `cargo test`, builds `release`, and runs `conformance --engine both
   --stress` in sequence) instead of three separate invocations across two working
   directories that I had to remember and re-run by hand after every edit. None of the
   three steps is slow on its own; remembering and sequencing them by hand, repeatedly,
   is the part that costs time.
