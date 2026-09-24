# What stopped LLVM's loop vectorizer, and the adapter fixes — 2026-09-23

Lane `perf/vectorizer-blockers`, from `base/vectorize` (`395d2490` = `main`
`35fcbc02` plus pinned hardware counters in `bench/parity`). It owns the LLVM
adapter (`experiments/llvm-backend/`); the parallel lane `perf/loop-range-facts`
works in the emitter. The one emitter change here is a comment marker (§2.2).
Evidence, scripts and batches are in
[`experiments/vectorizer-blockers-20260923/`](../../experiments/vectorizer-blockers-20260923/).

## Headline

- **Three adapter changes, all behind a SPEC tag:**
  - `LLVM-ELEMENT-GEP-1`: an element access reaches LLVM as a
    `getelementptr` from the storage word, not as `inttoptr` of an integer
    sum. Scalar evolution can then see the index.
  - `LLVM-ELEMENT-CLASS-1`: object headers and each kind of element storage
    get alias scopes that exclude each other. Frame slots now carry classes
    by a must-analysis across blocks, and copies between classes carry
    scopes. This needs a new emitter marker, `# myl-elem %v KIND`.
  - `LLVM-STICKY-REDUCTION-1`: an innermost loop whose overflow checks
    decide nothing else is versioned. The fast copy has no check branches.
    It is verified at its exits and falls back to the untouched loop.
- **Results.** Ratios are to Zig ReleaseFast on CPU 8, 9 rounds, as
  `bench/parity` prints them. "Before" is `main`; "after" is this branch.
  - suite geomean: **1.20× → 1.02×**; `--unchecked` is 0.96×;
  - micro-kernel geomean: **1.23× → 1.09×**;
  - `matmul`: **3.84× → 0.74×**;
  - `bytes_scan`: **1.33× → 0.37×**;
  - `nbody`: 1.81× → 1.60×;
  - `sieve`: 1.77× → 1.54×;
  - `fannkuch_redux`: 1.14× → 0.98×;
  - `spectral_norm`: 1.17× → 1.10×.
- **Paired, in one batch, after/before:**
  - `matmul` 0.208;
  - `bytes_scan` 0.278;
  - `nbody` 0.847;
  - `spectral_norm` 0.852;
  - `sieve` and `fannkuch_redux` 0.864;
  - `sort_quick` 0.919;
  - `list_records` 0.932;
  - `list_append_sum` 0.953;
  - geomean over 27 programs 0.877.

  Nothing got slower. Every apparent slowdown is either a byte-identical
  binary or 1.00 when re-measured with 31 rounds.
- **Trap output is byte-identical.** Four checks cover this:
  - the 45-program trap corpus in 5 build modes against `main`;
  - a 101-case reduction harness against both `main` builds (LLVM and QBE);
  - two new CLI tests that compare LLVM with QBE;
  - C-harness adapter tests that compare the rewritten loop with the
    unrewritten one and with a C reference.

**Acceptance:**

| criterion | result |
|---|---|
| `bytes_scan` ≤ 1.0× Zig, with branch misses near Zig's | **0.37×**. Branch misses fell from 1.40 to **0.02** per 1,000 instructions (Zig: 0.00). Branches fell from 16.8× Zig's to 0.5×. |
| `list_append_sum` improves | 1.20× → 1.16×, paired 0.953 [0.932, 0.980]. The sum loop is now vectorized. The append loop (a call on its slow path) is left. |
| reduction loops in `nbody` and `spectral_norm` improve | `nbody` paired 0.847 and `spectral_norm` 0.852. Their float reductions stay scalar (strict FP, §1). What improved is the header reloads and bounds checks around them. |
| branches and instructions fall | e.g. `matmul` instructions 6.35× → 0.34× Zig; `nbody` branches 195× → 85×; `bytes_scan` instructions 1.20× → 0.33× (table in §4) |
| nothing slower | met (§4) |
| trap output byte-identical, LLVM LTO and QBE | met (§5) |
| `test-llvm-adapter` green, with new tests for each rewrite | 44 tests: 11 new, 1 updated (§6) |

## 1. Census: what blocked the vectorizer

**How the census was taken:**
- *Builds.* Each suite program and micro-kernel was built through the
  release pipeline: LLVM O3, full LTO, frame map.
- *LTO remarks.* A `zig` wrapper (`zigwrap.sh`) adds these flags to the LTO
  link's `ld.lld`:
  - `--opt-remarks-filename`;
  - `--opt-remarks-passes loop-vectorize|licm|gvn|slp-vectorizer|loop-unroll`;
  - `--save-temps`.
- *Pre-link remarks.* The adapter's new `MYLANG_QBE_LLVM_REMARKS` hook records
  each unit's own pre-link remarks. A full-LTO pre-link compile already runs
  the loop vectorizer on a self-contained loop.
