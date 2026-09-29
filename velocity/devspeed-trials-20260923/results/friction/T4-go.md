# FRICTION.md — adding `%` to the Go Lox port

Overall this task went smoothly. Every build, vet, fmt and test command succeeded
on its first attempt; nothing here rises to "blocked." What follows is a candid
log of the few places I had to stop and think, or where the docs were silent and
I had to make a call.

## Points of friction / ambiguity

1. **`gofmt` is not on the path the task gives you, only `go`.**
   `lox/ports/go/NOTES.md` states its cleanliness bar as `gofmt -l .` is clean,
   but TASK.md names only one absolute tool path (`bin/go`); there is no
   `bin/gofmt`. Running `bin/go`'s sibling `gofmt` directly isn't an option
   without leaving the sanctioned toolchain path. I tried
   `/home/.../bin/gofmt -l .` once, got a plain shell `No such file or directory`
   (exit 127, not a Go diagnostic), and then used `bin/go fmt ./...` instead,
   which shells out to the real `gofmt` under the hood and reports the same
   thing. One wasted attempt, immediately resolved, no time really lost — but
   it took a second to realize the fix was "use the wrapper command," not
   "find the binary."
   Docs: NOTES.md's own stated check was slightly misleading here (it assumes
   a bare `gofmt` is reachable); TASK.md was silent on it (it only promises `go`).

2. **The spec has nothing to say about where a non-spec addition belongs.**
   `lox/SPEC.md` is explicit that "this document pins the design" and that
   ports may not edit anything outside `ports/<lang>/`, but it has no `%`
   operator at all — this task's operator is deliberately outside SPEC.md's
   scope. That's fine (TASK.md gives the actual behavior contract precisely:
   precedence, error message, `fmod` semantics with worked examples), but I
   had to decide for myself, with no doc guidance either way:
   - where in the `TokenKind`/`OpCode` `iota` blocks a new entry is safe to
     insert (verified nothing indexes them by raw integer before doing it,
     rather than being told it's safe), and
   - whether to record the addition under NOTES.md's existing "Departures from
     the spec" section (which is framed as deviations/mistakes to justify) or
     as its own thing. I added a new "`%` operator (task addition)" section
     rather than overload "Departures," since it isn't a departure — the spec
     simply doesn't cover it.
   This cost some reading time (re-scanning SPEC.md and grepping the port for
   any hardcoded numeric token/opcode values before trusting an insert-in-the-
   middle edit) but no wrong turns.

3. **No real Go or toolchain surprises.** `go build`, `go vet`, `go fmt`,
   `go test ./...` and `go test -count=1 ./...` all passed clean on the first
   try after the edits, both before and after adding the new tests. The
   conformance run (`lox_bench.py conformance --binary ./prog --engine both
   --stress`) matched the pre-existing 246/246 (vm) and 241/241 (tree) in both
   GC modes on the first run. `math.Mod` matched every example in the task
   (`7 % 3 = 1`, `-7 % 3 = -1`, `7 % -3 = 1`, `5.5 % 2 = 1.5`) with no sign
   fix-up code needed, confirmed by running the built binary directly, not just
   trusting the docs.

## Biggest time sink

Not a tool failure — it was reading SPEC.md (764 lines) and the six touched
files (`scanner.go`, `chunk.go`, `compiler.go`, `parser.go`, `vm.go`,
`interpreter.go`) closely enough to find *every* place `*`/`/` are special-cased
(the Pratt table, the parser's `factor()` level, the VM's non-number-operand
opcode group, the VM's `arithmetic` switch, and the tree engine's `arithmetic`
switch plus its shared "not both numbers" error path) so that nothing was left
half-wired. The code itself is clean and idiomatic enough that once each site
was found, the edit was a one- or two-line, low-risk addition — comprehension
dominated, not implementation.

## Ranked changes that would have saved the most time

1. **Give the trial a `bin/gofmt` next to `bin/go`** (or state in TASK.md that
   `go fmt`/`go vet` are the sanctioned formatting/lint checks and `gofmt -l .`
   from NOTES.md is not directly runnable). Smallest fix, removes the one
   genuine dead end.
2. **In SPEC.md or TASK.md, name the convention for documenting a deliberate,
   task-scoped addition that sits outside the shared spec** — e.g., "put it in
   its own NOTES.md section, not under Departures" — so every port doesn't
   independently invent the same answer (and so the four language ports stay
   comparably organized for whoever reads all four NOTES.md files side by side).
3. **A one-line pointer from TASK.md to the exact `rules`/Pratt-table and
   opcode-switch locations** (or just "grep for the existing `*`/`/` handling in
   each of the N modules and mirror it") would have skipped some of the
   comprehension pass — though this is a minor ask, since the code's own
   module boundaries (SPEC.md §2) already make the search tractable.
