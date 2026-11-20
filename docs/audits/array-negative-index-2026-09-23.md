# Fixed arrays: Python negative indices and the array-write leftovers — 2026-09-23

Lane `lang/array-negative-index` from `base/parity-leftovers` (`160a2d08`).
Follows [fixed-array-writes-2026-09-22](fixed-array-writes-2026-09-22.md), whose
"negative indices" decision the user settled: a fixed array takes Python's
negative indices exactly as a list does.

## What changed in the language

| spelling | before | now | SPEC |
| --- | --- | --- | --- |
| `a[-1]`, `a[i]` with `i < 0`, every write form, `replace(a, -1, v)` | trapped `R_INDEX_BOUNDS` | counts from the end; outside `-N <= i < N` traps `R_LIST_BOUNDS` with the index as written and the length — the list's code and text | `PY-ARRAY-NEGATIVE-1` (and `PY-ARRAY-WRITE-1` reworded) |
| `a[i].f += v` | **silently compiled as `a[i].f = v`** (the base accepted it after another lane added augmented field assignment, but the array-place path dropped the operator) | keeps its operator | `PY-ARRAY-WRITE-2` |
| `a[i], a[j] = a[j], a[i]`, `xs[0], xs[-1] = …`, `d[k], r.f, name = …` | `E_SYNTAX` (targets were names only) | element and field targets; the value is evaluated once, then each target in order | `PY-DESTRUCTURE-PLACE-1` |
| `for x in a` over a local array the body never writes | copied the array once per loop | reads the variable in place (same values, nothing can change it) | `PY-ARRAY-ITER-2` |
| `r.cells[i] = v` (value record), `c.cells[i] = v` (`class`) | 3–4 whole-array/record copies per element write | one bounds check and one store | `QBE-ARRAYWRITE-2` |
| `c.cells[i]` read of a class field array | snapshot of the whole array per read | a load from the cell | `QBE-FIELDARRAY-READ-1` |

The array trap code moved from `R_INDEX_BOUNDS` to `R_LIST_BOUNDS` because the
decision was "the same code and message shape lists use"; the detail text
(`(index -5, length 2)`) was already the same. Nothing emits `R_INDEX_BOUNDS`
now (`myl_qbe_fail_bounds`, which still names it, has no caller).

## How it is built

**Checker (`src/sema.zig`).** `arrayKey` decides each fixed-array index once —
reads (`checkValueIndex`), `replace(...)`, and every element step of an
assignment place (`checkArrayPlace`, before any spill). A table key never
counts from the end. A constant in `-N .. -1` is folded to `N + k`, so `a[-1]`
is `a[N-1]`. Otherwise `nonNegative` answers from facts the checker already
has: unsigned type, non-negative constant, `len`/array length, a `range`
induction variable whose start is non-negative (immutable binding), a
comprehension's range index, an `enumerate` position, and checked `+ * // rem`
of such values, `%` by a positive constant, `bit_and` with one, a right shift.
Anything else sets `from_end` on the typed `.index` / `.replace` node.

An `enumerate` position is a mutable binding (assigning it is allowed and —
pre-existing bug, see below — changes the iteration). Accesses proved through
it are recorded; if the loop body's write count of the binding changed, they are
flipped back to `from_end` when the body is done (`settleCounter`).

**Bytecode.** `get_index` / `replace_index` carry `Access{ ty, from_end }`
instead of a bare type (validator, disassembly — `GET_INDEX [4]i64 from_end` —,
IR typing, effects, inliner, borrow rules updated mechanically).

**Backend (`src/qbe_aggregate.zig`).** Without `from_end` the access is
byte-for-byte what it was. With it, no branch:

```
%s = add %i, N            ; one unsigned test accepts exactly -N <= i < N
%bad = cugel %s, 2N       ; (trap reports %i and N)
%a = add base, i*stride   ; the ordinary, affine address
%a = add %a, (sar %i, 63) & (N*stride)
```

Four candidate lowerings were built and timed (below); this one was the
cheapest because it keeps the ordinary address as a term, so LLVM still
strength-reduces it and shares it between the read and write of `perm[k - i]`.

**Destructuring (`src/parser.zig`, `src/sema.zig`, `src/generic_bodies.zig`).**
The target list accepts `name | xs[i] | r.f` (parsed as expressions and checked
for shape). A non-name target is written by the existing single-assignment
checker (array place, list/dictionary write, field assignment) with the tuple
element injected as the already-resolved value of the target node, so every
rule (mutability, `mut` parameters, arena, negative indices) is the ordinary one.

