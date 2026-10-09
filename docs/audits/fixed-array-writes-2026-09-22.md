# Fixed arrays as ordinary mutable values — 2026-09-22

Wave 3, item 2 of the [performance parity plan](performance-parity-plan-2026-09-22.md)
(§5.3). Branch `lang/fixed-array-writes` from `base/parity-w2` (`684be597`).
This is a language-surface change the user approved.

## The rule

`[N]T` (and the enum table `[Kind]T`) keeps its value semantics — assignment
and an ordinary argument still copy — and gains the list spellings:

| spelling | meaning | SPEC |
| --- | --- | --- |
| `a[i] = v`, `a[i] op= v` | `a = replace(a, i, v)`, written in place | `PY-ARRAY-WRITE-1` |
| `a[i].f = v`, `a[i].f.g = v`, `a[i][j] = v` | the same path rebuilt with `replace` per array step and a record update per field step | `PY-ARRAY-WRITE-1` |
| `r.cells[i] = v`, `c.cells[i] = v`, `xs[k][j] = v`, `xs[k].cells[j] = v` | the path below a record binding, a `class`, or a list or dictionary slot | `PY-ARRAY-WRITE-1` |
| `for x in a`, `for i, x in enumerate(a)`, `[f(x) for x in a]` | walk the value the array had when the loop began | `PY-ARRAY-ITER-1` |
| `def f(a: mut [N]T)` … `f(mut a)` | the parameter names the caller's variable; element writes land there | `PY-ARRAY-MUT-1`, `QBE-ARRAYREF-1` |

Generic bodies accept the same writes and loops over `[N]T` with a `const N`.

### What is rejected, and with what

| program | diagnostic |
| --- | --- |
| `a[0] = 1` where `a` is an array parameter without `mut` | `E_MUTATION_MARKER` "this function writes `a` (parameter 1) reachable from the caller; declare `a: mut [4]int`" — the list rule, produced by the same origin analysis |
| passing a non-`mut` array parameter on as `mut a` | the same, at the call |
| a `mut [N]T` the body never writes | `E_MUTATION_MARKER` "declared `mut` but never written" |
| `f(a)` where `f` declares `mut` | `E_MUTATION_MARKER` "`f` writes `a`; write `(mut a)`" |
| `a = other` / `a = replace(a, …)` / destructuring into a `mut` array parameter | `E_ASSIGNMENT_TARGET` "`a` is a `mut` array parameter and names the caller's array; write its elements …, or copy it into a local first" |
| `f(mut box.cells)`, `f(mut rows[0])` | `E_MUTATION_MARKER` "`mut` on a fixed array passes a variable itself; copy the field or element into a local, pass `mut` that local, and store it back" |
| `writer = f` where `f` has a `mut` array parameter | `E_CALLBACK_TYPE`; a lambda for such a callback is `E_LAMBDA_CONTEXT` |
| `mut [N]T` on a host or C ABI function, or over move-only / result elements | `E_MUTATION_MARKER` |
| a write through an immutable binding | `E_IMMUTABLE` "element assignment requires a mutable binding" |
| `outer[i] = managed` inside `with arena()` | `E_ARENA_ESCAPE`, as for a list; a callee storing an arena value into a `mut` array is caught by the runtime rescan (`R_ARENA_ESCAPE`) |
| `a[i].f += v` | `E_ASSIGNMENT_TARGET` from the parser, exactly as for a record field |
| `for x in reversed(a)`, `zip(a, b)` | unchanged `E_PRELUDE_TYPE` (left) |
| `for x in table` over `[Kind]T` | `E_COLLECTION_METHOD` (a table is indexed by key) |

**Negative indices — a decision the coordinator should confirm.** The task
said "exactly as for lists and as `replace` does today". Those disagree: a list
counts `-1` from the end, while a fixed-array read and `replace` trap
`R_INDEX_BOUNDS` on it. The branch keeps the array rule for writes, so a read
and a write of the same array agree: any index outside `0 <= i < N` traps with
the same index, length, message and position `replace` reports. Adopting
Python's rule for arrays would change reads too and add a normalization to
every array access (§5.6 priced that at −14 % on the list `fannkuch_redux`).

**Why element writes need `mut` on a parameter.** An array parameter without
`mut` is still the callee's own copy, and whole rebinding of it
(`values = replace(values, …)`, the existing spelling) is unchanged. But an
element write through it is refused, because the same text on a list writes
the caller's list: accepting it silently would make `a[i] = v` mean opposite
things for the two containers. `local = values; local[i] = v` is the explicit
spelling of "my own copy".

