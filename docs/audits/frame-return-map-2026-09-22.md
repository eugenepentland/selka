# Frame protocol → return-address map — wave 4, lane `perf/frame-return-map` — 2026-09-22

Implements plan item 6.8 (roadmap item 2) and assesses 6.4's second half from
[`performance-parity-plan-2026-09-22.md`](performance-parity-plan-2026-09-22.md).
Base: `base/parity-w4` (`0804a4cf`: the parity audit, lane 5, wave-0 fixes,
text scans, sorting, NaN when observed, noreturn failure paths, root liveness,
fixed-array writes). Result JSONs and the probe corpus are under
[`experiments/perf-parity-plan-20260922/results/wave4/`](../../experiments/perf-parity-plan-20260922/results/wave4/).

## Result

- **No guest call links a frame record any more** in a checked fast executable
  (`mylang build` ReleaseFast, `mylang run` without a ceiling). Nothing is
  linked, stored or unlinked, and the metadata pointer and positions are not
  stored either. A trap recovers every frame from return addresses:
  - a build-time table: QBE `.loc` lines; LLVM pseudo-probe call sites with
    their inline stacks;
  - a walk at trap time: call-frame information for LLVM, frame pointers for
    QBE.

  LLVM keeps inlining guest code freely. An inlined callee still reports its
  own frame at its own position, then its caller at the call site.
- **Trap output is byte-identical**: code, message, `in f at file:line` lines,
  `MYLANG-TRAP` record, `assert` message and exit status. The corpus is 280/280
  cases (40 programs × 7 modes). It covers traps several frames deep, callees
  LLVM inlined, a trap inside an inlined runtime helper, callbacks, recursion,
  mutual recursion and stack overflow. A CLI test pins four of them through
  LLVM LTO and QBE.
- **The plain build reproduces the ladder's frame rung without IL rewriting**,
  within the floor test the lane keeps:
  - lane / rung 1.008 on the thirteen-program geomean;
  - lane / (rung with the floor test kept) 1.001.
- **Against the base** (loaded machine):
  - thirteen-program geomean −2.6% [−3.4, −1.8] (−3.8% in an earlier run);
  - `raytrace` −23.5% (1.93× → 1.48× Zig);
  - `sieve` −10%, `nbody` −5%;
  - **`fib` −37.5%** (3.35× → 2.08× Zig);
  - parser census −4.8%, render −5.9%.
- **Acceptance.** Met: `raytrace`, the parser roughly, and trap output. Not
  met: `fib` ≤ 1.3× and geomean −5–7%. The rung itself is only −3.9% on this
  base, and what remains in `fib` is the checked add's lowering (see *What is
  left*).
- **6.4's second half (`readonly` guest functions) is not done.** It is not
  provably sound: trap paths write the context, and the adapter's integer
  pointers make `argmem` meaningless.
- **Gate:** no new failure against the base; `test-qbe-build`,
  `test-schematic`, `test-byte-io`, `fmt-check` and Guardian are green.

## What changed

A checked fast executable — `mylang build` ReleaseFast or `mylang run` with no
`--max-steps`/`--max-frames` — no longer links a frame record (`QBE-FRAMEMAP-1`).
Before, every guest call loaded `ctx->active_frame`, stored `prev`, the
metadata pointer and a zero position into a 32-byte record, published it,
stored the current position before every call, and unlinked on return; an
LLVM-inlined callee still did all of it. Now no guest call path touches
anything for the trace. The floor test is the only prologue work left: two
instructions (`cmp %rsp, 0x40(%rdi); ja cold`) in a function that calls.

### Positions in the IL

