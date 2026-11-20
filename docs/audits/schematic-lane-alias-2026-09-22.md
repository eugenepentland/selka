# Schematic lane 3: telling LLVM which memory a managed access touches — 2026-09-22

Lane 3 of the [schematic parity gap](schematic-parity-gap-2026-09-22.md) plan:
§4's *container headers are reloaded on every element access*, §5 item 3. The
LLVM adapter's first design rule used to forbid every aliasing annotation, so
LLVM could not keep a managed container's length or storage pointer in a
register across a loop. This lane gives it the one aliasing fact the runtime's
own invariants guarantee, without ever stating a fact a guard is about to
establish.

Branch `perf/schematic-3-adapter-alias`, base `base/schematic-20260922`
(`6ee47415`).

## Headline

1. The emitted QBE IL now marks managed addresses with a `# myl-obj %temp`
   comment line; the adapter combines those with the unit's own `alloc*` slots
   and two runtime helpers to place **99.8% of the 67,412 memory instructions**
   of the schematic closure in one of two classes, and emits scoped
   `!alias.scope`/`!noalias` metadata for each placed access.
2. **QBE's assembly is byte-identical.** All 124 units of the schematic closure
   assemble to the same bytes with and without the markers, and the LLVM arm
   built with the metadata switched off is byte-for-byte the audit's retained
   `gc-lto` binary — so the before/after below is a single-variable comparison.
3. The machine code moves where the audit said it would. `io::flush`'s output
   copy loop drops from **18 to 16 instructions per byte** (17 → 15 in the LTO
   arm), and in the LTO arm `io::flush` no longer survives as a symbol at all:
   the shorter body now fits the inliner's budget. `svg::render`'s loop set
   shrinks from nine loops to five as its frame block stops aliasing everything.
4. **The time it buys is real but small: 1.4%.** On the quietest batch this
   machine allowed (251 interleaved rounds, load average 14), the metadata arm
   runs at **0.986 [0.977, 0.994]** of its own byte-identical control, against a
   noise floor of ±0.8% measured by timing that control against the identical
   audit binary in the same batch. Against Zig the fixture goes 2.016 → 1.989.
   Batches taken while the machine carried a load average of 27–49 could not
   resolve the effect at all. The integrator should re-measure on a quiet
   machine.
5. `io::load`'s per-byte append loop is **unchanged at 13 instructions**, and no
   aliasing fact can change it: the loop body contains the grow call, so LLVM
   cannot promote the header across it. That loop is audit item 4 (bulk I/O),
   not item 3.

## 1. The memory-class model

Every memory access an emitted unit performs falls, where it can be placed at
all, into one of two classes.

| class | what is in it | where the adapter learns it |
|---|---|---|
| **frame** | the unit's `alloc4/8/16` slots — local slots `%l*`, operand scratch `%s*`, aggregate scratch `%agg*`, root records `%root*`, the frame record and `%empty` — the private copy an aggregate parameter arrives in, and the block `myl_qbe_frame_allocate` obtains on entry for a unit whose frame is too large for the stack | structurally: `alloc*` destinations, aggregate parameters, and one named runtime helper |
| **foreign** | a value the caller computed (every scalar parameter, `%ctx` first among them), a global's address, the context's embedded heap record `myl_qbe_heap` answers, and every managed container header or element-storage word the frontend marked | structurally for parameters, globals and `myl_qbe_heap`; from `# myl-obj %temp` markers for managed addresses |

Anything else is **unplaced** and carries no metadata at all, so it keeps
aliasing both classes exactly as every access did before.

### Soundness

The claim the metadata makes is only this: *an access of one class never aliases
an access of the other.* It holds because everything in **frame** is an
allocation this activation itself made after it was entered.

- An `alloc4/8/16` block is this activation's stack storage. Nothing that
  existed before the call can point into it, and it dies with the activation.
- An aggregate parameter is a private copy: the adapter passes it as `byval` or
  rebuilds it into a local `alloca`, and LLVM already models `byval` as
  callee-local storage.
