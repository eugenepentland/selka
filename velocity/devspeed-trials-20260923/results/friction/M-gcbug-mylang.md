# FRICTION.md — fixing the closure/`--gc-stress` bug in the mylang Lox port

## What I did, in order

1. Read `TASK.md`, then `lox/ports/mylang/NOTES.md` (its "Representation choices"
   and "Departures from the spec" sections) to learn the object model before
   touching code: `Value` is a 16-byte union, the object table is `list[object.Obj]`,
   `ClosureObj.upvalues: list[value.ObjRef]` is a "managed list" that survives
   inside the record, and the collector is a classic clox-style mark/gray-stack/sweep
   in `heap.my`.
2. Wrote `build.sh` (`bin/mylang build lox/ports/mylang/main.my --project -o prog
   --cache-dir .mylang-cache`, the same shape bench.json's `release` profile uses)
   and reproduced the reported program verbatim before writing any fix, to make
   sure I was chasing the real bug and not a stale report.
3. Found the root cause by reading, not by a tool: `heap.my`'s `blacken` function
   (SPEC §7.4 step 2, the "mark everything one object references directly" pass)
   has one `match` arm per object kind. The `Obj.closure` arm marked
   `payload.function` but never walked `payload.upvalues`. Compared against
   `object.my`'s `ClosureObj` record (`function`, `upvalues: list[value.ObjRef]`),
   the omission was visible on inspection — the compiler's checker has no way to
   flag "you forgot to mark a GC root," since that is a domain invariant, not a
   type or effect error, so it was silent about it in both directions (no error
   when the line was missing, no error when I added it).
4. Fixed it with the obvious analogue of clox's `blackenObject` for `OBJ_CLOSURE`
   (a `for upvalue in payload.upvalues: mark_object(mut rt.marker, upvalue)` loop),
   rebuilt, and the reported program went from `error[R_ASSERT]: native execution
   failed: object is not an upvalue` to printing `1` / `2`. First attempt.
5. Verified necessity, not just plausibility: reverted the one-line fix, rebuilt,
   and reran `python3 lox/harness/lox_bench.py conformance --binary ../prog
   --engine both --stress`. It dropped from 246/246 to 230/246 on
   `engine=vm gc=gc-stress`, failing all 16 closure-family tests
   (`this/closure.lox`, `this/nested_closure.lox`, `while/closure_in_body.lox`, …)
   with the identical trap. Restoring the fix brought it back to 246/246 (vm) and
   241/241 (tree), both normal and `--stress`. This is the strongest evidence I
   had that the fix is both necessary and sufficient, and it cost nothing beyond
   one extra build/test cycle.
6. Added `heap_test::test_gc_traces_closure_upvalues` to `heap_test.my`, in the
   same style as the existing `test_gc_traces_instance_fields`: build a closed
   (already-detached-from-`open_upvalues`) `UpvalueObj` reachable only through a
   rooted closure, `collect`, and assert it survives. Confirmed it fails on the
   buggy `blacken` and passes on the fixed one.

## Where I actually got stuck

**Effect-system reachability blocks an end-to-end regression test, and there is
no way around it short of tooling the runner doesn't expose to a directory run.**

I first tried to add the regression test at the level the bug report was phrased
at: run the literal reported program through `driver.run_source(source,
driver.Engine.VM, True, out, None)` from a new `driver_test.my`. That failed to
even compile as a test:

```
error[E_EFFECT_BOUND]: effect `clock` exceeds this signature's ceiling:
driver_test::test_vm_gc_stress_survives_closed_upvalue -> driver::run_source ->
driver::execute -> vm::interpret -> vm::run -> vm::call_value ->
natives::call_native -> natives::clock_native -> time::now, which no parameter
permits; add `clock: Clock` to the parameters
```

This is because mylang's effect checker charges a function with every effect its
*static* call graph can reach, regardless of the value actually passed — passing
`None` for the `Option[Clock]` doesn't matter, because the VM's native-call
dispatch can *statically* reach `time.now` for any program, whether or not that
particular program calls `clock()`. `NOTES.md` had already hit exactly this
(departure 3, friction item 1) and worked around it with a "provider fixture":
a `--cases` file that swaps in a fixture `natives.my` whose `clock_native` never
calls `time.now`, so the effect is no longer reachable. `docs/tooling/guest-tests.md`
("Deterministic provider fixtures") documents the same mechanism generically.
I rebuilt that fixture (a ~15-line `natives.my` with a `clock_native` that always
returns `0.0`) and a `driver_cases.json` mapping the two new test names to it, and
`mylang test driver_test.my --cases driver_cases.json --max-steps=100000000`
passed on the first try, both engines.

The second failure is what actually cost the time: adding `driver_test.my` to the
directory silently broke the plain, no-flags command every other test in the port
relies on, `mylang test lox/ports/mylang`:

```
error[E_EFFECT_BOUND]: effect `clock` exceeds this signature's ceiling: ...
not run: .../driver_test.my (exit 1, no report)
```

Per `docs/tooling/guest-tests.md`'s "Directory runs" section, a directory run
force-selects *any* file that declares a `test_` function — regardless of its
name, and regardless of whether it needs `--cases` — as long as no other root's
import closure already reaches it; and separately, "`--cases` is rejected for a
directory run, because its keys name the tests of one project." Those two rules
together mean a test that needs a provider fixture can never coexist with a plain
directory run: it will always be swept in and always fail, because there is no
way to hand it a `--cases` file in that mode. This is exactly the wall the port's
original author hit — `NOTES.md`'s first line records that `driver_tests.my` and
`driver_cases.json` were deleted "because they no longer compile on the installed
compiler," which I now believe is not a compile failure at all but this same
discovery/`--cases` conflict on the currently pinned compiler (their old file
apparently used to be exempted from directory autodiscovery by *not* ending in
`_test.my`, a workaround the current documented behavior explicitly no longer
honors: "a test file needs neither `main` nor the `*_test.my` suffix").

I spent about 3 attempts / ~20 minutes on this path (write fixture + cases,
confirm it passes standalone, discover the directory-run breakage, decide there
is no clean fix) before giving up on the end-to-end version and keeping only the
heap-level `test_gc_traces_closure_upvalues`, which needs no capability at all
and exercises the identical `blacken` code path. Net: the documentation
(`NOTES.md` and `docs/tooling/guest-tests.md`) was accurate and did explain both
halves of the problem, but neither says the two rules combine to make provider-
fixture tests fundamentally incompatible with a directory run — I had to
discover that by triggering it.

## Tools used

Mostly `Read` (to walk `heap.my` / `object.my` / `vm.my` / `driver.my` / `NOTES.md`)
and grep for cross-references (`ClosureObj`, `blacken`, `--cases`, `provider`,
`fixture` across `docs/tooling/guest-tests.md`). No compiler introspection command
(`mylang reference`, `context`, `tests-for`) was needed to find the bug itself —
it was a straightforward manual comparison between the object's declared fields
and the mark function's handling of them. The compiler *was* useful as an oracle
for verifying: rebuilding and rerunning the conformance harness after reverting
the fix, to get an objective before/after count (246→230→246), was more
convincing than reasoning about the mark/sweep algorithm on paper.

## Ranked: three tooling/language changes that would have saved the most time

1. **Let a directory test run supply `--cases`, scoped by file.** The flat
   restriction ("`--cases` is rejected for a directory run, because its keys name
   the tests of one project") is what forces provider-fixture tests out of the
   normal `mylang test <dir>` path entirely. Even a per-file cases file next to
   the test (`driver_test.cases.json`, auto-picked-up) would let a project mix
   ordinary and fixture-needing tests under one command, which is exactly the
   shape a real port's test suite wants. As it stands, any test that needs a
   deterministic clock/entropy/env fixture is unusable inside a directory run
   *and* unusable outside one without a hand-maintained second invocation and a
   naming convention (`_tests.my` vs `_test.my`) that the tool doesn't actually
   honor today.
2. **Make the effect ceiling depend on what a call can prove is unreachable, not
   just what the function signature enumerates.** `driver.run_source(..., clock:
   Option[Clock])` passing `None` provably never reaches `time.now` for *that
   call*, but the checker still charges the effect because some other caller
   passing `Some(...)` could reach it through the same shared function body. A
   test that always passes `None` (or, more generally, a call whose argument
   values statically rule out the effect-bearing branch) shouldn't need to carry
   a capability parameter it can never use. Short of full value-sensitive
   analysis, even an escape hatch — a per-call-site assertion like `# effects:
   none-reachable` that the checker verifies rather than trusts — would have let
   the end-to-end regression test exist without a fixture at all.
3. **Point at the missing mark, not just the corrupted read.** The trap
   (`object is not an upvalue`, thrown from `heap.upvalue_obj`'s `assert False` on
   a mismatched union case) is several allocations and one sweep removed from the
   actual bug (a `blacken` arm that doesn't walk one of its object's reference
   fields). A GC-authoring aid — even something as simple as a debug mode that
   cross-checks each `union Obj` payload's `ObjRef`/`value.Value` fields against
   what `blacken`'s corresponding `match` arm actually visits, and flags a field
   the collector's own dispatch never reaches — would have turned this from "read
   two files and compare by eye" into a one-command diagnosis, and would catch
   the same class of bug (a payload field added to a record without a matching
   line in `blacken`) before it ships instead of under `--gc-stress` in the field.
