# Trusted assumptions (mirror of design §8)

`docs/design/ownership-certificates.md` §8 lists A1-A7. This file says where each one
sits in the Lean model. **The development declares no Lean `axiom`.** Each assumption is
either a *definition* of the semantics (so it is true of the model by construction and
false of the real system only if the runtime differs), a *hypothesis* of a theorem, or an
assumption about the exporter that no Lean statement can express.

The only axioms a proof here may depend on are the three standard kernel axioms of Lean 4,
`propext`, `Classical.choice` and `Quot.sound` (pulled in by `simp`, `omega` and `grind`).

**Loans of every owned value are covered since 26 October (C3.8)**, with three explicit assumptions: A13
(a take marked `noloans` carries no loans, and a view into itself does not survive an update), A14 (slot-level ends of loans)
and A15 (forward-take views); see "Loans on owned aggregates" below.

**Calls that return an `emptied` record are covered since C9.4 (A16).** The write-back record of a function
with `mut` parameters, which the caller takes apart at once, is dissolved in the whole-program step; the
corollary no longer excludes the programs that have such a call (26% of the gate corpus, 73% of EDA stage 2 and
80% of selka before; `certcheck` prints the figure).

**The construct-read rule (J6, lane VAL) and assumption A19.** Both checkers refuse a constructor whose result is owned
or `emptied` and that reads a borrow rooted outside the owners it consumes, unless an owned result lists the borrow as a
loan and the certificate marks it a view (`views`, format v2) (`constructReadOk`, `Checker.lean`). A stricter checker
accepts fewer plans, so `check_sound` and the corollary stand as they were; the proof does not use the check
(`InstOk.cread`). Nor can it: the model gives a take out of an aggregate a fresh tree (NOTES.md item 13, A16), so the fault
the rule prevents, the take handing out as an owner storage that another owner still destroys (lane FX6's plan, a
dictionary's keys freed twice), is not a fault of the model. **A19** states what the rule is for, so that the gap is named
where the other trusted points are; per-field provenance in `Semantics.lean` (the A14 estimate, 25 to 40 hours), which
would make A19 a theorem, is not planned (the user's decision of 12 November 2026).

**Task groups are covered since 26 October (C6.2).** The 41 corpus functions that were `unchecked
task-group` are checked and under the theorem: `Fault.lentGone` (a cell lent to a live group is
destroyed) cannot happen, and a lent-to group is consumed only by its join (J2 `group-join`). The
design is §10 of the design document (A7.1-A7.8 below replace the old A7); the Lean pieces are listed
in `NOTES.md` ("The proof"). **A7.5 is the one assumption on the runtime that the proof leans on**:
the call that consumes a group returns only after its tasks are done.

**Status (26 October 2026).** The model was revised to the compiler's real IR (C3.3b) and the
soundness proof was redone on it (C3.4, C3.4b, C3.6 item 1): `Own.check_sound`, `Own.runs_sound`
and `Own.main_no_leak` build and depend on `propext`, `Classical.choice` and `Quot.sound` only
(`#print axioms` in `Soundness.lean` and `Program.lean`). The old proof (C0 model) is on the branch
`certs/lane2-proof-v0`.

| # | Design §8 text | Where it is in the model | Kind |
| --- | --- | --- | --- |
| A1 | The operation-class table (§3) describes what the emitter and the runtime do. | The model is uniform in the operation. `Step.inst` executes *any* instruction from its `reads`, its `consumes` and the result state the certificate gives it. The class table is applied by the exporter (C1.3) to produce those three things, so the exporter is trusted along with the table. The model needs a class only for the take protocol (J8): `isTransfer` is a `Project` with an `owned` result that names a `slot`, and `Inst.isClosing` an `Update` whose operation is in `closingOps` (`record_set`, `array_set`, `list_set`, `list_set_field`, `dict_set_value`, `list_pop`, `dict_remove`); the exporter also supplies `slot`, `released`, `slots` and `from`. | exporter + table; not a Lean statement |
| A2 | `drop` frees exactly its operand's allocation tree, and allocation returns storage disjoint from every live tree. | `Xform` (Semantics.lean). A consumed tree's cells are destroyed (`gone`) or moved into the result tree; no other cell changes (`keep`, `stay`); a freshly allocated cell was `unused`, and addresses are never reused (`dead` is permanent), so allocation cannot return storage of a live tree (`fresh`). `drop` is the instruction with no result: every consumed cell dies. | definition |
| A3 | A managed `undef` is the null owner: it owns nothing and is never freed. It appears as a phi operand (a cleanup phi carries an owner on the paths that built it and the null owner on the rest) and as an unnamed operand of a call or update. | **Revised (C3.3b):** the edge skip is gone. A phi edge from an `undef` is live; its operand is `Val.imm` (the null owner, state `immortal`), consuming it is a no-op (A4), and the checker joins the edge like any other. A void-typed `undef` defines no value. | definition + exporter |
| A4 | Immortal values are never freed, and consuming one changes nothing. | `Val.imm` is the run-time value of every scalar and immortal. `consumedRoots` ignores it, `Val.alive imm` is true, and `Val.cells imm` is empty. | definition |
| A5 | External functions (`myl_core_*`, `extern func`, the reserved marker calls) satisfy their signatures' contracts. | A call is an ordinary instruction, so a callee may do to the heap exactly what `Xform` allows (see "Calls" in Semantics.lean); `Post` states the same contract for a whole function. For an external function this is the assumption. For a function of the program the corollary proves it, since C9.2 from the callee table (a `program` entry, `ProgramSite.lean`). The table's `runtime`, `extern` and `marker` entries are checked for arity only (J1 `call-arity`). | definition; hypothesis of the corollary (`ExternRespects`) |
| A6 | LLVM emission keeps each function's instruction order for ownership effects: no destruction moves above a use. | `Step.inst` runs the instructions of a block in order (`k` to `k + 1`) and a block's terminator last. | definition |
| A8 | (new) A pure `cmp` or `fcmp` of the same predicate on operands whose values were not redefined gives the same answer; integer constants are compared by value. | `Step.branch` and `Step.branchPhiFault` (Semantics.lean): the machine state records the tests already decided (`DState.facts`), a branch decides its test, and it may not go against a decided test; defining a value forgets the tests that depend on it (`clearFacts`). The test a value stands for is `keyOfWith` (Syntax.lean), built from the instruction table and the exporter's `imm N` fields. | definition + exporter (`imm`) |
| A9 | (new) An argument passed for a parameter whose certificate state is `scalar` is an immediate. | The hypothesis `ScalarArgs` of `check_sound` (Entry.lean). An owned-kind parameter of an unmanaged type has the state `scalar`; `Pre` alone does not say its argument is an immediate. | hypothesis of the theorem; exporter |
| A10 | (new) A closing update (`record_set`, `list_set`, `list_pop`, ...) through a value that holds no tree returns a value that holds no tree. | `ResultOk` (Semantics.lean), owned case. A null owner stands for nothing to update. | definition |
| A11 | (new) A value whose certificate state is `stack` is a stack list of this activation, and no other state is. | `ResultOk` (Semantics.lean): a destination with state `stack` receives `Val.stk`, every other destination receives `imm`, an owner or a pointer set; `Inv.stk`/`Inv.nostk` carry it. The exporter's table gives `Fresh` (promoted by `promote.zig`), a filling `Update` and a stack phi the state `stack`. | definition + exporter |
| A12 | (new) The parents the certificate lists for an owned value (a call result, a constructor that holds a view, or an update that stores a borrow into a collection of borrows, RB2) cover every allocation its contents point into. | **Revised (C3.8).** `DState.held` and `heldAfter` (Semantics.lean): an owned result with root `t` holds a loan on every cell of every value its certificate lists as a parent (`held t x`). `Fault.dangling` (reading an owned value whose listed loan operand is not live) stays; the loan invariant `Inv.heldCov` and the fault `lentGone` (a cell held by a live tree is destroyed) are what the proof uses (the check `loansOk`, J4, for every holder). | definition + exporter |
| A13 | (new, C3.8) **A take marked `noloans`, and a view into itself.** (1) A take (`Take` class: `union_take`, `box_take`, `record_take`, ...) whose result the exporter marks `noloans` (its type cannot hold a view) carries none of the loans of the aggregate it comes out of. (2) An instruction that is not a constructor and consumes a tree ends the loans that tree's cells held on cells of the same tree (a view into itself). | (1) `Inst.dropsLoans := i.cls == .take && i.noLoans` (Syntax.lean): `instNext` gives such a take no inherited loans, `carries` is false for it, and `heldAfter` forgets the entries of the tree it consumes. **Every other take, and every other instruction with an owned result, carries the loans of what it consumes** (J4 `loan-outlives-root` is strict for a consumed holder that is carried). The assumption is that `noloans` is true of the type: the exporter writes it from the type (`!m.containsBorrow(inst.ty)`, `ownership_export.zig`), 859 takes in the corpus, among them the `None` arm of the lowering of `copy` of a `T?` (`tests/lang/borrowed_signatures.selka`, `test_read_only_wrapper_arguments_accept_borrowed_slices_and_owned_values`). (2) `heldAfter` forgets the same-tree entries: the checker drops a holder's loan on itself (`dropSelf`), so it cannot protect it across an update that may move the cells. | definition + exporter |
| A14 | (new, C3.8) **Slot-level ends of loans.** A view of one slot of an aggregate points into the storage of that slot, which a `take` of the slot hands to the taken owner. | **Checked half (C9.3):** after a take of slot `k` of `c`, no view in `D` has the root `slot(c, k)` or the wildcard `slot(c, *)` (`take_ends_slot_views`, `SlotEnds.lean`), so none is usable (`take_view_unusable`) and an instruction that reads one fails J4 `read-borrowed-usable` (`read_after_take_fails`). **Assumed half:** the model has one tree per aggregate and no cells per slot, so a take leaves every cell of the container where it is and returns a fresh tree: a view rooted at the taken slot stays live in the model when the taken owner is dropped, and the theorem does not say the checker's rule is what prevents the dangling read. Closing it needs a ghost per-cell slot path and a take that moves those cells into the taken tree, estimated at 25 to 40 hours of Lean (`docs/design/c9-slots.md`); not built. The constructor-operand-to-field table is not needed for it (a constructor without one tags its operands' cells with the wildcard, today's behaviour); it would only make the wildcard precise. Evidence: the gate's fault injection takes a slot while a view of it is read later (`ownership_mutants.zig`) and both checkers reject every mutant. | the checked half is a Lean theorem about the checker's state; the model half is not a Lean statement |
| A15 | (new, C3.8) **Forward-take views.** A view written before the take that will own its storage points, once the take has run, into the taken owner's tree. | Not modelled. `ResultOk` gives such a view an empty footprint, so a use of it after the owner is destroyed is not a fault in the model. The checker keeps the placeholder root `fwd(n)` alive only while the take's owner is live (`rootLive`). The model would have to rebind the footprint of the view when the take runs, and of every copy of it (a phi carries the value), and the checker would have to know that each copy still has the placeholder root at that point (a statement about position that a loop's stale incarnations break). | not a Lean statement; checker only |
| A16 | (new, C9.4) **The storage of an `emptied` call result is the storage of the parts the caller takes out of it at once.** A call whose value the certificate calls `emptied` returns a record (the declared result and the final values of the `mut` parameters, `build.zig` `returnType`) that has no allocation of its own; its managed parts are exactly the fields the caller's takes (`slots`) move out, each once, in the block of the call. | `dissolve`, `callVal`, `callHeap` and `callNext` (ProgramDefs.lean): the whole-program step destroys the callee's result tree and binds the destination to `imm`, and the takes that follow create fresh trees (`Xform`, NOTES.md item 13), as the per-function semantics already treats an `emptied` constructor, `record_get` and `union_take` (item 12). `effect_of_post_emptied` (ProgramLink.lean) shows that step is an `Effect`, so `runs_sound` needs no `noEmptied`. **Enforcement:** `Taking.empty` (`own.zig`) marks a record `emptied` only when each managed field is read exactly once in its defining block; J8 `emptiedOk` demands the same of the certificate (it holds for all 1,269 `emptied` values of the first corpus); the exporter refuses an `emptied` call whose callee returns no owner (`callDisagreement`, design entry 48; `CallWf.resEmptied`). **Evidence at run time:** see "Evidence for A16" below. A model that splits a tree by slot (A14, A15) would replace the dissolution by adoption of the parts. | definition + exporter |
| A17 | (new, C9.2) **A function value points to a function with the signature of its type.** A call through a function value (`call_indirect`) is checked against the entry of its function type (J1 `call-entry`, `call-arity`, `call-scalar`, `call-result`, `call-from`), but no certificate says which function the value points to. | The call keeps the contract semantics (`Step.inst`, as for a runtime function), which is sound when the actual callee, a function of the program, satisfies `Post` for arguments passed as the entry says. That holds when its signature is the type's. `verify_ir.zig` enforces the typing on the IR: a `func_ref` has the signature of the function it names and that function is internal (line 765), and a `call_indirect` has a function-typed callee operand with the result and parameters of the call (line 766), so by SSA typing a value that reaches an indirect call was made by a `func_ref` of a function of that signature. Naming the function at each `func_ref` in the certificate would not narrow the assumption: the certificate follows no values, so the link could compare the named function with its own header and never with the indirect calls the value reaches. **Proved for the Lean copy of the IR verifier** (`VerifyIr.a17`, `proofs/verify_ir/VerifyIr/FnProof.lean`): in a module that checker accepts, every value a register can hold under the small semantics `Reaches` is well typed (`reaches_holds`), so the callee of every `call_indirect` of a reached block is a pointer to an internal function whose signature is the callee's type, whose result is the call's and whose parameters are the arguments' types. Trusted (`proofs/verify_ir/AXIOMS.md`): that the copy agrees with `verify_ir.zig` (the differential, V3); that the operations other than function references, constants, parameters and calls build their results from parts of their operands (V6); that a union payload read in `Reaches` reads its own case (V7, narrowed in V4: `verify_ir.zig` now refuses a payload read the tag facts do not justify, and `VerifyIr.payload_of_verdict` proves such reads see their own case on every run of the tag semantics, V9; the step from those runs to `Reaches` is a modelling step, and the `list_get` reads of shape M are counted by the gate action, not justified); that the runtime returns, and passes to callbacks, values built from what it was given (V8, part of A5). | proved for the Lean copy; trusted: the differential, V6 to V8 |
| A18 | (new, O4, 8 November 2026; extended to frame blocks, RB1, 9 November 2026, and to collections of borrows, H5, 10 November 2026, by the user's decisions) **Frame storage is never returned by the call that made it.** `box_frame` is a stack slot of the call that executes it (one per parameter, written once at entry, class View, never dropped): a lent option `Some(p)` of a read-only record parameter. `block_frame` (RB1) is the block a borrowed record, or an element of a local collection of borrows (H5), holds for a read-only text, bytes or list parameter (class View of the parameter, never dropped by the ownership pass): the parameter's C9 owner when the argument was a whole value, else a shallow copy of the view with static storage, made lazily at the parameter's first such use in the call, kept in one slot per parameter (an entry-block `alloca ptr`, null until then) and freed by `myl_core_frame_block_release` before every `ret` of the call (`emit_block_frame.zig`). No value holding frame storage its own call made is returned, even under `from`; a box an ancestor made may be returned `from` the parameter that holds it. | Not modelled: a View of a parameter is returnable in the model, which does not tell frame storage from any other view, and the model has no free at return. Enforced by the ownership checker (`Roots.frame` with rule R4 for a frame box; `Roots.block_frame`, which keeps a return of a frame block's record on its owning construction, so it is refused as before RB1 with `E_SINGLE_OWNER_BORROW`, rule R1), by Core's `borrow_result` backstop, which never accepts a returned borrow reaching the call's own `box_frame` or `block_frame`, and by both Core inliners, which never inline a function that holds a `block_frame` (its slot is per call); tests in `src/core/borrowed_parent_test.zig`, `src/core/record_sources_test.zig`, `src/core/frame_block_collections_test.zig`, `tests/lang/borrowed_parents.selka`, `tests/lang/record_sources.selka` and `tests/lang/frame_block_collections.selka`; `experiments/borrowed-parent-20261108/DECISIONS.md`, `experiments/record-sources-20261109/DECISIONS.md`, `experiments/ownership-matrix-20261109/DECISIONS.md` (H5). | not a Lean statement; checker, `borrow_result` and the inliners |
| A19 | (new, VAL phase 2, 13 November 2026, by the user's decision of 12 November) **The parts an owned or `emptied` constructor hands out are the trees it consumes or the views it lists.** The destruction of an owned aggregate, and an owned take out of an owned or `emptied` aggregate, release only storage that the constructor consumed (its `consumes`) or that is reached through a borrowed operand the certificate lists in its `views`, which the destruction leaves alone (the operand's slot type is not managed: a span, a list view, a borrowed overlay, a record of those). Equivalently: no constructor stores a borrowed managed value (a `str`, list, dictionary or managed record it only reads) into a slot its destruction or a take would treat as owned. | Not modelled. The model gives every take a fresh tree (NOTES.md item 13) and destroys only an aggregate's own tree, so it does not connect what a take hands out to the operand that filled the slot; a plan that broke A19 (lane FX6's) faults nowhere in it. **Enforced by** J6 `construct-read` in both checkers (each borrowed operand an owned or `emptied` constructor reads is rooted in owners it consumes, or, for an owned result, is a listed parent and a listed view) and by the exporter's `views` (`ownership_export.viewsOf`: a borrowed operand whose slot type `ir.Module.managed` says is not managed). The view marks are the exporter's statement about types, trusted like the class table (A1). **A proof needs** per-field provenance: each cell tagged with the slot path it was stored at, a take that moves the cells of its slot into the taken tree, and a destruction that frees only cells of managed slots (`docs/design/c9-slots.md`; 25 to 40 hours, not planned). | assumption, checked as stated |
| A7.1 | (C6, design §10.5) A lent box has no layout: destroying it, or an environment that holds it, releases the lender's storage never. | A lend is a `Construct` that consumes nothing and yields a fresh owned tree (the box); the lender stays owned or borrowed where it was. The model never destroys the lender through the box. | exporter + emission; not a Lean statement |
| A7.2 | A task reads the storage lent to it and only that, read-only, between its submit and the end of its group. | Not modelled: the model does not run tasks. It forbids the submitter from destroying what a task may read: `Fault.lentGone` (`LentSafe`, Semantics.lean), proved absent by `lentSafe_ok` from the lent-cell invariant. A view parameter given to a task is stored in the task's environment as the view (FR58, by the user's decision of 17 November 2026): the validator sees the loan in the environment's record and does not follow it through the box, so that this loan ends before its root does rests on the source check (the parameter is read-only in the submitting function; K1 refuses a moved or written argument, K2 an escaping group) and on A7.5 (the group joins before the call returns). | modelling choice + runtime |
| A7.3 | `myl_core_owned_task_submit_indexed(g, run, env, item)` consumes the environment, reads the group and returns the task's index. | An ordinary call (A5): `Xform`; the group is read, the environment consumed. | A5 |
| A7.4 | `myl_core_owned_group_take(g, i)` waits for task `i` and returns its result box (owned); the group must be open. | An ordinary call (A5). Reading the group after its join is J3. | A5 |
| A7.5 | `myl_core_owned_group_end(g)` returns only after every task of the group has finished, and consumes `g`. | The group's consumption is a call that returns nothing (checked: J2 `group-join`), so by `Xform` the group's root cell is destroyed and the obligations of the lent cells end there. That the call waits is the assumption. | checked shape + runtime |
| A7.6 | `myl_core_group_open()` returns a fresh group, disjoint from every live tree. | An ordinary call result (`Xform.fresh`, A2). | A2, A5 |
| A7.7 | A group is confined to the thread that opened it. | Not modelled (`R_TASK_ESCAPE` is the runtime's backstop of `E_TASK_ESCAPE`). | runtime |
| A7.8 | `myl_core_owned_map` and `myl_core_owned_map_with` join before they return and treat their source and extra arguments as borrowed for the call. | Ordinary calls (A5); a lend inside the standard library's `map_with*` instances is checked like any other. | A5 |

## What the theorem does not cover

**J7 (stack escape) is covered since 26 October (C3.6, item 1).** A stack list is a value of its
own kind, `Val.stk` (an allocation in the activation's frame: no heap cell, no destruction, gone
when the activation ends), and escaping is a fault, `Fault.escape`: consuming a `stk` value other
than as the first operand of an update whose result is a stack list (a filling push), pushing a
value that owns a tree into one (a stack list holds no managed elements, so the tree would never be
destroyed), or returning one. The checker's J7 (`stackOk`, `ret-stack`) is what the proof uses to
show no execution reaches the fault. The assumption is **A11** below. Not covered: storing an
`emptied` value in a stack list (an `emptied` value is `imm` at run time, so the model cannot tell
it from a scalar; the checker refuses it).

**Loans on owned aggregates are covered since 26 October (C3.8, after C6.2 for task groups).** A cell an
owned tree points into (A12) is a `held` entry; `Inv.heldCov` says a cell held by a live tree is in that
tree or covered by a live root of the loans of its owner, and `Fault.lentGone` says destroying such a cell
before its holder goes is a fault. The checker's `loansOk` (J4 `loan-outlives-root`) is what the proof uses
for every holder, and `usable` refuses the read of a holder whose roots are gone. Loans are carried: a
constructor inherits the loans of the owners it consumes and renames the roots, a phi moves the holder
with its roots, and any other instruction with an owned result (an update, a call) hands the loans of
the owned values it consumes on to its result; a consumed holder whose loans are carried may not have a
loan root consumed in the same instruction (strict J4). A holder that is dropped, or consumed by an
instruction without an owned result, takes its loans with it (its cells die); so does a take marked
`noloans`. Not covered: **A13** (the `noloans` mark; a view into itself), the slot-level end of a loan (**A14**), and the loans of a value reached through an
`emptied` aggregate (the parts a take moves out are fresh trees: A16).

**Explicit gap, assumption A15: a view whose parent is a later take** ("forward take"). The checker enforces its
lifetime (the placeholder root `fwd(n)` must be alive); the semantics gives such a view an empty
footprint (`ResultOk` excludes forward parents), so the theorem does not say a use of it after
the owner is destroyed is a fault. The same holds for the view an `emptied` constructor reads of
the owner it consumes (J6 exception, lane 1's entry 28): the model destroys the consumed tree, and
the checker allows no later use of the view. Closing the gap means letting a take out of an
`emptied` aggregate adopt the cells the view points into (NOTES.md, "Open gaps").

**Outside the whole-program corollary:** a call whose result is a stack list (`CallWf.noStack`). A callee cannot
return its own stack allocation (`ret-stack`, J1). A call whose result is an `emptied` record is inside since C9.4,
under A16.

**The whole-program corollary** (`runs_sound`, `main_no_leak`, the callee contract of A5 for a
checked function) is proved on the revised model (`Program*.lean`); see the last section.

## Evidence for A16 (emptied call results)

What enforces it is in the A16 row: `Taking.empty`, J8 `emptiedOk`, `callDisagreement`. What the run time shows
(26 October 2026, compiler at main `23504dbb5`, release export of the gate corpus, 632 programs):

* **Static count.** 896 call results in state `emptied` in the unique functions of the gate corpus that are not the test
  runner's (C9.0 counted 891 with a slightly different rule). 661 of them are in functions of programs of `tests/lang`,
  `tests/value_semantics` and `tests/ported` (531 in `test_*` functions, 130 in helpers); 235 are in programs of
  `test/core` (32 programs), `benchmarks` (2) and `examples` (3). 129 programs of the first three suites have such a call.
* **The gate's leak-checked release run** (`test-lang`: `selka test` of those three suites with `--release --verify-facts`
  and `SELKA_CORE_LEAKCHECK=1`, which reports the blocks still allocated at exit) builds and runs all 129 programs
  and reports no leak. That is evidence about the 661 calls only as far as they are executed: every `test_*` function runs
  its body, but a call on a branch no test takes, or in a helper no test reaches, is not exercised, and I did not measure
  which calls run. So the run does **not** show that all 891 calls run.
* **The programs outside those suites** (37 with an `emptied` call): the gate's leak-checked run does not cover them. I ran 35
  by hand with `SELKA_CORE_LEAKCHECK=1 selka run … --release` (`selka test` for files without a `main`; the two servers
  `examples/http-server` and `examples/event-loop-echo` I did not run). 23 ran to the end with exit status 0 and no leak line
  (22 of `test/core` and `examples/standard-time-random`). 12 did not run clean as standalone programs (a missing C link
  file, a bounds trap, trials that fail by design, an exit status 2 for the two benchmarks; I did not investigate each) and
  give no evidence.
* A trap ends a process without walking owners and is not checked by the leak check, so a leak on a path that traps is
  invisible to it.

## Trap regions: not an assumption (C9.1)

An edge into a trap-region block names the owners the path leaks (`abandon` lines). The semantics treats that as a no-op on
memory plus a ghost record (`DState.abandoned`); the checker's J2 checks make it sound, and `main_no_leak` keeps its meaning
because a `ret` is never reached from the trap region. What this relies on at run time is only what the property says: the
process ends at a trap (`RC-TRAP-TEARDOWN-1`), so an abandoned owner is never read or destroyed again. The exporter's lists
(from `own.zig`'s skipped deaths) are checked, not trusted: a missing owner is a join mismatch (J2), an owner that is not live
on the edge is `abandon-live`.

## Not an assumption, but a modelling choice

`NOTES.md` lists every definition the design leaves open (how a take is modelled, per-slot
pending flags, what a closing update is, the shape of `Pre`, and so on). Each is a definition,
not an axiom, and each is visible in the statement of the theorem.

## `#print axioms`

`lake build` prints, at the end of `Soundness.lean`:

```text
'Own.check_sound' depends on axioms: [propext, Classical.choice, Quot.sound]
```

No `sorry`, no `native_decide`, no `axiom` declaration.

## Hypotheses of the whole-program corollary

`runs_sound` and `main_no_leak` (`Program.lean`) assume `ProgWf prog` (`ProgramDefs.lean`): **every function of the program
passes `check`** (the checker; `certcheck` and the Zig validator), and **the callee tables of the program link**
(`linkOk`, `Link.lean`; `certcheck --link` and `selka link-certificates`): every table entry of kind `program` names a
function of the program, and describes its header (the number of parameters, the state of each, the result, the borrow
contract). Nothing else is assumed about the program. In particular the call-site agreement `CallWf` is no longer a
hypothesis: the checker has established half of it for every call line (`InstOk.centry` to `cfrom`: the line names an entry
of its function's callee table; its arguments fit the entry's parameters, in parameter order; a scalar parameter receives a
scalar; its value follows the entry's result; a borrowed value lists the arguments of the borrow contract as parents), the
link the other half (the entry says what the callee's header says), and `callWf_of_site` derives it. `NOTES.md` lists every
hypothesis and who enforces it ("Hypotheses of the whole-program corollary").

The premises of `main_no_leak` that are about the run, not the program: the entry function has a scalar result, and it is
started on an empty heap with arguments that meet `Pre` and `ScalarArgs` (the process passes capability handles and
scalars). Calls to functions outside the program (the table's `runtime`, `extern` and `marker` entries) are resolved by the
contract (A5) and calls through function values by the contract, under A17: `Step.inst`.