- `myl_qbe_frame_allocate(ctx, n)` (`src/qbe_runtime.c`) `calloc`s a fresh block
  that holds only this activation's slots and that `myl_qbe_frame_release` frees
  on the way out. A live pointer cannot point into a block `calloc` has just
  returned, and no managed object is ever allocated inside it.
- Everything in **foreign** either existed before the activation (a parameter, a
  global), is the caller's context record (`myl_qbe_heap` returns
  `&((Context *)ctx)->heap`), or is memory `myl_native_heap_alloc` owns — a
  managed container's header, or the storage block its `storage` word names.
  None of those can be the activation's own fresh allocation.

Three details make the *partial* classification safe rather than merely lucky:

- **A contradiction discards the unit.** If the fixpoint ever reaches one
  temporary as both classes, the whole unit's classification is thrown away and
  nothing is tagged. No unit of the schematic closure does.
- **Only singly-defined temporaries are placed.** QBE temporaries are mutable
  cells; a name the unit redefines is never given a class.
- **A class travels through a stack slot only when it is established.** The
  adapter carries a class through `copy` and offsetting `add`, and through a
  slot whose address never leaves the unit in two ways: whole-slot, when every
  store to it agrees on one class *and* one of those stores dominates every load
  of it (computed with a real dominator relation over the unit's CFG, so a slot
  read on a path no store reaches is never placed); and within one block, from
  the last value stored above the load. That second rule is what carries a class
  across the push and pop the frontend's operand stack writes around every
  value, and it is what lets `len(out.buffer)` and `out.buffer[i]` in `io::flush`
  see that `out` arrived as a parameter.

A `blit` takes metadata only when its source and destination are the *same*
class, because LLVM applies one `!noalias` list to the whole `memmove`.

### What is emitted

Per module, when at least one access is placed:

```text
!0 = distinct !{!0, !"mylang memory classes"}
!1 = distinct !{!1, !0, !"frame"}
!2 = distinct !{!2, !0, !"foreign"}
!3 = !{!1}
!4 = !{!2}
```

A frame access carries `!alias.scope !3, !noalias !4` and a foreign access
`!alias.scope !4, !noalias !3`. The domain and both scopes are `distinct`, so
the IR linker cannot unify one unit's classes with another's during LTO — a
cross-unit pair simply draws no conclusion, which is the conservative answer.
`MYLANG_QBE_LLVM_ALIAS=0` turns the whole thing off for an A/B run.

### The emitter side

`src/qbe.zig` gains one helper, `Emitter.markObject(value)`, which prints
`# myl-obj %v<N>` as a line of its own. Five lowering sites call it:
`emitOperation`'s and `emitLength`'s receiver, `receiverLength`,
`elementAddress` (the receiver and the storage word it loads) and
`inlineAppend`'s backing pointer in `src/qbe_managed.zig`, and the byte-buffer
append receiver, source and storage in `src/qbe_bytes.zig`. That is 1,510
markers over the schematic closure, in 58 of its 124 units.

QBE's lexer drops a `#` comment to end of line, so the markers are invisible to
the QBE backend. Proven, not assumed: running the vendored `qbe` over all 124
units of the schematic closure with and without the marker lines gives **124
identical, 0 different** assemblies.

## 2. Coverage

Placement over the schematic closure's 67,412 memory instructions (21,403
loads, 45,628 stores, 381 blits), 124 units, 0 contradictions:

| configuration | frame | foreign | unplaced | placed |
|---|---:|---:|---:|---:|
| structural only, no markers | 56,113 | 989 | 10,310 | 84.7% |
| + `# myl-obj` markers | 56,113 | 2,273 | 9,026 | 86.6% |
| + `myl_qbe_frame_allocate` as frame | 58,529 | 2,273 | 6,610 | 90.1% |
| + `myl_qbe_heap` as foreign (shipped) | 58,529 | 8,736 | 147 | **99.8%** |

