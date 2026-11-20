# Loop range facts: proving checks away, and versioning loops that need a guard — 2026-09-23

Lane `perf/loop-range-facts`, from `base/vectorize` (`395d2490`), merged with
`main` `ba857f44` (the parallel lane `perf/vectorizer-blockers`) before the
final measurements, so every number below is this lane's gain **on top of**
that lane. Evidence, scripts and result files are in
[`experiments/loop-range-facts-20260923/`](../../experiments/loop-range-facts-20260923/).

## Headline

- **A loop-facts analysis** (`src/qbe_loop_facts.zig`, `QBE-LOOP-FACTS-1`)
  plans every innermost counted loop — `range`, `for x in xs`, `enumerate`,
  and `while i < n` / `i <= n` with a literal or invariant step — whose body
  cannot resize a list it reads, call, or allocate. It names every operand
  symbolically and proves index, overflow, iteration-check and append facts.
- **Loop versioning** (`src/qbe_loop_version.zig`, `QBE-LOOP-VERSION-1`): a
  guard in front of the loop checks the facts once; a check-free copy runs when
  they hold, and the **original, unchanged loop** runs when they do not. A trap
  therefore always comes from code that was there before, at the same
  iteration, with the same text.
- **Results against Zig ReleaseFast** (`bench/parity`, CPU 4, 9 rounds, final
  batch `results/bench-parity-lane.json`): suite geomean **0.96×** (the base
  lane was 1.02×), `bench-parity` PASS with 0 regressions.

  | program | task's start | before (`vecblock`) | **lane** | target | verdict |
  |---|---:|---:|---:|---:|---|
  | matmul | 3.86× | 0.72× | **0.62×** | ≤ 2.0× | met (also improves on the base: −12.5%) |
  | nbody | 1.99× | 1.72× | **1.71×** | ≤ 1.4× | **missed** — not checks; see *nbody* |
  | sieve | 1.66× | 1.48× | **1.01×** | ≤ 1.2× | met (−33% on the base) |
  | spectral_norm | 1.14× | 1.07× | **1.00×** | ≤ 1.05× | met (−6.5%) |
  | fannkuch_redux | 1.13× | 0.98× | **0.99×** | ≤ 1.0× | met by the base; +1.2% here, see *Costs* |
  | bytes_scan | 1.44× | 0.39× | **0.39×** | ≤ 1.0× | met by the base; unchanged |

  "Before" and "lane" come from one paired batch
  (`results/paired.json`, 15 rounds, arms shuffled each round). The full
  `bench-parity` batch agrees within 0.02 on every row but `nbody`, which it
  puts at 1.62× (a different Zig time on a loaded machine; the paired ratio
  to the base, 0.991, is the lane's own effect).
- **Hardware counters** (lane vs `vecblock`, both over Zig): `spectral_norm`
  branches **19.75× → 2.00×** and instructions 1.61× → 0.81×; `sieve`
  branches 4.28× → 0.96× and instructions 3.16× → 0.93×; `matmul` branches
  0.95× → 0.79×.
- **Traps**: a 10-program trap corpus, built by the base compiler and by this
  lane in three modes, is **30 of 30 byte-identical** (stdout, stderr with
  trace and `MYLANG-TRAP` record, exit status); 8 Zig tests compare every
  trap and value against the unversioned lowering in the gate.
- **Gate**: `test`, `test-qbe`, `test-qbe-build`, `test-schematic`,
  `test-byte-io`, `fmt-check` all green; `gate_diff.py` against the base's
  `vecblock-*.log`: **0 new failures** in every step (details under *Gate*).

## 1. The facts

`plan(allocator, .{ program, function, states })` returns a `Plan`: interned
symbolic `nodes` and one `Loop` per versioned loop, each with an ordered
`guard: []Step` and per-instruction `actions`. `Plan.at(pc)` finds the loop
whose header is at `pc`. The module comment states the API for other consumers
(an LLVM adapter pass could read the same facts).

**Which loops.** An innermost loop whose header is `load counter; load bound |
push; cmp lt|le; jump_if_false exit` and whose last two instructions are
`store counter (= counter + step); jump head`, entered only at its header, with
every instruction from an allow-list: local loads and stores, literals,
comparisons, forward jumps, integer and float arithmetic, casts, record and
fixed-array operations, the pure float conversions, and list/`bytes` `len`,
element read, element write and iteration check. No call, no allocation, no
`str` or dictionary access, no pop/insert/slice/extend. One exception: a single
append of a plain scalar in a straight-line body, to a list type the loop never
otherwise touches (a comprehension's fill). Such a loop changes the length of no
collection it reads and moves no element storage. The body must be at most 200
instructions (see *Costs*).

**Symbolic values.** Literals; *invariant locals* (the body never stores them);
the *counter* (between its entry value and its bound); *accumulators* (a local
whose one store is `a + e` with `e` built from non-carried values — at most once
per iteration, because the body is acyclic); *narrow* integers bounded by their
type (a `u8` element); sums, differences and products; a division by a nonzero
literal (bounded by its dividend); lengths of stable collections; and elements
read at an invariant position from a list whose element slots the loop never
writes (the row `c[i]`). A forward pass in program order merges the two states
at a join and marks a disagreement unknown.

**What is proven, and how.**

| check class | fact | guard step(s) | why it is sound |
|---|---|---|---|
| list/`bytes`/array bounds of `alpha*i + beta`, `alpha` ∈ {−1,0,1}, `beta` invariant | every index lies in `[min, max]` over the counter range | `min ≥ 0`; `max < len` (signed), or `beta <u len` for an invariant index | the counter only rises (literal step ≥ 1, or an invariant step checked ≥ 0) and stays below its bound in the body; the receiver's length cannot change (no resize in the loop) |
| the frontend's `idx < 0` normalization branch | never taken | the same `min ≥ 0` | same |
| checked 64-bit `+ − *` | value bounded by `c·X^d` with leaves in `[−X, X]` | each leaf `−2^b ≤ v ≤ 2^b`; `b` the widest ≤ 60 at which every candidate fits 63 bits | exact integer arithmetic over bounded leaves; an operation that needs `b < 20` keeps its check; the counter is within `[entry, bound]`, an accumulator within `|a0| + 3X·|e|` (trips ≤ 2X+1) |
| accumulator `count += e` | as above | `|a0| ≤ 2^b`, and a local step ≥ 1 | one store per iteration, every iteration advances the counter (no jump skips the update) |
| `for x in xs` length checks (two per iteration) | hold every iteration | `len(xs) == expected` once | no resize in the loop |
| invariant element read (`c[i]` inside `for j`) | same value every iteration | the read's own bounds step, then one read | no write to that list type, no call |
| element storage address of a stable list | same every iteration | read once | no growth in the loop |
| append in a fill loop | capacity holds every element | `capacity − length ≥ bound − entry` (+1 if inclusive) | one append per counter value, literal step |

`spectral_norm`'s `(i + j) * (i + j + 1) // 2 + i + 1` is at most `8·X²`, so
its leaves are guarded at `2^29` (the Zig test pins that constant). A list's
length is never assumed bounded by memory: a list of zero-sized elements can
be long without memory, so every bound is a runtime guard on the actual values.

To make `spectral_norm`'s arithmetic visible, the bytecode inliner now admits
`unary_float` (`float(i)`, `int(x)`, `sqrt`: the pure `myl_qbe_float_unary`),
so `a(i, j)` is spliced into its loop (`BYTECODE-INLINE-2` amended, with a test
that a trapping conversion still reports the callee's frame).

## 2. The lowering

- **Labels.** The guard takes the header's label `@i<head>`, so every entry
  reaches it. The check-free copy's instructions are `@fi<pc>`; the original
  header becomes `@oi<head>`, which only its own back edge and a failing guard
  name. `stripUnreferencedLabels` knows all three.
- **The guard** opens with `bound > entry and bound − entry ≥u 16` (a shorter
  loop runs the original, see *Costs*), then the leaf bounds, the step, the
  index/iteration/room comparisons in program order, the length bounds, and
  finally reads the hoisted rows, storage addresses and an append's length and
  generation. Each failure jumps to `@oi<head>`. No element is read before the
  step that bounds its position.
- **The copy** is the ordinary per-instruction lowering with, per action: value
  guards off (as `--unchecked` lowers that instruction, `QBE-UNCHECKED-1`),
  no from-end correction, a proven `jump_if_false` as a plain jump (the
  unreachable instructions behind it omitted), a proven iteration check as
  nothing, a hoisted read as the guard's value, the guard's storage address in
  the element address, and a presized append as a store plus the length and
  generation writes the inline append's fast path makes. The copy is thrown away
  if its text would name an allocating callee.
- **Not applied** under step accounting (a `--max-steps` build counts the
  original's instructions) or `--unchecked` (nothing to prove).

The emitter marks guard-loaded storage with the base lane's `markElements`, so
the adapter's element alias classes and element GEPs (`LLVM-ELEMENT-CLASS-1`,
`LLVM-ELEMENT-GEP-1`) apply to the copies.

## 3. Vectorization

LTO-link and per-unit remarks (the full-LTO pre-link compile of each unit
already runs the loop vectorizer), guest code only
(`results/vectorize-remarks.md`, `remarks_table.py`):

| program | vectorized loops, before | after | what now vectorizes |
|---|---:|---:|---|
| matmul | 1 | 3 | the kernel's copy, and the two `[[0.0 …]]` fills |
| spectral_norm | 0 | 3 | the three `[1.0 for _ in range(n)]` fills (the `a(i,j)` loop is a strict FP reduction; its gain is 22 check branches per element gone) |
| sieve | 1 | 3 | the `[True …]` fill (was 26% of cycles, now ~1%), and the count loop |
| fannkuch_redux | 1 | 5 | fills and copy loops (they rarely reach 16 iterations at `n = 10`) |
| bytes_scan | 1 | 2 | as before, plus a fill |
| list_append_sum | 1 | 3 | an appending fill whose list is not presized, so its guard fails at run time |
| nbody, fannkuch_redux_array | 0 | 0 | — |

The sieve fill is now a 128-byte-per-iteration vector store loop; the strided
marking loop is the same four instructions Zig emits.

## 4. Numbers

Paired batch, lane vs the base (`results/paired.md`, 15 rounds, CPU 4, loaded
machine, load average 1.2–3.6):

| program | Zig ms | before × Zig | lane × Zig | lane ÷ before [95% CI] |
|---|---:|---:|---:|---|
| matmul | 38.2 | 0.72 | 0.62 | **0.875** [0.866, 0.884] |
| sieve | 53.7 | 1.48 | 1.01 | **0.670** [0.660, 0.697] |
| spectral_norm | 164.4 | 1.07 | 1.00 | **0.935** [0.925, 0.944] |
| nbody | 147.3 | 1.72 | 1.71 | 0.991 [0.986, 1.001] |
| fannkuch_redux | 182.4 | 0.98 | 0.99 | 1.012 [1.005, 1.016] |
| fannkuch_redux_array | 182.4 | 0.86 | 0.87 | 1.002 [0.998, 1.006] |
| bytes_scan | 35.3 | 0.39 | 0.39 | 0.983 [0.969, 1.014] |
| list_append_sum | 41.2 | 1.16 | 1.14 | 0.991 [0.961, 1.008] |
| raytrace, mandelbrot, knucleotide, intloop, float_loop, list_records, records, str_build | | | | 0.99–1.01, every interval containing 1.00 except knucleotide 0.993 [0.989, 0.999] |

Counters (`results/counters.md`, `perf stat`, P-core events, median of 5):

| program | instr lane/Zig | before | branches lane/Zig | before | cycles lane/Zig | before |
|---|---:|---:|---:|---:|---:|---:|
| matmul | 0.31 | 0.35 | 0.79 | 0.95 | 0.61 | 0.70 |
| nbody | 2.48 | 2.49 | 78.4 | 78.4 | 1.59 | 1.59 |
| spectral_norm | 0.81 | 1.61 | **2.00** | 19.75 | 1.00 | 1.01 |
| sieve | 0.93 | 3.16 | **0.96** | 4.28 | 0.98 | 1.50 |
| fannkuch_redux | 1.40 | 1.35 | 2.57 | 2.48 | 1.00 | 0.99 |
| bytes_scan | 0.35 | 0.35 | 0.58 | 0.58 | 0.38 | 0.38 |
| list_append_sum | 1.43 | 1.43 | 1.00 | 1.00 | 1.15 | 1.14 |

## 5. Costs, and what was withdrawn

- **Short loops.** Versioning `fannkuch_redux`'s flip and shift loops (1–9
  iterations) made it 13% slower: the guard costs about what the checks it
  removes cost, and LLVM turned the check-free shift loop into a `memmove`
  call. Counterfactual builds with one loop's guard disabled
  (`cf_noversion.py`) located it (flip +6%, shift +9%). The guard now opens
  with the 16-iteration span test; `fannkuch_redux` is back to +1.2% of the
  base (the span test and code placement) and `fannkuch_redux_array` to
  +0.2% (interval contains 1).
- **Long bodies.** `nbody`'s 730-instruction pair loop ran 7% slower with an
  unused copy beside it (its loops run 4, 3, 2, 1 times) and no faster with a
  used one; bodies over 200 instructions are no longer versioned.
- **A withdrawn adapter change.** The first version derived a `getelementptr`
  from every `# myl-obj` address. That made `nbody --unchecked` six times
  slower: a record element copied with `blit` through a GEP became 32-byte
  vector moves that the element's later 8-byte field reads could not
  store-forward from. It was narrowed to guard-loaded scalar storage, and then
  dropped entirely when the base lane's `LLVM-ELEMENT-GEP-1` (a GEP at the
  access itself) covered the copies.

## 6. nbody

`nbody` stays at 1.71× (target 1.4×) because its remaining cost is not
checks: `--unchecked` is 1.56× in the same batch. Its inner loop is
`sqrt`/divide latency plus six whole-record copies per pair
(`bodies[i].vx = …` reads the 56-byte `Body` into scratch and writes it back).
A counterfactual that writes the field in place (`cf_nbody.py` rewrites the
emitted manifest) gained only 1.4% once
the element GEPs no longer turned those copies into vector moves. Zig keeps
`bi`'s velocity in registers across the inner loop and calls `@sqrt` without
the errno branch our `myl_qbe_float_unary` carries; neither is a range fact.

## 7. Trap evidence

- **Zig tests in the gate** (`src/qbe_loop_facts_test.zig`, 15 tests, 8 of them comparing runs):
  - `sameOutcome` runs a program under the versioned fast protocol and under
    the step-accounted lowering, which versions nothing, and requires the same
    value, status, stdout, stderr, trap code, line, column, frame count and
    detail: an index past the end (guard fails), an unproven sum and a
    division by zero trapping *inside* the check-free copy, an accumulator
    whose start the guard rejects, a short row, negative indices and a
    negative start, a presized fill whose element computation traps, a short
    loop under the span;
  - IL facts: no bounds, normalization or counter checks in a range loop's
    copy; no checks in a `while` loop with a local step; the `2^29` leaf
    bound of the spectral product; the row and storage hoists; no capacity
    test in a presized append; loops with calls, appends that read their
    list, step accounting and `--unchecked` stay single.
- **CLI test** `test/integration.zig` "versioned loops LLVM vectorizes compute
  and trap exactly as QBE does": LLVM LTO vs QBE builds of a byte count and a
  row update, same stdout, and a guard-failing `b[j + 1]` traps with the same
  text on both.
- **Corpus** (`traps/`, `results/trap-corpus-compare.log`): 10 programs, one
  per trap class, each trap in or at a versioned loop of at least 16
  iterations; built by the base compiler (`install-vecblock`) and by the lane,
  in the release default, the release default under `--gc-stress`, and QBE:
  **30 of 30 identical** — `R_LIST_BOUNDS` (list, row, fixed array from the
  end), `R_OVERFLOW` (sum in the copy, rejected accumulator, rejected product
  bound, a `while` step), `R_DIVISION_BY_ZERO` (in the copy, in a fill),
  `R_FLOAT_CONVERSION` (an inlined conversion).
- **Differential runs**: every `tests/lang` module turned into a program that
  prints each test's result, plus `examples/` and `bench/parity`, built by
  the base compiler and by the lane: **138 identical, 0 different**; lane LLVM
  against lane QBE: **135 identical, 0 different** (3 skipped: an example
  using a removed spelling, and two modules whose merged program hits a
  pre-existing emitter `InternalError` on the base too).

## 8. Gate

Final tree, each step diffed with `gate_diff.py` against the base's
`vecblock-<step>.log`:

| step | result | new failures |
|---|---|---|
| `zig build test --summary all` | 81/81 steps, 1798 passed (base 1781; +15 loop tests, +1 inliner test, +1 CLI test), 0 failed | 0 |
| `zig build test-qbe --summary all` | 50/50, 311/311 | 0 |
| `zig build test-qbe-build` | 32/32 | 0 |
| `zig build test-schematic` | 29/29 | 0 |
| `zig build test-byte-io` | 28/28 | 0 |
| `zig build fmt-check` | pass | 0 |
| `mylang test tests/lang --gc-stress` | 569 passed across 106 programs | — |
| `test_adapter.py` | 34/34 (my adapter test was withdrawn with the change) | — |

`mylang test` builds guest tests step-accounted, so the guest suite itself
never runs a check-free copy; the Zig and CLI tests above, the corpus and the
differential runs are what exercise them.

## 9. Left, and declined

- **Declined as unsound or unproven:** assuming list lengths are bounded by
  memory (zero-sized elements are not); versioning a loop whose `continue`
  returns to the header (an accumulator's trip count would be unbounded); an
  append on a conditional path or with a non-literal step; hoisting a record
  element (the loop writes its fields); versioning a loop with any call, even
  to a pure callee (it could reach the list).
- **Not done:** loops with calls (spectral's `a` was inlined instead);
  `while r != 1` and other `!=`/decreasing loops; appends that grow the list
  (`list_append_sum`), which would need an allocation in the guard; a
  statically-known short trip count (the span test is at run time); in-place
  field writes for list elements (1.4% on `nbody`); the `+1.2%` span-test cost
  on `fannkuch_redux`.
- **Found, not fixed:** `tests/lang/array_writes.my` and
  `array_negative_index.my`, merged into one program each, make `emit-qbe`
  fail with `InternalError` on the base compiler as well.
