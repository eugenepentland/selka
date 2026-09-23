# Aggregates read and written where they live — 2026-09-22

Lane 5 of the schematic performance plan: item 2 of
[the parity audit](schematic-parity-gap-2026-09-22.md) §5 and the remainder of
[roadmap](../performance-roadmap.md) item 6. Branch
`perf/schematic-5-aggregate-reads`, over `base/schematic-20260922`, with
`perf/schematic-integration` at `4d81f680` and `base/parity-20260922` at
`bbabfc85` merged in.

**Status: complete, gated, ready to land.** Six code-generation rules make an
aggregate read or written where it already lives instead of through a copy or a
runtime call. The compiler code is `24336bf2`'s: the later merge brought only
the parity plan's documents and experiments, and the one change since is an
IL-shape assertion reconciled with `QBE-RETFWD-1` ([Gate](#gate)). The lane
did not time itself; [the parity plan audit](performance-parity-plan-2026-09-22.md)
did, with a ReleaseFast build of `24336bf2`, and [Timing](#timing) cites it.
On thirteen idiomatic programs the geometric mean goes from **5.79× to 2.97×
Zig** (−49%), the schematic renderer from 1.98× to 1.73×, and one program,
`raytrace`, is 2–4.5% slower for a reason [Limits](#limits-and-what-is-left)
names.

## The finding

The audit's §4 measured the schematic guest at 988 µs against Zig's 287 µs with
every runtime check stripped, and named the cause: an aggregate value travels
through memory two or three times per read. `sexpr::at` loads a 48-byte `Node`
out of list storage into per-pc frame scratch, the frame record is unlinked, and
the scratch is reloaded and stored again into the caller's return slot — the
single hottest instruction in the program at 5.3% of samples, and an
overlapping-move-then-reload that defeats store forwarding. `layout::partPin`
does the same with a 112-byte `Pin`. `circuit::normalize` copies a whole `Pin`
out of the list, updates one field of the copy and writes the whole record back
through `myl_native_list_set`, eight times, each behind a push of every live
traced root.

## The six mechanisms

Each is a `// spec:`-tagged rule with its own SPEC bullet; each names the exact
shapes it declines.

### `QBE-LISTSET-1` — write a list element where it lives

`xs[i] = v` and `replace(xs, i, v)` on a managed list called
`myl_native_list_set`, whose whole body is an unsigned bounds test and one
`copy_element`. Both are emitted inline now, against the same length, the same
comparison and the same detail-carrying trap. The list's generation is untouched
because the helper never bumped it either.

The copy was never the cost; the call was. `loweredAllocates` reads the text a
lowering produced, so an element write naming an unknown callee is a safepoint,
and the frame pushed one root record per live traced local and operand across
it — **54 of them per write** in `circuit::normalize`. A write that names only
`myl_qbe_fail_*` helpers is not a safepoint, and the whole root push goes with
it.

A value that names storage inside the same receiver copies one stride-sized,
stride-aligned region onto an identical or disjoint one: a record cannot contain
itself, so a same-typed region inside the element can only be the element. That
is exactly the aliasing the runtime `memcpy` already had.

### `QBE-RETFWD-1` — return an element from the receiver's own storage

A result leaves through one copy the caller owns: `%out` for a result over
4 KiB, the frame's `%return_storage` for a heap-backed frame, QBE's return pad
otherwise. Each copies out of the address the `ret` names, so naming the
element's checked address removes the snapshot into scratch and the reload out
of it, leaving exactly the one copy the language promised.

Only the epilogue runs in between, so the address is claimed only where the
epilogue can neither release nor free what it names: a frame that drops a local
or closes an arena scope keeps the snapshot.

### `QBE-CALLREF-1` — a record result the caller only reads stays in the call's buffer

A local whose only write is the store of a record-returning call's result —
`x = f(...)`, and `x = f(...).field` through an uninterrupted chain of field
reads — holds the address of that result instead of a copy.

The soundness argument is about *storage that is the frame's own*. QBE allocates
one return pad per aggregate-returning call site, emitted into the caller's
entry block (`amd64/sysv.c`, the `rap` list), and the LLVM adapter reserves one
`alloca` per call instruction in its own entry block (`llvm_emit.py`,
`call_result_buffers`). Either way the buffer lives as long as the frame and is
rewritten only when that same call site runs again — which re-runs the store
first, because the store is the call's immediate successor. Nothing else in the
function can reach it, so **no live-range proof is needed at all**: a call, an
allocation or a collection between the store and a read cannot disturb it.

### `QBE-ELEMREF-2` — `x = xs[i]` names its element, with a real live range

`QBE-ELEMENT-ADDRESS-1` gave `for x in xs` the same treatment over "the
branch-free run that follows the store". That window stopped at the first
branch and never looked at a read past it, so a loop that returns the element
from inside an `if` — `layout::partPin`'s whole body — was both unclaimed and,
where it was claimed, proved over less than its real live range.

The rule now answers liveness over the control-flow graph. **The live range of a
borrow is every instruction that is**

1. **reachable from its store** without any write of the same local running
   again (each write ends one borrow and starts another), **and**
2. **either able to reach a read of the local, or still running with the operand
   that read pushed on the stack.**

The second clause is what makes `return x` and `f(x, g())` visible. A read
pushes the address at operand slot `k`; an instruction that produces a result
writes it one below its own resulting height, so one that leaves the stack
exactly at `k + 1` has overwritten the slot, and one that leaves it lower
removed the slot outright. An instruction that only pops — a branch, a store, a
`pop`, a return — writes nothing and ends the run only by taking the stack below
`k + 1`. `producesResult` says which is which and defaults to `false`, so an
opcode added later only widens the run.

Every instruction in that range must be **inert**: unable to call, allocate,
release or mutate. Admitted are local and constant reads, field reads, scalar
arithmetic and comparison, control flow, a store into a drop-free local, a
length read, an element read of a list, byte string or fixed array, a plain
record or variant construction or update, and a `replace` on a fixed array. Not
admitted: any call, an append or element write, a managed record's update, a
collection literal, a string concatenation or content comparison (`+` and `==`
over a managed type call the runtime), a `switch_variant`, a `try_result`, and
every opcode not on the list. A `return x` inside the range additionally needs
an epilogue that releases nothing.

**Several definitions.** A slot holds either an address or a value for the whole
function, never one and then the other, so a local written more than once is
claimed only when *every* write stores an address of the same type and
stability. The front end reuses one temporary for both element reads of
`xs[i].f = <expr reading xs[i]>`, which is exactly that shape; each write then
carries its own proof over a range the other writes end.

**Traced elements and the collector.** The slot of an `element` borrow is never
read by the root protocol. Nothing can collect inside an inert range, everything
the element names stays reachable through the receiver, and outside the range
the local is dead — so a root push can never follow an address into storage the
receiver has since reallocated or the sweep has freed. That is what lets a
128-byte `Pin`, which holds two `bytes` fields, be borrowed at all. A local's
slot now records which kind of address it holds (`qbe_borrow.Borrow`:
`none` / `value` / `element`); a `value` borrow — a caller's argument, a match
payload, a call's result buffer — is rooted exactly as before, and a traced one
starts out naming an all-zero value of its own type (`%lz{i}`) so a root push
before the store still finds a traceable record.

**Arena scopes.** Closing a scope scans every local declared before it through
its slot, which a borrowed element's one-word slot cannot answer, so a frame
that opens an arena scope keeps the copy. A `value` borrow is unaffected: its
slot holds a genuine record.

### `QBE-CTORREAD-1` — a constructor field read names its local

`consumesOperand` treated a record or variant constructor as leaving its
operands on the stack, so a whole-record field argument was snapshotted into
per-pc scratch first. A constructor reads each field operand once, writes it
into the destination and pops it, and the destination is either this pc's own
scratch or a local `constructorDestination` already proved no reachable
instruction reads — so a named operand can never point at the region being
written.

### What the merges added

`perf/schematic-integration`'s `QBE-UNCHECKED-1` wraps each bounds test in
`if (self.checks)`. This lane's new `inlineIndexWrite` got the same treatment, so
under `--unchecked` an element write is the store alone.

`base/parity-20260922` added only the parity plan audit, its
`experiments/perf-parity-plan-20260922` evidence and one `docs/performance.md`
paragraph; it merged without conflicts and changes no compiler code.

## Timing

These measurements are the parity plan audit's (§3.3, §4.1, §6.1 and §7),
not new runs; the raw rounds are in
[`experiments/perf-parity-plan-20260922/results/`](../../experiments/perf-parity-plan-20260922/README.md).
The **lane 5** compiler there is the audit's `install-lane5`
(`.tmp/perf-plan-20260922/install-lane5`), a ReleaseFast build of `24336bf2`,
which has the same compiler code as this branch's head. **Today** is
`.tmp/perf-audit-20260922/install-a3`: `acbee603` plus schematic lanes 2–4.
That is the code generation of `perf/schematic-integration` at `4d81f680`,
which adds only lane 1's runner policy.

Every binary is a default `mylang build` (LLVM O3 + LTO). The `l5` arm is the
lane-5 release manifest rebuilt unmodified; `counterfactual.py` checked that
it is byte-identical to a plain build. Every arm printed the agreed output
byte for byte. A cell is the median of the per-round paired wall-time ratios to
Zig ReleaseFast, with its 95% bootstrap interval. The machine was loaded: each
batch ran pinned to one core (CPU 6, or CPU 8 for the three slow programs)
while other work ran, at load averages of 1.5–4.9 (recorded in the suite,
ladder, micro and parser JSONs). Compare ratios within one batch, not across
batches.

**The program suite.** `results/suite-fast.json` (7 rounds, CPU 6) and
`results/suite-slow.json` (5 rounds, CPU 8, `nbody`, `fannkuch_redux`,
`matmul`), arms `my` and `l5` from the same batch:

| program | Zig ms | today | lane 5 | change |
|---|---:|---:|---:|---:|
| binary_trees | 219.0 | 2.17 [2.14, 2.29] | 2.16 [2.10, 2.18] | −1% |
| spectral_norm | 150.3 | 3.65 [3.62, 3.71] | 3.66 [3.61, 3.69] | +0% |
| mandelbrot | 123.3 | 1.32 [1.31, 1.34] | 1.32 [1.31, 1.32] | −1% |
| raytrace | 89.3 | 4.25 [4.01, 4.72] | 4.35 [4.07, 4.68] | +2% |
| knucleotide | 104.2 | 4.90 [4.54, 5.05] | 4.96 [4.79, 5.49] | +1% |
| text_ops | 26.0 | 6.86 [6.80, 6.90] | 6.86 [6.78, 7.07] | +0% |
| sort_builtin | 205.4 | 1.64 [1.60, 1.69] | 1.68 [1.34, 1.71] | +3% |
| sort_quick | 166.0 | 1.89 [1.86, 1.93] | 1.32 [1.29, 1.37] | **−30%** |
| sort_records | 111.7 | 5.32 [5.31, 5.48] | 5.30 [5.28, 5.42] | −0% |
| sieve | 54.1 | 7.14 [7.12, 7.26] | 1.78 [1.71, 1.87] | **−75%** |
| nbody | 154.3 | 71.72 [64.85, 76.94] | 4.93 [4.22, 5.80] | **−93%** |
| fannkuch_redux | 219.1 | 15.81 [13.98, 18.54] | 1.27 [1.23, 1.35] | **−92%** |
| matmul | 41.1 | 41.33 [40.41, 43.41] | 7.09 [6.93, 7.48] | **−83%** |
| **geomean** | | **5.79** | **2.97** | **−49%** |

The five programs that move are the ones whose hot loop writes a list element
(§4.1 of the audit): 35 root records per write in `nbody`'s `advance`, 22 in
`fannkuch_redux`, 19 in `matmul`, 8 in the quicksort and 7 in the sieve, all
gone with `QBE-LISTSET-1`. The other eight stay within ±3%. The same batches
timed the tuned spellings under both compilers:

| variant | today | lane 5 |
|---|---:|---:|
| `matmul_flat` (one flat `list[float]`) | 24.04 [23.15, 25.93] | 4.11 [3.99, 4.32] |
| `nbody_class` (`class Body`, field writes are plain stores) | 4.13 [4.12, 5.42] | 4.21 [3.95, 4.29] |
| `binary_trees_arena` | 1.35 [1.34, 1.38] | 1.38 [1.35, 1.42] |
| `knucleotide_tuned` | 2.84 [2.75, 2.87] | 2.84 [2.79, 2.89] |

With lane 5 the idiomatic `nbody` (4.93×) comes close to the class
workaround (4.21×), and the idiomatic `matmul` (7.09×) to within 1.8× of the
flat spelling.

**A second batch.** `results/ladder-fast.json` (7 rounds, CPU 6) timed the
same lane-5 build again as the ladder's `lad-l5` rung, through the ladder's
adapter copy. Its unmodified builds are byte-identical to the stock adapter's.
The slow three come from `suite-slow.json`'s own `lad-l5` arm. These are the
figures the audit's §6.1 and §7 quote: geomean **5.77× → 2.98×**; `nbody`
5.06 [4.35, 6.72]; `matmul` 7.10 [6.98, 9.62]; `fannkuch_redux` 1.30 [1.15,
1.34]; `sieve` 7.19 → 1.79 [1.76, 1.80]; `sort_quick` 1.87 → 1.31 [1.23,
1.33]. One cell in that batch moves the wrong way beyond noise: **`raytrace`
4.68 [4.64, 4.73] → 4.89 [4.84, 4.90], +4.5%**, with disjoint intervals.
`text_ops` +4% overlaps. The raytrace cause is a loop variable that the old
compiler borrowed and this lane copies; see [Limits](#limits-and-what-is-left).

**Micro-kernels.** `results/micro.json` (7 rounds, CPU 6), `my` against
`lad-l5`. The geomean is 1.36× → 1.36×, and every kernel is within ±4%:
`list_append_sum` 1.43 → 1.37, `list_records` 1.42 [1.39, 1.46] → 1.43
[1.42, 1.51], `alloc_churn` 2.24 → 2.29 (overlapping). None of the kernels
writes a list element in its loop, and `QBE-AGGREF-1` already read
`list_records`' elements in place.

**S-expression parser.** `results/parser.json` (11 rounds, CPU 6; medians
only, no intervals recorded) against the in-repo Zig reference:

| arm | census | render |
|---|---:|---:|
| Zig ReleaseFast | 16.4 ms | 20.6 ms |
| today | 1.73× | 2.21× |
| lane 5 | 1.73× | 2.22× |
| today, `--unchecked` | 1.55× | 2.00× |
| lane 5, `--unchecked` | 1.54× | 2.00× |

The parser does not move. It never writes a list element in its hot loop, and
its cost is the root chain at real safepoints plus memory traffic (the
audit's §3.3).

**Schematic SVG renderer.** `results/schematic.json` (31 interleaved rounds ×
3 inputs, CPU 6, every SVG hash checked), ratio to the Zig port:

| arm | `fixture` ms | `fixture` | `changed-net` | `changed-value` |
|---|---:|---:|---:|---:|
| Zig port | 1.487 | 1.00 | 1.00 | 1.00 |
| Rust port | 1.669 | 1.12 [1.09, 1.19] | 1.12 [1.07, 1.14] | 1.14 [1.10, 1.17] |
| today, GC | 2.937 | 1.98 [1.91, 2.08] | 1.98 [1.91, 2.04] | 1.96 [1.89, 2.03] |
| today, `--unchecked` | 2.523 | 1.70 [1.64, 1.81] | 1.72 [1.65, 1.77] | 1.68 [1.61, 1.72] |
| today, arena | 2.707 | 1.82 [1.77, 1.93] | 1.84 [1.76, 1.89] | 1.81 [1.73, 1.85] |
| **lane 5, GC** | 2.573 | **1.73 [1.68, 1.84]** | **1.74 [1.68, 1.78]** | **1.75 [1.67, 1.80]** |
| lane 5, `--unchecked` | 2.421 | 1.63 [1.59, 1.73] | 1.57 [1.51, 1.62] | 1.58 [1.52, 1.62] |
| lane 5, arena | 2.375 | 1.60 [1.54, 1.69] | 1.64 [1.55, 1.67] | 1.59 [1.50, 1.63] |

Lane 5 takes 11–12% off the render on every input, and `--unchecked` or an
arena takes a further 6–11%.

**Against this item's targets.** The schematic audit's §5 set model
construction ≤ 3× Zig, parsing ≤ 2.5×, placement ≤ 1.6× and `list_records`
≤ 1.3×. No per-phase run was taken on the lane-5 build, so the first three are
**not claimed**. `list_records` is **not met** at 1.43×. Also not measured:
the `myl_f_` survivor count after LTO, and anything specific to the LLVM arm
beyond these whole-program times.

## Evidence: the emitted manifest

`mylang emit-project-qbe src/schematic/guest/main.my --drop-debug --no-cache
--drop-step-checks --drop-frame-checks`, the same policy `build_arms.py` gives
the `gc-lto` arm, over this branch's guest (lane 4's rewritten
`io::load`/`io::flush` included). The **before** column is the `install-a3`
compiler and the **lane 5** column is `install-lane5`, the two compilers
[Timing](#timing) compares. `blit` counts every whole-value copy the emitter
emits, and "scratch" is the `%agg`/`%aux` per-pc aggregate buffers the lowered
bodies still declare. The scripts are this worktree's untracked
`.tmp/census.py` and `.tmp/blitkinds.py`, and the manifests are in
`.tmp/census-post/`.

| | before | lane 5 | change |
|---|---:|---:|---:|
| whole-value copies (`blit`) | 379 | **284** | −25% |
| bytes copied by them | 22,340 | **15,904** | −29% |
| per-pc scratch slots | 187 | **154** | −18% |
| per-pc scratch bytes | 9,296 | **8,104** | −13% |
| IL lines, whole program | 111,163 | **98,735** | −11% |
| functions | 126 | 126 | — |

By copy class:

| class | before | lane 5 |
|---|---|---|
| value → local (a `store_local` copying an aggregate into a local) | 220 / 13,676 B | 139 / 6,764 B |
| value → value (constructor and update field writes, element writes) | 126 / 7,508 B | 143 / 8,996 B |
| local → scratch (a `load_local` snapshotting into per-pc scratch) | 33 / 1,156 B | 2 / 144 B |

The `value → value` class grows because `QBE-LISTSET-1` turns a
`myl_native_list_set` *call* into an inline `blit` of the same bytes: the copy
was always there, it is now visible in this count and no longer behind a call.

Per function, the largest movements:

| function | before (copies, IL lines) | lane 5 |
|---|---|---|
| `circuit::normalize` | 43, 7,657 | 33, 4,174 |
| `layout_graph::build` | 33, 9,546 | 26, 6,010 |
| `layout::collectRows` | 6, 17,943 | 6, 13,701 |
| `layout_routes::build` | 75, 9,735 | 57, 9,699 |
| `ports::collect` | 27, 4,615 | 18, 4,717 |
| `circuit::collectParts` | 16, 1,909 | 10, 1,943 |
| `sexpr::parse` | 27, 4,503 | 23, 3,873 |
| `circuit::collectPins` | 11, 2,439 | 5, 2,434 |
| `layout::branch` | 6, 1,108 | **0**, 1,131 |
| `layout::partPin` | 4, 786 | 2, 787 |
| `sexpr::at` | 3, 214 | 2, 211 |
| `sexpr::form` | 2, 332 | 1, 336 |
| `layout::innerPin` | 2, 191 | **0**, 203 |
| `layout::bridge` | 2, 255 | **0**, 265 |
| `layout::groundBranch` | 4, 427 | **0**, 444 |
| `validate::pinoutCheck` | 3, 1,353 | **0**, 1,386 |

No function has more copies than before. The IL-line collapse in
`circuit::normalize` (−45%) and `layout_graph::build` (−37%) is the root-push
storm `QBE-LISTSET-1` removed: one root record is six IL lines and `normalize`
pushed 54 of them eight times.

Three locals the old compiler held by address are copies again:
`layout::nearest`'s `row = rows[i]` and `layout::endpoint`'s
`row = rows[chosen]` (48 bytes each), and one 16-byte element local in
`layout_graph::build`. The old window (`claimElementLocal`, which applied
`QBE-ELEMENT-ADDRESS-1`'s test to every element read followed by a store)
stopped at the first branch and never looked at a read past it. So it claimed
them without a proof over their whole live range.
`QBE-ELEMREF-2` proves the whole range and declines. In `nearest` and
`build` the range contains a second runtime-indexed list read, such as
`pins[row.index]`. That read's negative-index normalization converts the
receiver length with a `cast_integer`, which is not on the inert list. In
`endpoint`, `row` is also read after calls to `depth`, `bridge` and `nearest`.
See [Limits](#limits-and-what-is-left).

The census before the `perf/schematic-integration` merge (base compiler,
pre-lane-4 guest) gave 381 → 285 copies and 111,743 → 99,258 IL lines. Lane 4
moved the totals, not the per-mechanism picture.

The two named hot paths now read the way the audit said Zig reads them:

* `sexpr::at`'s `return nodes[index]` is `add` / `loadl` / `mul` / `add` and
  then `ret` on that address. Its two remaining copies are the
  `Node(kind=atom, …)` constructor on the out-of-range branch.
* `layout::partPin` no longer declares a 128-byte `%l20`: `pin = pins[i]` is a
  one-word slot holding the checked element address, `return pins[index]` is
  returned in place, and the two remaining copies are the `c.Pin(...)` fallback
  constructor's two 32-byte `Span` fields.
* `sexpr::form`'s `item = at(nodes, index)` is a one-word slot holding the
  call's own result buffer (`%l3 =l alloc8 8`, `%lz3 =l alloc8 48` for the root
  placeholder); `item.kind` is one `add`/`loaduw` through it.

## What the tests pin

New Zig IL-shape tests in `src/qbe_test.zig`, one primary `// spec:` per tag
plus `// spec-case:` for each declined shape:

* `QBE-LISTSET-1`: no `myl_native_list_set`, an unsigned test, the same
  `myl_qbe_fail_normalized_index_bounds` helper, no `%root0`; and the same over
  a traced record element.
* `QBE-RETFWD-1`: `def at(rows, i) -> Row: return rows[i]` emits no `blit` and
  no `%agg`; a frame that opens an arena scope keeps the copy.
* `QBE-CALLREF-1`: the caller of a record-returning helper emits no `blit` and
  its local is `alloc8 8`; a local the body reassigns keeps its copy.
* `QBE-ELEMREF-2`: a `while` loop whose element local is read across two
  branches and returned emits no `blit`; a call inside the range, an arena
  scope, and a write that is not an address each keep the copy; a temporary two
  element reads share is borrowed for both; a traced element borrow pushes no
  root.
* `QBE-CTORREAD-1`: both record field operands name their own slots.

`src/native_execute.zig` gains two rows to the structured-trap table: an
out-of-range positive index on a scalar element write and on a record element
write, both `R_LIST_BOUNDS` with the caller's own index and the receiver length.

`tests/lang/element_access.my` carries 14 guest tests, run under `--gc-stress`:
scalar and record element writes (including a negative index), a copy taken
before a write, 200 writes of a managed `str` field, an element write inside
`with arena()`, field and nested-field reads through an element, a returned
element's independence from a later write, an element local read across the
branch that returns it, the loop variable over every element, a call result
local and a call-result field read, a recursive record-returning helper, and a
borrow whose receiver is written 60 times in the loop that follows.

One existing test changed after `24336bf2`. The primary
`QBE-AGGREGATE-READ-1` test asserted a `blit` inside
`def snapshot(items, index) -> Item: return items[index]`. That is exactly
the shape `QBE-RETFWD-1` returns in place, and its own test asserts no `blit`,
so the two assertions contradicted each other. The full gate caught it; the
filtered `-Dtest-filter=QBE-` run had not selected it. The snapshot still
exists: `snapshot` returns an aggregate type, and the return copies the
checked element into storage the caller owns. The assertion now pins that form
instead: an aggregate return (`export function :`), no `%agg` scratch, the
bounds helper, and no `myl_native_list_get`. The test's `spec-case`
companion still runs the program with and without `--gc-stress` and checks the
returned record across an element write, 40 appends and collection. The
`QBE-AGGREGATE-READ-1` bullet in `SPEC.md` gains the matching clause: a record
returned straight from the read takes its snapshot in the return copy
(`QBE-RETFWD-1`). Neither change alters emitted code.

## Gate

The full gate ran on the merged tree, starting from a fresh, empty Zig cache
(`$HOME/.cache/mylang/zig-local-cache-lane5-gate`). Each step's output is in
this worktree's untracked `.tmp/gate/<step>.log`, and the first `test` run's
output is in `.tmp/gate/pre-fix/`. The base is red: another
session's half-finished `mutates(...)` → `mut` migration leaves 47 failing
tests in `zig build test` and 2 in `test-qbe` on `base/parity-20260922`. The
criterion is therefore **no new failure**. The coordinator's `gate_diff.py`
compares failing test names with the base logs in
`.tmp/perf-plan-20260922/gate/base-<step>.log`.

| step | exit | gate-diff against the base |
|---|---:|---|
| `zig build --summary none` (Guardian, 88 checks) | 0 | all passed |
| `zig build test --summary all` | 1 | base 47, lane 46: **0 new**, 1 cleared |
| `zig build test-qbe --summary all` | 1 | base 2, lane 2: **0 new**, 0 cleared |
| `zig build test-qbe-build --summary all` | 0 | 0 / 0 |
| `zig build fmt-check` | 0 | 0 / 0 |
| `zig build test-schematic --summary all` | 0 | 0 / 0 |
| `zig build test-byte-io --summary all` | 0 | 0 / 0 |

`zig build test` ran twice. The first run, on `8fe0735d` (the merge alone),
found **one new failure**: the `QBE-AGGREGATE-READ-1` IL-shape assertion
described under [What the tests pin](#what-the-tests-pin). After that
assertion was reconciled with `QBE-RETFWD-1`, the table's run finished with
45 failed tests and 1 leak, the same names as the base minus the cleared
one. The final run shows 1,593 passed rather than the first run's 1,631 because
Zig reused three unchanged unit runs that had passed the first time (39
tests, the schematic unit's 21 among them), and `mylang test` reused 263 of
the 265 guest results.
All 12 root shards and all 6 CLI shards ran again. The `test-native-boundary`
driver fails identically in the base and here
(`tool::bracket text-unicode.json`). The two `test-qbe` failures,
`native_test_wire…local mutation reuses a receipt` and
`golden_parity…checked-in golden corpora`, are the base's own.

`test-qbe`, `test-qbe-build`, `test-schematic` and `test-byte-io` ran once,
before the assertion change. None of them compiles `src/root_test.zig`, the
only root that contains `src/qbe_test.zig`. Guardian and `fmt-check` ran again
on the final tree.

`mylang test tests/lang --gc-stress` (265 guest tests across 70 programs,
`element_access.my`'s 14 included) passed inside `zig build test`, and the
focused `zig build test-units -Dtest-filter="aggregate projections"` passed 14
of 14 after the fix.

The one cleared failure is a real latent defect that this lane fixed:
`interfaces_test.named constraints index export render and accept function
bounds`. `interfaces.typeAuthority` and `resourceTypeEffect` look up a
signature's type names and recover when the index cannot resolve one, which
is normal for a type parameter. But `resolve` reports its refusal by recording
a problem on the *project*, and the swallowed diagnostic stayed there, so
`project_syntax.build` afterwards read the whole project as incomplete. Both
call sites now go through `optionalTypeIdentity`, which restores whatever
problem the project already had. (The paused report also listed
`qbe_test.QBE-PURE-READ-1`. That fix is on `perf/schematic-integration` too,
so it is not a failure of this base.)

## Files changed by this lane

`SPEC.md`, `src/qbe.zig`, `src/qbe_arena.zig`, `src/qbe_borrow.zig` (new),
`src/qbe_managed.zig`, `src/qbe_test.zig`, `src/native_execute.zig`,
`src/interfaces.zig`, `tests/lang/element_access.my`, `docs/performance.md`,
`docs/performance-roadmap.md`, and this file. After `24336bf2`, only
`src/qbe_test.zig` (one assertion, above), `SPEC.md` (one clause) and the
documents changed.

`src/qbe_borrow.zig` is new and holds the whole borrow analysis;
`elementLocals`, `claimElementLocal` and `inertInstruction` moved out of
`src/qbe.zig` into it. The rest of `src/qbe.zig`'s diff is small and local: the
`Borrow` enum replacing `by_reference: []bool`, `tracedRoot`,
`placeholderBytes` and its three call sites, and two entries added to
`consumesOperand`.

## Limits and what is left

* **An element local handed to a call is copied, and this is what costs
  `raytrace`.** `QBE-ELEMREF-2` counts the call that consumes a read's operand
  as part of the live range, and a call is not inert. In `raytrace`'s `shade`,
  `for k, s in enumerate(spheres): t = intersect(origin, direction, s)` hands
  `s` to a call, so both sphere loops now copy a 56-byte `Sphere` per
  iteration. The old compiler borrowed it only because its window ended at the
  read. In `raytrace` this is the only place the lane emits more copies than
  before, and it is the likely cause of the +2% (suite batch) and +4.5%
  (ladder batch). `layout::endpoint`'s `row` in the schematic is the same
  shape.
  Recovering it soundly needs a proof that the callee cannot reach the
  receiver mutably during the call: no `mut` argument that can alias it, and no
  class reference through which it is reachable.
* **A second runtime-indexed list read inside a borrow's range declines the
  borrow.** The front end normalizes a negative index with `BUFFER_length`,
  `CAST_INT` and `ADD_I64_CHECKED`. The `cast_integer` opcode is not on the
  inert list. When its target is an integer it can only trap, like the checked
  arithmetic that is on the list; a cast to text allocates. So the SPEC's
  "another element read of a list" holds for a constant index but not for a
  runtime one. This is why `layout::nearest` and `layout_graph::build` copy
  again (see the census). Admitting `cast_integer` with an integer target is a
  one-line change to `qbe_borrow.inert`, plus a `spec-case` test. It changes
  emitted code, so it is left as a follow-up to be timed rather than landed
  untimed here.
* **A borrowed element that a frame with an arena scope reads keeps its copy.**
  Closing a scope scans locals declared before it through their slots. A
  narrower rule — skip only the locals the scan would reach — would recover it.
* **`xs[i].f = v` still copies the record twice.** After `QBE-LISTSET-1` and
  `QBE-ELEMREF-2` the shape is: read the element address into a borrowed
  temporary, `update_record` blits the whole record into scratch and writes one
  field, then the element write blits the whole record back. Folding the
  `update_record` into the in-place write needs a proof that the write targets
  the same element the update read — the same receiver local and the same index
  operand — which is a narrow idiom match the backend does not do today. It is
  the largest single remaining item in `circuit::normalize`.
* **An inlined callee's spliced parameter still copies.** `bytecode_inline.zig`
  turns a parameter into a caller local the argument is blitted into, and the
  store is not the address producer's immediate successor, so `claimOne`
  declines. `sexpr::form`'s inlined `text::matches` span is one of these.
* **`layout_routes::build`'s `Segment(...)` append still builds in scratch and
  copies into the list's storage.** Constructing at the append destination would
  need the capacity test to run before the constructor's operands, which changes
  evaluation and trap order.
* **Array-typed record fields** (`r.cells = replace(r.cells, i, v)` through
  `update_record`) are still whole-value, as
  [fixed-array-inplace](fixed-array-inplace-2026-09-21.md) left them.
* **Only the QBE emitter changed.** Both backends consume the same IL, so the
  LLVM arm inherits everything here. Every timing above is of the default LLVM
  O3 + LTO build; no QBE-backend (Debug or `--backend qbe`) timing was taken.
