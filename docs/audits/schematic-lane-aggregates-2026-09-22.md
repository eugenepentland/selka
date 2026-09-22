# Aggregates read and written where they live — 2026-09-22

Lane 5 of the schematic performance plan: item 2 of
[the parity audit](schematic-parity-gap-2026-09-22.md) §5 and the remainder of
[roadmap](../performance-roadmap.md) item 6. Branch
`perf/schematic-5-aggregate-reads`, over `base/schematic-20260922`, with
`perf/schematic-integration` at `4d81f680` merged in.

**This lane was paused by the user before its timing runs.** Everything below
the mechanisms and the static evidence is measured; the wall-clock and
per-phase tables are not. See [Paused](#paused) for the exact state.

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

### What the merge added

`perf/schematic-integration`'s `QBE-UNCHECKED-1` wraps each bounds test in
`if (self.checks)`. This lane's new `inlineIndexWrite` got the same treatment, so
under `--unchecked` an element write is the store alone.

## Evidence: the emitted manifest

`mylang emit-project-qbe src/schematic/guest/main.my --drop-debug --no-cache
--drop-step-checks --drop-frame-checks`, the same policy `build_arms.py` gives
the `gc-lto` arm. Both columns are the **pre-merge** guest (before lane 4
rewrote `io::load`/`io::flush`), so they are a like-for-like A/B of this lane's
compiler changes alone. `blit` counts every whole-value copy the emitter emits;
"scratch" is the `%agg`/`%aux` per-pc aggregate buffers the lowered bodies still
declare.

| | base | this lane | change |
|---|---:|---:|---:|
| whole-value copies (`blit`) | 381 | **285** | −25% |
| bytes copied by them | 22,852 | **16,160** | −29% |
| per-pc scratch slots | 190 | **157** | −17% |
| per-pc scratch bytes | 9,600 | **8,408** | −12% |
| IL lines, whole program | 111,743 | **99,258** | −11% |
| functions | 124 | 124 | — |

By copy class:

| class | base | this lane |
|---|---:|---:|
| value → local (a `store_local` copying an aggregate into a local) | 222 / 14,188 B | 140 / 7,020 B |
| value → value (constructor and update field writes, element writes) | 126 / 7,508 B | 143 / 8,996 B |
| local → scratch (a `load_local` snapshotting into per-pc scratch) | 33 / 1,156 B | 2 / 144 B |

The `value → value` class grows because `QBE-LISTSET-1` turns a
`myl_native_list_set` *call* into an inline `blit` of the same bytes: the copy
was always there, it is now visible in this count and no longer behind a call.

Per function, the largest movements:

| function | base (copies, IL lines) | this lane |
|---|---|---|
| `circuit::normalize` | 43, 7,441 | 33, 3,942 |
| `layout_graph::build` | 33, 9,339 | 26, 5,789 |
| `layout::collectRows` | 6, 17,772 | 6, 13,514 |
| `layout_routes::build` | 75, 9,598 | 57, 9,562 |
| `sexpr::parse` | 27, 4,444 | 23, 3,808 |
| `layout::partPin` | 4, 754 | 2, 751 |
| `sexpr::at` | 3, 207 | 2, 204 |
| `sexpr::form` | 2, 325 | 1, 329 |
| `layout::innerPin` | 2, 191 | **0**, 203 |
| `layout::bridge` | 2, 255 | **0**, 265 |
| `layout::groundBranch` | 4, 421 | **0**, 438 |
| `validate::pinoutCheck` | 3, 1,343 | **0**, 1,376 |
| `circuit::collectPins` | 11, 2,417 | 6, 2,453 |

The IL-line collapse in `circuit::normalize` (−47%) and `layout_graph::build`
(−38%) is the root-push storm `QBE-LISTSET-1` removed: one root record is six
IL lines and `normalize` pushed 54 of them eight times.

The two named hot paths now read the way the audit said Zig reads them:

* `sexpr::at`'s `return nodes[index]` is `add` / `loadl` / `mul` / `add` and
  then `ret` on that address. Its two remaining copies are the
  `Node(kind=atom, …)` constructor on the out-of-range branch.
* `layout::partPin` has no `%l20 =l alloc8 128` any more: `pin = pins[i]` is a
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

## Gate

Not run to completion — see [Paused](#paused). What was run on the merged tree:

| step | result |
|---|---|
| `zig build` (Guardian whole-tree, 88 checks) | **pass** at every commit, including the merge |
| `zig build test-compile` | **pass** |
| `mylang test tests/lang --gc-stress` | **265 passed, 0 failed** across 70 programs |
| `zig build test-units -Dtest-filter=QBE-` | **40 passed, 0 failed** |
| `zig build test-qbe --summary all` | exit 0 (run twice, on the pre-merge tree at the third mechanism) |
| `zig build test --summary all` | **not run** |
| `zig build test-qbe-build --summary all` | **not run** |
| `zig build fmt-check` | **not run** |
| `zig build test-schematic --summary all` | **not run** |

Two tests the base branch already failed are fixed on this branch, because a
lane cannot tell a real regression from a red base:

* `qbe_test.QBE-PURE-READ-1` — its program predates the `mut`-at-call-sites
  rule; it now writes `bump(mut counts, …)`.
* `interfaces_test.named constraints index export render and accept function
  bounds` — a real latent defect. `interfaces.typeAuthority` and
  `resourceTypeEffect` look a signature's type names up and recover when the
  index cannot resolve one, which is normal for a type parameter; but `resolve`
  reports its refusal by recording a problem on the *project*, and the swallowed
  diagnostic stayed there, so `project_syntax.build` afterwards read the whole
  project as incomplete. Both call sites now go through `optionalTypeIdentity`,
  which restores whatever problem the project already had.

## Files changed by this lane

`SPEC.md`, `src/qbe.zig`, `src/qbe_arena.zig`, `src/qbe_borrow.zig` (new),
`src/qbe_managed.zig`, `src/qbe_test.zig`, `src/native_execute.zig`,
`src/interfaces.zig`, `tests/lang/element_access.my`, and this file.

`src/qbe_borrow.zig` is new and holds the whole borrow analysis;
`elementLocals`, `claimElementLocal` and `inertInstruction` moved out of
`src/qbe.zig` into it. The rest of `src/qbe.zig`'s diff is small and local: the
`Borrow` enum replacing `by_reference: []bool`, `tracedRoot`,
`placeholderBytes` and its three call sites, and two entries added to
`consumesOperand`.

## Paused

Paused by the user on 2026-09-22, after the merge of
`perf/schematic-integration` at `4d81f680` and before any timing run.

**Done.** All six mechanisms are implemented, tested, documented in `SPEC.md`,
committed, and Guardian-green at every commit including the merge. The static
evidence above is measured. The merge conflicts (two in `src/qbe_managed.zig`,
one append conflict in `src/qbe_test.zig`) are resolved and build green.

**Half-done.**

* **No timing.** `bench_svg.py`, `phases_my.py` and the micro-kernel suite were
  never run, so there is no wall-clock, per-phase or kernel number in this
  report and no claim about the audit's targets (model ≤ 3× Zig, parse ≤ 2.5×,
  placement ≤ 1.6×, `list_records` ≤ 1.3×). The static census is the only
  evidence this lane has.
* **Arms not rebuilt after the merge.** `.tmp/audit/before/arms` was built with
  the *base* compiler and the *pre-merge* guest, so it is no longer the right
  "before": the coordinator's is
  `/home/epentland/ai/canopy/mylang/.tmp/perf-audit-20260922/arms-a3/gc-lto`,
  built by `…/install-a3/bin/mylang`. `.tmp/spec-lane.json` already carries the
  `unchecked` arm the coordinator asked for.
* **The manifest census is pre-merge.** Lane 4 rewrote `io::load`/`io::flush`
  in the guest, so the whole-program totals above will move; the per-mechanism
  conclusions will not.
* **`docs/performance.md` and roadmap item 6 are not updated.** Item 6's
  remaining named changes — the by-reference destination local and return-slot
  forwarding — are done; array-typed record fields through `update_record` are
  not.

**Currently failing.** Nothing known that the integration branch does not also
fail. The two base failures named above are fixed here. The full `zig build
test` was never run on the merged tree, so the integration branch's inherited
set of 46 pre-existing failures has not been re-measured against it.

**Exact next step.**

1. `rm -rf .tmp/install && ZIG_LOCAL_CACHE_DIR=$HOME/.cache/mylang/zig-local-cache-aggregates ~/capbuild zig build -j4 -Doptimize=ReleaseFast --prefix "$PWD/.tmp/install"` (already done once for `6dfbe274`; the binary is at `.tmp/install/bin/mylang`).
2. `source .tmp/env.sh; bash .tmp/build-arms.sh after "$PWD/.tmp/install/bin/mylang"` and the same with `--compiler /home/epentland/ai/canopy/mylang/.tmp/perf-audit-20260922/install-a3/bin/mylang` into `before`, both over this worktree's guest sources, with `.tmp/spec-lane.json` (`gc-lto`, `unchecked`, `o3`).
3. `python3 .tmp/make-arms-json.py .tmp/arms-bench.json zig-o3=@…/zig-o3 rust-o3=@…/rust-o3 before=…/before/arms/gc-lto after=…/after/arms/gc-lto after-unchecked=…/after/arms/unchecked` then `python3 $S/scripts/bench_svg.py --arms .tmp/arms-bench.json --out .tmp/audit/results.json --cpu 0 --rounds 31` on a quiet machine.
4. `AUDIT_WORK=$PWD/.tmp/audit/after python3 $S/scripts/phases_my.py build && … measure`, and the same for `before`.
5. `python3 experiments/perf-parity-audit-20260921/micro/run.py --cpu 0 --only list_records,records,list_append_sum`.
6. `nm -g` the two LTO binaries and count `myl_f_` survivors.
7. Re-run the census (`.tmp/census.py`, `.tmp/blitkinds.py`) on the post-merge
   manifests and replace the table above.
8. Fill in `docs/performance.md` and roadmap item 6's status.
9. Run the full gate on the merged tree and record each exit status.

## Limits and what is left

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
  LLVM arm inherits everything here, but no LLVM-specific measurement was taken.
