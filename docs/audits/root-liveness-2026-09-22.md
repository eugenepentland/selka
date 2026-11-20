# Root liveness for hidden temporaries — 2026-09-22

Wave 2, item 2 of [the parity plan](performance-parity-plan-2026-09-22.md)
(§6.3), plus the two follow-ups [lane 5](schematic-lane-aggregates-2026-09-22.md)
left in its Limits section. Branch `perf/root-liveness` from `base/parity-w2`
(`684be597`, the parity audit plus lane 5).

**Status: done, gated.** A safepoint now publishes a root record only for the
traced locals that are live at it. Static root records across the thirteen
suite programs fall from 3,112 to 715; each safepoint's count is its live set.
On a loaded machine the suite geomean is −3.9% against lane 5 (the
collector-off, no-roots counterfactual measures −3.0% of headroom after lane 5).
The parser's render step is −14% and the schematic renderer is −2 to −6%. No
program is slower beyond noise, and `raytrace` is back below its pre-lane-5
time. Along the way the lane found and fixed a use-after-free that is already on
the base: invoking a function value was not a safepoint.

## What changed

### `QBE-ROOTLIVE-1` — publish only what is live

`src/qbe_liveness.zig` (new) runs a backward liveness dataflow over the
function's bytecode. `Emitter.roots` asks it, per safepoint, whether each traced
local is live there. Operand-stack values are published exactly as before.

**The rule.** At a safepoint at `pc`, local `x` is published when `x` is in
`uses(pc) ∪ live_out(pc)`, or when `x` is *pinned*.

- `live_in(pc) = (live_out(pc) − kills(pc)) ∪ uses(pc)`.
- `live_out(pc)` is the union of `live_in` over `pc`'s successors. The
  successor relation is the one the bytecode validator walks: jumps, both edges
  of `jump_if_false`, both edges of a `?` (`try_result`), every match arm, and
  no successor after `ret`.

The sets are computed to a fixpoint, one bit row per instruction.

Uses:

- `load_local` and `move_local`.
- The receiver of a collection method, and the handle of a resource or file
  method.
- `end_arena`: closing a scope scans every local declared before it through its
  slot.
- A `decode` two instructions after a fusible `slice`: `src[a:b].decode()`
  hands the slice's receiver to the decode in a register.
- A clearing `drop_local` of an owning type.

Kills:

- `store_local`.
- A clearing `drop_local` of a type that owns nothing.
- A match arm's payload binding, on the edge into that arm only.

Pinned: every local whose type owns something (`layout.drop`). The epilogue and
every overwriting store release such a local through its slot, so it stays
published everywhere, as before.

A hidden receiver temporary the front end made for one `xs[...]` stops being a
root after its read. A named local stops being a root after its last read. A
value read at a loop head stays a root across the whole body.

**Why it is sound.** After a collection the frame reaches a heap object only
through a value it reads: a local read (a use), an operand (still published), or
something reachable from either (traced). The lowering's reads that are not
bytecode reads are listed above as uses. They are the only ones: the only
cross-instruction register the emitter holds is the fused decode's receiver, and
the only lowerings that read local slots outside `load_local`/`move_local` are
the collection, resource and file methods, the arena scan, the epilogue's
releases and the root push itself.

*A root can never trace a stale pointer.* Suppose `x` is dead at safepoint `Q`,
so a collection there may free what `x` names. Suppose `x` is then published at
a later point `P` with no write of `x` on the path from `Q` to `P`. Then `x` is
in `uses(P) ∪ live_out(P)`, so a read of `x` is reachable from `P` without a
write, and therefore from `Q` without a write. That makes `x` live at `Q`,
which contradicts the assumption.

*Addresses into other storage are covered by what already roots them.* This
covers the cases where a slot or operand holds an address instead of a value:

- **Element borrows** (`QBE-ELEMREF-2`) are never roots and never live across a
  safepoint.
- **Payload projections** (`QBE-MATCHPROJ-1`) name frame or caller storage, and
  are rooted through their own address when live.
- **By-address parameters** are also rooted by the caller, whose argument is an
  operand at the call.
- **Local-slot operands** (`QBE-AGGREF-1`) are rooted by the stack half of the
  push.

Liveness also tightens one thing that was loose before. The old protocol pushed
every projected payload binding at every safepoint, including bindings whose arm
was not the variant the scrutinee held. A binding is now live only inside its own
arm.

