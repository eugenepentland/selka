# FRICTION.md — adding `break` to the Go Lox port

Candid log of everything that slowed the work down, plus what didn't.

## What I did, in order

1. Read `lox/SPEC.md` in full (it does not mention `break` at all — it predates
   this task, so there was no reference design to follow for the feature
   itself, only for the surrounding architecture).
2. Read `lox/ports/go/NOTES.md` and every source file under
   `lox/ports/go/internal/` that touches loops or statement dispatch:
   `scanner.go`, `compiler.go`, `vm.go`, `ast.go`, `parser.go`, `resolver.go`,
   `interpreter.go`. Used `grep`/the Read tool, not an IDE — there is no
   IDE-like "find all switch statements over TokenKind" query, so finding
   every place a new keyword has to be wired in was manual (see finding #1
   below).
3. Added the `Break` token, the VM-side per-loop break-jump bookkeeping, and
   the tree-side resolver/interpreter signal plumbing (details in
   `lox/ports/go/NOTES.md`, "Break statement" section).
4. Verified with `go build ./...`, `go vet ./...`, `go test ./...` (via the
   pinned `bin/go` wrapper), then by hand-running eight small `.lox` scripts
   against `--engine=vm` and `--engine=tree`, with and without `--gc-stress`,
   comparing stdout between engines.
5. Ran `python3 lox/harness/lox_bench.py conformance --binary ./prog
   --engine both --stress`: 246/246 (vm) and 241/241 (tree), both GC modes,
   unchanged from before the change.
6. Wrote the unit tests, re-ran everything, wrote `build.sh`, updated
   `NOTES.md`.

## Points of friction