`callSitePositions` (`src/qbe.zig`) replaces the fast protocol's position
stores. A unit opens with `dbgfile "SYMBOL"` and every call is preceded by
`dbgloc PC+1`, the bytecode instruction the call belongs to (pc 0 for the
prologue's own calls: a heap frame's allocation, the accounting refusal, exactly
where the record's initial position pointed). The entry guard's
`myl_qbe_fail_frame` call is `dbgloc 1, 1`; column 1 marks a frame that was
never entered, so its trace starts at the caller, as when the record was linked
only after the guard.

### QBE

QBE already parses `dbgfile`/`dbgloc` and prints `.file`/`.loc`. QBE never
inlines, so a call's `.loc` line is its position.

### LLVM: pseudo-probe call sites with inline stacks

The hard part is LLVM inlining. The trace must name a callee LLVM inlined into
its caller *and* the caller at the inlined call site, and nothing in a plain
return-address map carries the second half. What was tried:

| mechanism | outcome |
|---|---|
| `noinline` on every guest function that calls (so a return address has exactly one frame) | measured (E1): `spectral_norm` 1.66× → 3.15× Zig, `raytrace` 1.68× → 2.71×, `fib` 2.02× → 2.57×. Rejected. The bytecode inliner does not take `a(i, j)` (it converts to float). |
| `!pcsections` on calls | LLVM drops it in call lowering ("loosing !pcsections metadata"). |
| `llvm.experimental.stackmap` after each call | its label lands after the result copy, not at the return address, and it is an opaque side effect in every loop that calls. |
| DWARF line tables + `.debug_info` inline trees, read at trap time | needs a DWARF reader in the runtime, unstripped binaries and `/proc/self/exe`. |
| **pseudo probes** | **used** |

The adapter gives each call a debug location whose line is the position and
whose discriminator is a pseudo-probe *call* index equal to it
(`packProbeData(index, DirectCall, 0, 100)`), and lists the unit in
`llvm.pseudo_probe_desc`, which turns LLVM's `PseudoProbeInserter` on. LLVM then
prints `.pseudoprobe GUID INDEX 2 0 [@ GUID:INDEX ...] FN` immediately before
every call, where the `@` list names each function the call was inlined
through and the call-site probe index there — the inline stack, in assembly
text. A runtime helper LLVM inlines has no debug information, so each of its
calls inherits the location (and the probe) of the call it replaced
(`fixupLineNumbers`): a trap inside an inlined helper reports the helper's call
site, which is what the record's position said. In a program LLVM inlined
entirely into the C entry wrapper — which happens: the whole guest program of a
small test ends up in `entry_run` — the probes still carry every frame.

Other attributes, all frame-map units only:

- every non-intrinsic call `nomerge` — folding two call sites would fold two
  positions;
- `"disable-tail-calls"="true"` — a sibling call would replace the caller's
  frame, which the record kept;
- `uwtable` — asynchronous unwind tables, so the runtime can unwind an LLVM
  program by its call-frame information and guest code keeps no frame pointer
  (a first build used `"frame-pointer"="non-leaf"`; the unwind tables are
  worth −6.3% on `fib` and −3.9% on `spectral_norm` against it, `r7-*.json`);
- a probe index is 16 bits: a call past position 65 534 carries its location
  without a probe and is `noinline`, and so is its function, so nothing is
  inlined through a position a probe cannot name; its position comes from the
  `.loc` line instead;
- a unit that makes no call carries no debug information at all and stays
  inlinable.

The compile unit is `DebugDirectivesOnly`, and the build strips what LLVM
prints, so no DWARF reaches an object.

### The table and the LTO link

`src/qbe_frame_map.zig` (`QBE-FRAMEMAP-ASM-1`) rewrites one assembly file: a
local label after every positioned call, the `.file`/`.loc`/`.pseudoprobe`
directives and the `.pseudo_probe_desc` sections removed, and a retained
(`"aR"`) `mylang_frame_map` section appended with one 12-byte entry per logical
frame of each call site, innermost first: `{return address, word, metadata}`,
each field a 32-bit self-relative offset. The word is the position with bit 31
for an entry guard, bit 30 for "a caller this call was inlined through", and
bit 29 when the assembly carries call-frame information (LLVM's). It
fails the build on a position it cannot resolve, or a `.loc` that names another
unit's function without a probe (an inlined guest body whose caller the table
would miss).

- QBE and LLVM without LTO: per unit, before the unit's assembly is assembled
  (the object is cached as before).
- Full LTO (the release default): the code only exists inside the link, so a
  frame-map executable is linked in two steps. `zig ld.lld --lto-emit-asm`
  runs LTO over exactly the ordinary link's inputs, with the same
  `--lto-O3 -O3` Zig passes and `main` as the entry root, and writes one
  assembly file; it is annotated, assembled with `zig cc -c`, and linked
  natively with the inputs that were never bitcode (the text formatter, user
  link inputs). `zig cc` rejects `--lto-emit-asm`, which is why LLD is invoked
  directly. The metadata C keeps every unit's `_meta` alive in one `used`
  array, because no code names it any more and LTO would otherwise drop it
  before the table exists.

### The walk at trap time

`fail` (now `noinline`) calls `walk_frames`, which visits every return address
on the guest stack from its own frame outward. Each is looked up — the table
is decoded and sorted once, on the first trap — and each hit contributes its
entries innermost first, skipping an entry guard's; each (function, position)
goes through `trace_frame`, so bytecode-inliner splices expand exactly as
before. `myl_qbe_fail_assert` finds the innermost frame the same way. A
record-protocol program still has `ctx->active_frame` and walks it; the frame
map is used only when no record is linked, and a program with no table finds
nothing.

How the stack is walked depends on the backend, which the table's bit 29 says:

- **LLVM** — by call-frame information. The executable links Zig's LLVM
  libunwind statically (`-lunwind`, with `-u _Unwind_Backtrace -u
  _Unwind_GetIP` because the runtime names both weakly so a program without it
  still links), and the runtime calls `_Unwind_Backtrace`. Guest functions
  carry `uwtable`; the runtime and the generated C carry unwind tables by
  default; the walk ends at glibc's `__start_context`, the bottom of the
  `makecontext` stack.
- **QBE** — by the frame-pointer chain, which QBE keeps in every function that
  calls, bounded by the guest-stack mapping (`native_stack_bottom`/new
  `native_stack_top`) and stopping at the first link that does not move
  outward. The generated C and every runtime unit that can reach `fail` — the
  `qbe_*` units and `native_text_methods.c` — keep a frame pointer where they
  call. The heap, collector and container units only return a status, which
  generated code turns into a trap itself, so they keep every register:
  compiling the whole runtime with frame pointers cost `binary_trees` 4.5%. A
  test over the bundled sources keeps the list honest.

### Stack overflow

The floor test stays, now against the real stack pointer (the adapter reads
`llvm.stacksave`; QBE compares a stack probe allocated after its frame) with no
record. Two instructions remain in a function that calls:
`cmp %rsp, 0x40(%rdi); ja cold`. Its price is the gap between the ladder rung
(`fr`, which also deletes the floor test) and this lane: 0.8% on the
thirteen-program geomean (`lane / ladder rung` 1.008), 5.5% on `raytrace` and
5.2% on `fib`, within noise elsewhere.

A guard page with a `SIGSEGV` handler on an alternate stack would remove it,
and it was not done, because it changes where overflow is detected. Today the
test sits in a guest prologue with 64 KiB of headroom below it, and runtime
code runs inside that headroom unchecked. With a guard page, a runtime helper
called by a recursive function can be the frame that touches the guard, and
the innermost frame of the trace becomes the helper's call site instead of the
recursive call. That is a plausible program (a recursive function that appends
to a list), so the byte-identical requirement rules it out. Keeping today's
semantics with page protection needs a probe at `rsp - 64 KiB` in every
prologue, which is a load from a line that is usually cold. That is no cheaper
than the compare.

## Soundness, mode by mode

| mode | policy | frame protocol | trace from |
|---|---|---|---|
| `mylang build` ReleaseFast, checked, no ceiling | step off, frame off | **frame map** | return addresses |
| `mylang run` without a ceiling | step off, frame off | **frame map** | return addresses |
| `build`/`run` with `--max-steps` or `--max-frames` | accounting on | linked record (unchanged) | `active_frame` chain |
| `mylang build --mode Debug` | accounting on | linked record | `active_frame` chain |
| library / embed API / guest-test runner | accounting on | linked record | `active_frame` chain |
| `run-project` | frame accounting by default | linked record | `active_frame` chain |
| `--unchecked`, no ceiling | no guards | none (unchanged: no trace) | — |

The new assumption is that the walk reaches every guest frame. For LLVM, every
function between `fail` and the top of the guest stack has unwind tables —
guest code through `uwtable`, the runtime, the generated C and glibc's
`__start_context` by default — and libunwind is linked in. For QBE, from `fail`
to the first guest frame only runtime units with frame pointers can intervene
(a unit that names no `myl_qbe_*` symbol cannot reach `fail`, and the runtime
never calls guest code), and every QBE frame that calls has one; that walk is
bounded by the stack mapping and monotonic, so a broken link ends the trace
early and never reads outside the stack. Tail calls are off in guest code; in
runtime code a tail call only removes a C frame. Merged call sites cannot
happen (`nomerge`), and a runtime helper inlined into guest code inherits its
call site's position.

## Trap output

What the trace shows for a frame LLVM inlined is the frame it would have shown
had the call not been inlined: its own function at its own position, then the
caller at the call site. The pseudo-probe inline stack is how that is pinned.

- **Corpus, base against lane, byte for byte** (stdout, stderr — code, message,
  every `in f at file:line`, the `MYLANG-TRAP` record — and exit status):
  40 programs (the 21 `trapdiff` fixtures, the 3 adapter trap tests and 16 new
  cases) × 7 modes:
  - `mylang build` (LLVM, LTO);
  - LLVM without LTO;
  - QBE;
  - `mylang run`;
  - LLVM under `--gc-stress`;
  - QBE under `--gc-stress`;
  - a fast binary given `--max-steps=5`, the `R_NO_STEP_ACCOUNTING` refusal.

  Result: **280/280 identical** (`results/wave4/traps/compare-cfi.log`; the
  frame-pointer build before it: 240/240 over six modes).
- **What the new cases cover:**
  - a trap three frames deep;
  - a 20-frame chain (the 16-line cut);
  - uniform and mutual recursion to the stack floor;
  - an overflow inside a callee LLVM inlines into a loop;
  - an `assert` message from a callee;
  - a key callback called back by `sorted`;
  - a callback through a function value;
  - a missing dictionary key;
  - `R_EMPTY_SEPARATOR` from `split`;
  - `R_FLOAT_CONVERSION` raised inside a runtime helper;
  - `R_MEMORY_BUDGET`;
  - a narrowing cast;
  - a trap inside `with arena()`;
  - a heap-backed frame (five `[1024]i64` locals);
  - a program that does not trap.
- **Pinned in the gate:**
  - `integration.zig` "a frame-map trap names every logical frame…" builds
    four programs (inlined callee, assert in a `sorted` key callback, runtime
    helper trap, recursion to the floor) with LLVM LTO and with QBE, and
    requires today's exact stderr from both.
  - The existing QBE-NORETURN-1 test compares the fast (now frame-map) build
    against a `--max-frames` (linked-record) build and `mylang run` against
    `run --max-frames`.
  - Unit tests pin the IL shape (`qbe_frame_map_test.zig`), the assembly
    rewrite (`qbe_frame_map.zig`), the adapter lowering (`test_adapter.py`,
    run by hand: it is not in the gate) and the runtime-unit frame-pointer
    split.
- **Not reachable.** A function past 65 534 bytecode instructions exercises the
  `noinline` fallback only in the adapter's unit test. A 120 000-instruction
  function fails to build before and after this lane, in both backends: QBE
  and the adapter run out of memory.

## Numbers

Loaded machine (load average 13–20, other agents building), CPU 0, wall time,
arms shuffled inside every round, medians of per-round paired ratios with 95%
bootstrap intervals. The final run is `r6-*.json`: 11 rounds for the suite,
15 for the micro-kernels and 11 for the parser.

The table's columns:

- **base** is `0804a4cf`;
- **ladder rung** is the base's own IL with the record, the floor test and the
  position stores deleted — the plan's `-fr` rung, rebuilt on this base (the
  audit's prebuilt `lad-l5-nr-lang-fr` binaries also strip negative indexing and
  the loop re-check, so they are not comparable).

