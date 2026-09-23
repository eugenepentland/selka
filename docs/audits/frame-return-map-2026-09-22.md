# Frame protocol → return-address map — wave 4, lane `perf/frame-return-map` — 2026-09-22

Implements plan item 6.8 (roadmap item 2) and assesses 6.4's second half from
[`performance-parity-plan-2026-09-22.md`](performance-parity-plan-2026-09-22.md).
Base: `base/parity-w4` (`0804a4cf`: the parity audit, lane 5, wave-0 fixes,
text scans, sorting, NaN when observed, noreturn failure paths, root liveness,
fixed-array writes). Result JSONs and the probe corpus are under
[`experiments/perf-parity-plan-20260922/results/wave4/`](../../experiments/perf-parity-plan-20260922/results/wave4/).

## Result

@@RESULT@@

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
- `"frame-pointer"="non-leaf"` — the chain the runtime walks;
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
for an entry guard and bit 30 for "a caller this call was inlined through". It
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

`fail` (now `noinline`) calls `walk_frames`, which follows the frame-pointer
chain from its own frame while the chain stays inside the guest-stack mapping
(`native_stack_bottom`/new `native_stack_top`) and moves outward. Every saved
return address is looked up — the table is decoded and sorted once, on the
first trap — and each hit contributes its entries innermost first, skipping an
entry guard's; each (function, position) goes through `trace_frame`, so
bytecode-inliner splices expand exactly as before. `myl_qbe_fail_assert` finds
the innermost frame the same way. A record-protocol program still has
`ctx->active_frame` and walks it; the frame map is used only when no record is
linked, and a program with no table finds nothing.

Frame pointers: guest code keeps them (QBE always does in a function that
calls; LLVM through the attribute), and so do the generated C and every runtime
unit that can reach `fail` — the `qbe_*` units and `native_text_methods.c`.
The heap, collector and container units only return a status, which generated
code turns into a trap itself, so they keep every register: compiling the
whole runtime with frame pointers cost `binary_trees` 4.5%. A test over the
bundled sources keeps the list honest.

### Stack overflow

The floor test stays, now against the real stack pointer (the adapter reads
`llvm.stacksave`; QBE compares a stack probe allocated after its frame) with no
record. Its price, measured as the counterfactual without it: @@FLOOR@@. A
guard-page detector would remove that, but it moves where overflow is detected
— a runtime helper's frame can hit the guard where today only guest prologues
test — so the innermost frame of an overflow trace could differ from today's,
and large LLVM frames would need stack probes. Not done; recorded as the next
lever.

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

The one new assumption is the chain: from `fail` to the first guest frame only
runtime units with frame pointers can intervene (a unit that names no
`myl_qbe_*` symbol cannot reach `fail`; the runtime never calls guest code),
and every guest frame has one. Tail calls are off in guest code; in runtime
code a tail call only removes a C frame. The walk is bounded by the stack
mapping and monotonic, so a broken link ends the trace early, it never reads
outside the stack.

## Trap output

@@TRAPS@@

## Numbers

@@NUMBERS@@

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

@@GATE@@

## What is left

@@LEFT@@
