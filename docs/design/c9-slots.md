# Slot-level ends of loans (design note, package C9.3 / assumption A14)

**Status (26 October 2026): decided. Keep A14; the model is sized below and not built. The cheap steps are in section 5.**

This is the sizing note the coordinator asked for before building: what closing A14 needs on the Lean side, what it
costs, and whether to do it. It changes nothing in `src/` or `proofs/`. **Recommendation: keep A14, do not build the
model.** The reasons are in sections 3 and 4.

## 1. What A14 leaves unproved

A view of one field of an owned aggregate (`record_get`, `list_get`, ... with a `slot`) has the root `slot(c, k)`. The
checker ends that root at the take of `(c, k)`, at the consumption of `c`, and, for a root that a constructor renamed,
at the take of any slot of the new aggregate (`slot(h, *)`, `renameRoot1`). So a view of the taken field is unusable after
the take (J4 `read-borrowed-usable`), and the take hands the field's storage to the taken owner, which may free it.

The semantics has one tree per aggregate and a take that creates a fresh tree (`Xform`: the result root is an unused
cell). The container keeps every cell. So in the model the view's cells stay live when the taken owner is dropped, and a
use of the view after the drop is not a fault. The checker prevents that use; the theorem does not say the prevention is
needed or enough. That is A14: a documented gap between the model and the runtime, not a gap in the checker.

Evidence that the checker's rule works: the gate's fault injection has a class for exactly this
(`ownership_mutants.zig`, "a slot taken while a borrow of it is still read afterwards") and both checkers reject all its
mutants (409 of 409 in the C9.2 gate). The rule fires on 187, 167 and 39 takes of the gate, EDA and selka corpora
(C9.0: 8%, 2% and 5% of slot takes) and the corpora have 0 rejects.

## 2. What the Lean side needs

1. **Per-slot cells.** A ghost map `DState.part : Addr → List String`: the path of slots from the root of the cell's tree
   to the storage the cell belongs to (`[]` for the aggregate's own header). A path, not one name, because a taken field is
   itself an aggregate whose fields are slots of the new tree. Cells whose structure the model does not know (the result of
   a call, a `list_new`, anything the callee built) get an arbitrary path, which is sound for a universal theorem: the real
   assignment is one of the models' executions, and the checker must be safe for all of them. `Covers (.slot n k) x` becomes
   "x is a cell of the tree of `n` whose path starts with `k`", where the unknown path `*` stands for any slot.
2. **A take that moves cells.** For a take of `(t, k)` the set `S` of cells of `t` whose path starts with `k` moves to a
   new tree: `heap' x = live r` for `x ∈ S`, with the result root `r ∈ S`, and the paths lose the prefix `k`. This replaces
   the fresh result tree. A cell tagged `*` may or may not move (any subset), which keeps the model an over-approximation
   when the structure is unknown. The closing store of a slot is the reverse: the stored element's cells join the container
   tree with the prefix `k`.
3. **The checker rule.** None. `Root.endsAt` and `instD0` already end `slot(c, k)` at the take of `(c, k)` and `slot(c, *)`
   at any take of `c`. What the closure proves is that this rule is enough.
4. **The exporter's constructor-to-field table (the plan's C9.3).** Not needed for the closure. A constructor that does not
   say which operand fills which field tags its operands' cells `*`, which is the present wildcard. The table only makes
   `slot(h, *)` precise, so a take of another field no longer ends the loan: fewer false rejections. The corpora have none
   to remove (0 rejects), so it buys nothing today (C9.0: 6 to 18 constructors per corpus could use it).

## 3. What it costs

The take stops being a uniform instruction. `Effect` is one rule for every instruction, built on `Xform`, whose clauses
`keep` (cells outside the consumed trees keep their label), `gone`, `fresh` and `root` hold for all of them. A take that
relabels cells of a tree it does not consume breaks `keep` and the freshness of the result root, so a take needs its own
clause. The fields of `Xform` are used 26 times, in `InstCtx` and `InstPres` only, so the interface change is small. The
cost is in what the clauses are used for, the invariants about whose cells a value reaches:

* `Covers`, `rootCells` and `Dcov` gain the tag condition (`Covers` appears 22 times in 5 files, `.slot` 65 times in 11),
  and `Dcov` is preserved by every kind of step: the instruction (`Dcov'` and the lemmas around it are about 700 lines of
  `InstPres.lean`), the phi edge (`EdgeStep`), the branch (`SoundFacts`), the abandon (`Abandon`), the join (`Inv.conv`);