| program | base / Zig | lane / Zig | lane / base [95% CI] | ladder rung / base | lane / ladder rung |
|---|---:|---:|---:|---:|---:|
| binary_trees | 1.82 | 1.73 | 0.978 [0.944, 1.007] | 0.960 | 1.010 |
| spectral_norm | 1.59 | 1.61 | 1.027 [0.958, 1.038] | 1.026 | 1.006 |
| mandelbrot | 1.01 | 1.01 | 1.006 [0.978, 1.057] | 1.022 | 0.977 |
| raytrace | 1.93 | 1.48 | **0.765** [0.739, 0.788] | 0.704 | 1.055 |
| knucleotide | 4.95 | 4.87 | 0.986 [0.943, 1.016] | 0.970 | 1.020 |
| text_ops | 4.24 | 4.32 | 1.011 [0.990, 1.084] | 1.000 | 1.002 |
| sort_builtin | 0.53 | 0.52 | 1.002 [0.981, 1.015] | 0.999 | 0.991 |
| sort_quick | 1.29 | 1.31 | 1.015 [1.004, 1.027] | 1.017 | 0.994 |
| sort_records | 0.70 | 0.70 | 0.990 [0.972, 1.009] | 0.983 | 1.012 |
| sieve | 1.86 | 1.67 | **0.899** [0.892, 0.904] | 0.906 | 0.998 |
| nbody | 2.01 | 1.92 | 0.953 [0.936, 0.962] | 0.946 | 0.995 |
| fannkuch_redux | 1.18 | 1.20 | 1.031 [1.026, 1.036] | 1.022 | 1.006 |
| matmul | 3.85 | 3.99 | 1.038 [1.027, 1.044] | 0.999 | 1.039 |
| **13-program geomean** | 1.70 | 1.64 | **0.974** [0.966, 0.982] | 0.961 | 1.008 |
| fib | 3.35 | 2.08 | **0.625** [0.617, 0.633] | 0.587 | 1.052 |
| calls | 1.01 | 1.01 | 0.990 [0.985, 1.001] | 0.991 | 0.997 |

