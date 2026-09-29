# FRICTION.md — fixing the closure/`--gc-stress` bug in the Zig Lox port

## What the bug was

`lox/ports/zig/src/heap.zig`'s `blacken()` function implements SPEC §7.4 step 2
("Trace ... Closure: function, then upvalues"). Its `.closure` case only did the
first half:

```zig
.closure => |closure_obj| {
    try rt.markObject(closure_obj.function);
},
```

It never marked `closure_obj.upvalues`. A closure is a GC root only while it sits
on the value stack or (transitively) in a table/object the roots already reach;
its *upvalues* are otherwise reachable only by tracing the closure itself. Once an
upvalue is closed (the enclosing call returned) it also drops off the VM's
`open_upvalues` root list, so at that point the closed `Upvalue` object's only
path to a root is "closure → upvalues[i]" — exactly the edge `blacken` was
missing. Any GC triggered while such a closure is stored somewhere other than the
value stack (a global, a field, another closure's own upvalue) would sweep the
"orphaned" `Upvalue` object and hand its slot to the next allocation. The next
`GET_UPVALUE`/`SET_UPVALUE` through the stale `ObjRef` then either panicked
(checked builds) or silently reinterpreted unrelated memory (`ReleaseFast`) —
exactly the crash-or-wrong-value split the bug report describes.

Fix: mark `closure_obj.upvalues` too. One line, in `blacken`'s `.closure` arm.

## Points of friction, in the order I hit them

1. **Finding `build.sh`'s correct invocation cost one failed attempt.** I first
   ran `bin/zig build --help` from the run root (not the port directory) and got:

   ```
   error: no build.zig file found, in the current directory or any parent directories
   ```

   `zig build` resolves `build.zig` relative to the working directory with no
   obvious "point at a project" flag surfaced by that error message itself — it
   doesn't suggest `--build-file`. I found `--build-file [file]` only by running
   `--help` again from *inside* `lox/ports/zig` and reading the full option list.
   One wasted attempt, a few minutes; the error message could have named the flag
   that fixes it (`zig init` did get suggested, which is irrelevant here since a
   `build.zig` already exists elsewhere).
2. **`ZIG_GLOBAL_CACHE_DIR` is an env var, not a build argument.** Easy to
   typo as a bare `KEY=VALUE` token appended to the `zig build` argv (it would be
   silently swallowed or misparsed); caught this before running by re-reading
   `bench.json`'s `"env"` block, which already documents it has to be exported,
   not passed positionally. No wasted run here, but only because I happened to
   check `bench.json` again before executing — the port's own `NOTES.md` doesn't
   say this explicitly next to the `ZIG_GLOBAL_CACHE_DIR` mention in "Layout and
   build", so a reader skimming just that section could get it wrong on the first
   try.
3. **Confirming *why* the two existing closure tests
   (`run_closure_counter`, `run_shared_upvalue`, `run_gc_stress_same_output`)
   didn't already catch this** took real thought, not tooling. In all three, every
   closure that ever holds a live upvalue is *also* continuously reachable through
   the value stack or the VM's `open_upvalues` list at every point a collection can
   run — `run_gc_stress_same_output`'s `adder(i)(0)` closure is created and called
   in the same expression, so its upvalue closes and the closure is immediately
   re-pushed before any further allocation can trigger a GC. The bug needs a
   closure that (a) escapes to a place the stack scan doesn't cover — a global —
   and (b) survives across an *unrelated* allocation after its upvalue has
   closed. Nothing in the existing suite does both. This is a genuine gap in test
   design, not a tooling problem, but it is the reason the bug shipped past
   "63/63 unit tests, 246/246 + 241/241 conformance, both gc-stress" — a coverage
   metric that looks complete can still miss a timing-shaped bug. I didn't find a
   way to have a tool tell me this; I had to trace the rooting story by hand
   against SPEC §7.4's step list.
4. **The union-kind panic was the single most useful diagnostic in this whole
   task**, and it came for free from Zig's safety-checked builds. Reproducing the
   bug report's exact program under `--engine=vm --gc-stress` in a Debug build
   gave:

   ```
   thread ... panic: access of union field 'upvalue' while field 'string' is active
   heap.zig:167:28: 0x... in upvalue (main.zig)
           return &rt.get(ref).upvalue;
   vm.zig:257:47: 0x... in run (main.zig)
               const upvalue = rt.upvalue(rt.closure(frame.closure).upvalues[slot].?);
   ```

   That is effectively a free assertion that "this `ObjRef` no longer points at
   an `Upvalue`", which pointed straight at the reused/freed-slot hypothesis
   without any manual instrumentation. The flip side is real, though: the same
   program under `-Doptimize=ReleaseFast` (the profile most benchmark runs use)
   would not panic at all — it's UB that happens to reinterpret a `String`
   payload as an `Upvalue` payload, so a fleet only ever run in `ReleaseFast`
   could carry this class of bug for a long time with nothing but "wrong values"
   as a symptom, exactly as the report says. The compiler/runtime were not
   silent or misleading here — the checked build's message was exact and the
   docs (`NOTES.md` §"Kind checks are a build-profile property") already flag
   this Debug/ReleaseSafe-vs-ReleaseFast asymmetry — but it means the *default*
   benchmarking profile is also the one with the weakest safety net for this
   whole bug family.
5. **Everything else was low-friction.** `zig build test -Drerun-tests=true` and
   `zig fmt --check` behaved exactly as `NOTES.md` describes; the harness's
   `conformance` subcommand ran against my binary with no surprises once
   `--binary` pointed at it. I did not need to touch anything under the pinned
   `lib/std` reference path at all for this fix.

## Tools used

`grep -n` for `blacken`, `markObject`, `.closure =>`, `open_upvalues` across
`src/heap.zig` and `src/vm.zig` to find every place a `Closure`'s or `Upvalue`'s
liveness is decided; `sed -n` to pull the exact SPEC §7.4 wording to check the
implementation against; building and running the interpreter directly (Debug,
ReleaseSafe, ReleaseFast) to both reproduce and then disprove the bug; the
`lox_bench.py conformance` harness for the corpus-level regression check;
`zig build test --summary all` for the unit count; `zig fmt --check` for style.
No web access was used or needed.

## Three changes that would have saved the most time

1. **A GC-liveness lint/checker for exactly this class of bug.** The mistake —
   a `blacken` arm that traces some but not all of an object's outgoing
   references — is mechanical: for every field of every payload type that holds
   an `ObjRef`/`?ObjRef`, there should be exactly one place that marks it, and a
   tool could statically diff "fields that hold object references" (from the
   `Object`/`Closure`/etc. type definitions) against "fields `blacken` actually
   visits" and flag the gap. This bug would have been a compile-time or
   lint-time finding instead of a runtime heisenbug gated behind
   `--gc-stress` and a specific allocation-timing window.
2. **Make `zig build`'s "no build.zig found" error suggest `--build-file`.**
   Small, but it is the one place the tool had the information (it already knows
   the flag exists) and didn't offer it, versus `zig init`'s suggestion, which
   doesn't apply when a `build.zig` already exists somewhere else in the tree.
3. **Make the Debug/ReleaseSafe union-kind panic available (as an opt-in check,
   not full ReleaseSafe) inside ReleaseFast.** The panic message was the best
   diagnostic in this entire task; the fact that it disappears exactly in the
   profile most likely to be used for real runs (and for benchmarking) means the
   most informative safety net is the one most often switched off. A
   `-Dcheck=kind-only` style flag that keeps just the tagged-union access check
   without ReleaseSafe's other overhead would preserve nearly all of that
   diagnostic value at a much lower cost than full ReleaseSafe.
