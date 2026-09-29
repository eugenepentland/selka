# FRICTION.md — adding `break` to the mylang Lox port

Scope: `break;` in both engines (`lox/ports/mylang/{scanner,ast,parser,resolver,
interpreter}.my` for the tree walker, `lox/ports/mylang/compiler.my` for the
bytecode VM — `chunk.my` and `vm.my` needed no changes, since `OP_JUMP`,
`OP_POP` and `OP_CLOSE_UPVALUE` already existed for `if`/`and`/`or`/scope
exit). Tools used: `grep`/`Read` over the port's `.my` files to find where
`while`/`for` were compiled and resolved, plus a handful of throwaway
`.my` scripts (deleted afterward) run with `mylang run-project` to dump a
chunk's raw opcode bytes and to execute short Lox snippets against the built
binary — the fastest way to confirm exact jump offsets and closure semantics
was to just run the thing, not to read more source.

## What went smoothly

The port's own module boundaries made this mostly mechanical. `chunk.my`
already had every opcode `break` needs (`OP_JUMP`, `OP_POP`,
`OP_CLOSE_UPVALUE`), so the bytecode compiler change was additive: a
`LoopState` per active loop (scope depth at the body's start, plus a list of
pending break-jump offsets), a `discard_locals` helper that emits the same
pops `end_scope` would without removing them from the compiler's own local
list (so code after `break;` in source order still compiles with correct
slot arithmetic), and patching every loop's break jumps to land exactly
where the loop's own normal-exit code already lands. `vm.my` needed zero
changes. On the tree side, the existing `Flow` enum (`NORMAL`, `RETURN`)
already had the right shape for "a statement result that unwinds through
blocks"; adding `BREAK` and changing `run_block`/`run_body`'s `if flow ==
Flow.RETURN` to `if flow != Flow.NORMAL` was enough to make `break` bubble up
through arbitrarily nested blocks to the nearest `while_stmt`, which then
converts it back to `NORMAL` — that's also naturally where closures already
get correct per-iteration values, since `execute_block` allocates a fresh
env per iteration and always restores the caller's env regardless of which
`Flow` came back.

## Where I was blocked or slowed down

1. **Verifying exact jump-patch offsets by hand doesn't scale, and there's
   no disassembler exposed.** I wrote out the expected byte sequence for
   `while (true) { break; }` by hand-simulating `emit_jump`/`patch_jump`/
   `emit_loop`, then didn't trust the arithmetic (two-pass jump patching
   with a jump landing point that must differ between the "condition false"
   exit and the "break" exit, to keep the value stack balanced, is exactly
   the kind of thing that's off-by-one until proven otherwise). I could not
   find a `mylang` command that disassembles a chunk's bytecode with opcode
   names (`mylang reference --query` doesn't cover a specific program's
   compiled output; there's no `dump-bytecode` help entry for chunk-level
   detail despite it showing up in the top-level command list). I resolved
   this by writing a five-line throwaway `.my` script that calls
   `compiler.compile` directly and prints `code.code` as a plain integer
   list, run with `mylang run-project`, then decoded the opcode numbers by
   hand against `chunk.my`'s constants. That worked, but it took a few
   minutes and a wasted first attempt (`mylang run dump_chunk.my --project`
   fails with the generic usage dump and no pointer toward `run-project`;
   the two subcommands aren't cross-referenced in the error). Cost: about 3
   attempts (find the command, name the module to match its filename because
   of `E_MODULE_NAME`, then get the invocation form right) plus a second
   round for a variant with a local declared before `break`. A `mylang
   dump-bytecode`-style command that prints a chunk with opcode mnemonics
   and resolved jump targets (the way `javap -c` or clox's own
   `disassembleChunk` does) would have replaced all of this with one
   command.

2. **`mylang run <file> --project` is not the same as `mylang run-project
   <file>`, and the error for the wrong one doesn't say so.** My first
   attempt at the throwaway dump script used `run --project` (by analogy
   with `build main.my --project`, which is the form `bench.json` and
   `README.md` use); it fails with exit 2 and the full multi-page usage
   block, not a targeted "did you mean `run-project`" hint. `--help`'s own
   listing does mention `run-project is the explicit project-entry alias`,
   but only in a sentence about `run`'s semantics, not next to `--project`
   as a flag — I had to re-read that line rather than being told directly.
   One attempt lost; documentation was present but easy to misread as "the
   flag works on both."

3. **No unit test in this port can actually execute a Lox program — only
   the standalone binary can, which set the ceiling on what "unit tests in
   the port's style" could cover.** `NOTES.md`'s friction item 1 already
   flags this (`driver_tests.my` needed a `--cases` file and a hand-patched
   `natives.my` fixture just to give the tests a `Clock`, and that whole
   apparatus is marked removed in this checkout because it "no longer
   compile[s] on the installed compiler"). I hit the same wall from a
   different angle: I wrote a `break_test.my` that called
   `driver.run_source(source, engine, False, out, None)` from a plain `out:
   Stream` test function, expecting the `None` clock argument to make the
   `Clock` capability irrelevant. It doesn't — `zig build test`-style effect
   checking is static, not value-sensitive: because `vm.run`'s `OP_CALL`
   dispatch can reach `natives.clock_native` for *some* bytecode, every
   caller of `vm.interpret`/`interpreter.interpret` (and therefore
   `driver.run_source` itself) is charged with the `clock` effect
   unconditionally, regardless of what particular script is passed in or
   that the clock argument is `None`. All ten new tests failed identically
   with `E_EFFECT_BOUND: ... which no parameter permits; add clock: Clock to
   the parameters` — a clear, correctly-attributed error (it names the exact
   call chain down to `time.now`), but there is no fix available to a test
   that only has `out: Stream`, and the one fix that exists
   (`driver_tests.my`'s fixture mechanism) is exactly what this checkout
   already gave up on. I deleted that file rather than resurrect a mechanism
   the port's own author had already abandoned, and instead verified actual
   `break` execution (while/for, nested-loop scoping, for-loop increment
   skipping, closure capture of a pre-break value, all under
   `--gc-stress`) by hand against the built `prog` binary — which is exactly
   the port's real fallback for this, per `NOTES.md`: "end-to-end
   correctness is the conformance corpus." Cost: one wasted file (~10
   tests, maybe 20 minutes) before accepting that boundary. The fix isn't
   really about `break`: it's that *no* unit test in this port can exercise
   either engine's actual execution, only its front end, which is a real gap
   for a language interpreter's own test suite and cost real time here even
   though the eventual answer was "this is expected, move on."

4. **Cascading parse errors made my first attempt at a "missing semicolon"
   test wrong, not the feature.** `while (true) { break }` (no `;`) produces
   *two* diagnostic lines, not one: the missing-`;` error, then a second
   "Expect '}' after block." because `synchronize()`'s recovery advances past
   the `}` it needed (the `}` isn't one of `synchronize`'s statement-starting
   keywords, so it gets eaten). This is pre-existing jlox/clox recovery
   behavior, unrelated to `break`, but I initially wrote an exact-match test
   expecting only the first line and had to loosen it to a substring check
   once I saw the second line appear. Cost: one failed test run, a minute
   to diagnose, no tool or doc issue — just a case of not having internalized
   how error recovery here treats an unexpected `}`.

## Ranked: three changes that would have saved the most time

1. **A chunk disassembler command** (`mylang dump-bytecode <file.my>` with
   opcode names and resolved jump targets, or equivalent output from `build
   --report`/`--timings=json`). I ended up writing and discarding a
   throwaway script to get exactly this for one function; anyone adding or
   debugging control flow in a bytecode-compiled language on this toolchain
   will hit the same need immediately, and it is the single most
   mechanical, most reusable piece of tooling missing here.

2. **A documented (or built-in) way to exercise real *execution* in a
   `mylang test` unit test when the guest module under test needs a
   capability the test itself structurally cannot hold** (here, `Clock`,
   because the effect checker is a static, not a per-value, ceiling). Either
   a sanctioned "fake capability for tests" pattern in the docs, or a
   language feature that lets a function's effect signature be narrowed by
   an unreachable branch (the `None` case never calls `clock`, but the
   checker can't see that), would turn "only the compiled binary can test
   real behavior" from a standing limitation into a one-line workaround.
   This cost real time twice in this port's history (`driver_tests.my`,
   then this task) for the same root cause.

3. **Cross-reference near-miss commands in the CLI itself**, not just in
   prose in `--help`. `run --project` failing with the full usage block
   instead of a one-line "did you mean `run-project`?" (and, more generally,
   any flag/subcommand combination that's a common typo for a different
   valid one) is a small fix with an outsized effect on how many times a
   agent has to re-read `--help` to figure out what it typed wrong.
