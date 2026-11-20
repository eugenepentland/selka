# Fact certificates (design, package C7.0 of the 2026-10-26 plan)

This is the fixed reference for packages C7.1–C7.4 of
`docs/audits/ownership-certificates-plan-2026-10-26.md` (§7.1) and for the Lean lane
(C7.3). It defines:
- what a fact certificate states, and which of the compiler's facts it covers;
- the transfer rule of every integer operation in its checked, wrapping and proven forms;
- branch-edge refinement, and the one-trip rule for loops;
- the checks F1–F8 the validator makes;
- the theorem the Lean model proves, and the trusted assumptions;
- the text format `fact-certificate-v1`.

It follows `ownership-certificates.md` in structure and in method: the compiler writes
down what it believes, a small checker that shares no code with the producer re-derives
it, and the Lean model proves the checker sound. C7.1 and C7.2 may refine a rule where
`facts.zig` or the emitter does something this document did not anticipate. Every such
change is recorded in §11, and the Lean model follows it. The theorem in §7 is not
weakened without Claude's approval.

## 1. Where the certificate applies

Facts exist only in optimizing builds (`--release`, the default optimized debug build and
`--optimize-debug`, with trusted facts, and `--verify-facts`, which computes the same facts
and keeps every check). A
debug build has no facts and no certificate.

The certificate describes the **final IR and the final fact tables**: the module and
`Facts` as `emit_llvm` receives them, after every pass that reads or writes facts:
- `facts.analyze` (ranges, list facts, length bounds, reachability, and `mark`, which
  turns checks into `proven` and folds decided comparisons);
- `byte_index.forward` and `version.versionReductions` / `versionBounds`, after each of
  which `facts.analyze` runs again on the changed function;
- `index_checks.run`, which marks a bounds check `proven` because a dominating access
  already made it (the key analysis of `index_keys.zig`);
- `forward.ranges` and `extend` in `passes.zig`, which add intervals to forwarded values
  and grow the tables over instructions added after the analysis.

A function has one certificate whatever pass wrote a fact. Two **inter-procedural**
tables are derived from the whole module and are part of the certificate of every
function that uses them: the parameter intervals (`passes.parameterRanges`: the hull of
what the callers pass) and the return intervals (`facts.returnRange`), and a third is
**whole-program**: the integer intervals of record fields (`fields.zig`).

### 1.1 What reads a fact

A fact is dangerous exactly where something stops checking it. The readers are:

| Reader | Uses | If the fact is wrong |
| --- | --- | --- |
| `emit_llvm` `proven` | no guard for an overflow, shift count, division, conversion, or bounds check; `nsw`/`nuw`; `udiv`/`urem` | undefined behaviour, or an access out of bounds |
| `emit_llvm` `loadRange`, `fitsI32`, `fitsU32`, `nonNegative`, narrowed division | `!range` metadata; 32-bit arithmetic; masks | LLVM undefined behaviour, a truncated value |
| `mark` with `fold` | a comparison the ranges decide becomes `iconst bool`; the branch on it folds | an executed path is dropped |
| `promote.zig`, `destination.zig`, `own.zig` (`reserveFills`) | list capacities from a fill loop's bound; a stack list; a reserved push | a write past the allocation |
| `vector.zig` | a vectorization plan from a counted loop | a wrong trip count |

The certificate states every fact these readers use (§2), so a reader cannot rely on
anything the checker has not seen. What the readers do with a *valid* fact is
the emitter's job and is assumption A5 (§8).

### 1.2 What the certificate does not cover

- That a pass preserved the program's meaning (ownership, forwarding, inlining,
  loop versioning): the certificate is of the *final* IR, so a pass that changes the IR
  after the facts is covered only if the facts still hold of what it produced.
- Anything the emitter does with a valid fact beyond §1.1's table (A5).
- A function the exporter cannot describe; it is named, counted, and its facts are not
  used as certified.

## 2. What the certificate states

A certificate describes one **module** of functions (the whole program in a release
build). For each function it states the following.

### 2.1 Value intervals

`range(v) = [lo, hi]` for an integer or boolean value `v`: every execution of `v`'s
definition produces a value in the interval. `lo <= hi`, and the interval lies in the
**type range** `R(t)` of `v`'s type: `[-2^(n-1), 2^(n-1)-1]` for `iN`, `[0, 2^n-1]` for
`uN`, `[0, 1]` for `bool`. A value that has no stated interval is claimed to lie in `R(t)`.

A *value* here is the integer the instruction yields: for a wrapping operation, the value
after wrapping; for a checked one, the exact result (the operation traps when that is not
in `R(t)`); for a proven one, the exact result (§4).

`copy` instructions are resolved first (`Function.resolve`): a `copy` is its operand.

### 2.2 Reachability

`dead(b)` for a block `b`: no execution enters `b`. Every block not stated dead is only
claimed to be reachable, which is no claim.

### 2.3 Parameters and returns

- `param(k) = [lo, hi]`: in every call of this function, argument `k` lies in the interval.
  Only a function with `internal` linkage whose address is never taken (`func_ref`) has
  one; a function anyone else can call has the type range.