**The lane reproduces the rung.**

- On the geomean the lane lands within 0.8% of the rung (`lane / ladder rung`
  1.008). That remainder is the floor test, which the rung deletes and the lane
  keeps.
- Against the counterfactual that keeps the floor test (`frk`), the lane is
  1.001. The earlier run (`r1-*.json`, frame-pointer build) put the lane at
  0.962 of base, and `frk` at 0.965.

**Against the acceptance:**

- **Geomean −5–7%: not met.** The lane measures −2.6% [−3.4, −1.8] in the final
  run and −3.8% in the first. The rung itself measures only −3.9% on this base,
  so the target is not reachable by removing the frame protocol. Part of what
  the audit priced is gone from the base already: noreturn failure paths and
  root liveness removed most of the frame traffic from `spectral_norm`'s inner
  loops, and it now moves by noise.
- **`fib` ≤ 1.3× Zig: not met.** It went from 3.35× to 2.08× (1.93× in
  `r7`), −37.5%, and the rung is 1.97×. The rest is the checked `+`, whose
  lowering LLVM does not turn into `add; jo`: 5 instructions, see below. Zig
  ReleaseSafe runs this kernel at about 1.9× ReleaseFast.
- **`raytrace`: met.** −23.5% (−32% in `r1`), 1.93× → 1.48× Zig. The plan's
  column is 1.55×.