The markers more than double the foreign placements, and they reach the accesses
that matter: `sexpr::at` goes from three unplaced accesses to zero, `io::flush`
from sixteen to ten before the helper rules, `layout_routes::build` from 776
unplaced to 589. The `myl_qbe_frame_allocate` rule unlocks the large-frame
functions — `svg::render` keeps its locals in that block rather than in `alloc8`
slots, and went from 2,707 unplaced accesses to 283. The `myl_qbe_heap` rule
places the root-list traffic every call site writes.

## 3. The machine code

Non-LTO `-O3` arms built from the same manifest, `objdump -d`, innermost
backward-branch loop bodies. `off` is the control (metadata disabled), `on` is
the shipped adapter.

| loop | off | on |
|---|---:|---:|
| `io::flush` output copy, per byte | **18** | **16** |
| `io::load` append, per byte | 13 | 13 |
| `svg::render`, largest loops | 209, 220, 237, 426, 445, 449, 453 (nine loops) | 173, 189, 591 (five loops) |
| `layout_routes::build` | unchanged | unchanged |

`io::flush`'s copy loop, before:

```text
test %rax,%rsi ; js …                  # position + i overflow guard
mov 0x0(%r13),%r9                      # reload out.buffer
mov (%r9),%rdx                         # reload the header's length
mov %rsi,%r10 ; sar $0x3f,%r10 ; and %rdx,%r10 ; lea (%r10,%rsi,1),%r11
cmp %rdx,%r11 ; jae …                  # bounds guard
add 0x20(%r9),%r10                     # reload the header's storage word
movzbl (%rsi,%r10,1),%edx              # the element
mov %dl,(%r8)                          # into the 256-byte payload
dec %rcx ; inc %rsi ; inc %r8 ; cmp %rcx,%rdi ; jne …
```

and after, with both reloads hoisted out of the loop (`%rax` now holds the
buffer object across it):

```text
test %rdi,%rsi ; js …
mov %rsi,%r10 ; sar $0x3f,%r10 ; and %rdx,%r10 ; lea (%r10,%rsi,1),%r11
cmp %rdx,%r11 ; jae …
add 0x20(%rax),%r10
movzbl (%rsi,%r10,1),%r10d
mov %r10b,(%r9)
dec %rcx ; inc %rsi ; inc %r9 ; cmp %rcx,%r8 ; jne …
```

The store into the 256-byte payload is `frame`; the `out.buffer` field read, the
length and the storage word are `foreign`; the two classes cannot meet, so LICM
hoists both header loads. What remains per byte is the overflow guard, the
negative-index normalisation, the bounds guard, the element load, the store and
five instructions of loop bookkeeping — the checks and the loop, not the header.

In the LTO arm the same loop goes 17 → 15 and `io::flush` is inlined into
`main::main` outright, which it was not before.

**`io::load` cannot be fixed this way and is not.** Its per-byte body is the
inline `append_byte` fast path, and the *slow* path in the same loop calls
`myl_native_bytes_buffer_append_byte`, which writes the header. LICM's store
promotion needs no aliasing access anywhere in the loop, and a call that may
write the location is one, so the length, capacity and storage words are re-read
every iteration no matter what the metadata says. That is audit item 4 — one
`write_bytes(buffer)` host call instead of 40 K appends — not item 3.

`layout_routes::build` is unchanged for the same reason: its 87 markers place
195 accesses, but its loops all contain calls.

## 4. Timing

Other lanes were building on this machine throughout, so every batch carries a
load average well above idle and the reference arm is inflated against the
audit's own measurement of it (Zig's fixture median 2.92 ms in the best batch
here against 1.31 ms in the audit). These are therefore ratios between arms
measured in the same interleaved batch and nothing else. Because `lane3-off` is
byte-for-byte `base-gc-lto`, every batch also measures its own noise floor: the
`lane3-off / base-gc-lto` row is what "no difference" looks like in that batch.

### Fresh-process wall clock

`bench_svg.py`, CPU 8, 251 interleaved rounds, three warmups, every run's SVG
hash checked against the reference arm's; taken at load average 14, the quietest
window available.

