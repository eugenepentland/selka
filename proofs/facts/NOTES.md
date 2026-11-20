# Fact certificates in Lean: notes (package C7.3)

The single list of where the Lean checker differs from `src/core/validate_facts.zig`, what the soundness proof needed
that the Zig validator does not check, and the findings. Lane 1 reads it.

On the 13,200 functions of `tests/lang` the verdicts and the statistics of the two checkers are identical, with every
check below on. The differences matter only for IR the builder does not produce.

## Deviations of the Lean checker from the Zig validator

Each is a check the Lean checker makes *in addition* to the validator's (the proof needs it, or it verifies a result the
validator trusts). The last column is for lane 1: mirror it in `validate_facts.zig`, or name the `verify_ir.zig` check that
already covers it.

| # | Lean check | Where | Why the proof needs it | Zig side |
| --- | --- | --- | --- | --- |
| 1 | The entry block has no predecessor and no phi (`entryOK`). | `Prep.lean` | `refining(0)` would apply a branch refinement to the function's first entry, which no edge reaches; a phi at the entry has no edge to read. | finding 1: mirrored |
| 2 | A counted loop (`countedAt`) also requires `dominates(body, latch)` and a refining edge into `body` from the header. | `Rules.lean` | The counter bound `[s.lo, max(s.hi, n.hi)]` holds at the back edge only if the header's `counter < n` guards every path to the latch. | finding 2: mirrored |
| 3 | The dominator tree and the reached set are computed as the validator does, then *verified* (`domOK`, `reachOK`); a failure is F1. | `Prep.lean`, `View.lean` | The proof uses the verified properties only; a correct computation always passes. | lane 1 to confirm |
| 4 | The definitions table is exactly the items: each constant, parameter, phi and instruction is recorded once, at its own position, as its own definition (`defsOK`). | `Prep.lean` | The proof reads a value's definition from the table. | lane 1 to confirm |
| 5 | The predecessor lists are exactly the blocks whose terminators name the block (`edgesOK`); each phi has one operand per predecessor, in the predecessors' order (`phisOK`). | `Prep.lean` | A phi's operand is read by the edge taken. | lane 1 to mirror or name the `verify_ir` check |
| 6 | The constants and parameters (`pre`) are constants, parameters, or operations whose result is not derived, and have no operands (`preOK`); a `param` instruction has the type of the parameter it reads (`paramsOK`). | `Prep.lean` | The initial registers of an activation are defined from nothing. | lane 1 to mirror or name the `verify_ir` check |
| 7 | The operands of integer arithmetic have the instruction's type, and the operands of a phi the phi's (`typedOK`). The validator's `sameTypes` (design change 14) is the same check, except that it also covers `bit_and` and `bit_or`, which Lean reads as unmodelled operations, and leaves out `shift_left`, whose left operand Lean requires to have the result's type. | `Prep.lean` | An operand's interval is read at its own type's range. | lane 1 mirrored all but `shift_left` (and the proof needs it); name the `verify_ir` check for it |
| 8 | A stated interval is non-empty, lies within the type's range, and is stated only of an integer or boolean (`statedOK`). | `Prep.lean` | Intervals are read as sets of integers in the type. | lane 1 to confirm |
| 9 | The list facts the checker indexed are exactly the stated ones: one fact per value, no stray one (`listsOK`). | `Prep.lean` | A value's stated list fact is unique. | the validator's F1 on a duplicate fact (`shape`) is the computation; `listsOK` verifies it |

## Design changes 15 and 16 (mirrored at lane 1's 7161fe245)

* **15, empty intervals.** An interval with `lo > hi` says the value is never produced. F1 accepts it, `Interval.within` holds
  it in every interval, `Ctx.operand` reads an operand that is never produced as its type's range and a rule that reads one
  derives the empty interval (`Ctx.derive`: `ruleVacuous`), a phi hulls only the operands that are produced
  (`phiHullStep`), a refining edge whose bound is empty refines nothing, F6 compares neither an argument nor a returned
  value that is never produced, and a `proven` check on a never-produced operand is validated (`partsVacuous`). The
  theorem needs no new statement: "every value of a frame lies in the interval stated for it" says, for an empty interval,
  that no execution produces the value. The proof needed three things: the operand soundness is now about the raw view
  (`OperandSound` reads `operandRaw`; `operand_eq_raw` gives the old shape and `emptyView_false` says the view of a
  register holding an integer is not empty), so a rule whose operand is never produced cannot run (`ruleVacuous_false`,
  `partsVacuous_false`, `ub_reads_ints`); `within` has the empty disjunct (`within_iff`); and a counted loop whose start is
  never produced is never entered (`FrameInv.cstart`, `counter_start_next`: `counterBound` is not empty). The Lean model
  found no unsound case in the new rule.