**In-place loop (`beginWalk`/`endWalk`).** For a fixed array held in a local
that is not a `mut` array parameter, the loop's copy is created only after the
body is checked, and only if the body wrote the variable (write count, which
now also counts a `mut` argument naming it).

**Field element writes.** The statement the checker builds for `r.cells[i] = v`
is `load r; load r; get_field k; <index>; <value>; replace_index; update_record
{k}; store r`. `fieldWriteAt` recognizes exactly that shape over one local when
the window between the field read and the `replace` is scalar pushes and
computations only, the field is a fixed array of scalars (no barriers), and a
value record is the frame's own storage (not a caller's address). The field read
then names the field inside the record, the `replace` writes in place, and the
update and store copy nothing. `elementRead` does the same for a class field
read immediately consumed by one element read.

## Evidence

IL, `emit-qbe`, base compiler vs this branch:

* `for i in range(64): a[i] = start + i` and `total += a[i] * …`: identical
  lines; the only change in the function is the `a[63 - i]` read (`63 - i` is
  not provably non-negative), which gains `add`, `sar`, `and`, `add`.
* A probe with `board.cells[i] = 5; board.cells[1] += board.cells[i]` on a
  `class`: 0 `blit` and 0 `%agg` lines (base: 8 and 12); the same on a local
  value record: 1 blit, the array literal (base: 13); `walk(values)` with
  `for x in values` and `enumerate(values)`: 0 (base: 2). A class-field read
  loop `board.cells[i] * board.cells[(i+1) % 4]` has no snapshot left. The
  zero counts are pinned in `src/array_places_test.zig`.
* `fannkuch_redux_array` / `_tuned`: 7 accesses get the from-end form each
  (`count[r - 1]`, `perm[k - i]` ×2, `perm1[r]`, `count[r]` ×3); the rest
  (`perm[i]`, `perm1[i + 1]`, constant indices) are unchanged.

## Numbers

ReleaseFast compilers (this branch; base = `160a2d08` built the same way), default
build (LLVM O3 + LTO), `bench.py --cpu 2`, prebuilt `--cf` arms, paired
per-round ratios with 95 % bootstrap intervals. **Loaded machine** (load average
3–6 during the runs; other agents active).

Final lowering, 21 rounds
([`fannkuch-final.json`](../../experiments/perf-parity-plan-20260922/results/array-negative-index/fannkuch-final.json)):

| arm | ms | vs Zig ReleaseFast | branch / base (paired) |
| --- | ---: | --- | --- |
| Zig ReleaseFast | 213.9 | 1.00 | |
| `fannkuch_redux` (list) | 251.6 | 1.19 [1.17, 1.21] | 0.996 [0.991, 1.007] |
| `fannkuch_redux_array` | 188.8 | 0.89 [0.89, 0.91] | **1.071 [1.050, 1.078]** |
| `fannkuch_redux_tuned` (`replace`) | 205.4 | 0.98 [0.97, 0.99] | **1.112 [1.101, 1.128]** |

Lowering candidates, 15 rounds, paired against the base arm
([`fannkuch-lowering-candidates.json`](../../experiments/perf-parity-plan-20260922/results/array-negative-index/fannkuch-lowering-candidates.json)):

| lowering of a possibly-negative index | array | tuned |
| --- | --- | --- |
| branch on `i < 0`, access duplicated on each path | 1.119 [1.110, 1.131] | 1.138 [1.122, 1.142] |
| `i + ((i >> 63) & N)` then the ordinary test | 1.059 [1.051, 1.066] | 1.119 [1.104, 1.135] |
| ordinary test first, from-end access on the failing path | 1.071 [1.069, 1.093] | 1.096 [1.091, 1.105] |
| **`i + N <u 2N`, affine address + sign-masked correction (kept)** | **1.050 [1.039, 1.056]** | **1.087 [1.070, 1.101]** |
| (control: the tuned program with every such index masked by `bit_and(x, 15)`, which the checker proves non-negative) | — | ≈ 1.03 |