- **`spectral_norm` (the audit's −13%): not reproduced on this base.** The rung
  itself is +2.6% here.
- **Parser: roughly met.** Census −4.8% [−5.9, −3.9] (1.57× → 1.49× Zig) and
  render −5.9% [−12.9, −2.2] (1.82× → 1.71×), against the audit's −8%
  (`parser.json`).

**Small regressions.** `fannkuch_redux` +3.1%, `sort_quick` +1.5% and `matmul`
+1.2–3.8% show up in both the lane and the counterfactual (`frk`/`fr`), whose
code differs from the base only by the deleted record. The hot loops of these
programs contain no call and no frame code. LLVM's layout and unrolling choices
move once the record is gone, and nothing in them is frame-map machinery.

**Build time.** Measured on the parser project and on `raytrace`, cold object
cache and a relink, `buildtime.sh`:

- The two-step LTO link (LLD to assembly, annotate, assemble, native link) adds
  2–3% to a relink: parser 1.14 s → 1.18 s, `raytrace` 0.44 s → 0.45 s.
- A cold build is unchanged: parser 4.02 s → 4.00 s.
- Binaries grow by the table (10 KiB on the parser) and by the statically
  linked libunwind (about 18 KiB): parser 330 KB → 352 KB, `raytrace`
  72 KB → 90 KB.

## 6.4, second half: `readonly` guest functions — not done

The plan's idea: with the record gone, mark a guest function whose signature
says it cannot write — no `mut`, no effects, no allocation — `readonly` or
`memory(argmem: read)`. It is not provably sound, so it is not done:

- **Every trap path writes memory.** A pure function still carries its checks.
  Their `myl_qbe_fail_*` call stores the trap code, the detail and the trace
  into the context (and the first trap sorts the frame-map table into a
  `malloc` block kept in a static) before `longjmp` leaves. A `readonly` or
  `memory(argmem: read)` claim is false on exactly those paths. In practice the
  writes are observed only after control has left every guest frame, but LLVM's
  semantics give no such exemption, and the benefit would come precisely from
  LLVM relying on the claim across calls.
- **`argmem` does not describe this IL.** The adapter passes every pointer as an
  `i64` and converts it at each use (`inttoptr`), and a list's elements sit
  behind a pointer loaded from its header. Neither is "memory based on a pointer
  argument", so `memory(argmem: read)` would make the function's own loads of
  its collection's elements undefined — worse than unsound, it would license
  deleting them. Only a whole-memory `memory(read)` fits, and the trap paths
  break that one.
- **What LLVM now infers by itself.** With no record escaping through `ctx`, a
  guest function that makes no call is no longer a writer at all, and LLVM's
  own attribute inference sees that: such functions are inferred
  `memory(none)`/`memory(read)` under LTO and are freely inlined, hoisted and
  CSE'd. A function that calls a check's fail helper stays opaque, as it must.

A sound version needs the trap paths to write nothing LLVM can see — a fail
helper that only reads its arguments and leaves through `longjmp`, with the
trace built in a buffer the helper owns — and a parameter convention that
carries pointers as `ptr` so `readonly` parameter attributes can say which
argument is only read. Both are adapter/runtime changes larger than this lane.

## Gate

Final tree (`fc7477cb` plus this report), `gate_diff.py` against the
coordinator's gate of the base (`w23-*.log`). Logs are in the lane's
`.tmp/gate/fm-*.log`.

| step | verdict |
|---|---|
| `zig build test` | 47 failures; base 47. **No new failure** once a flake is rerun (below). `native_test_wire` "a record, an array…" passes here, failing on the base (the `/tmp` quota issue). |
| `zig build test-qbe` | 2 failures; base 3. **No new failure.** |
| `zig build test-qbe-build` | green |
| `zig build test-schematic` | green |
| `zig build test-byte-io` | green |
| `zig build fmt-check` | green |
| Guardian | 88/88 checks passed in every step, and in the whole-tree pre-commit run |

The one failure the diff reported as new is
`qbe_build_io` "concurrent staging in one destination never loses a child to
another build's reclaim". It hit `unexpected errno: 2` in shard 10/12 while the
machine was loaded, and it passes when rerun alone with `-Dtest-filter`
(12/12). The lane does not touch `qbe_build_io.zig`, so this is load, not a
regression. The previous build of the lane passed the same gate with zero new
failures.

## What is left

- **The floor test** (0.8% geomean, about 5% on `raytrace` and `fib`). A
  guard-page detector would change which frame an overflow names (see *Stack
  overflow*). A cheaper exact check would need the compare hoisted out of
  functions whose recursion depth is statically bounded. Every function that
  calls still pays it.
- **Checked `+` in `fib`.** The emitter's overflow test,
  `(s ^ a) & (s ^ b) < 0`, reaches LLVM as `add; mov; xor; mov; xor; test; js`,
  and LLVM does not fold it into `add; jo`. Lowering checked add and sub to
  `llvm.sadd.with.overflow` in the adapter, or matching the pattern there, is
  the next `fib` lever. It is unrelated to frames.
- **`fannkuch_redux`/`sort_quick`/`matmul`** move 1–4% the wrong way once the
  record is gone, in the counterfactual as well. The cause is unexplained
  layout and unrolling changes, not frame code.
- **Unchecked builds** still report no trace. The frame map could give them
  one for free, but that changes their documented output (`native-build.md`,
  *Unchecked release builds*), so it is left alone.
- **`test_adapter.py` is not in the gate.** Its new frame-map test passes. Its
  one failure, `myl_native_text_points` missing from the benchmark registry,
  is on the base as well.
- **`MYLANG_FRAME_MAP_KEEP=PATH`** saves the assembly the rewrite refused.
  It is a debugging aid and is only read on that failure path.