## How it is built

**Checker (`src/sema.zig`).** `arrayPlace` walks an assignment target's
declared types (no diagnostics) and answers the root and the steps below it
when the path writes inside a fixed array; everything else falls back to the
list/record rules untouched. `checkArrayPlace` rebuilds the path —
`replace` per array step, `update` per field step — and stores it with a new
`typed.Store.element` flag (an element write, not a rebinding), or through the
list/dictionary slot the path runs through. Order is Python's: the value is
spilled first when it is not inert and could be reordered; an index is spilled
only when it is not effect-free, since it is used to read and to rebuild. So
`a[i] = v` with plain operands is exactly `assign a = replace(a, i, v)` — the
`QBE-ARRAYWRITE-1` shape. `for`/comprehensions read `owner[i]` of a one-time
copy with a constant limit and no iteration guard. `mut` on `[N]T` is accepted
(`typed.referenceArray`), whole rebinding of such a parameter is refused, the
call-site target must be a mutable variable, and function values/lambdas with
one are refused. `call_evaluation` no longer spills a `mut` `.local`
argument when keyword arguments are reordered.

**Mutation analysis (`src/effects.zig`, `src/origins.zig`).** An element store
into a fixed-array parameter is a write of that position, so the existing
declaration-side check produces the list diagnostics for free. A fixed array
passed at a `mut` position writes only the caller's variable: its origin is
the parameter it forwards, or fresh for a local (plus the shared origins of any
managed elements), so `b = a; f(mut b)` does not claim to write `a`.

**Bytecode.** One new op, `ref_local`: push the address of a local's storage.
`lower.zig` emits it for every argument bound to a `mut` array parameter. The
validator accepts it only on a fixed-array local; disassembly, IR typing,
effects and the inliner's slot shift know it; the inliner never splices a
callee with a `mut` array parameter.

**QBE (`src/qbe.zig`, `src/qbe_aggregate.zig`, `src/qbe_borrow.zig`).**
`callerStorage(index)` identifies a `mut` array parameter; it is an
address-holding slot like a read-only aggregate parameter (`QBE-AGGREF-1`) but
written through: element writes go through its address, forwarded in place by
`QBE-ARRAYWRITE-1` (`replaceDestination` admits it, `localPointer` loads the
address), and any other store blits into the caller's storage. A read the
borrow rule cannot name is snapshotted, and so is a read of a local whose
`ref_local` is already on the operand stack (`pendingReference`), which is what
gives `f(mut a, a)` a snapshot. `ref_local` counts as a write everywhere the
backend proves a local unwritten, and as a read where it proves one unread.
Roots are unchanged: the caller's slot stays its own frame's traced root.

## Lowering evidence