- `ret = [lo, hi]`: every value the function returns lies in the interval.
  `facts.returnRange` states the hull of each reached `ret` operand's view at its block (§5.2): its
  interval narrowed by the branch edges that dominate the block, so a returned parameter that an `if`
  bounds, or an `@ensures` on the result, narrows it (proof steps S2, 11 November 2026). That view is
  the one the return check below reads, so the claim is the same kind as before, only narrower.

### 2.4 List facts

For a value `v` of list type:
- `len(v) = [lo, hi]`: the list has between `lo` and `hi` elements wherever `v` is used;
- `elements(v) = [lo, hi]`: every element of it lies in the interval (integers and bools);
- `length(v) = L` (a **fill length**): `v` is the loop phi of a counted fill loop (§5.5)
  or derives from one, and has `max(L, 0)` elements once the loop has exited;
- `bound(x) = (p, strict)` for an integer value `x` and a list parameter `p`:
  `x <= len(p)`, or `x < len(p)` when `strict`.

### 2.5 Other facts

Record-field intervals (`fields.zig`), dictionary lengths and hulls, and `f64` intervals
are stated too. They are **stage 2**: the validator accepts them as assumptions
(§8, A6) and counts what rests on them, and the Lean model adds their rules after the
integer rules (§9).

### 2.6 Uses

For each `proven` instruction, the **site**: the intervals of its operands as the facts
saw them where the instruction runs (§5.2), which is the reason the check cannot fail
(§6, F7). For each fact a reader above consumes (`!range`, `fitsI32`, a folded
comparison), the value interval it reads, which is §2.1's: a reader cannot read a fact
that is not stated.

## 3. Abstract values

Everything is a mathematical integer; `R(t)` bounds each value by its type.
An **interval** is `[lo, hi]` with `lo <= hi`. `x ∈ [lo, hi]` means `lo <= x <= hi`.
`hull`, `meet` and `within` are the usual ones: `meet` may be empty, which is a fault of
the certificate unless the block is dead.

A **base interval** `base(v)`:
- `iconst`: the point `{c}`, `c` read with the type's signedness;
- `param`, `call`: the stated interval, else `R(t)`;
- `undef`, `union_payload`, `union_take`, `record_take`, `box_take`: `R(t)`;
- anything else: the stated interval; none stated is `R(t)`.

## 4. Operations in their three forms

An integer operation carries `check ∈ {none, exact, proven}` (`ir.Check`):
- **none** (*wrapping*): the operation wraps modulo `2^bits`, and cannot trap;
- **exact** (*checked*): it traps when the exact result is outside `R(t)`; otherwise the
  result is exact;
- **proven**: the emitter emits no guard (`nsw`/`nuw` arithmetic, `udiv`/`urem`, a shift
  with no count check, a list access with no bounds check). The result is the exact result
  **if** the facts are right; otherwise the behaviour is undefined (F7).

`x`, `y` below are the intervals of the operands **at the instruction's block** (§5.2),
`R = R(t)`, and `full` stands for `R`. A missing operand interval is `R(t_operand)`.