- *Loop census.* The post-LTO module (`*.0.4.opt.bc`) was split into natural
  loops (`census.py`, `loops.py`). For each innermost guest loop it records:
  - its exits, by the `myl_qbe_fail_*` helper each trap exit calls;
  - its calls and stores;
  - loads whose loop-invariant address LICM left inside;
  - header phis;
  - whether it is a vector body.
- *Remark summary.* `remarks.py` tallies the vectorizer's and LICM's missed
  reasons per program.

**Blockers.** B1 to B4 are adapter-side and are fixed.

| # | blocker | how it shows | where | now |
|---|---|---|---|---|
| B1 | **Overflow-check exit.** A checked `+=` is a branch to a block that calls `myl_qbe_fail_overflow_op`. The vectorizer rejects a loop exit whose block has a call (`TooManyUncountableEarlyExits`, `CantComputeNumberOfIterations`, `NoInductionVariable`). A conditional `count += 1` stays a data-dependent branch: `bytes_scan` ran 1.40 branch misses per 1,000 instructions. | the sums and counts in `bytes_scan`, `sieve`, `list_append_sum`, `list_records` | **fixed** where the checks decide nothing else (§3); the fast copy vectorizes |
| B2 | **Element address is `inttoptr` of an integer sum.** Scalar evolution does not look through `inttoptr`, so `data[i]` is an unknown pointer every iteration: no consecutive access and no dependence distance. Even `--unchecked` `bytes_scan` vectorized only by **gathering** one byte per lane (`vpinsrb` ×4 per vector) and ran at 1.39× Zig. | every element loop | **fixed** (§2.1): unchecked `bytes_scan` 1.39× → 0.37× |
| B3 | **Header, storage word and row pointers reloaded every iteration.** A store into element storage and a load of a container header were both just "foreign", so LICM kept neither `len(xs)` nor `xs`'s storage word, nor a list of lists' row pointers, across the store (`LoadWithLoopInvariantAddressInvalidated`: 86 in `matmul`, 115 in `fannkuch_redux`, 63 in `nbody`). Because the length is reloaded, every bounds check stays in the loop. | `matmul` (4 bounds exits per element), `fannkuch_redux`, `sort_quick`, `spectral_norm` | **fixed** (§2.2) |
| B4 | **Record read-modify-write through an unannotated copy.** `bodies[i].vx = …` copies the element to frame scratch and back (`blit`). The copy carried no alias metadata because its two ends are different classes, and a copy source reloaded from an operand-stack slot two blocks later was not placed at all. After SROA, the copy's element stores alias every header load. | `nbody`: 12 bounds exits and a length reload per body pair | **fixed** (§2.2) |
| B5 | **Bounds checks the loop bound does not imply.** `j < n` says nothing about `len(c[i])`. | `matmul`, `nbody`, `sieve`, `fannkuch_redux` | emitter-side loop facts (the parallel lane). Once B3 is fixed, LLVM versions `matmul`'s loop itself, because the lengths are invariant. |
| B6 | **Checks inside a callee LLVM inlines at LTO.** `spectral_norm`'s four overflow checks live in `a(i, j)`, a separate unit, and `c = mix(c, v)` in `sort_quick` is the same. A per-unit rewrite of the IL never sees these checks in a loop. | `spectral_norm`, `sort_quick`, `records`, `calls` | **left** (§8) |
| B7 | **Strict floating-point reduction.** `s = s + a * v[j]` cannot be reordered without fast-math, which would change results. | `spectral_norm`, `matmul`'s sums, `nbody`'s energy | left; Zig does not vectorize these either |
| B8 | **A value that may wrap decides control, or a loop-carried recurrence.** Examples: `total = (total + v) % M`, whose floor-mod adjustment branches on the sum; `x = x * 0.999 + sqrt(i)`; a `while` counter `j += i` that is also the exit test and the index. | `intloop`, `alloc_churn`, `float_loop`, `sieve`'s inner loop | left; the sticky rewrite declines these (§3) |
| B9 | **Calls in the loop:** the append slow path, `sqrt`, text and dictionary helpers (`CantVectorizeLibcall`). | `list_append_sum` append, `knucleotide`, `text_ops`, `dict_count`, `raytrace`, `nbody`, `float_loop` | left |
| B10 | **Strided stores:** `flags[j] = False; j += i`. | `sieve` | left |

**Checked and ruled out:**
- *`nomerge` on calls, `"disable-tail-calls"` and `uwtable`* (`QBE-FRAMEMAP-1`).
  No remark in any program mentions them. They apply to calls, and every loop
  that contains a call is already blocked by the call itself (B9). Trap calls
  sit in exit blocks, which the fast copy (§3) never enters.
- *The frame map's pseudo-probes* live only in the discriminators of call
  locations. No loop contains an `llvm.pseudoprobe` block probe.