`fannkuch_redux_array.my` is the list program with `[10]int` declarations and
no `replace` (it keeps the list version's element-by-element copy loop). QBE IL
of `fannkuch`, from `mylang emit-qbe`:

| variant | IL lines | whole-array `blit` | `%agg` lines | `call` lines |
| --- | ---: | ---: | ---: | ---: |
| `fannkuch_redux_tuned.my` (`replace`) | 2578 | 1 (`perm = perm1`) | 2 | 33 |
| `fannkuch_redux_array.my` (`a[i] = v`) | 2907 | 0 | 2 | 36 |

The two `%agg` lines in each are the returned tuple's buffer, not an array
copy; the extra `call` lines in the array variant are mostly the cold bounds-failure paths
of its ten-element copy loop.

Every element write is the in-place form: bounds test, `mul`/`add` to the
element address inside the local, one `storel` (the `%v…` from `copy %l…`).
`src/array_places_test.zig` pins: the callee of `f(mut values, 9)` stores
`%a0` into its slot, contains no `blit` and no `%agg`, and stores through the
loaded address; the caller hands `storel %l0, %s0` (its own slot) and copies
nothing; `reverse_into(mut v, v)` snapshots the read-only argument exactly once;
a loop of element writes into a local emits no `blit` or scratch.

## Numbers

ReleaseFast compiler, default build (LLVM O3 + LTO), `bench.py --cpu 5
--rounds 11`, **loaded machine** (load average 24.2 → 17.3 during the batch).
Paired per-round ratios to Zig ReleaseFast, median and interval, from
[`results/wave3/fannkuch-array.json`](../../experiments/perf-parity-plan-20260922/results/wave3/fannkuch-array.json):

| arm | ratio to Zig |
| --- | --- |
| Zig ReleaseFast | 308.7 ms (1.00) |
| `my` — `list[int]` | 1.24 [1.17, 1.27] |
| `my-tuned` — `[10]int` with `replace` | 0.83 [0.76, 0.86] |
| **`my-array` — `[10]int` with `a[i] = v`** | **0.78 [0.76, 0.84]** |

`my-array / my-tuned`, paired per round: median 0.95 (wall and CPU). The
natural spelling is at the tuned variant's speed — slightly faster, because the
10-element copy loop beats the tuned version's whole-array copy under LLVM.
Acceptance (≈0.8–0.9× Zig, IL in place) is met. As in the plan, `n` is a
compile-time constant in both array variants and not in Zig's.

## Tests

* `tests/lang/array_places.my` — 22 guest tests, run under `--gc-stress` by
  `zig build test-lang`: every write form, value-semantics copies, a class
  field, list-slot roots, tables, evaluation order against a `mut` side effect,
  `[N]str` and records holding lists written by callees while collections run,
  loops that change the array they walk, `mut` pass-through.
* `src/array_places_test.zig` — rejections, `R_INDEX_BOUNDS` traps (out of
  range, negative, nested augmented), arena escape, and the IL facts above.
* `docs/records-and-unions.md` gains three sections with runnable examples,
  `docs/effects.md` a pointer; `src/features.json` gains
  `fixed-array-element-writes`, `mut-fixed-array-parameters`,
  `fixed-array-iteration`.
* The agent-a repro `agent_a_diag_mut_fixed_array.my` now runs and prints
  `1.0`; its header records the old diagnostics.

## Gate

Each step's log was diffed against the lane-5 base logs with
`gate/gate_diff.py`; the base is red (46 failing tests in `zig build test`, 2 in
`test-qbe`).

| step | result | against the base |
| --- | --- | --- |
| `zig build test --summary all -j4` | 45 tests failed, Guardian 88/88 | **0 new, 0 cleared** (46 = 46) |
| `zig build test-qbe --summary all` | 270/272, 2 failed | **0 new** (2 = 2) |
| `zig build test-qbe-build --summary all` | 30/30 steps | green |
| `zig build test-schematic` | 27/27 steps, 21/21 tests | green |
| `zig build test-byte-io` | 26/26 steps, 11/11 tests | green |
| `zig build fmt-check` | pass | green |
| `zig build test-docs` | 924 blocks, 167 run, 0 failed | green |
| `zig build test-lang` | 265 guest tests (70 programs), 0 failed | green |

The first `zig build test` attempt lost its `src/root_test.zig` compile to a
`SIGTERM` under memory pressure and showed four `test/integration.zig`
failures that each pass when rerun alone (`CLI checks array schemas …`,
`C3s provider body …`, `loadConfiguredPolicy …`, `named constraints fake-only
…`, all exit-status/host timing on a loaded machine); the `-j4` rerun above is
the complete one. No existing test pinned the old rejections: the only
previously asserted message this touches, `MUT-PARAM-3`'s "only a list, dict,
class, Cell, array, …", is unchanged and now true.

## Left

* **`mut` on a field or element** (`f(mut box.cells)`, `f(mut rows[i])`) is
  refused with a message naming the workaround. Supporting it needs an interior
  address and, for a list slot, a guarantee the list cannot move during the call.
* **A record holding a fixed array as `mut`** (`mut r: R` with `cells: [4]int`)
  is still "nothing to write": only `[N]T` itself is by reference.
* **Element writes below a `class` or list slot copy the array.**
  `c.cells[i] = v`, `r.cells[i] = v` and `xs[k][j] = v` are correct but rebuild
  the array (the `update_record` path `QBE-ARRAYWRITE-1` does not forward). A
  nested `a[i][j] = v` on a local writes the outer element in place but copies
  one row; `a[i].f = v` copies one element.
* **`for x in a` copies the array once per loop** (not per iteration), even when
  the body never writes it.
* `reversed(a)`, `zip(a, b)`, `a[i], a[j] = a[j], a[i]` and `a[i].f += v` are
  unchanged.
* Negative indices: see the decision above.