| arm | fixture, ms | min | × zig-o3 |
|---|---:|---:|---:|
| `zig-o3` | 2.918 | 1.960 | 1.00 |
| `base-gc-lto` (the audit's binary) | 5.882 | 4.003 | 2.02 [2.00, 2.03] |
| `lane3-off` (this tree, metadata off) | 5.883 | 3.993 | 2.02 [2.00, 2.03] |
| `lane3-on` | 5.803 | 3.995 | **1.99 [1.97, 2.01]** |

Paired bootstraps over the same rounds:

| comparison | ratio | 95% |
|---|---:|---|
| `lane3-on` / `lane3-off` | **0.9864** | **[0.9771, 0.9945]** |
| `lane3-on` / `base-gc-lto` | 0.9865 | [0.9779, 0.9947] |
| `lane3-off` / `base-gc-lto` | 1.0001 | [0.9935, 1.0085] |

The third row is this batch's noise floor — two identical binaries, ±0.8% at
95% — so the 1.4% the metadata buys is outside it, if not by much. About 40% of
the fixture's wall time is process floor (§3.1 of the audit), so 1.4% of wall is
roughly 2.3% of the guest's own work.

Two earlier batches of the same arms, taken while the machine carried a load
average of 27–49, could not resolve it: 251 rounds gave 0.984 [0.888, 1.015]
against a ±7% noise floor, and 101 rounds gave 0.978 [0.948, 1.003] against
±3%. Load, not the change, is what moved between them.

### Guest CPU clock, per phase

`phases_my.py`'s `--wrap` probes around 13 guest functions, both arms
interleaved inside one batch so machine load lands on both, CPU 8,
`CLOCK_PROCESS_CPUTIME_ID`, 201 rounds. Values are inclusive microseconds;
`ratio` is the median of the per-round paired ratios.

| phase | off | on | ratio | p10..p90 |
|---|---:|---:|---:|---|
| `main::main` | 2297.8 | 2303.7 | 0.993 | [0.903, 1.136] |
| `io::load` | 134.5 | 139.0 | 1.013 | [0.921, 1.145] |
| `sexpr::parse` | 325.7 | 329.9 | 0.987 | [0.881, 1.111] |
| `schematic::build` | 658.0 | 660.1 | 0.997 | [0.918, 1.100] |
| `svg::render` | 1089.2 | 1128.4 | 0.994 | [0.860, 1.219] |
| `layout::build` | 418.0 | 426.7 | 1.004 | [0.867, 1.241] |
| `layout_routes::build` | 68.8 | 68.7 | 0.978 | [0.830, 1.330] |
| `io::flush` | 111.1 | 111.2 | 0.993 | [0.793, 1.343] |

An earlier 61-round batch of the same two arms, taken while the machine was
about twice as loaded, put `main::main` at 0.979 [0.930, 1.023] and its minimum
at 0.905. Both batches ran at a load this probe cannot see through: its p10..p90
spread is ±10% or worse on every phase, an order of magnitude wider than the
1.4% the wall-clock batch resolves. The per-phase attribution of this change is
therefore **not measured**; §3's loop sizes are what the phase numbers would
have to confirm, and a quiet machine is what it would take.

### Micro kernels

Not run. `experiments/perf-parity-audit-20260921/micro/run.py` builds its arms
through the tree's `zig-out/bin/mylang`, and a matched before/after needs two
full eleven-kernel builds plus about twenty-five minutes of timing per side; on
a machine this loaded the result would be less trustworthy than the loop counts
in §3, which are deterministic. The kernels that would show the effect are
`bytes_scan` and `list_records`, whose inner loops are exactly the
`while i < len(xs): … xs[i] …` shape §3 measures directly.

## 5. Correctness

| check | result |
|---|---|
| QBE assembly identity over the schematic closure | 124 identical, 0 different |
| `verify_traps.py` (differential trap corpus, both arms, every accounting mode, with and without GC stress) | 504 built-binary comparisons across 21 fixtures, **0 mismatches** |
| `qualify_traps.py` (trap, ceiling, GC-stress and exit-status matrix) | 72 arm comparisons across 18 probes, **0 failures** |
| `verify_units.py` on the schematic manifest | 124 units translate and assemble, OK |
| `test_adapter.py` | 24 tests, 22 pass; the two failures are pre-existing (§7) |
| `zig build test-qbe-build --summary all` | exit **0** |

`verify_semantics.py` and `qualify_sweep.py` were **not** run: both build
`experiments/sexpr-port/main.my`, which does not check on this base —
`sexpr/printer.my:209` still carries a `mutates(...)` clause and the current
checker rejects it with `E_REMOVED_SPELLING`. That is the same pre-existing
breakage as §7 and is unrelated to this lane.

The trap corpus is the check that matters here: an annotation applied ahead of a
guard would let LLVM delete the guard, and the corpus asserts that every trap
still fires with the same message and the same exit-status byte, in both
backends and in every accounting mode. Nothing here annotates ahead of a guard —
the two classes are a fact about *where* memory lives, established at the point
the address is produced, independent of any check.

### New tests

- `src/qbe_test.zig`: `// spec: QBE-ALIAS-CLASS-1` pins that a
  `while i < len(values): … values[i] …` body marks each `len` receiver, the
  element read's receiver and the storage word it loads; that every marker is
  its own comment line, which is what makes QBE's output byte-identical; and
  that a function touching no managed container is marked nowhere. `SPEC.md`
  carries the matching `- [QBE-ALIAS-CLASS-1] …` bullet.
- `experiments/llvm-backend/test_adapter.py`: five cases covering a marked
  object address that only the marker can place (with an executed binary), an
  unmarked address from memory left unplaced, `MYLANG_QBE_LLVM_ALIAS=0`, a slot
  no store dominates being left unplaced, and the two runtime helpers' classes.

## 6. What was left out, and why

- **`nsw` / `nuw` on arithmetic.** Unsound here, and not marginally so. The
  emitted IL computes the wrapped result and *then* tests it
  (`%v614 =l add %v613, %v612` followed by the `xor`/`and`/`csltl` triple that
  reads `%v614`). `nsw` makes signed overflow undefined, which makes the test
  that follows dead, which deletes the guard. Every checked arithmetic site in
  the IL has this shape.
- **`inbounds` on GEPs.** Sound after the bounds guard, but it buys nothing the
  class metadata does not already buy here: the loads it would apply to are
  already proven not to alias the frame, and `inbounds` mostly helps
  reassociation and the distinct-objects rule the classes already cover. Left
  out to keep the annotation set minimal.
- **Splitting `foreign` into a header class and an element class.** Sound — a
  list header and the block its `storage` word names are separate allocations,
  and a `bytes` view or snapshot that shares another's storage is still element
  storage — and it would let an element store not clobber a header load. Left
  out because the loops where it would pay are the append loops, which already
  have a call in the body that blocks promotion for the same reason, so it would
  add a class for no measured gain.
- **`noreturn` on the `myl_qbe_fail_*` helpers.** This would be a large win:
  every guard's failure block would become a terminator and the join would
  vanish. It is **not sound**. `fail()` in `src/qbe_runtime.c` longjmps only when
  `ctx->unwind` is armed and otherwise returns with the sticky trap flag set,
  which is the path the direct C entry points and budget parsing take. An
  emitted unit cannot know which context it will run under.
- **`memory(argmem: readwrite)` on the managed runtime helpers.** Their argument
  memory reaches the header and the storage block, so it does not make a header
  load survive a call, and non-escaping frame slots are already safe across
  calls. No measured value.
- **Record field accesses on class instances.** `svg::render` and friends still
  leave a field read unplaced when the receiver came out of memory; the receiver
  is known to be heap only from its *type*, so placing them needs a marker at
  each field-access lowering site rather than one per managed operation. Left
  for whoever takes audit item 2, which rewrites those accesses anyway.

## 7. Gate

Through the build protocol (`ZIG_LOCAL_CACHE_DIR=…/zig-local-cache-alias
~/capbuild zig build …`):

| step | exit |
|---|---|
| `zig build test --summary all` | **1** — 49 failing tests, every one pre-existing |
| `zig build test-qbe --summary all` | **1** — 2 failing steps, both pre-existing |
| `zig build test-qbe-build --summary all` | **0** |
| `zig build fmt-check` | **0** |

**The failures are the base branch's, not this lane's.** All 49 fail inside the
checker — `sema.checkCached`, `effects.check` or `parser.rejectMutatesClause` —
with `E_MUTATION_MARKER`, `E_MUTATION_PERMISSION` or `E_REMOVED_SPELLING`: the
`mut`-marker work landed on `base/schematic-20260922` without updating the tests
and fixtures that spell the old contract. Three independent facts pin this down:

- This lane's diff touches `src/qbe.zig`, `src/qbe_managed.zig`,
  `src/qbe_bytes.zig` and `src/qbe_test.zig` and nothing else under `src/`;
  `sema.zig`, `effects.zig`, `parser.zig` and `effects_test.zig` are untouched.
- The compiler frozen at the audit's own base commit (`acbee603`) rejects the
  same sources the same way — `QBE-PURE-READ-1`'s `bump(counts, key)`, and the
  `qbe_arena` golden whose case appends to a plain `list` parameter.
- The emitter change produces byte-identical QBE assembly for all 124 units of
  the schematic closure, and `zig build test` runs its guest programs through
  QBE, so nothing this lane emits can reach those tests at all.

`zig build test-qbe`'s two failures are the same thing:
`native_test_wire.test.local mutation reuses a receipt while output executes
again`, and `golden_parity`'s 11 mismatches, every one of which is a corpus case
that now fails to *check* (`rc=1`, empty stdout) rather than producing its
recorded trap.

One of the 49 is fixed here as collateral: `QBE-PURE-READ-1` lives next to the
test this lane adds, and its fixture is updated to the `mut` spelling
(`def bump(counts: mut dict[str, i64], …)` and `bump(mut counts, "k")`). The
`QBE`-filtered subset of `src/root_test.zig` is green: 39 selected, 39 passed.

`test_adapter.py`'s two failures are likewise pre-existing and untouched here:
`test_heap_getter_has_only_proven_memory_effects` references `ATTRIBUTES`, which
the test module never imports, and `test_benchmark_runtime_registry_is_complete`
reports `myl_native_text_points` missing from `runtime_signatures.py`.

## 8. Method and limits

- Compiler: this worktree built `-Doptimize=ReleaseFast` to a private prefix.
  The adapter installs beside it under `lib/mylang-llvm/`; the control arm uses
  a copy of that directory with the metadata default flipped off, selected with
  `--llvm-adapter`.
- Arms: `build_arms.py` with `spec-base.json` (`gc-lto`: LLVM `-O3` + LTO, GC,
  unbounded) and `spec-o3.json` (`o3`: the same manifest without LTO, which is
  what the phase probes relink). Each control arm was built from the identical
  manifest with the alias-off adapter and its own object cache.
- The control arm `lane3-off` hashes
  `074a4c32ce62068a6dae9f48d8d5fd9b09ea5b50259d02413317e26ab707805b`, exactly
  the audit's retained `gc-lto` binary. The emitter markers therefore change
  nothing at all when the metadata is off.
- Timing pinned to CPU 8; every timed run reproduces the fixture's SVG hash.
  `perf_event_paranoid` is 4 and there is no `valgrind` on this host, so there
  are no instruction or cycle counts; the deterministic evidence in §3 is static
  loop size from `objdump`, and the timing is wall and CPU clock only.
- One machine (i7-12700H), one circuit, one input case for the long batches. The
  headline batch ran at load average 14; the phase batches ran at 27–49, which
  is why they resolve nothing. Every batch reports its own noise floor by timing
  two identical binaries in it.