- *Frame records and position stores.* Fast builds link neither, so there are
  no frame-position stores in loops.
- *`sqrt`'s `errno`.* LLVM models it as `errnomem`. A header load is 8 bytes,
  so it cannot alias an `int`, and `sqrt` clobbers nothing this code loads.

**Hot loops, before and after** (post-LTO IR):

| program | hot loop | before | after |
|---|---|---|---|
| `bytes_scan` | `if data[i] == 109: count += 1` | 4 blocks; `count == MAX` trap exit; data-dependent branch | fast copy is branch-free and vectorized: `vpcmpeqb` on 16 bytes per iteration, 4 × `<4 x i64>` accumulators (§3) |
| `list_append_sum`, `list_records` | `for v in values: total += v` | `sadd.with.overflow` → trap exit | vectorized: `<4 x i64>` × 2 with the magnitude sums |
| `sieve` | final count (as `bytes_scan`), sieving loop | count: B1; sieve: B5, B8, B10 | count vectorized; sieving loop unchanged |
| `matmul` | `c[i][j] = c[i][j] + aik * b[k][j]` | 5 blocks; 4 bounds exits; row pointer, length and storage word of `c[i]` and `b[k]` reloaded every element (B3) | the lengths are invariant, so LLVM turns the bounds tests into a trip-count bound, adds a runtime alias check between the two rows and runs **4 × `<4 x double>` per iteration** |
| `nbody` | `advance`'s pair loop | 13 blocks; 12 bounds exits; length reloaded after every field store (B4) | 3 blocks, 2 bounds exits; −33% instructions, −56% branches. 5 bodies, `sqrt`, AoS: not a vector loop. |
| `spectral_norm` | `s = s + a(i, j) * v[j]` | 6 blocks: 4 overflow exits (from inlined `a`), 1 bounds exit with the length reloaded | the bounds check is gone (the length is invariant and `j < n = len(v)`); −15% instructions; B6 and B7 remain |
| `fannkuch_redux` | the permutation loops | bounds exits; header reloads | −22% instructions; one copy loop vectorized |

## 2. Fixes to how the adapter lowers memory accesses

### 2.1 Element addresses as `getelementptr` (`LLVM-ELEMENT-GEP-1`)

- **What.** A load or store gets its address as `getelementptr i8, ptr
  (inttoptr base), offset…` instead of `inttoptr (add base, offset)` when all
  of the following hold:
  - the address operand is a singly-defined `add` emitted earlier in the same
    block;
  - the `add` chain reaches a singly-defined marked base (`# myl-obj` or
    `# myl-elem`);
  - at least one term of the chain is not a constant, which makes it an
    element access;
  - no temporary on the way is redefined between the sum and the access.
- **Why it is sound.**
  - The GEP is plain, not `inbounds`, so it is wrapping address arithmetic:
    the same bits as the integer sum, and no new fact.
  - Every operand is reloaded from its slot at the access. The rule proves
    that each slot still holds the value the sum used: each operand is singly
    defined, and none is defined in this block after the sum.
- **Why it is narrow.** The first version gave *every* marked `add` a GEP at
  its definition, and `nbody` ran **5.5× slower**:
  - InstCombine folds `ptrtoint(gep(inttoptr x, y))` back into `add x, y`.
  - The element address stored to a local and reloaded became `inttoptr` again.
  - A record copy then had one end as a GEP and the other as `inttoptr`, and
    LLVM could no longer tell that `memmove(p, p)` was a self-copy.

  So the integer `add` stays for every other reader, and a constant-offset
  header field and every `blit` keep the integer form. The shipped version is
  neutral on every program where it does not help (§4).
- **Effect.** `--unchecked` `bytes_scan` goes from 1.39× to 0.37× Zig: a
  gather becomes a wide load. In the checked build, on its own, it moved no
  program outside noise except `spectral_norm` (−4.5%): the checked loops were
  still blocked by B1 and B3. It is what lets the fast copies in §3 and the
  loops §2.2 frees load whole vectors.

### 2.2 Objects and element storage (`LLVM-ELEMENT-CLASS-1`)

**The emitter change** (in `src/qbe.zig`, `src/qbe_managed.zig` and `src/qbe_bytes.zig`):
- A new `Emitter.markElements(value, element)` prints
  `# myl-elem %v<N> <size><r|v>`: `r` when the element's layout copies by
  reference (a GC reference), `v` otherwise.
- The five sites that marked a *storage word* with `markObject` now call it:
  - `elementAddress`;
  - the backing pointer of `inlineAppend`;
  - the destination and source storage of the inline byte-buffer appends.
- It is a comment line, so QBE's assembly is unchanged.
- It is pinned by a `qbe_test.zig` test. `QBE-ALIAS-CLASS-1`'s count test now
  expects 5 `myl-obj` markers and 1 `myl-elem`.