1. **No exhaustiveness checking on the keyword/statement switches — biggest
   time sink.** A new token (`Break`) and a new AST node (`ast.BreakStmt`)
   each have to be added to several `switch` statements scattered across
   packages: the compiler's `statement()` dispatch and its `synchronize()`
   panic-mode recovery list, the parser's `statement()` dispatch and its own
   `synchronize()` list, the resolver's `resolveStmt`, and the interpreter's
   `execute`. Go's compiler gives no warning for a missed case in a `switch`
   over an `int`-like `TokenKind` or over an interface type with a type
   switch — a missed `case scanner.Break` in `synchronize()` would just
   silently give worse panic-mode error recovery (no test would catch it
   unless it specifically probes recovery after a `break`-related error), and
   a missed `case *ast.BreakStmt` in `resolveStmt`/`execute` would panic at
   runtime with `resolver: unknown statement %T` / `interpreter: unknown
   statement %T` (the file's own catch-all `default: panic(...)`), but only
   the first time a test actually exercises that path. I found every site by
   `grep -n "scanner.Return\|scanner.While"` and by reading each package's
   dispatch function in full, then cross-checking after the fact. It worked,
   but it was pure memory-and-grep discipline with nothing enforcing
   completeness; on a larger AST or a language with more statement kinds this
   would not scale. Cost: no wrong turns, but a genuinely careful, slow pass
   through six files that a linter should have done in one command.

2. **No bytecode disassembler.** This Go port (correctly, per SPEC's "no
   extra optimizations/tooling beyond what's specified") has no equivalent of
   clox's `debug.c` `disassembleChunk`. To confirm the new `break` jump's
   target offset was correct — specifically, that it lands at the same place
   as the loop's own false-condition exit *without* double-popping the
   condition value — I had to write a throwaway `probe_test.go` that called
   the existing `compile()` test helper and `t.Logf`'d the raw `[]byte`, then
   hand-decode each byte against `chunk.go`'s `const (OpConstant = iota; ...)`
   block (`OpTrue=2, OpJumpIfFalse=26, OpPop=4, OpJump=25, OpLoop=27, ...`).
   For a two-instruction loop body this was maybe ten minutes of counting
   bytes on paper; I did not attempt it for the `for`-loop case (more jumps,
   an increment clause) and instead trusted the empirical program output plus
   the conformance suite. A `--dump-bytecode` mode (even test-only, gated
   behind a build tag) printing mnemonics and resolved jump targets would
   have turned this into a five-second visual check instead of arithmetic.
   Not a blocker — I removed the probe file once satisfied — but a real time
   sink for a change that is entirely about jump-offset correctness.

3. **No oracle reachable from inside the sandbox.** SPEC.md §11.3 and
   `lox_bench.py check` describe comparing output and `--stats` against
   `clox-oracle` and the other three ports, both of which live under
   `.tmp/lox-bench/` in the *main* mylang checkout — outside the directory
   this task confines me to (`/home/epentland/ai/trials/devspeed-20260923/
   runs/M-break-go/`). Confirmed by running `lox_bench.py`'s own
   `repo_root()`/`oracle()` helpers: `oracle().exists()` is `False` here, and
   there is no `ports/` sibling for zig/rust/mylang to diff against either.
   So the only correctness signal for `--stats` counts and byte-for-byte
   output was (a) the existing 246+241 conformance corpus, which contains no
   `break` test at all (it predates the feature) and so exercises none of the
   new code, and (b) my own hand-written scripts checked for agreement
   *between the vm and tree engines*, which is a real check but a weaker one
   than an independent oracle. This is a sandboxing artifact of the trial,
   not a defect in SPEC.md's design, but it meant "done" for this task rests
   on self-consistency and my own test suite rather than the harness's
   intended cross-implementation check.

4. **One self-inflicted but instructive wrong turn.** My first version of a
   "does `break` skip the `for` increment" test declared `for (var i = 0; ...)
   ...; print i;` and expected to read `i` after the loop. That failed at
   runtime with `Undefined variable 'i'.` (exit 70) — correctly: the `for`
   initializer's `var i` is scoped to the loop by jlox/clox's own desugaring
   (`§9.2`/clox's `forStatement`, both wrap the loop in its own block), so
   this was a bug in my test, not in `break`. The error message was exact and
   immediate, so it cost only one iteration once I read it, but it's worth
   noting because the failure mode (a runtime error, not a compile error)
   momentarily looked like it could be a `break`-handling bug rather than an
   ordinary scoping fact. Fixed by declaring `i` outside the loop.

## What did *not* cause friction

- The Go toolchain itself: `go build`, `go vet`, `go test`, `gofmt -l .` via
  the pinned wrapper at `bin/go` were all immediate and clean, first try,
  every time, including after every edit.
- `bench.json`'s `env` block already documented the `GOCACHE`/`GOMODCACHE`/
  `GOTOOLCHAIN=local` requirement, so I copied it straight into `build.sh`
  instead of discovering it the hard way.
- The shared error-formatting helpers (`compiler.error`/`resolver.error`)
  made getting the exact required message —
  `[line N] Error at 'break': Can't use 'break' outside of a loop.` — free;
  no iteration needed on message format in either engine.
- `funcState`/resolver already reset `currentFunction` per function body, so
  giving `break` the same "resets at a function boundary" behavior for the
  "break inside a function inside a loop" compile error was a direct
  copy of an existing pattern, not a new design problem.

## Ranked: the three tooling/language changes that would have saved the most time

1. **Exhaustiveness checking for switches over a closed token/AST-kind set**
   (a linter pass, or a language feature that makes these sum types the
   compiler can check). This is the change I'd want most: it turns "did I
   remember every dispatch site for the new keyword" from a grep-and-reread
   exercise into a compiler error, and it scales to codebases much larger
   than this one where memory-and-grep stops working.
2. **A bytecode disassembler / `--dump-bytecode` debug mode for the VM
   chunk.** Any change to jump emission (which `break` inherently is) is
   currently verified by hand-decoding raw bytes against an opcode table in a
   throwaway test. A mnemonic dump would make that a direct visual check.
3. **A self-contained oracle/reference fixture shipped with the corpus**
   (or at least a documented standalone way to build `clox-oracle` without
   the full mylang checkout), so that `lox_bench.py check`'s intended
   cross-implementation verification is available even when working in an
   isolated copy of just `lox/`.