* the loan invariants `heldCov` and `lentCov` mention cells that now change tree at a take, and `acct`, `Lfree` and
  `Ldisj` a result root that is a cell of a tree that was not consumed;
* new invariants: the tags of a tree partition its cells, and a view rooted at a slot has its footprint in that slot's
  cells, each preserved by every kind of step;
* the closing update, the pending-take bookkeeping (`pend`), the phi renaming and the call results all need a tag rule;
* the `emptied` aggregates and the forward-take views (A15) interact: an `emptied` take is a complete move of every slot.

My estimate, from reading and not from a spike, is 25 to 40 hours of Lean, with real risk of rework in `Dcov`, and nothing
on the Zig side. The benefit is one numbered assumption turned into a theorem about a rule that fires on 2% to 8% of
takes and that fault injection already exercises.

## 4. Recommendation and what to do instead

Keep A14. Do not build the tag model; do not ask the Zig lane for the constructor table (it buys nothing until a corpus
function is rejected for want of it).

Cheap steps that make A14 less of a gap, if wanted:

* **Extend the fault injection** (Zig, about 3 hours): mutants that take a slot while a view of the same slot is read later
  through a phi, and a view of the slot of a field renamed by a constructor (`slot(h, *)`), so the wildcard path is
  exercised too. Both checkers must reject every mutant, which the gate already checks.
* **State the rule as a lemma** (Lean, about 3 hours): no view of `D` has a root that ends at the instruction after a take.
  It is what the proof already uses for `Dcov`; the statement documents what the take does to the checker's state, but it is
  not about the heap.
* **Revisit** if a corpus function is ever rejected only because of the wildcard, or if a second assumption of the same
  kind (A15, forward-take views) is closed, because both need the same tag model and the cost is shared.

## 5. Decision and what was done

The coordinator agreed: keep A14, do not build the cell-moving model (25 to 40 hours, rework risk in `Dcov`, for a rule
the corpora already pass and fault injection already exercises). Done instead:

* **The checked half is a theorem.** `SlotEnds.lean`: after a take of slot `k` of `c`, no view in `D` has the root
  `slot(c, k)` or the wildcard root `slot(c, *)` (`take_ends_slot_views`), so no such view is usable (`take_view_unusable`),
  and an instruction that reads one fails J4 `read-borrowed-usable` (`read_after_take_fails`). It is stated about the
  checker's state, so it holds for a view reached by any path the roots record, a phi included, and for a view whose root
  a constructor renamed to the wildcard. `AXIOMS.md` cites it from A14 as the checked half.
* **Fault injection (asked of the Zig lane):** two more mutant classes, a slot taken while a view of it, reached through a
  phi, is read later; and a slot taken while a view of a constructor-renamed field (the wildcard path) is read later. Each
  mutant must be rejected by both checkers in the gate.

## 6. If a later session builds the model

The plan, in the order that prices it early:

1. **Spike, about 6 hours.** The ghost `DState.part : Addr → List String` and a take that moves the cells whose path
   starts with `k`, on `Xform` and on `Dcov` for the instruction-level proof only (`InstPres.lean`). If `Dcov'` goes through
   without new invariants beyond "the tags of a tree partition its cells" and "a view rooted at a slot has its footprint in
   that slot's cells", continue; if it needs more, stop and keep A14.
2. **Edges and joins, about 8 hours.** `EdgeStep`, `SoundFacts`, `Abandon` and `Inv.conv` carry the tags (they do not
   change them); the phi renaming moves owners, not cells.
3. **Loans, about 6 hours.** `heldCov` and `lentCov` for cells that change tree at a take; the `emptied` take is a complete
   move.
4. **The closing store and calls, about 4 hours.** The stored element's cells join the container with the prefix `k`; a
   call result gets arbitrary tags.
5. **Tests and documentation, about 3 hours.**

**A15 at shared cost.** A forward-take view (a view written before the take that will own its storage, root `fwd(n)`) has an
empty footprint in the model today. With the tags its footprint is "the cells of the slot at the take", so the take can
rebind it by the same relabelling, and the missing checker invariant (every copy of the view still has its placeholder root
when the take runs) is the only part that does not come with the tag model. I did not size A15 separately; since the
relabelling is most of the work, building the tags for both together should cost clearly less than two separate builds,
but that is a judgement, not an estimate, and the spike of step 1 should be repeated on a forward-take view before
promising it.

**The exporter.** Nothing is needed for A14. The constructor-operand-to-field table makes `slot(h, *)` precise, which
removes a false rejection only if a corpus function is ever rejected for want of it (none is; C9.0 counted 6 to 18
constructors per corpus that could use it).