**The adapter.** `MemoryClasses` refines the "foreign" class:
- **Seeds.** A `# myl-elem` temporary is `(ELEMENT, kind)`. Every other
  marked temporary is `OBJECT`.
- **Propagation.** A refined class travels through `copy` and offsetting
  `add` (as the coarse class does) and through simple slots (below). An `add`
  that combines two refined classes is a contradiction, and a contradiction
  drops the refinement for the whole unit.
- **Metadata.** Both new kinds of scope live in the unit's existing
  `distinct` domain:
  - object scope `!5`; its `!noalias` list names the frame scope and every
    element scope;
  - one scope per element kind; its `!noalias` names the frame scope, the
    object scope and every other kind's scope;
  - a plain foreign access (a parameter, a global, the context) keeps
    `!alias.scope !4, !noalias !3`, so it still aliases all of them;
  - up to 29 kinds per unit, which keeps the numbers clear of the frame-map
    nodes; more stay plainly foreign.

**Why it is sound:**
- *Objects and storage never overlap.* Every storage block is its own
  allocation (`myl_native_heap_alloc`/`_alloc_at`/`_extend`), and no object
  header or payload lies inside one. Emitted code writes a class body only
  through `qbe_alloc.cell` (marked as an object), and element storage only
  through the five marked storage words or runtime helpers, which carry no
  scopes. Even a container whose storage followed its own header in one
  block would be safe: element accesses start at the storage word and header
  accesses end before it, so the bytes they touch never meet.
- *Each block holds one element kind.* A block holds elements of one size and
  one kind, GC references or plain values. Nothing reinterprets a block as
  another kind:
  - a bytes snapshot or view shares storage only with another octet block;
  - text and bytes conversions copy;
  - a list of references can never be read as plain values (the collector
    traces it).

  The kind key is deliberately coarse: size plus reference-or-not. Two
  element types that could share a block always get the same key.
- *Freed and reused memory.* Storage freed and reused by another object is
  only reached across a call (a collection, a growth). Calls carry no scopes,
  so they order every access around them.
- *Placement is conservative.* A plain foreign access still aliases every
  refined class, and an unplaced access carries nothing.

**Two further changes were needed for `nbody` (B4):**
- *A must-analysis through simple slots.* `_through_slots` used to carry a
  class through a slot in two cases only: within one block, or when every
  store agreed and one store dominated every load. It is now a forward
  must-analysis over the CFG (`_slot_flow`).
  - A load answers the class that the last store put in the slot on every
    path that reaches it.
  - It answers nothing when two paths disagree, or when a path reaches the
    load before any store.
  - This covers both old rules, and also the operand-stack slot that carries
    a record's element address across the bounds check's branch. The coarse
    and refined classes use the same analysis.
- *Scopes on copies between two classes.* LLVM puts one scope list on a
  `memmove` for both its read and its write. So a copy between two placed
  classes now names the *union* of their scopes in `!alias.scope`, and the
  *intersection* of their "cannot alias" sets in `!noalias`.
  - This holds: the copy touches only those two classes' memory.
  - A copy from element storage to the frame and back is then no-alias with
    every header load.
  - An end the unit cannot place still gets no metadata.

**Effect** (instructions after/before, from the census builds):

| program | instructions | time |
|---|---:|---|
| `matmul` | 0.056 | 3.84× → 0.74× Zig |
| `fannkuch_redux` | 0.78 | |
| `nbody` | 0.67 | branches 0.44 |
| `spectral_norm` | 0.85 | |
| `sieve` | 0.84 | |
| `sort_quick` | 0.96 | |

## 3. Checked reductions with no branch per check (`LLVM-STICKY-REDUCTION-1`)

**Where it runs.**
- In the adapter, before emission, on the parsed QBE IL
  (`experiments/llvm-backend/sticky_loops.py`, called from `llvm_emit.translate`).
- The adapter is the right place because:
  - the rewrite needs nothing the emitter knows that the IL does not show;
  - it is LLVM-only by construction, since QBE never vectorizes;
  - it leaves the frontend, the QBE backend and every trap path untouched;
  - it composes with the parallel lane's loop facts: any check that lane
    removes simply leaves one fewer branch here.
- LLVM itself cannot do the rewrite, because the adapter cannot insert a pass
  into the LTO pipeline.

**The rewrite.** It applies to each innermost natural loop of a unit:
1. **Classify the checks.** A `jnz` one of whose targets is a trap block (only
   `dbgloc`, one `call $myl_qbe_fail_*`, `hlt`) is a check. Its operation is
   the `add/sub/mul` in the same block whose operands are the fail call's
   operands.
   - An overflow check of a 64-bit signed `add`/`sub` whose left operand
     (either operand for `add`) is a value some frame cell R held, where every
     store to R's allocation in the loop is a `storel` to R of such a
     result, is a **reduction site**. "Held" and "result" are found by a
     forward must-analysis over temporaries and frame cells, which follows
     the operand-stack shuffles across blocks.
   - Any other overflow check is **sticky**.
   - Every other check (bounds, cast, division, iteration guard, allocation)
     is **kept**.