The acceptance item "fannkuch_redux_array not slower" is **not met**: the
program indexes with `k - i`, `r - 1` and `r`, which no local fact proves
non-negative, so Python's rule costs 5–7 % there (9–11 % on the tuned
`replace` spelling). The branchy forms lose to LLVM's block layout (the hot path
takes a jump over the from-end block; QBE IL has no branch weights), and the
index-rewriting form loses the affine address. The plan priced the same rule at
up to 14 % on the list version (§4.7), and the list version still pays it. What
would recover it: a relational range fact (`i < (k + 1) >> 1` and the loop
running imply `k - i > 0`) or loop versioning on an invariant sign test; both
are analyses, not lowering, and are left.

## Tests

* `tests/lang/array_negative_index.my` — 20 guest tests (`module` + `main`),
  run by `zig build test-lang` under `--gc-stress`: reads, every write form,
  `replace`, nested, record/class fields, list slots, tables, enumerate with an
  assigned position, range/modular indices, a `const N` generic, traced
  elements, in-place loops, swaps over arrays/lists/dicts/fields/tuples from a
  call, evaluation order, traced list swaps under collection.
* `src/array_places_test.zig` — traps with the list code at the right line
  (`PY-ARRAY-NEGATIVE-1`), the IL facts above (`QBE-ARRAYWRITE-2`,
  `QBE-FIELDARRAY-READ-1`, `PY-ARRAY-ITER-2`, no adjustment on proven indices).
* `src/native_execute.zig` — the structured trap-detail table now expects
  `R_LIST_BOUNDS` for arrays and gains two negative-array rows (index as written).
* Updated pins: `test/integration.zig` (two `R_INDEX_BOUNDS` → `R_LIST_BOUNDS`),
  `src/generic_arrays_test.zig`, `src/arrays_test.zig` (op payload).
* Docs: `docs/records-and-unions.md` gains "Negative indices" with a runnable
  example and notes on field writes and in-place loops; `docs/tuples.md` gains
  "Element and field targets"; `docs/experiments/arrays.md` reworded;
  `src/features.json` gains `fixed-array-negative-indices` and
  `destructuring-element-targets`.

## Left, and why

* **The fannkuch cost above** — needs a relational or loop-versioning analysis.
* **`a[i][j] = v` still copies one row, `a[i].f = v` one element, and writes
  below a list slot (`xs[k][j] = v`) rebuild the array**: forwarding them is the
  same pattern as `QBE-ARRAYWRITE-2` through more steps; not done.
* **Field writes of arrays of records or of managed elements** keep the copying
  lowering (they would need the collector/arena barriers `update_record` emits).
* **`for x in a` over a field (`for x in r.cells`) or a `mut` array parameter**
  still copies once; comprehensions over arrays still copy once.
* **`a[i].items += more` where `items` is a list** concatenates (as `xs[i] +=`
  on a list slot does today) rather than extending in place as `r.items += more`
  does; pre-existing inconsistency, unchanged.
* **Pre-existing bug found, not fixed (checker lane):** assigning the position
  name of `for i, x in enumerate(xs)` inside the body changes the loop's own
  counter (`i = 10` ends the loop after one pass); Python rebinds a copy. The
  negative-index proof accounts for it (see `settleCounter`).
* `myl_qbe_fail_bounds` (`R_INDEX_BOUNDS`, no caller) is dead runtime code.

## Gate

Each step's log diffed against `gate/w4-<step>.log` with `gate_diff.py`.

| step | result | against w4 |
| --- | --- | --- |
| `zig build test --summary all` | 73/73 steps, 1756 run (19611 selected incl. skips), 0 failed | 0 new; clears `QBE-INLINE-ALLOC-1 a small class body…` (fixed by `160a2d08`) |
| `zig build test-qbe --summary all` | first run: 1 failure, `golden_parity … replay natively` — `tests/goldens/qbe_parity.json` pinned `R_INDEX_BOUNDS` for `xs[2]` on `[2]i64`; the golden's code was updated to `R_LIST_BOUNDS` (the decision); rerun 48/48 | 0 new after the update |
| `zig build test-qbe-build` | 30/30 | 0 new |
| `zig build test-schematic` | 27/27 | 0 new |
| `zig build test-byte-io` | 26/26 | 0 new |
| `zig build fmt-check` | pass | — |
| `zig build test-docs` | 938 blocks, 173 run, 0 failed | — |
| `zig build test-lang` (`--gc-stress`) | 511 guest tests, 98 programs, 0 failed | — |