| Op | Result interval (transfer) | `proven` is implied when |
| --- | --- | --- |
| `iconst c` | `{c}` | — |
| `add`, `sub`, `mul` | let `e` be the exact interval (`x+y`, `[x.lo-y.hi, x.hi-y.lo]`, or the hull of the four products, saturating at the `i128` bounds); `e` if `e ⊆ R`; else `R` when `check = none` and `e ∩ R` when checked | `e ⊆ R`, and for an unsigned type also `x.lo >= 0 ∧ y.lo >= 0` (the `nuw` flag is for the operands' own signedness) |
| `saturating_add` | `[clamp(x.lo+y.lo, R), clamp(x.hi+y.hi, R)]` | — |
| `shift_right` | if `y ⊆ [0, bits-1]`: `[min(x.lo>>y.lo, x.lo>>y.hi), max(x.hi>>y.lo, x.hi>>y.hi)]`, else `R` | `y ⊆ [0, bits-1]` |
| `shift_left` | `R` | `y ⊆ [0, bits-1]` |
| `floor_div`, `div` | if `y.lo > 0 ∧ x.lo >= 0`: `[⌊x.lo / y.hi⌋, ⌊x.hi / y.lo⌋]`, else `R` | `x.lo >= 0 ∧ y.lo > 0` (`udiv`) |
| `floor_rem` | if `y.lo > 0`: `x` when `0 <= x.lo ∧ x.hi < y.lo`, else `[0, y.hi-1]`; else `R` | `x.lo >= 0 ∧ y.lo > 0` (`urem`) |
| `rem` | if `y.lo > 0 ∧ x.lo >= 0`: `[0, min(x.hi, y.hi-1)]`, else `R` | `x.lo >= 0 ∧ y.lo > 0` |
| `neg` | `R` | unsigned: `x = {0}`; signed: `x.lo > R.lo` |
| `bit_xor` | if `x.lo, y.lo >= 0`: `[0, 2^k-1] ∩ R` with `k` the bit length of `max(x.hi, y.hi)`, else `R` | — |
| `convert` | if `check = none ∧ x ⊄ R`: `R`; else `x ∩ R` | `x ⊆ R` |
| `float_to_int` | the truncation of the operand's float interval, when it lies in `i64` and in `R`; else `R` | the truncated interval `⊆ R` (stage 2) |
| `cmp pred` | `{1}` or `{0}` when the operand intervals decide `pred`; else `[0, 1]` | — |
| `not` | `[1 - x.hi, 1 - x.lo]` | — |
| `list_len` | `len(a)` meet `[0, M]`; else `[0, M]` | — |
| `str_len`, `dict_entries` | `[0, M]` | — |
| `dict_len` | the dictionary's `len`, else `[0, M]` | — |
| `list_get`, `array_get` | `elements(a)`, else `R` | the access is in bounds (F7, §6.2) |
| `call f` | `ret(f)` meet `R`, when `f` is a direct call to a module function with a stated return; else `R` | — |
| `phi` | §5.3 | — |
| every other op | `R` | — |

`M = max_list_length = 2^47` (`target.zig`), the largest list or string the address
space holds (A2). Decision of `cmp`: `lt` is true when `x.hi < y.lo` and false when
`x.lo >= y.hi`; `le` true when `x.hi <= y.lo`, false when `x.lo > y.hi`; `gt`, `ge` are the
mirror images; `eq` is true when both are the same point, false when the intervals are
disjoint; `ne` is the negation.

`mul` and `saturating_add` of 64-bit operands do not overflow `i128` except in `mul`,
which saturates, and a saturated product is outside `R` by construction.

The **bounds checks** of list and array accesses (`list_get`, `list_get_field`,
`list_set`, `list_pop`, `array_get`, `array_set`) are `proven` by §6.2.

## 5. The inductive step

The facts are computed by a fixed-point iteration with widening. The certificate is not
the iteration; it is its **result**, and the validator checks that the result is an
**inductive invariant**: every stated interval contains what the rules derive from the
other stated intervals. No fixed point and no widening is replayed (§5.4).

### 5.1 Reachable blocks and live edges

The entry block is reachable. An edge `P → C` is **live** when `P` is not dead and, if `P`
ends in `branch c, T, F` with `T ≠ F`, `base(c)` is not the point 0 when `C = T`, nor the
point 1 when `C = F`. A block is dead only if every incoming edge is not live (F5).
(A `branch` on a folded `iconst bool` decides its edge the same way.)

### 5.2 The view of a value at a block

`at(v, B) = base(v) ∩ caps(v, B) ∩ ⋂ refine(e, v)`, over the **refining edges** `e` on the
dominator chain of `B`.

A block `C` has the refining edge `P → C` when `C` has exactly one predecessor `P`, `P`
ends in `branch c, T, F` with `T ≠ F`, and `c` is a `cmp`. The edge is *taken* when
`C = T` and *not taken* when `C = F`. Every block on the dominator chain of `B` (including
`B`) with such an edge contributes: any execution of `B` passed through the dominators,
each reached only through its single predecessor, so the comparison had the value that
selects the arm.

`refine(e, v)`, for `cmp pred l r`, with `pred` negated when the edge is not taken
(`eq↔ne`, `lt↔ge`, `le↔gt`):
- if `v` is neither `l` nor `r`: the **square rule**, below; otherwise
- put `v` on the left (`l < v` is `v > l`); let `o` be the other operand and `b = at(o, P)`,
  its view at the block `P` that holds the comparison (a dominating edge of `P` may bound
  it more tightly than its stated interval; `facts.zig` uses `base(o)`, which is never
  tighter, so this is the same refinement or a stronger one):
  `lt`: `hi := min(hi, b.hi - 1)`; `le`: `hi := min(hi, b.hi)`; `gt`: `lo := max(lo, b.lo + 1)`;
  `ge`: `lo := max(lo, b.lo)`; `eq`: meet with `b`; `ne`: no change.

The **square rule** (NEW-CORE-F1-OVERFLOW-2): if one operand of `pred` is a checked or
proven product `v * v` (`mul` with a check, both operands `v`) and the other is `y`, then on
an edge where `v * v <= y` or `v * v < y` or `v * v == y` holds, `|v| <= ⌊√top⌋`, with `top`
`base(y).hi` (`<=`, `==`) or `base(y).hi - 1` (`<`), when `top >= 0`. A checked product
cannot wrap, so the square is exact.

`caps(v, B)`: a **fill cap** `v <= M` holds in every block dominated by the exit block of a
counted fill loop whose bound is `v` (§5.5): the list the loop built has `max(v, 0)`
elements, at most `M` (A2).

The view is what a rule below calls the operand's interval. The views are acyclic: the view
of `v` at `B` reads the view of another value at a block strictly higher in the
dominator tree (the block holding a comparison that dominates `B`), so a view is a
function of the stated base intervals and the CFG only.

### 5.3 Phi

Let `phi` be in block `B` with operands `o_i` from predecessors `P_i`:

`range(phi) ⊇ hull_{i : P_i → B live} at(o_i, P_i)`

An operand is viewed **at its predecessor block**, so the refinement of the edge into the
phi's block applies. A phi on a loop header takes the back-edge operand's view at the
latch block with the *stated* ranges of the header's phis: that is the **one-trip rule**.
If every stated interval satisfies it, the interval holds on entry and, if it holds at the
top of an iteration, it holds at the top of the next. There is no fixed point to compute.

A phi of a counted loop's counter and a reduction phi have stronger intervals than this
rule alone gives; they follow from §5.5.

### 5.4 Widening is invisible

`facts.zig` widens a phi that keeps changing to the next threshold (`0`, `M`, `M+1`, the
type's limit). The result is a larger interval than the fixed point, so it satisfies the
inductive rule with room; the validator never needs the thresholds. A widened interval is
sound and merely loose.

### 5.5 Counted loops, reductions and fill lists

A **counted loop** is a builder loop record (`header`, `body`, `latch`, `exit`) whose
header has two predecessors (the entry and the latch), ends in `branch c, body, exit`, `c`
is `cmp lt k n` and `k` is the header phi `k = phi(s, k')` with `k' = add k 1` (checked or
proven, the constant 1), `s` entering from the non-latch predecessor. The validator
recognises the pattern on the IR; the certificate does not say which loops are counted.

- **Counter.** `range(k) ⊇ [s.lo, max(s.hi, n.hi)]` with `s = base(s_operand)` and `n` the
  view of `n` at the header. This is inductive: on the back edge `k < n` holds (the body
  edge of the header's branch), so `k' <= n.hi <= max(s.hi, n.hi)`, and `k' >= k >= s.lo`.
  It is the generic phi rule (§5.3) with the body edge's refinement, so a counter needs no
  rule of its own.
- **Trips.** At most `trips = max(n.hi - s.lo, 0)` iterations complete, where `n` is the view
  at the header.
- **Reduction.** A header phi `a = phi(init, next)` in a counted loop where `next` moves `a`
  by an amount in `step = [lo, hi]` each iteration (`next` is `a` itself; a checked or
  proven `add`/`sub` of such a value and a value with a view; or a phi joining such values;
  an inner counted loop's accumulation counts its own trips) satisfies, after `j <= trips`
  iterations, `a ∈ [init.lo + min(0, j·step.lo), init.hi + max(0, j·step.hi)]`. So
  `range(a) ⊇ [init.lo + min(0, trips·step.lo), init.hi + max(0, trips·step.hi)]`.
  This is not inductive in the interval domain alone (`a + step` leaves the interval by
  one step), so the validator checks it with the loop's own induction on the iteration
  count: it derives `step` and `trips` from the IR and the stated intervals (F4). The bound must
  be contained whole, and a stated interval lies inside the type (F1), so the pass (`facts.zig`
  `reduction`) states a reduction only when the bound lies inside the phi's type on both sides.
  A bound that leaves the type on one side (`if value <= 100: total += value`: `trips * step.lo`
  is far below the minimum of `i64`) is true when clipped, but the clipped interval is not
  inductive (the operands reach one more step past its top, F3) and F4 cannot contain the
  unclipped bound; such a phi takes the plain rule and widens (§5.4).
- **Fill list.** A header phi `l = phi(list_new, list_push(l, x))` of a counted loop with
  `s = {0}`, where the push lies on a straight chain executed exactly once per iteration
  (every block from the body to the latch has one live way on, and nothing else enters the
  chain), has `length(l) = n`: in a block dominated by the loop's `exit`, `l` has exactly
  `max(n, 0)` elements. `elements(l)` is the hull of the pushed value's view at the push
  block. Inside the loop the list is shorter than `n` and the fill length does not apply
  (`lengthHolds`).

### 5.6 The module-level checks

- **Parameters.** For each `internal` function `g` with no `func_ref` to it and each
  parameter `k` with stated `param(k)`, for every direct call `call g(…)` in a block of
  any function that is not dead: the view of argument `k` at the call lies in `param(k)`.
- **Returns.** For each function with stated `ret`, the view of the operand of every `ret`
  in a block that is not dead lies in `ret`.
- **Fields.** (Stage 2.) Each field interval contains every value any write in the module
  stores in the field.

These close the inter-procedural facts: a stated parameter or return interval is a
claim about *every* caller or *every* return, so the checker looks at all of them.

## 6. The checks F1–F8

A **fault** is a violated rule. The validator reports the first fault, with the function,
block, instruction, the check's name and the nearest source rule (the Reader column of
§1.1 or the `NEW-CORE-F…` tag of the fact).

- **F1 Shape.** The certificate describes the IR: instruction lines in IR order with
  their operand lines, block predecessor lists consistent with the terminators, every
  stated interval inside the type range and non-empty, values defined once, operands defined
  before use or by a phi, a stated interval only on an integer or boolean value.
- **F2 Transfer.** For every instruction that has a rule in §4 (not a phi), and a stated
  interval, the interval contains the rule's result for the stated and viewed operand
  intervals (§5.2). A rule marked *assumed* (§2.5, §8 A6) is accepted if the interval lies
  in the type range; the sweep counts them.
- **F3 Phi.** Every phi's stated interval contains the hull of §5.3, or the meet of that hull
  with the loop bound of F4 (change 17).
- **F4 Loops.** A reduction phi's stated interval contains §5.5's bound, with the step and
  trips the validator derived, or that bound's meet with the hull of F3. A counted loop's
  counter contains its counter bound, or the meet of the counter bound with the hull when the
  counter bound fits the type (so the counter cannot wrap). Each bound holds on its own, so the
  phi's values lie in the meet; the validator derives both and trusts neither from the
  certificate, and an interval tighter than the meet is rejected.
- **F5 Reachability.** Every block stated dead has no live incoming edge (§5.1), and the
  entry is not dead. A comparison folded to a constant in the final IR is `iconst`, so its
  value is its constant; a `branch` on a constant decides its edges (§5.1).
- **F6 Inter-procedural.** The module-level checks of §5.6.
- **F7 Proven.** Every instruction with `check = proven` satisfies its row of §4's
  last column at the intervals of its site. For the bounds checks:
  - `array_get`, `array_set`: the index view `⊆ [0, n-1]`, `n` the array's length;
  - `list_get`, `list_get_field`, `list_set`: the index view is `>= 0` and one of the
    following holds:
    - **len** — `index.hi < len(l).lo` for the list `l` (through `list_view_of`/`borrow`);
    - **bound** — `bound(index) = (l, strict)` or a dominating edge `index < y` with
      `bound(y)`, and `l` is the list (stage 2);
    - **edge** — a dominating edge `index < len(m)` with `m` a list of the same length
      (the keys of `index_keys.zig`, stage 2);
    - **fill** — `length(l) = L`, the fill has exited where the access runs, and
      `index.hi < view(L).lo`, or a dominating edge `index < L`, or the index is
      `x % L` with `L >= 1` (stage 2 except the first);
    - **dominated** — an earlier access that dominates this one made the same check on the
      same index and the same list length (`index_checks.zig`, stage 2);
  - `list_pop`: `len(l).lo >= 1`.

  A reason outside the stage-1 set is reported as **unchecked** with its name; it is not a
  rejection (§8 A6, §9).
- **F8 Readers.** A reader that wants an interval takes it from the stated intervals only
  (F2–F4 validate each one), and the `!range` or 32-bit narrowing of a value needs the
  interval to lie in the encodable range: a half-open `!range` cannot spell an upper bound
  one past the type's maximum, so a value whose upper bound is the type's maximum gets none.

## 7. The theorem

**Model.** The Lean model abstracts a function to its blocks of integer instructions with
the three forms of §4, branches on comparisons, direct calls, and the list/array reads of
§6.2, as a small-step machine over mathematical integers with a trap state.

**Theorem (soundness of a checked certificate).** If the checker accepts the certificate of
a module `M`, then for every execution of `M` that starts at an external entry with
arguments in their type ranges, at every step:
1. **Intervals.** Every value produced by an instruction with a stated interval lies in it.
2. **Reachability.** No block stated dead is entered.
3. **Proven checks.** No `proven` instruction takes the failing case of its form: the
   operation does not overflow, the shift count is in range, the divisor is positive, the
   conversion is exact, and the access is in bounds. Its emitted form therefore computes the
   exact result.
4. **Readers.** Every interval a reader of §1.1 consumes is among 1, so a `!range`,
   a narrowed operation or a folded branch is justified.

Cases not covered by the *derived* rules of §4 hold under the *assumed* facts (§8 A6).

**Proof sketch.** By induction on the length of the execution, with the invariants
(1)–(3) for the current activation and, for the calls, the parameter and return intervals
as the induction hypothesis of the callee, discharged by F6 at each call site and each
return. Within an activation, each rule of §4 is a lemma on the integers (the exact
interval contains the exact result; `omega`), a refining edge is a lemma on the branch
(§5.2), a phi is the join over the edge taken, and a counted loop and a reduction are
inductions on the iteration count (§5.5).

**Corollary.** In a release build whose certificates check, no `proven` check can fail at
run time on any input, and `--verify-facts` finds nothing at run time that the facts
claimed.

Traps end the execution and are excluded: a failing *checked* operation traps with its
message, as in a debug build.

## 8. Trusted assumptions (`proofs/facts/AXIOMS.md` mirrors this list)

- **A1** The three forms (§4) are what the emitter emits: `exact` traps before an
  out-of-range result is used, `none` wraps, `proven` emits an unguarded `nsw`/`nuw` or
  unsigned operation. The lowering formulas are C8's (plan §7.2).
- **A2** A list or string has at most `M = 2^47` elements or bytes (`target.zig`), and a
  fill loop's list has `max(n, 0)` elements: the runtime allocates what the builder asked
  for and the fill pushes once per iteration.
- **A3** The module is closed: an `internal` function with no `func_ref` is called only by
  direct calls in the module, and its parameters are exactly what those calls pass.
- **A4** An external entry (`main`, an exported or `extern` function) is called with
  arguments in the type ranges.
- **A5** The emitter and the other readers of §1.1 use a fact only where §1.1 says, and
  reproduce the rule of the form they select. That the passes that change the IR after
  the facts (inlining, forwarding, ownership, versioning) preserve each fact is covered
  by the certificate being of the *final* IR.
- **A6** (stage 1) The following are stated and accepted by the checker without a
  derivation; the report counts the instructions and checks that rest on each. Each
  becomes a derived rule in a later stage (§9):
  - field intervals (`record_get`, `list_get_field`, `forward.ranges`, `record_make`);
  - dictionary facts;
  - `f64` intervals and `float_to_int`;
  - length bounds (`bound`), `index_keys` edges and dominated accesses (§6.2);
  - a `proven` constant addition or subtraction on a phi (or on a field read through a record phi) whose
    operation is checked on the path into every edge of the phi's block (`overflow_edges.zig`);
  - the pattern validation of fill lists.
- **A7** IEEE-754 binary64 is what `f64` operations compute (used only by A6's floats).
- **A8** A comparison between a non-aliased pair of SSA values has the value its operands
  give it: SSA values are immutable between definition and use.
- **A9** The IR the certificate describes passed the verifier (`verify_ir.zig`: a debug compiler,
  `--verify-facts`, `--verify-written-copies` and `--verify-facts-static` run it before the validator):
  every reachable block of an internal function ends in one terminator with its phis first,
  predecessor lists match the terminators, each phi has one operand per predecessor and operands of
  its own type, each operand has the type its operation's signature asks for (the integer rules read
  operands of the result's type), each use is dominated by its definition (a phi operand by the end
  of its predecessor), and a fixed array is built from its declared number of elements. A certificate
  file is read without the IR, so the validator re-checks from the text what the text shows: the
  edges and predecessors, the phi edges, the entry block, the leaves (no operands outside blocks,
  the header's parameter types, constants that fit their types), the operand types of the integer
  rules and phis, and the dominator tree and reached set it computes (F1). SSA dominance of an operand
  over its use is not re-checked from the text.

## 9. Evolution of the checker

| Stage | Derived (the checker re-derives) | Assumed (A6) |
| --- | --- | --- |
| C7.2 | integer and boolean intervals; phis, counted-loop counters, edge refinement and the square rule; reachability; parameter and return intervals; reductions with direct steps; `len` and `elements` of lists; `proven` for arithmetic, shifts, division, conversion, `neg`; arrays; `list_get`/`list_set` by `len`; `list_pop` | the rest of A6 |
| C7.3 | the same, in Lean | — |
| later | fill lists and `length`; length bounds; `index_keys` edges; dominated accesses; fields; dictionaries; floats | — |

## 10. Format `fact-certificate-v1`

The format is UTF-8 text, one item per line, fields separated by single spaces.
- `%N` names value `N`, `bN` a block, `#N` a function index; `-` stands for an empty list or
  an absent operand; lists are comma-separated, with no spaces.
- Intervals are `lo hi` in decimal (`i128`).
- Lines are in this order, and the bytes are deterministic.

```text
fact-certificate-v1
function <name> linkage <internal|other> addr <0|1> params <T,…|-> ret <T>
param <K> <lo> <hi>|-                                        one per parameter
returns <lo> <hi>|-
block bN <reach|dead> preds <bM,…|->
phi %N <T> edges <bM:%V,…> range <lo hi|->
inst %N <op> <T> <none|exact|proven> a <%V|#N|-> b <%V|-> x <%V,…|-> imm <N> aux <N> range <lo hi|->
term jump bN | term branch %V bT bF | term ret <%V|-> | term unreachable
loop header bH body bB latch bL exit bE
list %N len <lo hi|-> elems <lo hi|-> length <%V|-> pattern <0|1>
bound %N <%P> <strict|loose>
site %N <lo:hi|->…                                           one per `proven` instruction
end
```

- **Types** `T`: `void bool i8 i16 i32 i64 u8 u16 u32 u64 f64 list other`.
- **Order.** Blocks in index order, each block's `phi` lines first, then its `inst` lines
  in order, then its `term`. `loop`, `list`, `bound` and `site` lines follow the blocks of
  their function in the order of the value or header they name. `param` and `returns`
  lines come right after `function`.
- **Instructions.** `a`, `b` and `x` are the IR's two operands and the `extra` operands in
  order, after `copy` resolution. For a `call`, `a` is `#N`, the callee's function index,
  and `x` the arguments. `imm` is the instruction's `data` in decimal (`u64`); for `cmp` it
  is the predicate in `ir.Predicate` order (`eq ne lt le gt ge` = 0..5); for an `iconst` it
  is the value's two's complement bits, read at the type's signedness. `aux` is the length
  of the array for `array_get`/`array_set` and 0 for every other op.
- **Ranges.** `range -` is no claim. A `range` on a non-integer, non-bool value is a fault
  (F1).
- **Sites.** `site %N` lists, as `lo:hi` tokens (`-` for none), the viewed intervals the
  check of §4 reads, in this order: `add sub mul div rem floor_div floor_rem` the intervals of
  `a` and `b`; `neg`, `convert` that of `a`; `shift_left`, `shift_right` that of `b` (the
  count); `array_get`, `array_set` that of the index `b`; `list_get`, `list_get_field`,
  `list_set` that of the index `b` and the `len` of the list `a`; `list_pop` the `len` of `a`.
  It is the *reason* of §6. The validator recomputes each viewed interval and demands the
  stated one contain it (a site narrower than what the edges and the stated ranges give is
  a fault: the certificate claims a refinement nothing justifies); and the condition of F7
  must hold of the stated site (a site wider than the check needs fails it).
- **Lists.** `list` lines are written for list values with a stated fact; `length` is the
  fill length's value or `-`.
- **Functions** are in module order and include every function with a body, so the
  inter-procedural checks (F6) see every call site. `addr 1` marks a function whose address
  a `func_ref` takes; a function with `linkage other` or `addr 1` has no `param` interval
  (its parameters have the type range).

C7.1 implements exactly this grammar. C7.3 reads it. A change to the grammar is a §11
entry.

The exporter is a direct serialization of the IR and the fact tables the passes kept, so it
is trusted along with them (A5); the checker does not look at `facts.zig`.

## 11. Changes after C7.0

Each entry gives the date, what changed, why, and whether the Lean model followed.

| # | Date | Change | Reason | Lean model |
| --- | --- | --- | --- | --- |
| 1 | 2026-10-26 (C7.1) | §10: a pseudo-block `block b- reach preds -` lists every constant and parameter of any type (before `b0`); every instruction, void ones included, has an `inst` line; the file lists every function of the module in module order, a function without a body having only its header and `param`/`returns` lines, so that a call's `#N` is the position in the file. | Operands name constants of every type (a string, a function reference); a unit value is an operand; `#N` is the module function index. | the format is as written |
| 2 | 2026-10-26 (C7.1) | §2.4, §10: the type token `list` covers lists, list views and fixed arrays; their `len` and `elems` are list facts. | `array_get`/`array_set` read the element hull of a `record_make` array (`facts.listFact`). | follows |
| 3 | 2026-10-26 (C7.1) | §1, §10: the exporter fills the slots the passes left empty (an instruction a later pass added, which `passes.extend` covers with no interval) from a fresh analysis of the final function, with the parameter intervals as stated and the callees' final return intervals. It replaces nothing the passes stated, so the emitter reads what it read. | `own.zig` and the forwarding pass add instructions after the facts; the instructions that read them kept the intervals they had, and the certificate can only show those follow from the new instruction's. | follows |
| 4 | 2026-10-26 (C7.2) | §5.5: the counter rule is a rule of its own, not the generic phi rule: `range(k) ⊇ [s.lo, max(s.hi, n.hi)]` with `s = base(entry operand)` and `n` the view of the bound at the header. | The phi rule reads the stated interval of the increment `k + 1`, which the passes may state looser than the counter's own bound. The counter rule needs nothing but the loop structure. | follows |
| 5 | 2026-10-26 (C7.2) | §5.1: liveness uses the blocks **reached** from the entry along edges no decided branch rules out, not the stated flags. A block stated reachable that no open path reaches (one a pass added on a dead edge, which `extend` defaults to reachable) is unreached; its instructions are not checked. A block stated dead must be unreached. | `own.zig` splits edges that lead into dead blocks and adds cleanup blocks, which are reachable by default. | follows |
| 6 | 2026-10-26 (C7.2) | §5.6: an argument is read at the parameter's type: the same bits at the parameter's signedness (a `u64` constant passed to an `i64` parameter). | The Core IR passes integers of one width as one register, and a call may mix the signedness of an argument and its parameter. | follows |
| 7 | 2026-10-26 (C7.2) | §6 F7: a `proven` check that has a row in §4 and no `site` is rejected. A list access whose `len` row does not hold is reported unchecked, by reason, not rejected. | A site is the reason; a check with none states none. | follows |
| 8 | 2026-10-26 (C7.2) | §8 A6: the results of `list_get`, `array_get` and `call` whose stated interval the final IR cannot derive are accepted as assumptions and counted. | A pass that runs after the facts rewrote the list or the callee (ownership splits writes and copies lists), and the interval the facts computed before is still right but no longer shown: 10 results in 14,607 functions of the language suites. A future stage derives them or the passes keep the facts current. | follows |
| 9 | 2026-10-26 (C7.2) | §10 (wiring): the validator runs in `pipeline.emittedCached` after emission, on the description of the final module and the tables the passes kept. `checksFacts` is true for a Debug compiler (whenever the build computed facts), for every compiler under `--verify-facts` and `--verify-written-copies`, and under the new `--verify-facts-static` (build, run and test), which also turns off the deferral of facts that the default optimized-debug build uses, so they exist to check. The sabotage modes state false facts on purpose and are not validated. A rejection is `E_FACT_VALIDATION` (exit 2); with `--emit-certificates` the certificate is written first and the build fails at the end. | The ownership validator's policy (Debug compilers, `--verify-facts`, a flag), except that a facts build is not forced: an ordinary optimized-debug build computes none, so a Debug compiler checks only the builds that did. `checksFacts` is part of the build's replay key. | follows |
| 10 | 2026-10-26 (C7.4) | `selka dump-ir FILE --fact-certificate` prints the fact certificate of the program after the release passes; `--emit-certificates DIR` writes it as `program.fact-certificate` next to the ownership certificates and removes a stale `*.fact-certificate`. | The mutants and the gate step lower a program without the native toolchain. | follows |
| 11 | 2026-10-26 (C7.2) | §6 F1: a function whose block 0 has a predecessor is a shape fault (`F1 at b0`). | `refining(x)` applies the branch refinement of the single incoming edge to any block with one predecessor, block 0 included; block 0 is also where an execution starts, which no edge has refined. Found by the Lean model (`proofs/facts/NOTES.md`, deviation 1); the Lean checker rejects it too. | follows |
| 12 | 2026-10-26 (C7.2) | §5.5: a loop is counted only if its header's `then` is the body, the body has the header as its only predecessor and the guard `counter < bound` refines it (`refining(body)` from the header), and the body dominates the latch. | Without this, a header whose `else` reaches the latch without the body (or a body with another predecessor) leaves the back edge unguarded and the bound `[s.lo, max(s.hi, n.hi)]` is false: the counter keeps growing. The builder never makes such a loop. Found by the Lean model (deviation 2); fixture `a counter is bounded by its bound only when the body guards the latch` is accepted before the fix and rejected after it. | follows |
| 13 | 2026-10-26 (C7.4) | §1, §10 (exporter): the exporter reads the whole-program field intervals the facts were computed under (`passes.Result.emission.fields`) when it completes a function's tables, and closes the stated intervals under each instruction's transfer rule over the stated operands (`facts.Viewer.derive`, the meet with what is stated, up to three sweeps). | The forwarding pass gives the phi it makes the interval of its record's field, while the `add` that feeds it keeps the interval it had before, and the fresh analysis the exporter used had no field intervals, so a field read was stated as the type's whole range: three functions of the EDA stage-2 test program were refused (F3), by a phi stated tighter than the `add` and the `record_get` that feed it. Everything stated is already true of the final function, so the meet is too; the emitter reads the passes' tables, not these. After the change all 1630 functions are accepted and 3 fewer intervals of the clean corpus rest on an assumption. | follows |
| 14 | 2026-10-26 (C7.2) | §6 F1 and §8 A9: the validator also checks the shape facts the Lean model needs. The entry block has no predecessor and no phi (the first half is row 11). Values defined outside every block take no operands, a `param` has the type its header gives, and an `iconst` fits its type (a capability constant has no interval and is left alone). The integer rules (`add`, `sub`, `mul`, `div`, `rem`, `floor_div`, `floor_rem`, `saturating_add`, `neg`, `shift_right`, the bit operations) read operands of the result's type and a phi reads operands of its own. The dominator tree is verified (a tree rooted at the entry in which, for every edge out of a block a path reaches, the target's dominator is the source or one of its ancestors, which makes each claimed dominator a true one), and so is the reached set (no open edge leaves it); the verified tree's numbering answers `dominates` in constant time. | The Lean checker makes these checks (`proofs/facts/NOTES.md`), the theorem uses them, and a certificate read from a file has no IR to hold them. The compiled IR already satisfies those the verifier checks (A9). | follows |
| 15 | 2026-10-26 (C7.2) | §2.1, §3, §6: an interval may be empty (`lo > hi`): the value is never produced, which is what the facts state for an `exact` operation that always traps (`i64::MAX + 1`, a product whose smallest value is past the type). F1 no longer refuses it, `within` holds an empty interval in every interval, and a rule whose operand has an empty view derives the empty interval (the instruction never runs), so what is stated for it is vacuously true and its `proven` check is validated; a phi hulls only the operands that are produced, and a call argument or a returned value that is never produced is not compared to a claim. The emitted code keeps the trap: the range of an always-trapping operation is not within its type, so the check is never proven. | The corpus the Lean lane swept has no definite overflow; `test/core/overflow.selka` and `runner_cases.selka` have, and the Debug compiler, which now validates every release build, refused them. | follows (`proofs/facts`, C7.3) |
| 16 | 2026-10-26 (C7.2) | §6 F7, §8 A6: a `proven` `i64` addition or subtraction of a constant whose left operand is a phi of a block `H` that dominates it (or the read of a field of a record phi of `H`) is counted as unchecked (`edge-checked`) when, on the path into each edge of `H` (the predecessor or a block that dominates it), the same operation with the same constant is checked on the value the phi takes from that edge (or on the same field of the record it takes; two reads of one field of one record are one value), and the instruction under test does not count itself. Anything else is still F7. | The pass `overflow_edges.zig` proves such an operation safe because the earlier checks ran on every path into the phi, which no interval shows (`test/core/f2_header.selka`, `u1_sink.selka`). The check of the shape is the pass's rule less its alias analysis, so it is counted with the other assumptions, not validated. | follows (`proofs/facts`, C7.3) |
| 17 | 2026-11-11 (lane VT) | §6 F3, F4: a phi is accepted when its stated interval contains the meet of the hull of its live operands with its counter bound (when that bound fits the type) or its reduction bound, not only when it contains one of them (`Checker.loopBound`, `Ctx.phiOut`). | The facts pass states a loop accumulator that grows by a constant and wraps at a modulus (`bits += 6; if bits >= 8: bits -= 8`) as the meet of the two bounds: the hull alone exceeds it by one step at the top, the growth bound alone at the bottom. The validator refused it (F3) in `--release` builds and under `--verify-facts-static`, the protobuf library's `pjson.parse_bytes` among them. The Lean proof covers the meet: the chain rule (`ChainProved`) and the counter case of `phi_valok` show the value lies in each bound, so it lies in the meet; no assumption grows. | follows |