2. **Taint.** A forward dataflow tracks, per temporary and per frame
   allocation, which dropped checks' possibly-wrapped values may reach it.
   The seeds are the sticky and reduction operations' results and the
   reduction cells at the header.
   - A *hazard* is a tainted value reaching any of these:
     - a `jnz` that is not a check;
     - a load or store address;
     - a shift amount;
     - a divisor (or a dividend with a divisor other than a nonzero constant
       ≠ −1);
     - a float-to-integer conversion;
     - a store into a frame cell whose address escapes.
   - A hazard demotes exactly the checks that reach it: they become kept.
     Then the analysis runs again, until no hazard remains.
3. **Decline** a loop that contains any of the following, or in which nothing
   is left to drop:
   - a call, a `blit` or a phi;
   - a store outside this activation's `alloc` cells;
   - a temporary live across the loop boundary;
   - the entry block as its header;
   - an exit target that starts with a phi.
4. **Rewrite.**
   - The loop's entry edges go to `@skN.entry`. It saves every frame cell the
     loop writes and zeroes the bookkeeping: the sticky word, an iteration
     counter, and a high and a low magnitude sum per reduction cell.
   - A clone of the loop follows, with every temporary renamed:
     - the header counts iterations;
     - a sticky check becomes `sticky |= flag` and falls through;
     - a reduction check becomes `hi += |x| >> 32; lo += |x| & 0xFFFFFFFF`
       (nothing, for a literal `x`) and falls through;
     - a kept check branches to `@skN.fallback` instead of its trap.
   - Each normal exit goes through `@skN.exit.*`, which verifies (below) and
     then continues or falls back.
   - `@skN.fallback` restores the saved cells and jumps to the **original
     loop header**. The original loop is unchanged, including its trap blocks
     and their `dbgloc` positions.

**The verification** at every normal exit. With `c` the iteration count,
`R0` the saved entry value, and `K` the sum of the magnitudes of the literal
operands, all of these must hold, each computed without wrapping in unsigned
64-bit IL:
- `sticky == 0`;
- `c · (number of variable sites) < 2^32`, so the low sums cannot wrap;
- `hi < 2^31`;
- `lo ≤ 2^63 − 1`;
- `c ≤ (2^63 − 1) / K`;
- `|R0| + (hi << 32) + lo + c·K ≤ 2^63 − 1`.

**Why passing the verification means the fast copy computed exactly the
checked loop's results.**
- Until the first operation whose check the original would have trapped on,
  the two executions are the same instruction for instruction: a dropped
  branch is one the original did not take.
- Suppose that first failing operation is a **sticky** one. Its flag is
  exact, so it is OR-ed into `sticky`, and `sticky` is only ever OR-ed.
  Verification fails.
- Suppose it is a **reduction** update of R. Every value R took before it was
  exact. By induction, each value R takes, and each update result, is at most
  `|R0| + Σ|x|` over the updates run so far, because each is some earlier
  value of R plus or minus one `x`. This update overflowed, so that bound
  already exceeds `2^63 − 1`. The fast copy keeps adding every later `|x|`
  exactly, with no wrap under the per-iteration limits, so the final sum is
  larger still. Verification fails.
- Otherwise no check the original would have trapped on ever fired, and every
  value is the checked loop's value.

**Why the fast copy is harmless when it runs past an overflow before falling
back.**
- *It terminates.* No wrapped value reaches a branch other than a check, so
  every exit decision is the original's.
- *It cannot fault.* No wrapped value reaches an address; the kept bounds
  checks guard every element access; divisors are safe.
- *It computes no poison.* Shift amounts and float-to-integer conversions are
  untainted, and the adapter emits no `nsw`/`nuw`.
- *It has no visible effect.*
  - It makes no call and stores only this activation's frame cells.
  - The fallback restores those cells.
  - No wrapped value lands in a cell whose address escaped, so no other
    route can read one.
- The original loop then runs from the loop-entry state and traps (or not)
  exactly as before: same code, operands, message, `in f at file:line`
  trace, `MYLANG-TRAP` record and exit status.

**Costs and limits:**
- A loop whose reduction magnitudes exceed the bound without the sum
  overflowing runs twice: once fast, once checked. Such sums have mixed-sign
  terms near 2^63.
- So does a loop with more than about 4 billion iterations in one execution,
  or any loop that traps.
- Same-sign sums never fall back unless the program traps.
- Code size: each versioned loop is cloned once.
- Build time: translating is about 30–50% slower in Python on small units.
  The cold build of `selfhost/lexer.my` (45 units) spent 2.35 s in codegen,
  against 2.37 s on `main`, because the units compile in parallel and
  `zig cc` dominates.