* **16, edge-checked.** A `proven` `i64` addition or subtraction of a constant whose left operand is a phi of a block `H`
  that dominates it (or the read of a field of a record phi), and which has the same checked operation on the path into
  every edge of `H`, is counted as `unchecked` with reason `edge-checked`, not rejected (`Ctx.edgeChecked`). It is a
  checker rule only: an unchecked operation carries no proof obligation, so the theorem says nothing about it and its
  unguarded form rests on `overflow_edges.zig` (`AXIOMS.md` E4).

Neither occurs in the five corpora (`factcheck --census` prints `empty_stated` and `edge_checked`); both occur in the four
programs lane 1 named: `test/core/overflow.selka`, `runner_cases.selka`, `f2_header.selka` and `u1_sink.selka` (2 empty intervals and 4
edge-checked operations). Fixtures: `empty_*` and `edge_*` in `fixtures/`.

## Hypotheses of the proof that the checker does not check

Not deviations (the Lean checker does not check them either), but what the soundness theorem takes from elsewhere
(`AXIOMS.md`):

* SSA (`ModWf`): every use is dominated by its definition. `verify_ir.zig` checks it. The proof states it as `SsaWf`; `proofs/verify_ir` proves it for its Lean copy of the verifier (`modWf_of_verdicts`, `AXIOMS.md` H2).
* Typing (`TY1`-`TY3`): the machine's steps are typed. The IR verifier and the runtime's type safety give it.
* The execution honours `Adm` (`AXIOMS.md`): the facts accepted on trust.

## Findings

Findings 1 and 2 are the deviations 1 and 2 above, reported to lane 1 (approved, mirrored in Zig). Both involve IR the
builder does not produce: an entry block with a predecessor, and a counted loop whose body does not dominate its latch
(or whose header has no refining edge into the body).

The proofs of the list facts and of the counters found nothing further: the derivation of every list operation
(`list_new`, `list_push`, `list_pop`, `list_copy`, `list_view_of`, `borrow`, `list_set`, `array_set`, `record_make`) and the
join of a list phi are sound for every execution of the machine, with no extra condition.

## Reductions (design 5.5): proved for chains and joins, assumed for inner loops

**What the rule says.** For a phi `p` in the header `H` of a counted loop (not the counter), with an entry edge and the
latch edge, the checker computes `step`, the interval of `latch - p` in one iteration (`growth`: the latch value is `p`
moved by checked additions and subtractions, joins of such values, and inner counted loops), `start`, the view of the
entry value, and `trips`, the most iterations the counter allows (`bound.hi - start.lo`). It accepts a stated interval
that contains `grown(start, step, trips)`.

**What is proved.** The reductions whose growth is a chain of checked additions and subtractions of `p`, with joins of
such chains (`ChainProved`, `Chain.lean`, `jGrowth`): their stated interval holds in every honest execution, with no
assumption. Two clauses of the frame invariant carry the proof:

* `FrameInv.red`, for each reduction phi `p` at `H`, in the states `H` dominates: `R p` lies in
  `start + T * [min(step.lo, 0), max(step.hi, 0)]`, where `T = min(R counter - s0, trips)` and `s0` is the lower bound
  of the counter's start (`ChainBound`). Instruction steps and entering any other block change neither `p` nor the
  counter. Entering `H` along the entry edge: the entry value lies in `start` (`operand_at`), `T >= 0`. Along the latch
  edge: `chain_sound` gives `R latch - R p` in `step`, the counter moves by exactly one, below the bound
  (`counter_enter_x`, the strengthened `counter_enter`), so `T + 1 <= trips` and the bound grows by one step. The
  reduction phi and the counter phi take the same edge: the two predecessors of a counted loop's header differ
  (`counted_preds_ne`).
* `FrameInv.jn`: a join phi whose growth from a phi of the header `H` is derived holds it. `chain_sound` follows an
  accumulator chain from `Cons` (every available instruction has the value its operands give it) and the exactness of a
  checked operation (`eval_addsub`), and reads a join from this clause; entering the join's block gives the clause from
  the growth of the edge taken (`jEdges_spec`), which is live.

