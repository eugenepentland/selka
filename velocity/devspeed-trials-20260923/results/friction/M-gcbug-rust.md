# FRICTION.md — M-gcbug-rust

Candid log of the bug-fix session (missing GC trace for `Closure.upvalues` in the Rust
Lox port's VM engine). Overall this was a low-friction fix once the spec was in hand;
logged below are the actual points that cost time or attention, plus the tools I used
and the improvements I'd rank highest.

## What I tried, in order

1. **Read `TASK.md`, `lox/SPEC.md` (§7 Heap and GC), and `lox/ports/rust/NOTES.md`.**
   No friction — `NOTES.md`'s "Representation" and "Language friction" sections already
   explained the object table's `Cell<bool>` mark bit and why `Marker<'a>` splits
   `slots: &'a [Slot]` out from `gray: &'a mut Vec<ObjRef>` (so tracing can hold a
   `&Object` borrowed from `slots` while still pushing onto `gray` through `&mut self`).
   That explanation is exactly the trick the fix needed to lean on, so I didn't have to
   rediscover it from the borrow checker. Documentation helped here, unreservedly.

2. **Cross-read `SPEC.md` §7.4 ("Trace ... Class: name, then methods... Closure:
   function, then upvalues...") against `heap.rs`'s `Marker::blacken` match.** This is
   where the bug is: every other variant's `blacken` arm mirrors its spec line
   one-for-one (`Function` marks name then constants, `Env` marks enclosing then
   slots), except `Closure`, which only marked `closure.function` and silently dropped
   "then upvalues." Tool used: plain reading + `grep -n "Object::" src/heap.rs`
   side-by-side with the spec table — no debugger, no test failure, needed. This took
   one pass; the spec's wording is precise enough that the diff from the code was
   visible without running anything. **1 attempt, spec was not silent — it directly
   named the missing edge.**

3. **Confirmed the theory would actually explain the reported symptom before trusting
   it.** There's no git repository in this task directory (`git diff` in
   `lox/ports/rust` returned "fatal: not a git repository ... Stopping at filesystem
   boundary"), so I hand-copied `src/heap.rs` to a scratch file, reverted the fix,
   rebuilt with the wrapped `bin/cargo`, and ran the report's exact `counter.lox`
   program:
   - `--engine=vm --gc-stress`: `thread 'main' panicked at src/object.rs:194:9:
     expected a Upvalue object, found a String` — a freed `Upvalue` slot had been
     reused by one of the loop's `"x" + "y"` string allocations, and the closure's
     stale `ObjRef` then read it back as a `String`. This is exactly "crash or print
     wrong values" from the report, and exactly why it's nondeterministic-looking
     (which object kind lands in the reused slot depends on allocation order).
   - `--engine=vm` (no stress): clean `1`/`2`, because ordinary allocation in this
     script never crosses `next_gc` (1 MiB), so no collection ever runs.
   - `--engine=tree --gc-stress`: clean, because the tree engine has no `Upvalue`
     object — captured variables live in a heap `Env` whose `slots: Box<[Value]>` was
     already traced correctly.
   Restored the fix, rebuilt, reran: `1`/`2`, exit 0, on all three combinations.
   **1 revert/rebuild/run cycle**, all by hand since there was no VCS to lean on for a
   scratch stash — mildly slower than `git stash` would have been, but not a real
   blocker (the port has no other uncommitted state to worry about losing).

4. **Applied the fix**: `Marker::blacken`'s `Object::Closure` arm now also marks every
   `ObjRef` in `closure.upvalues`, following the exact loop idiom already used two arms
   down for `Function`'s constants and `Env`'s slots. It compiled on the first try —
   the borrow-checker concern from NOTES.md ("a `&Object` cannot live across
   `allocate(&mut self)`") doesn't apply here because `blacken` only *reads* the
   already-borrowed `closure.upvalues` and calls `mark_object`, which touches
   `self.slots` (read) and `self.gray` (write), not `self.slots` mutably — the same
   shape as the sibling arms, so no new borrow pattern was needed.

5. **Added a regression test** (`driver::tests::run_closed_upvalue_survives_gc_stress`
   in `src/driver.rs`) using the report's own program almost verbatim, engine `Vm`,
   `gc_stress: true`, asserting `stdout == "1\n2\n"` and empty `stderr`. I checked it
   fails on the un-fixed code (same panic as step 3) and passes on the fixed code
   before trusting it as a regression net. The port's two existing GC-under-stress
   tests (`run_gc_stress_same_output`, `run_shared_upvalue`) don't catch this bug
   because their closures either never survive past the call that closes their upvalue
   (`adder(i)(i)`, called and discarded in the same expression) or never close an
   upvalue that outlives its frame while more allocations follow — worth knowing if
   another closure-related GC bug shows up later: "gc-stress + closures" tests need to
   specifically keep a closure alive in a *global* across *further* allocations after
   its capturing frame has returned, not just call it once.

6. **Verified the full gate**: `cargo test` (64/64, was 63/63), `cargo clippy
   --all-targets` (clean, matching `NOTES.md`'s claim), `cargo fmt --check` (clean, no
   diff), `python3 lox/harness/lox_bench.py conformance --binary ./prog --engine both
   --stress` (246/246 vm, 241/241 tree, both normal and `--gc-stress`), and the same
   conformance run again against the unoptimized `debug` profile binary (overflow
   checks on) for good measure — same counts. No surprises in this step; the harness's
   error messages (`FAIL <path>` plus a diff of expected vs. actual output/exit code)
   are clear enough that I never needed to add printouts to debug a failure, because
   there were none.

## Tools used to navigate

`grep -n` across `src/*.rs` and `SPEC.md` was the whole toolkit for finding the bug —
the object-kind `match` in `blacken` is short and enumerable, and the spec's trace list
uses the same order and names as the code, so a manual diff was faster than instrumenting
anything. `cargo test`, `cargo clippy --all-targets`, `cargo fmt --check`, and
`lox_bench.py conformance` were the only commands needed to validate. I did not need
`RUST_BACKTRACE=1`, a debugger, or `--stats` diffing — the panic message and the report's
own repro were specific enough on their own.

## Minor environmental note (not a blocker)

`lox_bench.py`'s `repo_root()` walks up from `lox/harness/` looking for a
`.tmp/lox-bench/` directory (the vendored `craftinginterpreters` checkout used only by
the `check` and `expected` subcommands, for the clox oracle). That directory doesn't
exist inside this task's sandboxed copy, so `check`/`expected` would fail here if
invoked (I didn't need them — `conformance` parses each corpus file's own `// expect:`
comments and needs no oracle). Flagging only because it's the kind of thing that would
have cost real time if the task had required `check` instead of `conformance`.

## Ranked recommendations

1. **Make heap-tracing exhaustiveness a compile-time property, not a spec-reading
   exercise.** The bug was one match arm quietly doing less than its sibling arms, and
   nothing — not the type system, not clippy, not a test — flagged that `Closure` has an
   `ObjRef`-bearing field (`upvalues: Vec<ObjRef>`) that `blacken` never visits. A
   `match` that returns `()` for every arm gives the compiler no signal that "trace
   every `ObjRef` field" is even a rule being followed. A small derive/macro (or even a
   `debug_assert!`-driven runtime check walking each `Object` variant's fields via a
   generated "list of ObjRef offsets") that ties `cost()`-style exhaustive-match
   boilerplate to a `trace()` twin would have made this bug a compile error or an
   immediate, obvious assertion failure instead of a `--gc-stress`-only, allocation-order-
   dependent panic three call frames away from its cause. This is the change that would
   have saved the most time on this *class* of bug, even though this specific instance
   was fast to find.
2. **Give stale/reused `ObjRef` reads a GC-specific diagnostic.** The panic I hit —
   `expected a Upvalue object, found a String` — is indistinguishable from an ordinary
   type-confusion bug in interpreter logic (e.g., a genuinely wrong `ObjRef` computed by
   the compiler). A generation counter per slot (bump on reuse) that a debug build checks
   before every payload access, panicking with something like `stale ObjRef 42: slot
   reused (generation 3, held reference from generation 1)`, would immediately tell the
   next person "this is a GC rooting bug," not "go audit the compiler's constant table."
3. **A standing convention for "closure survives past its capturing frame, under
   stress" as its own test shape**, distinct from "call a closure once" or "read a
   shared upvalue immediately." The port already had two GC-stress-and-closures tests
   and neither exercised a *closed* upvalue outliving its frame across *further*
   allocations, which is precisely the gap the report's example lives in. A one-line
   note in the spec's §7.4 or in a testing-conventions doc — "at least one test must
   keep a closure alive in a global across allocations made after its capturing call
   returns" — would have caught this before it shipped, without needing a bug report at
   all.