**The zero-fill.** `dropUnusedRoots` still strips the per-local zero-fill from a
function that pushes no root at all, but it now keeps it when the function
closes an arena scope. That scan reads locals declared before the scope whether
or not the body has assigned them yet. With fewer pushes, more functions reach
this path.

### `QBE-INVOKE-SAFEPOINT-1` — a function-value call is a safepoint (existing bug)

`loweredAllocates` and `unitAllocates` looked only for `call $name`, so an
indirect call `call %vN(...)` was treated as a non-allocating operation:

- No root push was emitted around it.
- A function that invoked a callback counted as "cannot allocate" for its
  callers (`QBE-PURECALL-1`).

This program printed 205 instead of 62 under `--gc-stress` on the lane-5
compiler:

```
def apply(f: def(int) -> int, n: int) -> int:
    keep = [n, n + 1, n + 2, n + 3]
    r = f(n)
    return r + keep[2]
```

The callee allocated, the collection swept `keep`, and `keep[2]` read freed
memory. Liveness could not be made sound on top of that, so the lane fixed it:
any `call %` makes the instruction a safepoint and the unit allocating. The guest
test `root_liveness::test_a_list_survives_a_callback_that_allocates` fails on the
lane-5 compiler and passes here.

### `QBE-ELEMREF-3` — an integer cast is inert (lane 5 follow-up a)

`cast_integer` with an integer target only range-checks and traps, like the
checked arithmetic already on the inert list. It is how the negative-index
normalization of a runtime index converts the receiver length. So `row =
rows[i]; … counts[row.b] …` no longer cancels the borrow. A cast to text
allocates a string and still ends the claim.

### `QBE-ELEMREF-4` — a borrow may cross a call that cannot reach the list (follow-up b)

**The decision: yes, provably, for a restricted but common class of callee.**
The borrowed element stops naming what was checked only if the receiver's
backing storage is grown, overwritten, shrunk or freed. A direct call in the
borrow's live range is admitted when all of these hold:

1. **The allocation analysis proved the callee cannot allocate**: not directly,
   not through any guest callee, and (after the fix above) not through a
   function value. So it can neither collect nor grow a list.
2. **None of its parameter types traces a reference.** The language has:
   - no mutable globals (a module constant is an immutable scalar literal);
   - no closures;
   - no function-value state (a function value names a top-level function).

   A callee that starts with no heap reference and cannot allocate one can name
   no heap object, so it cannot name the receiver. That rules out classes,
   lists, dicts, `Cell`s and records holding any of them.
3. **It has no mutation footprint** (`mutates`/`declared_mutates` empty) **and
   writes no aggregate parameter.** A `mut [N]T` of scalars traces nothing, so
   this is what rules out a callee writing storage its caller names.

The borrowed element itself may be an argument. Its type then traces nothing
either, and the callee reads it in place (`QBE-AGGREF-1`). The first emission
pass has no allocation analysis, so every call declines there. The second pass
only removes copies, so the analysis measured from pass one stays conservative.