The proof's class is narrower than the checker's, with no change to the checker (the extra conditions are in `jGrowth`,
the proof's own reading of the growth): a join must lie in a block the header dominates, other than the header, and not
be a loop header; the counter's bound must fit its type (`CounterSafe`). On every corpus the join conditions hold for
every reduction that has joins.

**What stays assumed.** A reduction phi accepted only by `reduction` (not by the hull of its operands, not as a counter)
and not `ChainProved` is the assumption `AdmFrame.phi` (`AXIOMS.md` A6.2): in practice the reductions whose growth passes
an inner counted loop.

**How many rest on the remaining assumption** (`lake exe factcheck --census DIR` counts `reductions_proved_by_chain`,
`--reductions DIR` prints one line per phi with its class; the lines for `tests/lang` are in
`~/.cache/selka/certs-c8/facts-corpus/reductions-lang.txt`, not in git):

| Corpus | Functions | Reduction phis | Proved | Assumed (inner counted loop) |
| --- | --- | --- | --- | --- |
| `tests/lang` | 13,200 (120 hold one) | 152 in 62 test modules | 140 (106 chains, 34 with joins) | 12 |
| `tests/value_semantics` | 673 | 2 | 2 | 0 |
| `tests/ported` | 734 | 48 | 48 | 0 |
| `examples/` | 130 | 4 | 4 | 0 |
| `bench/` | 477 | 14 | 13 | 1 |

(The proved count is `Ctx.chainProvedB`, a Boolean that implies `ChainProved` (`chainProvedB_sound`, `ChainLink.lean`); it
agrees with the classes of `Ctx.reductionClass`, the smallest set of constructs whose `growth` the rule needs.)

**Review of the rule (no counterexample found).** The points that could be unsound, and why none is, for IR the builder
produces:

* A step through `add` or `sub` needs `check != none`, so the operation does not wrap; the other operand's contribution is
  its view at the instruction's own block. Both operands are available there (SSA), so the accumulator is the one of the
  current iteration.
* A join takes the hull over the *live* edges, each of which must itself have a growth; the edge actually taken is live
  (executions do not take a closed edge). A cycle through non-header phis exhausts the budget and gives no growth.
* An inner counted loop's phi is its entry value's growth plus `trips` times its own per-iteration growth, relative to
  the phi itself; `trips = max(bound.hi - start.lo, 0)` bounds the iterations because the counter starts at least at
  `start.lo` and each iteration needs `counter < bound`.
* `grown(start, step, trips)` is the interval after at most `trips` steps each in `step`; the iteration count of the
  header is at most `trips`, because the back edge is taken only when `counter < bound`.

**One hypothesis the proof uses that the validator does not state.** `CounterSafe`: the bound's view lies within the
counter's type (`bound.hi <= lim.hi`), so the counter does not wrap and `trips` bounds the iterations. For a comparison of
two values of one type it holds by the type; the checker does not require the types to agree. `ChainProved` includes it,
so a reduction of a loop whose bound is wider than its counter is not proved but assumed (none in the corpora).

**What the rest needs.** The same pair of clauses for the inner loop's phi `q` with the accumulator as the reference: `R q
- R acc` in the entry growth plus `T'` steps, `T'` read off the inner counter. `chain_next` and `counter_enter_x` are the
pieces; the reference register turns `ChainBound`'s absolute bound into a relative one, and `jGrowth` needs an inner-loop
case that recurses with the inner phi as the accumulator and the inner header as `H`. I estimate 150 to 250 lines.

## The meet of a phi's bounds (11 November 2026, lane VT; design change 17)

**The rule.** `Ctx.phiOut` (and `Checker.joinPhi` with `Checker.loopBound` in the Zig validator) accepts a phi whose stated
interval contains the hull of its live operands, or that hull's meet with its counter bound (`counterAccepts`: the counter
bound alone, or its meet when `b.hi <= limits.hi`), or that hull's meet with its reduction bound. Before, each candidate had
to contain the stated interval alone. Every candidate is derived by the checker; none is read from the certificate. A
counter phi and a reduction phi are never the same phi, so at most two candidates meet.

**Why.** The facts pass states the phi of an accumulator that grows by a constant and wraps at a modulus (the protobuf
library's base64 decoder: `bits += 6; if bits >= 8: bits -= 8`) as the meet of the two bounds; the hull alone exceeds it by
one step at the top and the growth bound alone at the bottom. Fixtures: `test/fixtures/fact-proof/certificates/`
(`counted_phi_meet_*`, `counter_meet_*`, `reduction_meet_*`: one accepted certificate and two rejected mutants each, the lower
end raised by one above the meet's and the upper end lowered by one below it).

**What the proof needed.** `phi_valok` never read the checker's verdict: it shows the value of every phi lies in its stated
interval by cases, with `Adm.phi` (A6.2) as the last case. So the change is in the cases, so that no new acceptance falls to
that assumption:

* `ChainProved` also holds when the meet of the chain bound with the phi's hull is within the stated interval. The hypothesis
  `hchain` of `phi_valok` now gives the value's membership in the chain bound itself (the caller already proved it from
  `FrameInv.red`), and the hull membership comes from `phiHull_contains`; `meet_contains` does the rest.
* The counter case accepts `counterAccepts`. When only the meet is within the stated interval, `CounterSafe` comes from the
  guard `b.hi <= limits.hi` instead of from `b` being within the stated interval.
* `PhiLoop`, the scope of `Adm.phi`, excludes counters that `counterAccepts`. Both changes make `Adm.phi` apply to fewer
  phis: the theorem's statement is unchanged and it assumes no more than before. A reduction whose growth passes an inner
  loop and which only the meet accepts is assumed, as every inner-loop reduction is (A6.2).
* The census (`Ctx.phiKind`, `Ctx.reductionClass`, `Ctx.chainProvedB`) counts by the same rule; `chainProvedB_sound` covers
  the meet.