**Where it applies today** (verdicts, `MYLANG_QBE_LLVM_STICKY_LOG`):

| program | loop | verdict |
|---|---|---|
| `bytes_scan` | the count | versioned: 1 reduction (literal), 2 kept |
| `list_append_sum`, `list_records` | the sum | versioned: 1 reduction, 4 kept (the counter's check decides the exit, and the iteration and bounds checks are kept) |
| `sieve` | the final count | versioned: 1 reduction, 4 kept |
| `text_ops` | one scan loop | versioned: 2 sticky |

- Every other loop in the suite makes a call, stores outside its frame, or
  has only checks that decide control or an address, for example
  `(total + v) % M` or a `while` counter.
- The test programs also exercise `total -= v`, `total += v * 3` (sticky
  multiply feeding a reduction), a sum through `values[i]` with Python's
  negative-index normalization (kept), and a bytes scan.

The code LLVM makes of the `bytes_scan` fast copy, once the count check is
gone and the index is a GEP:

```text
vmovd  (%r9,%r10,1),%xmm7 ; … ×4          # 16 bytes per iteration
vpcmpeqb %xmm2,%xmm7,%xmm7
vpmovzxbq %xmm7,%ymm7 ; vpand %ymm1,%ymm7,%ymm7
vpaddq %ymm7,%ymm3,%ymm3 ; … ×4
add $0x10,%r10 ; cmp %r10,%rsi ; jne …
```

## 4. Numbers

**Method:**
- *Hardware.* CPU 8 (its SMT sibling is CPU 9) on the i7-12700H. Each
  benchmark records its sibling's busy fraction; the machine was shared.
- *Separate batches.* `bench/parity/bench_parity.py`, 9 rounds, two batches
  run back to back:
  - after: this branch's ReleaseFast install;
  - before: `install-main`, `35fcbc02`.

  Each batch has its own Zig arm, so each ratio is same-batch. Files:
  `results/bench-lane.*` and `results/bench-base.*`.
- *Paired batch.* `experiments/perf-parity-plan-20260922/bench.py` with the
  two sets of prebuilt binaries as arms, 11 rounds, arms shuffled every round
  (`results/paired.json`). Programs whose interval was wide were re-timed
  with 31 rounds (`results/paired-31.json`).

**Time and counters.** The counters are from `perf stat` pinned to CPU 8.

| group | program | before ×Zig | after ×Zig | `--unchecked` ×Zig | after/before, paired [95% CI] | instructions my/zig, before → after | branches my/zig | branch misses/ki, my (zig) |
|---|---|---:|---:|---:|---|---|---|---|
| suite | matmul | 3.84 | **0.74** | 0.64 | **0.208** [0.205, 0.212] | 6.35 → **0.34** | 36.1 → **0.9** | 0.08 → 0.09 (0.05) |
| suite | nbody | 1.81 | **1.60** | 1.55 | **0.847** [0.414, 0.863] | 3.71 → 2.50 | 194.9 → 85.0 | 0.00 → 0.00 |
| suite | sieve | 1.77 | **1.54** | 1.44 | **0.864** [0.840, 0.911] | 4.13 → 3.44 | 5.5 → 4.6 | 2.02 → **0.01** (0.01) |
| suite | fannkuch_redux | 1.14 | **0.98** | 0.88 | **0.864** [0.807, 0.921] | 1.75 → 1.35 | 2.8 → 2.5 | 5.52 → 7.04 (9.18) |
| suite | spectral_norm | 1.17 | **1.10** | 1.00 | **0.852** [0.841, 0.891] | 1.89 → 1.61 | 24.0 → 20.0 | 0.02 → 0.02 |
| suite | sort_quick | 1.25 | 1.19 | 1.06 | **0.919** [0.907, 0.935] | 1.31 → 1.26 | 4.1 → 4.1 | 17.3 → 18.2 (21.5) |
| suite | binary_trees | 0.50 | 0.53 | 0.45 | 0.984 [0.793, 1.160] · identical binary | 0.81 → 0.81 | | |
| suite | knucleotide | 1.40 | 1.46 | 1.43 | 1.001 [0.994, 1.007] (31 rounds) | 1.85 → 1.85 | | |
| suite | mandelbrot | 1.03 | 1.02 | 1.04 | 1.009 [0.980, 1.063] | 0.93 → 0.93 | | |
| suite | raytrace | 1.35 | 1.40 | 1.26 | 1.000 [0.974, 1.027] · identical binary | 2.15 → 2.15 | | |
| suite | sort_builtin | 0.53 | 0.52 | 0.51 | 0.996 [0.953, 1.018] | 0.79 → 0.79 | | |
| suite | sort_records | 0.27 | 0.26 | 0.27 | 1.009 [1.000, 1.019] | 0.24 → 0.24 | | |
| suite | text_ops | 3.64 | 3.59 | 3.52 | 1.003 [0.866, 1.109] | 5.18 → 5.18 | | |
| lib | scan_count | 1.01 | 0.65 | 0.64 | 0.997 [0.987, 1.005] | 0.95 → 0.95 | | |
| lib | scan_replace | 0.33 | 0.34 | 0.35 | 1.038 [0.990, 1.041] · identical binary | | | |
| lib | scan_split | 2.96 | 3.08 | 3.04 | 1.002 [0.964, 1.091] | 7.19 → 7.14 | | |
| micro | bytes_scan | 1.33 | **0.37** | 0.37 | **0.278** [0.277, 0.282] | 1.20 → **0.33** | 16.8 → **0.5** | 1.40 → **0.02** (0.00) |
| micro | list_append_sum | 1.20 | **1.16** | 1.12 | **0.953** [0.932, 0.980] | 2.39 → 1.84 | 1.9 → 1.0 | 0.01 → 0.02 |
| micro | list_records | 1.40 | **1.31** | 1.23 | **0.932** [0.913, 0.987] | 3.32 → 1.85 | 6.8 → 0.8 | 0.02 → 0.04 |
| micro | alloc_churn | 1.95 | 1.98 | 1.97 | 0.977 [0.953, 0.995] | 3.60 → 3.60 | | |
| micro | calls | 0.98 | 1.04 | 1.03 | 0.999 [0.967, 1.153] · identical binary | | | |
| micro | dict_count | 1.10 | 1.05 | 1.02 | 1.001 [0.986, 1.012] (31 rounds) | 1.20 → 1.20 | | |
| micro | fib | 2.10 | 2.13 | 1.05 | 0.997 [0.983, 1.009] (31 rounds) · identical binary | | | |
| micro | float_loop | 1.00 | 1.01 | 1.01 | 0.990 [0.971, 1.100] | | | |
| micro | intloop | 0.93 | 0.94 | 0.94 | 1.017 [0.902, 1.069] | | | |
| micro | records | 0.93 | 0.94 | 1.05 | 0.983 [0.941, 1.010] | | | |
| micro | str_build | 1.17 | 1.16 | 1.14 | 1.012 [0.980, 1.040] · identical binary | | | |
| | **suite geomean** | **1.20** | **1.02** | 0.96 | | | | |
| | **micro geomean** | **1.23** | **1.09** | 1.02 | | | | |
| | paired geomean, 27 programs | | | | **0.877** | | | |

**No regressions.**
- Six programs that read slower in one of the batches link byte-identical
  executables before and after: `fib`, `calls`, `scan_replace`,
  `binary_trees`, `raytrace` and `str_build`. For these the batch-to-batch
  noise is 2–8%.
  - The `binary_trees` lane batch ran with CPU 9 39% busy.
  - Zig's own times differ by up to 1.5× between the two batches: the
    `binary_trees` reference was 334 ms in one and 230 ms in the other.
- The two programs whose binaries do differ and that read slower in the
  11-round batch (`dict_count`, `knucleotide`) are **1.001** at 31 rounds.
- `scan_count` 1.01 → 0.65 is the Zig arm's noise between the two batches.
  Paired, it is 0.997.

## 5. Trap evidence

- **Corpus.** The 39 programs of the checked-arithmetic lane's corpus, plus 6
  new ones that trap inside or around versioned loops:
  - `sticky_sum_trap`, `sticky_count_trap`, `sticky_scaled_trap`,
    `sticky_octets_trap`;
  - `sticky_then_bounds`: an overflow the fast copy defers, then a bounds
    error later in the same loop, which must report the overflow;
  - `sticky_bounds_trap`: a bounds error in a versioned loop with no
    overflow.

  All ran in 5 modes (LLVM LTO, LLVM without LTO, `--gc-stress`,
  `--max-steps=5`, QBE) with `main` and with this branch, comparing stdout,
  stderr and exit status. **222 pairs identical.** The 3 remaining pairs are
  a build failure on `main` that this branch does not have (below).
  `results/trap-corpus-compare.log`.
- **Reduction harness.** `traps/reductions.my` runs 101 cases:
  - sums, indexed sums, scaled sums, differences, conditional counts and a
    bytes scan;
  - at, just below and just past each bound, from both ends of the range;
  - 48 of them trap.

  `main` LLVM, this branch's LLVM and `main` QBE are identical on all 101
  (`traps/compare.py`).
- **In the gate:**
  - `test/integration.zig` "checked reduction loops sum and trap the same from
    the LLVM fast copy as from QBE" (`// spec: LLVM-STICKY-REDUCTION-1`):
    15 cases, plus one trap pinned in full (code, operands, two frames,
    record).
  - "element loops … compute and trap the same from LLVM as from QBE"
    (`// spec: LLVM-ELEMENT-GEP-1`): a matrix product over lists of lists,
    record fields updated in a list, a bytes scan, a float dot product, and a
    bounds trap in a prefix sum.
- **Adapter harness** (`test_adapter.StickyReductionTests`). The rewritten
  and the unrewritten loop are compiled side by side and checked against a C
  reference of the checked loop, which uses `__builtin_add_overflow`. They
  must agree on result, trap, and trap operands:
  - 19 sum cases (mixed signs, `INT64_MIN`, sums that overflow and come back,
    counts past `2^40` magnitudes);
  - 10 count cases.
- **A base bug found on the way.** `main` cannot build `sticky_bounds_trap.my`
  or `sticky_then_bounds.my` with the default LLVM LTO. It fails with "a call
  site's frame-map position names another guest function than the one it was
  compiled into". This branch builds the second one and not the first. The
  bug is in the frame-map annotation, not in this lane; it was filed as a
  separate task.

## 6. Tests and SPEC

- `SPEC.md`: three new bullets, `[LLVM-ELEMENT-CLASS-1]`,
  `[LLVM-ELEMENT-GEP-1]` and `[LLVM-STICKY-REDUCTION-1]`.
- `src/qbe_test.zig`:
  - `// spec: LLVM-ELEMENT-CLASS-1` checks that a list of lists, a list of
    floats and a byte string mark `8r`, `8v` and `1v`;
  - the `QBE-ALIAS-CLASS-1` counts are updated.
- `test/integration.zig`: the two CLI tests of §5.
- `experiments/llvm-backend/test_adapter.py`, now 44 tests (33 before):
  - **`StickyReductionTests`:**
    - the sum and the count are versioned, and `MYLANG_QBE_LLVM_STICKY=0`
      turns it off;
    - the two C harnesses of §5;
    - both fast copies vectorize at O3;
    - five declines: a store outside the frame, a call, the total deciding a
      branch, the total addressing memory, the total passing through an
      escaping cell;
    - a reset total stays sticky rather than a reduction.
  - **`ElementAddressTests`:**
    - the GEP form, and that it can be switched off;
    - another block keeps the integer form;
    - the object and element scopes, and two kinds excluding each other;
    - a contradiction drops the refinement;
    - an executed element program;
    - a byte scan loads vectors only with the GEP form.
  - The existing `QBE-ALIAS-CLASS-1` metadata test is updated: the marked
    header is an object now.
- `build.zig` installs `sticky_loops.py` beside `qbe_llvm.py`, because an
  installed compiler imports it.

## 7. Gate

The gate ran on commit `c452983c`, under `slot.sh gate`. Each step was
compared with the coordinator's green base logs (`tmpfix-*.log`) using
`gate_diff.py`:

| step | result | gate_diff |
|---|---|---|
| `zig build test` | green: 81/81 steps, 1781 tests passed; `test-llvm-adapter` ran 44 | no new failure (base 0, lane 0) |
| `zig build test-qbe` | green: 50/50 steps, 311/311 | no new failure |
| `zig build test-qbe-build` | green: 32/32 | no new failure |
| `zig build test-schematic` | green: 29/29 | no new failure |
| `zig build test-byte-io` | green: 28/28 | no new failure |
| `zig build fmt-check` | green | — |
| Guardian | 88/88, and 88/88 whole-tree in the commit hook | — |

Every step has one step more than the base. That is the new install of
`sticky_loops.py`.

## 8. What is left

- **B6, checks inside an inlined callee.** `spectral_norm`'s `a(i, j)`,
  `sort_quick`'s `mix`, `records` and `calls` keep their overflow branches
  after LTO inlines them into the loop. A per-unit IL rewrite cannot see
  them. Two ways out:
  - an IL-level inliner for small pure leaf units into the *fast copy only*.
    The fallback keeps the real call, so traces are unchanged; the callee's
    IL would have to travel through the signature sidecar;
  - a range fact from the parallel lane that removes the checks outright.

  `spectral_norm` would still keep its strict float reduction (B7).
- **B5, bounds checks the loop bound does not imply.** This is the parallel
  lane's. Where the lengths are now invariant (after §2.2), LLVM already
  versions the loop by trip count (`matmul`). `nbody`'s and `sieve`'s checks
  remain.
- **Implicit flows.** A branch on a possibly-wrapped value that cannot affect
  termination (the floor-mod adjustment in `(total + v) % M`) makes the loop
  decline. Admitting it needs control-dependence taint: a hammock region with
  no exit, whose definitions become tainted. The payoff is small: those loops
  carry a recurrence and would not vectorize.
- **Unsigned and narrower reductions** (`u64`, `i32` counters) are sticky,
  not reductions. Their running value then makes an OR chain rather than a
  vectorizable sum.
- **`--unchecked`** builds have no overflow checks, so §3 does nothing there.
  §2 applies to them (`bytes_scan` unchecked 1.39× → 0.37×).