`raytrace`'s `for k, s in enumerate(spheres): t = intersect(origin, direction,
s)` and the second sphere loop now read each 56-byte `Sphere` in place. `shade`
goes from 3 whole-record copies to 1.

## Root records, before and after

Static census of the release-policy manifests (`emit-qbe --drop-debug
--drop-step-checks --drop-frame-checks`). **Before** is lane 5's
(`.tmp/perf-plan-20260922/work/bench/l5/<name>.manifest.json`). **After** is this
branch's ReleaseFast compiler. A push is one safepoint's record list, and its
length is now that safepoint's live traced locals plus traced operands.

| program | pushes | records before → after | largest push before → after |
|---|---:|---:|---:|
| binary_trees | 35 → 34 | 248 → 89 | 8 → 4 |
| spectral_norm | 11 → 9 | 102 → 26 | 13 → 6 |
| mandelbrot | 10 → 9 | 26 → 20 | 3 → 3 |
| raytrace | 8 → 6 | 16 → 6 | 2 → 1 |
| knucleotide | 42 → 42 | 966 → 166 | 27 → 14 |
| text_ops | 99 → 97 | 1,006 → 260 | 20 → 5 |
| sort_builtin | 5 → 3 | 30 → 3 | 6 → 1 |
| **sort_quick** | 4 → 2 | 24 → 2 | 6 → 1 |
| sort_records | 39 → 39 | 334 → 88 | 14 → 6 |
| **sieve** | 3 → 1 | 21 → 1 | 7 → 1 |
| **nbody** | 9 → 6 | 9 → 6 | 1 → 1 |
| **fannkuch_redux** | 17 → 14 | 160 → 29 | 22 → 3 |
| **matmul** | 12 → 8 | 170 → 19 | 20 → 4 |
| **total** | 294 → 270 | **3,112 → 715** | |

Per function, for the five programs the task names:

- **`nbody`**: `advance` pushes nothing either way, because lane 5 removed its
  list-write safepoints. `initial_bodies` goes from 6×1 to 5×1 and `main` from
  3×1 to 1×1.
- **`matmul`**: `main` goes from `[19, 19, 19, 19, 19, 20, 19, 19]` to
  `[1, 2, 3, 4, 4]`, and `random_matrix` from `[4, 4, 4, 5]` to `[1, 2, 2]`.
- **`fannkuch_redux`**: `fannkuch` goes from `[22 ×6]` to `[1, 1, 2, 2, 3]`.
- **`sieve`**: `main` goes from `[7, 7, 7]` to `[1]`.
- **`sort_quick`**: `main` goes from `[6, 6, 6, 6]` to `[1, 1]`.

Elsewhere, `knucleotide`'s `main` averaged 26.6 records per push and now
averages 4.4. `sort::sort_by_key` goes from 12–14 per push to 1–3.

The tool is `.tmp/tools/census_table.py` in the worktree (untracked), and the
per-function JSON is `.tmp/census.json`.

## Timing

All timing is on a **loaded machine**:

- Load average 13–20 during every batch.
- Pinned to **CPU 1**, which is the hyperthread sibling of CPU 0, so Zig
  reference times are about 2× the audit's.
- Fresh processes, arms shuffled per round.
- A cell is the median of per-round paired wall-time ratios, with a 95%
  bootstrap interval.

Compare ratios within a batch, not across batches or with the audit's CPU 6/8
numbers.

Arms:

- **`l5`**: the audit's prebuilt lane-5 binaries (`.l5`).
- **`my`**: this branch's ReleaseFast compiler (`.tmp/install`), default build
  (LLVM O3 + LTO).
- **`l5-nogc` / `l5-noroots`**: new lane-5 counterfactuals built for this lane
  with `counterfactual.py` against `install-l5`. The collector is off, with and
  without root publication, and every control rebuild is byte-identical. The
  audit's own `cf-noroots`/`cf-nogc` are pre-lane-5 and answer a different
  question.
- **`rl-nogc`**: this branch with the collector off.

`rl-nogc / l5-nogc` is the root-publication change at equal memory behaviour.
Set it beside `l5-noroots / l5-nogc`, the target this item moves toward.

**Suite, batch 1** — `results/wave2/root-liveness-suite.json`, 7 rounds, all
thirteen programs:

| program | Zig ms | l5 ×Zig | this ×Zig | **this / l5** | rl-nogc / l5-nogc | target: l5-noroots / l5-nogc |
|---|---:|---:|---:|---:|---:|---:|
| binary_trees | 514.5 | 2.23 | 2.13 | 0.971 [0.912, 0.998] | 1.001 | 0.956 |
| spectral_norm | 338.1 | 4.95 | 4.99 | 1.009 [0.982, 1.041] | 0.996 | 1.011 |
| mandelbrot | 268.0 | 1.84 | 1.85 | 1.004 [0.991, 1.006] | 1.016 | 0.998 |
| raytrace | 172.1 | 5.41 | 5.11 | **0.960** [0.957, 0.971] | 0.952 | 1.002 |
| knucleotide | 246.5 | 5.17 | 5.00 | 0.956 [0.943, 0.985] | 0.930 | 0.893 |
| text_ops | 53.0 | 6.42 | 5.85 | 0.962 [0.872, 1.124] | 0.831 | 0.945 |
| sort_builtin | 436.2 | 1.46 | 1.48 | 1.021 [0.973, 1.037] | 0.964 | 0.998 |
| sort_quick | 358.0 | 1.28 | 1.24 | 0.939 [0.923, 1.008] | 0.979 | 1.007 |
| sort_records | 183.9 | 5.86 | 4.93 | **0.911** [0.703, 0.921] | 0.972 | 0.898 |
| sieve | 109.8 | 1.60 | 1.59 | 0.992 [0.979, 1.028] | 1.020 | 1.030 |
| nbody | 291.3 | 7.04 | 6.92 | 0.935 [0.915, 0.998] | 1.017 | 1.005 |
| fannkuch_redux | 408.3 | 1.55 | 1.53 | 0.984 [0.964, 1.011] | 1.011 | 0.978 |
| matmul | 121.3 | 7.08 | 5.88 | **0.861** [0.820, 0.894] | 0.848 | 0.898 |
| **geomean** | | | | **0.961** | **0.962** | **0.970** |

**Batch 2** — `results/wave2/root-liveness-recheck.json`, 11 rounds. It adds the
pre-lane-5 compiler as `a3` (the audit's `cf-plain` binaries) and rechecks the
programs closest to 1.0:

| program | this / l5 | this / a3 (pre-lane-5) | l5 / a3 |
|---|---:|---:|---:|
| raytrace | **0.937** [0.933, 0.950] | **0.976** [0.964, 1.019] | 1.046 [1.027, 1.085] |
| sort_builtin | 1.027 [1.015, 1.078] | 1.038 [0.976, 1.063] | 1.007 |
| spectral_norm | 1.033 [0.871, 1.061] | 0.985 | 0.987 |
| mandelbrot | 0.986 [0.849, 1.089] | 0.965 | 0.975 |
| sieve | 0.988 [0.965, 1.045] | 0.242 | 0.232 |
| fannkuch_redux | 0.984 [0.970, 0.999] | 0.070 | 0.072 |

`sort_builtin` looked 2.7% slower in batch 2, so it got a third, 21-round batch
(`results/wave2/root-liveness-sort-builtin.json`). There it measures **0.991
[0.973, 1.013]** against lane 5 and 1.001 against a3. Its time is
`values.sort()` in the C runtime, and its only generated change is the
append-grow path's push going from 6 records to 1. The batch-2 cell is noise.

**Reading it:**

- **Against the acceptance counterfactual.** After lane 5 the collector-off
  no-roots arm has only −3.0% of geomean headroom. The audit's −36% was
  measured before lane 5 removed the list-write safepoints. This branch
  measures −3.9% with the collector on and −3.8% with it off, so it reaches that
  target on the geomean.
- **Programs that beat their no-roots cell** (`matmul`, `text_ops`,
  `raytrace`, `sort_quick`) also gain from `QBE-ELEMREF-3/4` copies that the
  counterfactual does not remove.
- **Programs still short of their no-roots cell** (`knucleotide`,
  `binary_trees`, `sort_records` with the collector off) still publish their
  live values. The remainder there is the protocol itself: one record per live
  value per safepoint.
- **`raytrace`** is back below its pre-lane-5 time: 0.976× a3 and 0.937× lane
  5.
- **Nothing is slower beyond noise.** Every cell above 1.0 has an interval
  containing 1.0 or was re-measured.

**S-expression parser** — `results/wave2/root-liveness-parser.json`, 11 rounds,
paired against lane 5:

| | census | render |
|---|---:|---:|
| lane 5 ×Zig | 1.71 | 2.32 |
| this ×Zig | 1.67 | 1.93 |
| **this / lane 5** | 0.973 [0.922, 1.026] | **0.861** [0.817, 0.925] |

The audit put the root chain at 19% of render. Liveness recovers most of it.

**Schematic SVG renderer** — `results/wave2/root-liveness-schematic.json`, 31
rounds × 3 inputs, every SVG hash checked. The arms are the lane-5 binaries
from the audit and this branch's `build_arms.py` builds:

| policy | fixture | changed-net | changed-value |
|---|---:|---:|---:|
| GC, ×Zig (lane 5 → this) | 1.72 → 1.68 | 1.80 → 1.75 | 1.78 → 1.73 |
| GC, this / lane 5 | 0.982 [0.961, 1.000] | 0.972 [0.945, 1.000] | 0.960 [0.938, 0.998] |
| arena, this / lane 5 | 0.955 [0.926, 1.002] | 0.960 [0.922, 0.998] | 0.943 [0.927, 0.974] |

## Tests

**Zig IL-shape tests** (`src/qbe_test.zig`). `rootsPerPush` counts the records
of every push in a unit, so each test asserts the exact per-safepoint count:

- `QBE-ROOTLIVE-1`, a value live across a call: `[1, 1]` for three
  `make(...)`s.
- Hidden receiver temporaries in a list-writing loop with an allocating call:
  `[1]`, the receiver only.
- An operand held only on the stack: `[1]`.
- A closing arena scope keeping a dead outer local published: `[1]`.
- A value read after a propagating `?` call: `[1]`.
- `QBE-INVOKE-SAFEPOINT-1`: the indirect call is preceded by a one-record push
  and followed by the restore.
- `QBE-ELEMREF-3`: a runtime-indexed second read emits no `blit`.
- `QBE-ELEMREF-4`: a plain, allocation-free callee keeps the borrow, and one
  with a traced parameter keeps the copy.

Three existing tests changed their programs, not their assertions:

- *roots are linked and restored with inline stores* and *a scalar root is
  traced through a value copy* now keep `values` live across a second call. With
  liveness, the old program had no live root at its only safepoint.
- *an iteration local keeps its copy when a call sits before its last read* now
  calls a callee that allocates. The old `doubled(value)` is exactly the shape
  `QBE-ELEMREF-4` now borrows soundly.

**Guest tests** (`tests/lang/root_liveness.my`, 10 tests, run under
`--gc-stress` by `test-lang`) cover:

- a local read after many collections;
- list writes around allocations in a loop;
- operands held only on the stack;
- a value read after `?`;
- an arena scope over a live outer local;
- a match payload across an allocation;
- a fused `src[a:b].decode()` over a dynamically built `bytes`;
- a list across an allocating callback;
- a borrowed element handed to a plain call while the list is written after it;
- a borrowed element indexing another list at run time.

## Gate

Full gate on `15d72730` (the compiler and tests as committed; this report and
the result JSONs are the only later changes), one step at a time through the
gate slot. Logs are in the worktree's `.tmp/gate/<step>.log`.
`gate_diff.py` compares each against lane 5's
`.tmp/perf-plan-20260922/gate/l5-<step>.log`.

| step | exit | gate-diff |
|---|---:|---|
| `zig build` (Guardian, 88 checks) | 0 | all passed |
| `zig build test --summary all` | 1 | base 46, lane 46: **0 new**, 0 cleared |
| `zig build test-qbe --summary all` | 1 | base 2, lane 2: **0 new** |
| `zig build test-qbe-build --summary all` | 0 | 0 / 0 |
| `zig build test-schematic --summary all` | 0 | 0 / 0 |
| `zig build test-byte-io --summary all` | 0 | 0 / 0 |
| `zig build fmt-check` | 0 | 0 / 0 |

`mylang test tests/lang --gc-stress` ran inside `zig build test` twice:

- **First gate run:** 265 of 265 passed across 70 programs.
- **Final run:** 275 across 71 programs, all passed (12 run, 263 reused from
  receipts). This run includes `root_liveness.my`'s 10 tests.

An earlier `zig build test`, run before the commit, found 3 new failures: the
three tests above. Their programs had stopped exercising what they asserted, and
they were updated before `15d72730`.

## What is left

- **`raytrace`'s `hit = spheres[hit_index]` still copies once per `shade`
  call.** Its live range contains an inlined `sqrt` (`unary_float`, lowered to
  the pure `myl_qbe_float_unary`), which is not on the inert list. Admitting
  `unary_float` is the same argument as `QBE-ELEMREF-3`, but it was not made
  here.
- **`QBE-ELEMREF-4` is deliberately narrow.** A callee that takes any traced
  parameter declines, even one whose type cannot alias the receiver (a
  `list[str]` beside a `list[Vec]` borrow). A type-directed alias rule
  (parameter types that cannot transitively reach the receiver's list type)
  would widen it. It needs its own proof over generics and `Cell`.
- **Remaining root cost is the protocol.** `knucleotide`, `binary_trees` and
  `sort_records` still publish a few records per safepoint in hot loops, 1–6
  where they used to publish 12–27. What remains between this branch and "no
  records at all" is the shadow-stack protocol itself (§6.7 stack scanning, or
  §6.8's frame map).
- **Liveness is on locals only.** Operand-stack values are published whenever
  they trace. They are live by construction, since every stack value is consumed
  later.

## Files

- `src/qbe_liveness.zig` (new): the analysis.
- `src/qbe.zig`: publishing live roots, the indirect-call safepoint, and the
  arena zero-fill guard.
- `src/qbe_borrow.zig`: `cast_integer` and `blindCall` in `inert`.
- `src/qbe_test.zig`, `tests/lang/root_liveness.my`, `SPEC.md` (four bullets).
- `experiments/perf-parity-plan-20260922/results/wave2/*.json`.
- This file.
