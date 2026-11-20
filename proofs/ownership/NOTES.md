# Definitions the design did not give

**Revised 26 October 2026 (C3.3b, C3.5, then guards, loans and C3.4).** The compiler's real IR is
authoritative: the design document on main (`docs/design/ownership-certificates.md`, after C1)
replaced the C0 text this model was first built on. `Syntax.lean`, `Semantics.lean` and
`Checker.lean` follow it, and the soundness proof (`Soundness.lean` and the files it imports) is
redone on the revised model: `check_sound` builds, with no `sorry` and only the axioms
`propext`, `Classical.choice`, `Quot.sound`. The C0 proof is on the branch
`certs/lane2-proof-v0`. `lake exe certcheck` runs over the real corpus (see "Findings from the
corpus" at the end).

## Single list for the Zig validator (differential test)

Everything the Zig validator (lane 1) must do the same way as `Checker.lean`. Items marked
**new** are not in the design text yet or differ from it; each is explained below or in the
section named.

1. **State** `(L, D, R, P, G, F)`.
   * `L`: owned values defined and not yet consumed. **`stack`, `emptied`, `immortal`,
     `scalar` and `none` values are never in `L`.**
   * `D`: borrowed values defined on every path to the point.
   * `R` **(new)**: for each borrowed value of `D`, and for each owned value that holds a loan,
     its roots on this path (owned values, `slot` roots, `caller(i)`). Flow-sensitive, see
     items 2 and 18.
   * `P` **(new, per slot)**: the open takes, as pairs `(container, slot key)`.
   * `G` **(new)**: guarded takes `(container, slot, test, polarity)`: open exactly when the test
     came out `polarity` (item 19).
   * `F` **(new)**: the decided tests, each with its outcome when the paths that met agree.

   Joins: `L` equal as sets; the open and guarded takes fit (`slotsFit`); the decided tests fit
   (`factsFit`); `D` of the target contained in the edge's `D`; each edge's roots of a name of the
   target's `D` or `L` contained in the target's roots. The target's entry state is the join of
   its edges (`joinState`): the solver proposes it, the recheck verifies it.
2. **Roots follow ownership (new).** A borrowed result gets the roots of its parents: an owned
   parent is its own root (a view of one slot of an owned container is rooted at that slot,
   item 18), a borrowed parent contributes its recorded roots, a `caller(i)` stays, a parent that
   is a take defined later is the placeholder root `fwd(n)` (item 5). When an owned phi consumes
   an owner `o`, or a `Construct` consumes it, every recorded root `o` becomes the new holder (the
   storage does not move); all the moves of one edge happen at once. A borrowed phi's roots on an
   edge are the roots of its operand on that edge (an owned operand is its own root).
3. **Usable.** Scalar, immortal, stack and emptied values always; an owned value when it is in
   `L`; a borrowed value when it is in `D` and every root is alive (an owned root in `L`, a
   placeholder root once the take defined its owner); a value in the state `none` never (a read of
   it is a J3 failure, except as a consumed no-op operand).
4. **Redefinition.** Defining an owned value removes from `D` (and keeps out of `D`) every name
   that has it among its roots. A view written before a take of the same container keeps its
   placeholder root `fwd(n)` and becomes usable when the take defines `n`. Defining a value also
   forgets every decided test that depends on it (item 19).
5. **Parents (J1).** A borrowed result's parents are operands the instruction reads, a parent
   of a read operand that is borrowed **or an owned call result holding loans** (a projection
   of such a value is lent by the same owners), or a **later take of the container being read**
   ("forward take": `inst %8 record_get ... borrowed parents %9` with `%9` the take of the
   same slot defined right after, or the take replaces a view the instruction reads), or, for a
   projection, **a `from` value of the call its container comes from** (design §3, Project, R3: a
   leaf of a call's result borrows what the callee's `from` contract names; the call may return an
   `emptied` record, which lists no parents of its own; `callFromOperand`, C9.4). Each
   parent is usable where the result is defined, except a forward take. An owned result may
   list parents (loans on an owned aggregate): they must be operands the instruction reads.
6. **Phis (design §3).** Dead phis (state `none`) are skipped. An owned phi takes owned or
   immortal operands; it consumes the owned ones; **an `undef` operand of a managed type is the
   null owner (immortal): its edge is live (the edge skip approved at C3.3 is removed), and
   consuming it is a no-op.** A stack phi takes stack operands and is not in `L`. A borrowed
   phi takes borrowed or immortal operands, or the owned value it selects between (the owned
   fallback of a borrowed selection, not consumed); its roots are those of its operands.
   Scalar and immortal phis take scalars and immortals. A phi never consumes a container with an
   open or guarded take; two phis never consume one value; a phi never defines a value already
   live; a phi never defines a value a guard depends on.
7. **`ret`.** **A take still open is reported first (J8 before J2, entry 37).** Owned result: `L` is exactly the returned owned value (or empty for an
   immortal); never a stack or borrowed value. Borrowed result: the value is borrowed (usable,
   all roots `caller(i)`, `i` in `from`), immortal or scalar. Otherwise scalar or immortal.
   `P` and `G` are empty and, but for the returned value, `L` is empty.
8. **Take protocol, per slot (J8, new).**
   * A *take* is a `Project` whose state is `owned` or `emptied` and that names a `slot`. A take
     of an `owned` container requires the container in `L` and `(c, k)` neither open nor
     guarded, and adds `(c, k)` to `P`. A take from an `emptied` aggregate is a complete move:
     nothing is pending, nothing is required of `L`.
   * *Closing updates* are `record_set`, `array_set`, `list_set`, `list_set_field`,
     `dict_set_value` (slot `k`), `list_pop` (the slot it names; `tail` closes none) and
     `dict_remove` (the entry it reads: slots `k%E` and `v%E`). A container with an open take
     is consumed only by a closing update, as its first consumed operand. The update closes the
     slots it names (none of them guarded) and passes the container's other open and guarded
     takes on to the container it returns (when the result is `owned`).
   * `released` agrees with the slot (`closeAgrees` in `Syntax.lean`): `released -` needs the
     slot open, `released old` needs it not open; `record_set`/`array_set` need the slot open;
     `list_pop` of a named slot needs it open; `dict_remove` may release `key`/`value` only
     when `k%E`/`v%E` is not open.
   * A phi may not consume a container with an open take.
9. **`emptied` aggregates (J8, new).** The value is defined by an instruction (never a phi),
   is never consumed, and every use of it is the first read of a `Project` in the block that
   defines it; each key of the definition's `slots` is taken exactly once, and no other slot is
   taken. (Verified on all 1,269 `emptied` values of the corpus.) A misuse is reported at the
   instruction that misuses it (a second take of a slot, a slot the aggregate does not list, a
   consumption or a read as a whole: `b0 3`, `b0 2`), as the Zig validator does; a slot never taken
   and a use outside a projection (a phi, a branch, a `ret`) are reported for the function (`b- -`).
10. **Consumption.** A scalar, immortal, stack or `none` (void-typed `undef`) operand at a
    consumed position is a no-op; a borrowed one is J5; an `emptied` one is J2. A consumed
    owned value is in `L`. **`stack` values (J7):** consumed only by an `Update` whose result
    is the same stack list (a filling push), never dropped, returned, stored, built into a
    constructor or passed to an owned call position; **and a stack list holds no managed
    elements: what is pushed into it is not an owned, emptied or stack value** (design §9 entry
    26; the Zig validator's `stackRules`). J7 is covered by the theorem since C3.6 (`Val.stk`,
    `Fault.escape`).
11. **J6.** No value fills two consumed positions of one instruction; a consumed operand is not
    read by the same instruction; a consumed owner is not a root (or the container of a slot
    root) of another operand, except that a `Construct` with an owned result may read a view of
    the owner it takes (the loan it records, which the result lists among its parents), and a
    `Construct` with an `emptied` result may read a view of the owner it takes whatever its
    parents (lane 1's entry 28: `borrowed_signatures`). Every `Construct` is exempt from J4
    `loan-outlives-root` (the loans move with the storage).
    **`construct-read` (lane VAL, design entry 61):** a `Construct` whose result is owned or `emptied`,
    and that is not a lend, reads a borrowed operand only when every root `R` records for it is an owner
    the instruction consumes (or a slot of one), or when the result is owned and lists the operand among
    its parents and among its `views` (format v2: the borrowed operands it reads into a slot whose type its
    destruction leaves alone; J1 `views` asks that they be operands of a constructor). A borrowed operand
    rooted in the caller, in a forward take (`fwd`) or nowhere fails
    (`reject J6`, tag `construct-read`, checked after the other J6 checks in both checkers). The Zig
    validator counts it in builds (`build_mode`) and refuses it everywhere else.
12. **Trap regions and `abandon` lines (C9.1, design entry 55; replaces the trap meet of C3.8).** Every block is an
    ordinary block: the edges into it must agree (`joinCompat`: equal `L`, open takes that agree up to guards, `D`
    intersected, `R` united). `own.zig` schedules no drop on a path that ends in a trap, so such edges used to disagree;
    now the block carries `abandon bP %V,…` lines (`Block.abandons`, one line per predecessor, values strictly ascending),
    and the edge from `bP` removes the listed owners from `L`, and their open and guarded takes from `P` and `G`
    (`AbsState.abandon`), before the block's phis take their operands. `D` and `R` stay: a view of an abandoned owner, and
    an owned value that holds a loan on one, is no longer usable (its root is not in `L`), the way a drop ends it, and
    the loans an abandoned holder holds are not looked at again. The checks, in this order: J1 `abandon-shape` (a line
    for a block that is not a predecessor, a predecessor twice, values not strictly ascending), reported at the target
    block with no instruction; J2 `abandon-region` (the target is not in the trap region), `abandon-live` (a value that
    is not an owned value live on the edge: a scalar, a borrowed value, an `emptied` aggregate and a value already
    consumed are refused) and `abandon-group` (a lent-to group is never abandoned: its tasks read the lent cells until the
    process ends), reported at the predecessor's terminator. The **trap region** (`region`) is the least fixpoint of
    "ends in `unreachable`, or has successors and all of them are in the region"; a region block never returns, and its
    successors are in the region. Removed: `meetState`, `trapCompat`, `trapChain`, `trapDsts`, `trapB`, `trapLocal`,
    `trapFresh`, `trapHolders`, `TrapShadow.lean`.
13. **Pre-block and placement (new).** `param` and constant instructions may appear inside
    blocks (the exporter keeps a re-read of an argument and some constants where the builder
    put them): a `param` in a block changes nothing; a constant defines a value. Block ids may
    have gaps (the exporter drops blocks nobody can reach); a gap is an empty
    `unreachable` block, and an edge to a block the file lacks is a malformed file. An owned
    parameter whose value is `scalar` (an unmanaged value passed to a taking parameter) owns
    nothing. **A value is defined once** (check `dst-unique`: instruction and phi values are
    pairwise distinct); the guarded takes and the proof rely on it.
14. **Solver and recheck.** Forward passes in reverse postorder, repeated until no entry state
    changes (loops need up to a few rounds), then the recheck: every block that has an entry
    state is run again from it and every live edge is compared with its target's entry state
    (item 1), back edges included. `check` is the recheck's verdict. **A loop head forgets the
    decided tests** `F` when it is first entered (the decisions known on entry need not hold on
    the back edges; a loop head is a block some edge returns to, a successor not after its source
    in the reverse postorder), as the Zig validator does. **Fast:** the proposal of the solver is an
    array computed once (`solveArr`); a function-typed definition (`solve`) is compiled with the
    function's parameters and would run its body again at every application. The largest corpus
    function takes 0.04 s (it took 168 s), each corpus about 4 s on one core, and `certcheck` checks
    the files in parallel.
15. **Heap contract** (design §6): `Pre` has `wf` and `apart`.
16. **Parameters.** `param <I> %N <state>`; a borrowed parameter's parents are `[^I]`.
17. **Void values.** An instruction without a destination (`inst - call`, void-typed
    `undef`, marker calls) defines nothing; a value that is the unnamed operand of such an
    instruction has no state (`none`).
18. **Loans (J4, new).**
    * A view of one slot of an owned container (a borrowed `Project` with a `slot`, whose first
      read is an owned parent) is rooted at that slot: `slot(container, key)`. It ends when the
      container is consumed, or when that slot is taken (a taken slot also ends a view rooted
      at the wildcard slot `*`, which is what a constructor leaves of a slot root it absorbs).
    * An owned value that lists parents (a call result or constructor holding a view) *holds the
      loan*: while it is in `L`, no root of the loan may end. Consuming a root owner while the
      holder lives, or taking the rooted slot, is J4 `loan-outlives-root`. A constructor that
      consumes an owner does not end the loans on it (the storage moves into the aggregate): it
      inherits the loans its operands held, and loans on the constructor's own result are
      dropped. A phi that consumes a holder carries its loans.
19. **Guarded takes and decided tests (J8, new).** The export gains a trailing ` imm <decimal u64>`
    (the instruction's `data`) on `iconst`, `cmp` and `fcmp` lines.
    * *Same test.* Two branch conditions are the same test when they are the same value, or
      the same pure `cmp`/`fcmp` (same predicate) of the same operands, constants being
      compared by value (`iconst` operands by `imm`): `Key` in `Syntax.lean`.
    * *Facts.* A branch decides its test on each outgoing edge: `F` gets `(test, outcome)`. An
      edge whose test is already decided the other way is infeasible and is not taken. Defining a
      value (an instruction or a phi) forgets the tests that depend on it; a guard that depends
      on a value being defined is a J8 failure (`guard-redefined`). At a join a test stays
      decided when all the paths decided it; its outcome stays known only when they agree.
    * *Guards.* A slot open on one edge into a join and not on another becomes guarded at the
      join by a test the two edges decided differently: `(container, slot, test, outcome of the
      edge where it is open)`. A later branch on the same test (same key) decides it: the true
      edge turns the guarded take into an open one, the false edge drops it. A guarded take
      cannot be taken, closed or consumed with its container; at `ret` there is none.
    * *Edge fit.* The edge state fits the entry state when: what the entry says is open is open on
      the edge; each guarded take of the entry is what the edge says (open when the edge decided
      the test the guard's way, closed when the other way, the same guard while undecided); an open
      take of the edge is open in the entry or guarded there under a test the edge decided that
      way; each guarded take of the edge is guarded in the entry; the guarded containers are live
      (this clause is needed by the proof, `Inv.Gin`: a guard names a container of `L`).
    * *One guard per entry.* A slot has one state in the join: open, closed, or guarded by one
      test and polarity. An entry that is guarded by a different test on each edge, or open on
      one edge and guarded on the other where the open edge did not decide the guard's way, has
      no single decision to carry: the join is refused (J8 `join-pending`), as in the Zig
      validator's `guardedBetween`.

20. **Named unit values and `taken` (v2 export).** A unit value an instruction names is
    `inst %N undef Constant ... state none` (or a `Call` line): it owns nothing, consuming it is a
    no-op, reading it is J3. `dict_remove` exports `slot v<I>`, `released PARTS` and
    `taken PARTS`: the parts it finds already moved out. It closes the slots `taken` names (both
    when the export says nothing), a taken part must be pending, a released part must not be, and
    it passes the container's other pending slots on.

21. **Task groups (C6, design §10).** The class table gives the lend no class of its own: a
    `box_make` with `flags.lent_box` is a `Construct` line with the extra `lent %G`.
    * *Lend shape (J1, `lend`).* `lent %G` appears only on a `Construct`; the lend reads exactly
      two values, the lender first and `%G` second (`%G` is owned and is not the lender), consumes
      nothing, has state `owned` and no parents.
    * *Effect.* The lend gives its own result (the box) the roots of the lender; it adds the same
      roots to the group `%G`, and **the group's own value as a root of itself** (`.val G` in
      `R(G)`): that is the state's mark that `G` has been lent to. Joins unite the roots, an owned phi
      moves the entry with the group.
    * *Join (J2, `group-join`).* A value that carries the mark is consumed only by a call whose
      result state is `none` (`myl_core_owned_group_end`): not by a constructor, an update, a take, a
      drop, nor a call with a result. Checked after `consume-live`.
    * *Strict emptied constructor (entry 41).* `loan-outlives-root` exempts a constructor only when
      its result is `owned` (it moves the loans with the storage); a constructor whose result is
      `emptied` destroys what it consumes.
    * *Trap regions.* A group is never abandoned (J2 `abandon-group`, item 12): its tasks read the lent cells
      until the process ends. (Before C9.1 an edge into a trap block had to keep the groups of its `L` in the
      meet, `trap-group`, then `trap-holder`, items 21 and 22 of the C3.8 text.)
    The loans themselves are the existing J4: while the group is in `L`, consuming a root of its
    loans, or taking the slot a lent view lives in, is `loan-outlives-root`; the group is exempt on
    the instruction that consumes it.

22. **Holders on a path to a trap (C9.1).** An owner that holds loans and is live on some edges into a trap-region block
    only is listed on the edges that have it (`abandon`), and then its loans end with it (item 12); unlisted, the edges
    disagree (J2 `join-live`). `trap-holder` and `trap-group` of C3.8 are gone.
23. **A re-read of a parameter in a trap block** needs no rule any more: the block is an ordinary one.

24. **Loans are carried through every consumer with an owned result (C3.8).** `instNext` gives an owned
    result the loans of the owned values it consumes for every class (a constructor renames the roots of
    the owners it takes, the others do not), except a take marked `noloans` (`Inst.dropsLoans`, A13). `loan-outlives-root`
    is strict for a consumed holder that is carried: it is exempt only if the instruction has no owned
    result or is a take (`loansOk`: `consumed && !carries`). So `list_push` of a record that holds a view
    of `%0`, then `drop %0`, is `reject J4` at the drop; a call that consumes a holder and returns an owned
    value does the same; a holder consumed together with its own root by such an instruction is `reject
    J4` at that instruction.

`docs/design/ownership-certificates.md` is the specification. Where it stops, the model
takes the smallest definition consistent with it. A choice that needs lane 1 (the Zig exporter
and validator) to agree is marked **(lane 1)**.

## Syntax (Syntax.lean)

1. **Parameter numbering.** The export names the value of each parameter explicitly,
   `param <I> %N <state>`. `Function.paramVals[I]` is `%N`.
2. **Class spellings (canonical).** The parser accepts `Parameter Constant Pure Inspect Fresh
   Copy Project View Character TextFrame Borrow Update Construct Take Drop Call Output Trace` on
   `inst` lines, plus `Join Forward Jump Branch Return Trap` in `class` lines. `Forward` is the
   class of the operation `copy` (`class copy Forward`; a `copy` is resolved away and never
   appears on an `inst` line); `Join`, `Jump`, `Branch`, `Return` and `Trap` classify `phi`,
   `jump`, `branch`, `ret` and `unreachable`. `Copy` is a different class (an operation that
   copies a value into fresh storage) and does appear on `inst` lines.
3. **`Certificate` is two total maps** (`state`, `parents`), built from the `inst`, `phi` and
   `param` lines. A value no line defines has state `none`.
4. **The extras of an `inst` line** (design §4.1): `slot KEY`, `released PARTS`, `slots KEYS`,
   `from VALUES` (calls), `imm N` (`iconst`, `cmp`, `fcmp`; optional on every line).
   `St.emptied`, `Class.forward`, `Root.slot` and `Root.fwd` are new; the last two arise inside
   the checker only.
5. **Operation sets.** `closingOps`, `storeOps` and `takeOps` (the last is documentation: a take
   is recognised by class `Project`, state `owned`/`emptied` and a `slot`). `closeAgrees` and
   `closedKeys` (shared with the semantics) say what a closing update does with the open slots.
6. **Names.** A function name is kept as the file spells it (`\xHH` escapes are not decoded):
   verdict lines print the exporter's name.
7. **Tests.** `Key`, `keyOfWith` (the canonical form of a test), `forwardTakeWith` (shared
   between the checker and the semantics), `Function.defOf?`.

## Semantics (Semantics.lean)

8. **Uniform instruction.** One step rule serves every class; the proof does not use the
   class-shape part of J1 (the exporter's table, A1).
9. **Heap.** Cells are `unused | live t | dead`; addresses are never reused. A tree is the
   cells with one label; its root is the cell whose address is the label. The model does not
   split a tree by slot: a `slot` root covers the cells of the whole aggregate.
10. **Borrowed values** are pointer sets `bor fp`, in the trees of the result's `parents`
    (`ResultOk`), except that **a view whose parent is a take defined later (a forward take) has
    an empty footprint**: see "Open gaps".
11. **Consumption of scalars and immortals** is a no-op. **(lane 1)**
12. **`stack` and `emptied` are `imm` at run time.** A `stack` value owns nothing that must be
    destroyed (the pass schedules no drop); an `emptied` aggregate owns nothing (its parts were
    taken). A managed `undef` is the null owner, `imm`.
13. **Takes (J8).** The read's result is a fresh tree (or `imm` for a take whose result is
    `emptied`) and the container's slot is marked `pend t k`; what the model keeps is the
    obligation: consuming a container with a pending slot, other than as the first consumed
    operand of a closing update, is the fault `stranded`, as is a take of an open slot, a take
    out of a container that is not an owned live tree, and a closing update whose `released`
    mark disagrees with the slot. The closing update passes the other open slots to the tree it
    returns. **So the model cannot show why the construct-read rule (item 11) is needed.** A take
    out of an `emptied` aggregate, or out of an owned one, is a fresh tree whatever operand filled
    the slot, so an `emptied` record that read a borrow of a dictionary's key and handed it out as an
    owner (lane FX6's plan, the keys freed twice at run time) faults nowhere in the model. The checkers
    refuse that plan and the theorem holds of the stricter checker unchanged; a model in which the take
    hands out the cells of the operand that filled the slot (per-field provenance, the A14 estimate,
    not planned) would make the rule part of the theorem; it is stated as assumption A19 instead
    (AXIOMS.md, lane VAL phase 2, the user's decision of 12 November).
14. **`Pre`** adds `wf` and `apart` (see C3.2); `Post` is as in C3.4 of the old model, with
    per-slot `pend`.
15. **Phi evaluation.** All live phis of a block read the old environment; a phi operand that
    is not live faults (`readDead`); the value flows unchanged, except that a *borrowed* phi that
    selects an owned operand holds a pointer to its tree (`Val.toBorrowed`). A dead phi is
    skipped. There is no edge skip for `undef`.
16. **Constructors retain.** J6 lets a `Construct` with an owned result consume an owner it also
    reads a view of (the loan the aggregate records). The semantics matches: such a
    `Construct` keeps every consumed cell in its result tree (`Retains`) and is exempt from the
    `overlap` fault. A `Construct` with an `emptied` result is exempt from `overlap` too (the
    storage moves into the parts that are taken out at once), but destroys what it consumes, so
    a view of the consumed owner is dead afterwards and the checker allows no later use of it;
    the views of the taken parts are the forward-take views of "Open gaps".
17. **Traps.** Any instruction may trap; `unreachable` traps.
17b. **Stack lists (C3.6).** A `stack` value is `Val.stk`, a frame allocation with no heap cell.
    `Fault.escape` (`NoEscape`): a `stk` value consumed other than as the first operand of an update
    whose result is `stack`; a value that owns a tree pushed into one; a `stk` value returned
    (`Step.retEscape`). `Inv.stk` (a stack-state value holds `imm` while undefined, then `stk`) and
    `Inv.nostk` (nothing else holds `stk`).
18. **A `Parameter` instruction in a block** re-reads an argument and changes nothing.
19. **Decided tests (A8).** `DState` records the tests already decided on the path. A branch
    whose two targets differ decides its test (`setFact`) and may not go against a decided
    test; defining a value, by an instruction or a phi, forgets the tests that depend on it
    (`clearFacts`). This is assumption **A8**: a pure `cmp` or `fcmp` of the same predicate on
    operands that were not redefined gives the same answer, constants being compared by value.
20. **Closing through an immediate (A10).** A closing update whose first consumed operand holds no
    tree (`imm`) returns an immediate. Without it a take of a null owner and a later pass-on to
    a fresh tree would have no counterpart in the heap.
21. **Scalar arguments (A9).** `check_sound` takes the hypothesis `ScalarArgs`: an argument passed
    for a parameter whose certificate state is `scalar` is an immediate (the exporter gives an
    owned-kind parameter of an unmanaged type the state `scalar`).

26. **Lent cells (C6.2, design §10.6).** `DState.lent g x` says the cell `x` was lent to the group
    whose tree has the root cell `g`: a lend (`lent %G`, `lentAfter`) adds the cells its lender gives
    access to (`Val.cells`: the whole tree of an owned lender, the trees containing the pointers of a
    view) to the group, the root cell of the tree `%G` owns. Nothing is lent at entry. A group is
    live while its root cell is a live cell (a constructor that stores the group keeps it live).
    `Fault.lentGone` (`LentSafe`): an instruction consumes the tree of a cell lent to a group that
    is live, without consuming the group's tree in the same instruction (that is the join) and
    without being a constructor with an owned result (which keeps what it consumes, `Retains`). The
    model does not run the tasks: it forbids the submitter from destroying what a task may still
    read.
27. **The lent-cell invariant** (`Inv.lentSeen`, `Inv.lentCov`): a cell lent to a live group is
    covered by a root of the loans of a live owned value of `L` whose tree contains the group's root
    cell and that records itself as lent-to (`.val v ∈ Rget σ v`); the root is not a placeholder, is
    alive, and covers the cell (`Covers`). Preservation: an instruction that does not consume the
    holder keeps the covering root (renamed if a constructor with an owned result took its owner,
    `nextRoot`); one that consumes the holder is the join, a call without a result, so the group's
    cell is destroyed; a lend adds the pair and the covering roots (`Rget_next_lend`). A phi edge
    renames the roots and moves the holder (`Rget_edge_moved`, `Rget_edge_keepL`). `lentSafe_ok`:
    `loansOk` for the marked holders (`InstOk.loans`) says no covering root ends here, and the
    consumed owner is the one the root names (`root_consumed`).

28. **Held cells (C3.8).** `DState.held g x`: the tree whose root cell is `g` holds a loan on the cell `x`.
    An owned result with root `t` holds a loan on every cell of every value its certificate lists as a
    parent (A12, `heldAfter`); a constructor keeps what the trees it consumes held (the cells and their
    keys stay where they are, `Retains`), and so does any other instruction with an owned result (the
    result tree holds the cells the consumed tree's cells kept). A take marked `noloans` (`Inst.dropsLoans`) forgets what
    the tree it consumes held, and an instruction that is not a constructor forgets the loans a consumed
    tree held on cells of the same tree (A13). `LentSafe`/`Fault.lentGone` covers `held` as well as `lent`:
    destroying the tree of a held cell while the holder's tree stays is a fault.
29. **The loan invariant** (`Inv.heldSeen`, `Inv.heldCov`): a cell held by a live tree is in that tree or
    covered by a live non-placeholder root of the loans of the live owned value that owns it. The same
    tree case is what the checker's `dropSelf` stands for (a holder does not hold a loan on itself): an
    aggregate that took an owner it reads a view of holds a view into its own tree. Proof: `root_next`
    (a root of a surviving holder keeps its cells, or the constructor's result does), `root_new` (a root
    a new owned value is given), `heldCov'` in `InstPres.lean`; the edge and join versions in
    `EdgeStep.lean` and `SoundBlock.lean`; `abandon_inv` in `Abandon.lean` (the `held` entries of an abandoned holder, and on an abandoned tree, are forgotten).
30. **A call that returns an `emptied` record (C9.4, A16).** `callNext` binds the destination of such a
    call to `imm` and destroys the callee's result tree (`callVal`, `callHeap`, `dissolve`,
    ProgramDefs.lean); the takes that follow create fresh trees (item 13). The per-function semantics
    already did the same through the contract (`ResultOk`: an `emptied` destination is `imm`, `Xform`
    with no result tree destroys what the call consumes), so `effect_of_post_emptied` (ProgramLink.lean)
    is the same `Effect` built from the callee's `Post`: a cell outside the owned arguments' trees stays
    live and is not in the result tree (`Post.frame`, `Post.fresh`), a dead cell stays dead, a consumed or
    created cell is dead or in the result tree, which `dissolve` destroys. `CallWf.noEmptied` is gone; the
    exporter's check that an `emptied` call has an owner callee is `CallWf.resEmptied`.
31. **Calls name their callee (C9.2, design entry 57).** Each function carries a callee table, one entry per distinct
    callee, `callee N NAME KIND PARAMS RESULT FROM` (`Function.callees`), and each call line names its entry with the extra
    `callee N` (`Inst.entry`). `KIND` is `program`, `runtime`, `extern`, `marker` or `indirect` (the function type's signature, `NAME` is
    `-`). A parameter is `take` (consumed, the callee's value is owned), `take-scalar` (consumed, the callee's value is a
    scalar), `read` (read, borrowed) or `read-scalar`; `RESULT` is `scalar` (a unit function too), `owned` or `borrowed`;
    `FROM` the positions of the borrow contract. The arguments in parameter order are not written: walk the parameters, a taking
    one takes the next value of `consumes`, any other the next of `reads` (an indirect call's first read is the function
    value, skipped) (`walkArgs`, `Inst.argsOf`). The checker's J1 checks are `callee-table` (at the signature: the ids are
    0, 1, 2, ..., the name is `-` iff the entry is indirect, a `FROM` position is a parameter), and at the call instruction, in this order,
    `call-entry` (the line names an entry of its table, an indirect one iff the line is a `call_indirect`; no other line names
    one), `call-arity` (as many consumed values as taking parameters, as many read as the others), and for program and
    indirect entries only `call-scalar` (an argument of a `*-scalar` parameter is a scalar, an immortal or a unit value, A9),
    `call-result` (no value or a scalar value needs a scalar result, an owned or `emptied` value an owner, a borrowed value a
    borrow) and `call-from` (a borrowed value lists, as parents, the argument at each position of `FROM` that is not a scalar;
    the position is a read parameter). A runtime, extern or marker entry is judged for arity only (A5). The **link**
    (`Link.lean`, `certcheck --link`, `selka link-certificates`) checks the other half, per program: every `program` entry
    names a function of the program (the first of that name) and describes its header: `callee-missing`, `callee-arity`,
    `callee-param` (the state half of the word is the state of the `param` line; Lean also asks that the parameter value's
    state is that state), `callee-result`, `callee-from`. `callWf_of_site` (`ProgramSite.lean`) derives `CallWf` from
    `InstOk` and a passing entry; `ProgWf` is `check` for every function and `linkOk`. A call without a value is covered
    (`CallWf.voidRes`, `effect_of_post_void`; the old `CallWf.dst` was a hypothesis a unit call does not meet). A taking
    parameter whose value is a scalar is in `consumes` (`CallWf.mode`).

## Checker (Checker.lean)

22. **Two phases.** `solve` runs forward passes until the proposed entry states stop changing;
    `verifyBlocks` is the recheck. `check` is the recheck's verdict, so a proof depends on the
    recheck alone, for any proposal.
23. **Report positions.** `blk` is the block (`none` for the signature or pseudo-block);
    `idx` is the instruction index in the block, or the number of instructions for the
    terminator and the edges leaving it. A join mismatch is reported at the terminator of the
    predecessor the forward pass reached **second**, so a mismatch can name either edge.
24. **Tags.** Every failing check carries a tag (`Failure.why`); `certcheck --explain` prints
    it. The tags are not part of the verdict a test compares.
25. **The edge state of a phi.** `edgeNext` renames roots by the owned phis' moves
    simultaneously, puts the roots of borrowed phis first in `R`, and forgets the tests the phis
    redefine.

## The proof (C3.4)

`Soundness.lean` proves `check_sound`: if `check f c = true`, `Pre f args h0 pend0` and
`ScalarArgs`, then `Safe f c args h0 pend0` (no execution faults, every return meets `Post`).
The files, in import order:

| File | Content |
| --- | --- |
| `Facts.lean` | the Boolean tests as propositions; `InstOk`, what a passed instruction check says |
| `Invariant.lean` | `Inv`: the relation between the abstract state and the machine state |
| `Entry.lean` | the invariant holds at entry |
| `InstBase.lean`, `InstGuards.lean` | the membership view of `instNext`, root lemmas, the value an instruction defines; a checked instruction cannot fault |
| `InstCtx.lean`, `InstSlots.lean`, `InstPres.lean` | the hypotheses of one step; the pending, guarded and decided-test fields; the other fields; `inst_step` |
| `EdgeBase.lean`, `EdgeStep.lean` | the phi-edge lists; a checked edge preserves the invariant (`edge_inv`) |
| `SoundBlock.lean`, `SoundFacts.lean` | a passed check gives facts about blocks; the fit of an edge state to an entry state (`Inv.conv`); a branch decides its test |
| `Abandon.lean` | an edge that abandons owners preserves the invariant (`abandon_inv`): `acct` has the disjunct "abandoned" (`DState.abandoned`), and the invariant has `abLive`, `Ldisj`, `abFree` (C9.1) |
| `SlotEnds.lean` | the checked half of A14 (C9.3): after a take no view in `D` has a root that ends at it, so none is usable and a read of one fails J4 |
| `SoundRet.lean` | the after-return condition at a `ret` |
| `StaticFacts.lean` | the checker's table of defining instructions is the model's |
| `Soundness.lean` | the reachability invariant `Good` (the instructions and the terminator of a block pass; nothing is abandoned unless the block is in the trap region), the trap region (`region_succ`, `region_false_of_ret`), `check_sound` |
| `Link.lean` | the program-level link of the callee tables (C9.2): `Header`, `LinkFn`, `entryTag`, `linkRejects`, `linkOk` (`certcheck --link`) |
| `ProgramSite.lean` | `CallWf` is derived (C9.2): the walk over the entry's parameters rebuilds the arguments, `entryTag_none`, `ProgWf.entry_link`, `callWf_of_site` |
| `ProgramDefs.lean`, `ProgramCall.lean`, `ProgramLink.lean`, `Program.lean` | the whole-program corollary: a program whose calls run the callees (`PStep`, `RunsAt`), the call-site agreement `CallWf`, the callee's contract at a call (`pre_of_call`, `effect_of_post`), `runs_sound`, `main_no_leak` |
| `SoundnessExample.lean` | the theorem applied to two concrete functions |

The proof uses all of J1's non-class-shape parts and J2-J8. It uses the loans on owned aggregates
(`loansOk`) only for the values that carry the lent-to mark (`InstOk.loans`, the task groups of
C6.2); for any other holder `loansOk` is checked and not used.

**Task groups (C6.2).** The new pieces, in the files above: `Inv.lentSeen`/`Inv.lentCov` and
`Entry.lean` (nothing lent at entry); `lend_shape`, `lendR`, `nextRoot`, `Rget_next_keep` and
`Rget_next_lend` in `InstBase.lean`; `root_consumed` and `lentSafe_ok` (the fault `lentGone` cannot
happen) in `InstGuards.lean`; `IC.lentSeen'` and `IC.lentCov'` in `InstPres.lean`;
`lookup_moveHolders`, `Rget_edge_moved`, `Rget_edge_keepL` and the edge versions in `EdgeStep.lean`;
`abandon_inv` in `Abandon.lean` (the `lent` entries on an abandoned tree are forgotten, and a group is not
abandoned: `abandon-group`); `callNext` and `effect_of_post` carry `lent` through calls of
the program. The group-join check (`groupJoinOk`) is what makes the consumption of a group end it:
without it an update or a call with an owned result could hand the group back with no loans, and
the invariant would break.

**Trap regions (C9.1, design entry 55).** `DState.abandoned t` says the tree rooted at `t` was abandoned by an edge
(`abandonNext`): memory, environment and pending takes are untouched; the `held` entries whose holder or whose cell is in
an abandoned tree, and the `lent` entries on an abandoned cell, are forgotten, because nothing reads an abandoned
holder again and nothing destroys an abandoned tree. The invariant (`Invariant.lean`) allows the live cells of abandoned
trees to be unaccounted (`acct`), and asks for three facts: an abandoned tree is live (`abLive`), no value of `L` owns
one (`Ldisj`), and none is labelled like a frame cell (`abFree`). Instructions keep the set (`Effect`, `IC.habn`), a
phi edge keeps it (`EC`), and an abandoning edge adds to it (`abandon_inv`). A `ret` needs the set empty
(`post_core`): `Good` says so for every block outside the trap region (`region`), the checker lets an edge abandon only
into the region (J2 `abandon-region`), and the region is closed under successors and contains no `ret`
(`region_succ`, `region_false_of_ret`). Entry abandons nothing, so `main_no_leak` keeps its meaning: a leak is allowed on
a path to a trap and on no other.

## Open gaps

* **Slot-level ends of a view (A14).** The semantics does not split a tree by slot, so "taking or
  closing that slot ends the loan" is enforced by the checker and not modelled. Bringing it under the
  theorem needs cells per slot, and the export does not say which operand of a constructor fills which
  slot (`wild` roots), so a part of the tree cannot be followed through an aggregate. The checked half is
  proved since C9.3 (`take_ends_slot_views`, `SlotEnds.lean`: after a take no view in `D` has a root that ends
  at it). Closing the model half needs a model of takes that moves cells, which is sized and not built
  (`docs/design/c9-slots.md`; the exporter field is not needed for it).
* **Forward-take views (A15).** Now an assumption (the empty footprint of such a view in `ResultOk` stays, and so does the checker's placeholder root `fwd(n)`; the view an `emptied` constructor reads of the owner it consumes is the same case). The rebinding design (the take rebinds the footprint
  of every forward view of the value it defines) is incomplete: a phi copies the view, and the copy keeps
  the empty footprint, so the model would need every copy rebound; and the checker would need the
  position invariant that each copy still has the placeholder root when the take runs.
* **Loans (C3.8).** Covered for every holder: see items 24 and 29. What stays outside: A13 (a take carries
  no loans; a view into itself does not survive an update), A14 and A15.
  * *The flip (done, `certs/c3.8-flip`).* `Inst.dropsLoans` is `i.cls == .take && i.noLoans`: a take carries
    the loans of the aggregate it comes out of unless the exporter marks it `noloans` (it does, for a take
    whose result type cannot hold a view: 859 takes in the corpus). The proofs did not change (they use
    `dropsLoans` abstractly). A13 (1) is the assumption that the mark is true of the type. The corpus
    function `borrowed_signatures::test_read_only_wrapper_arguments_accept_borrowed_slices_and_owned_values`
    (`tests/lang/borrowed_signatures.selka`, lines 377 to 407) keeps accepting because its three `union_take`s
    on the `None` arm carry `noloans`.
  * *Fixtures.* `fixtures-zig/take.cert`: `bad_take_holds_view` (a take of a part that really holds a view,
    then the root dropped while the part is live: `reject J4 b0 4`), `ok_take_none_arm` (the same shape with
    `noloans` on the take: accept) and `ok_take_holds_view_dropped_first` (accept).
  * *A14 closes with* a model of takes that moves the cells of a slot into the taken tree, with a ghost per-cell
    slot path (`docs/design/c9-slots.md`); an export that records which operand fills which slot of a constructor
    would only make the wildcard roots precise.
  * *A15 closes with* a model that rebinds the footprint of a forward view, and of every copy of it, when the
    take runs, and a checker invariant that each copy still has its placeholder root at that point.
* **Task groups (C6.2): what is covered.** K1 is the fault `lentGone` (no cell lent to a live
  group is destroyed before its join), K2 is J2/J3 plus `group-join`, K3 needs nothing. The cells
  lent are whole trees (the semantics does not split a tree by slot), so a lender that is a view of
  one slot is lent as the whole container: taking or closing another slot of it is allowed by the
  checker and not looked at by the model. Not modelled: the tasks themselves (what a task reads or
  writes, A7.2), a handle (an `i64` index; a read of the group after its join is J3), the thread
  pool (A7.5, A7.7). A group that is consumed ends its obligations, including by a call that is not
  `myl_core_owned_group_end`; that the call waits for the tasks is the runtime's A7.5.
* **The whole-program corollary** assumes nothing about a program beyond `ProgWf`: all its functions check and its callee
  tables link (item 31). A call whose result is a stack list is refused by J1; a call whose result is an `emptied` record
  is covered under A16 (item 30); a call without a value is covered since C9.2. Calls to runtime functions are A5; calls
  through function values are A17. `certcheck` prints how many programs of a corpus meet the hypotheses (`summary
  corollary: …`).

* **What a constructor hands out (A19).** The construct-read rule (item 11) is checked by both checkers and not covered:
  the model gives every take a fresh tree and destroys only an aggregate's own tree, so a constructor that stored a
  borrowed managed value into an owned slot (lane FX6's plan) faults nowhere in it. A19 states the property. **Per-field
  provenance would close it** (not planned, by the user's decision of 12 November 2026): each cell carries the slot path
  it was stored at; a constructor's result tree adopts the consumed trees under their field paths and records, per
  listed view, a borrowed slot that adopts nothing; a take moves the cells of its slot into the taken tree (A14's model
  half, `docs/design/c9-slots.md`); and destruction frees only cells of managed slots. Then a take of a slot filled by a
  borrowed operand would yield the lender's cells, its drop would be `Violates .overlap` against the lender, and the
  checker's rule would be what the soundness proof needs, so `InstOk.cread` would be used. Estimated with A14 at 25 to
  40 hours of Lean; nothing is built.

## Hypotheses of the whole-program corollary: who enforces what (C9.2)

`runs_sound` and `main_no_leak` assume `ProgWf prog` (all functions check; the callee tables link) and, for `main_no_leak`, a
run premise. This is the list of everything they use about the program, and who enforces it. The census of `certcheck` counts
a program when everything that is not a numbered assumption is enforced for it.

| Hypothesis | Who enforces it |
| --- | --- |
| Every function passes `check` (J1 to J8) | the checker: `certcheck` and the Zig validator (`selka validate-certificates`); the gate compares them (`ownership-proof`). A function the exporter could not describe (`unchecked`) or a malformed file keeps a program out of the census |
| Each call line names an entry of its function's table; the arguments fit the entry's parameters | the checker, J1 `call-entry`, `call-arity` (both checkers) |
| A scalar parameter, and a parameter whose value is a scalar, receives a scalar, an immortal or a unit value (A9) | the checker, J1 `call-scalar` (for program and indirect entries) |
| The value of a call follows the callee's result (owner, `emptied` record, borrow, scalar; a call without a value returns a scalar) | the checker, J1 `call-result` |
| A borrowed result lists the arguments of the borrow contract as parents | the checker, J1 `call-from` |
| The call's value is not a stack list | the checker, J1 `classOk` |
| The table is well formed (ids 0, 1, 2, ...; the name is `-` iff indirect; the positions of the borrow contract are parameters) | the checker, J1 `callee-table`; unknown words are refused by the reader |
| Each `program` entry names a function of the program | the link: `certcheck --link` and `selka link-certificates` (`callee-missing`) |
| The entry describes that function's header: parameters, their states, result, borrow contract | the link (`callee-arity`, `callee-param`, `callee-result`, `callee-from`) |
| The program holds all the functions of the build | the exporter (a function it cannot describe is missing, so the link fails); the units of a debug build share a directory |
| Function names are unique in a program | not used by the proof (a call goes to the first function of the name); the linker and the Zig exporter refuse two |
| The result of a call to an `emptied` record is a record whose parts the caller takes at once | numbered assumption A16 (enforced by `Taking.empty` and J8) |
| A call to a runtime function, an extern function or a marker respects its contract | numbered assumption A5 (arity is checked, J1 `call-arity`) |
| A function value points to a function with the signature of its type | numbered assumption A17 (the IR verifier; proved for its Lean copy, `proofs/verify_ir`, `VerifyIr.a17`; the site is checked against the type's entry) |
| The operation table, the loan, slot and task-group assumptions of the per-function theorem | numbered assumptions A1 to A15 and A7.1 to A7.8 |
| Run premise of `main_no_leak`: the entry function returns a scalar and starts on an empty heap with arguments that are immediates | nobody; it is the statement of what is run (the process hands the entry function capability handles and scalars), not a property of the program |

*Not enforced by anybody and not a numbered assumption:* nothing, except the run premise. Before C9.2 the destination of every
call (`CallWf.dst`) was such a hypothesis, false for a call to a unit function; it is gone.

## Proposed design entries (for the coordinator; the design document is not edited here)

**Entry 56 (C9.4)** for the table of design §9. Date 2026-10-26. Where: §6, §8. Change: the whole-program corollary covers a call
whose value is `emptied` (the write-back record of a function with `mut` parameters, which the caller takes apart at once).
`CallWf.noEmptied` is replaced by `resEmptied` (the callee returns an owner, which entry 48 already checks); the step of such a call
destroys the callee's result tree and binds the destination to an immediate, as the per-function semantics treats an `emptied`
constructor. New assumption A16: the storage of the returned record is exactly the storage of the parts the caller takes at once
(enforced by `Taking.empty` and J8 `emptiedOk`). Reason: the corollary excluded 26% of the gate programs, 73% of EDA stage 2 and 80%
of selka (891, 2,036 and 279 calls). Mechanism: `callNext`, `effect_of_post_emptied`. Entry 48's last clause ("`CallWf.noEmptied`
is not enforced ...") is superseded. Entries 28 and 41 stay: they are the per-function treatment of an `emptied` constructor, which A16
extends across calls.

**Entry for C9.2** (the number is the coordinator's: 58 is C9.9 on main, so 59, or folded into the Zig lane's entry 57) for the table of design §9. Date 2026-10-26. Where: §4.1, §5 (J1), §6, §8. Change: calls name their callee
(the Zig lane's entry 57); the Lean corollary no longer assumes `CallWf`: the call-site half is the checker's (J1 `call-entry`,
`call-arity`, `call-scalar`, `call-result`, `call-from`, `callee-table`), the entry half the program-level link (`Link.lean`,
`certcheck --link`), and `ProgWf` is `check` for every function plus the link. The destination of a call is no longer required
(a call to a unit function is covered). `CallWf.mode` allows a taking parameter whose value is a scalar. New assumption A17
(a function value points to a function with the signature of its type; `verify_ir.zig` 765 and 766). Reason: `CallWf` was an
unchecked hypothesis, and `CallWf.dst` was false for every unit function. Mechanism: `walkArgs`, `callWf_of_site`,
`ProgWf.entry_link`, `effect_of_post_void`. The audit table in this file lists every hypothesis of the corollary and who
enforces it. The census of `certcheck` now counts a program only when all its functions are accepted and its tables link.

**Census (§6).** `certcheck` prints `summary corollary: programs meeting every checked hypothesis of the corollary: N of M (…)` and `summary calls: …` after its summary line: a program is counted when every function of it is accepted and its callee tables link (`ProgWf`).

## Findings from the corpus (C3.5)

*The passages below that speak of the trap meet (`trap-group`, `trap-holder`, the united open takes and roots, the region as chains of jumps) describe C3.5 to C3.8 and are superseded by item 12 (C9.1).*

**First export (v1).** Lane 1's export of 627 programs: `corpus-debug` (4,988 files, 10,730
functions) and `corpus-release` (627 files, 10,719 functions). With the checker as of C3.5
(before guards) 8 functions were rejected in both: 10,681 and 10,670 accepted, 41 `unchecked
task-group`, no parse errors.

* **3 exporter/table defects, J5 `ret-from`**: `path::basename`, `path::dirname`,
  `dictionary_range_keys::built`. `text_frame(a, b)` exported `parents %a`, the cache owner;
  `borrow_result.zig:74` and the functions' own `from` set take the view `b`. Fixed by lane 1
  (the parent is the second read).
* **2 path-correlated take/close across a join, J8 `join-pending`**:
  `m_none_keys::test_none_key_remove_reinsert_tombstones_and_defaults` and
  `rc_collection_builtins::test_dictionary_results_survive_receiver_clear`: `i = dict_find(d, k)`;
  `if i != -1`: take `v%i`; later `if i != -1`: `dict_remove`. Accepted with guarded takes and
  the `imm` field.
* **3 drops of a container with an open take on a path into `unreachable`, J8 `pending`**:
  `recursive::test_a_copied_recursive_box_shares_and_separates_nested_lists`,
  `recursive::test_repeated_write_through_a_boxed_child`,
  `recursive_values::test_writes_to_copies_leave_other_values_unchanged`. A compiler defect
  (a double release on a path that traps); fixed by lane 1 in `own.zig` (a block from which only
  trap blocks are reachable schedules no drop).

**Second export (v2, after lane 1's fixes).** `corpus-debug-v2` (4,988 files): 10,730 functions,
10,689 accepted, **0 rejected**, 41 `unchecked task-group`, 0 errors. `corpus-release-v2`
(627 files): 10,719 functions, 10,678 accepted, **0 rejected**, 41 `unchecked task-group`,
0 errors.

Other findings:

* A void-typed `undef` that an instruction names is exported as a named value of state `none`
  (v2); the checker treats consuming it as a no-op.
* The v2 export adds `taken PARTS` on `dict_remove` and ` imm N` on `iconst`, `cmp`, `fcmp`.
* Loans on owned aggregates are enforced by the checker (J4) and the 19 corpus cases pass.
* Corpus run time: one `certcheck` process per corpus, about 4 minutes on an idle machine and
  about 7 minutes when the machine is shared.

**Third export (C6.2, 26 October, after the C6.1 exporter).** `export_certificates.py` with the
C6.1 compiler (worktree `selka-certs-c6`, built 12:39Z, exporter changes uncommitted at the time):
`debug` (optimized-debug, 5,008 files) and `release` (632 files), 632 programs, **10,775 functions
each, 10,775 accepted, 0 rejected, 0 `unchecked`, 0 errors** (`certcheck` 0.85 s and 0.40 s). The
41 functions that were `unchecked task-group` are checked: `parallel_groups`, `parallel_map` and
`parallel_wrapper_inputs` hold 260 functions and 38 lends, all accepted in both modes.

Mutants of the real task-group functions (release export, 30 functions with a lend): the lender's
`drop` moved above the join, 17 mutants, all `reject J4`; the join replaced by a `drop` of the
group, 38 mutants, all `reject J2` (`group-join`).

Additions to the design's §10.4 that the proof needed (reported to the coordinator when found):
`group-join` (a group is consumed only by a call that returns nothing, J2) and `trap-group` (a group
live on an edge into a trap block is live at the meet, J2); a block with a lend is not part of the
trap-only region. None changes a corpus verdict.

**Where Lean is stricter than the Zig validator (for mirroring, 26 October, C6.2).** Every item
accepts and rejects the same on the corpus; they show on constructed functions only.
`fixtures-zig/taskgroup.cert` holds 25 task-group functions with real operation names and their Lean
verdicts in `fixtures-zig/expected.txt` (`selka validate-certificates fixtures-zig` against it). The
C6.1 validator as of 12:39Z matched Lean on 24 of the 25; `bad_trap_group` was the one difference.
* `group-join` (J2): a lent-to group is consumed only by a call whose result state is `none`.
* `trap-group` (J2): an edge into a trap block has every lent-to group of its `L` in the meet's `L`.
* Trap-region blocks (`trapLocal`) hold no closing update, no `param` re-read and no lend, define each
  value once, and a chain block jumps only to a block with no live phi; a block whose terminator is a
  branch is not part of the region and is checked like any other.
* The meet unites the open takes `P` and `G` of its edges (Zig keeps the first edge's).
* A guard names a container that is live (`slotsFit`'s clause, needed by `Inv.Gin`).
* A lend whose second read is not its group, or a `lent` extra on another operation, is read by Lean
  and rejected as J1 (`lend`); the Zig reader refuses the file.

**Cost (C6.2, measured 26 October 13:00Z, 20 CPUs, load 3 to 8).** `lake build` of `proofs/ownership`
from a clean tree 14.7 s, 13.2 s after a definition change in `Checker.lean`; `certcheck` over the
10,775 functions of a fresh export 3.4 s (release) and 4.9 s (debug) on one thread, 0.4 s and 0.85 s on
all; the action `ownership-proof` on the gate corpus (9,140 functions) 27.5 s from an empty private
store (six certificate directories regenerated, 9,140 functions by both checkers, 249 mutants),
2.2 s unchanged, 16.7 s after a definition change in `proofs/` (Lean verdicts recomputed). Budget
(plan §5a): 3 min for a `proofs/` edit, 60 s when every program changed.

**C3.8 (26 October): the deviations from the Zig validator, one direction each.** The fixtures of every (a)
item are in `fixtures-zig/` with Lean's verdict in `fixtures-zig/expected.txt` (`selka validate-certificates
fixtures-zig` against it). The C6.1 validator (copy built 12:39Z) accepts all the cases below.

| Deviation | Direction | Why | Fixture |
| --- | --- | --- | --- |
| The meet of a trap block keeps the open takes of the first edge only | **(a)** Zig unites them | Unsound: a slot left open on a later edge is invisible at the meet, so a second take of it passes | `bad_trap_meet_take_first` (`reject J8 b3 0`) |
| The meet keeps the roots of the first edge only | **(a)** Zig unites them | Unsound: a borrowed phi selecting views of two owners is rooted at both; dropping the second owner in the block ends it on one edge | `bad_trap_meet_roots_swapped` (`reject J4 b3 1`) |
| Owners that hold loans live on some edges only | **(a)** Zig requires them live at the meet (`trap-holder`) | The loans of a holder the meet does not know are not looked at in the block | `bad_trap_holder` (`reject J2 b1 0`), `bad_trap_group` |
| A closing update inside a trap block | **(a)** Zig leaves such a block out of the region | The take protocol compares the open takes with the `released` mark; a union of open takes does not say which edge it is checked on. (b) would need a monotone version of the check for the meet | `bad_trap_closing` (`reject J8 b3 0`) |
| A block that branches to trap blocks only | **(a)** Zig restricts the region to chains of jumps | The shadow proof follows a jump chain; a branch needs the decided tests (the meet has none) and a proof per successor. (b) would be a new proof case of about the size of `good_trap_jump` | `bad_trap_branch_chain` (`reject J2 b1 1`) |
| A chain block that jumps to a block with a live phi | **(a)** Zig stops the chain there | The proof renames roots along the chain; a phi in the middle needs the edge step inside the shadow. (b) would be that proof | `bad_trap_chain_phi` (`reject J2 b1 1`) |
| A `Parameter` re-read inside a trap block | **(b) done**: Lean relaxed | Zig's rule is sound (nothing changes); the proof only had to skip the instruction in the freshness and distinctness sets (`Inst.freshDst`) | `ok_trap_param` (accept) |
| Distinct values in the chain | none | The reader refuses a value defined twice, so `dst-unique` already holds on every function Zig sees | n/a |
| A guarded take names a container of `L` (the `slotsFit` clause) | **(a), no fixture possible** | It matters only for an entry state the solver did not produce (a guard on a dead container whose test came out the other way). Zig's solver builds its entries from edges, so it cannot produce one; one line in its recheck makes the parity exact | n/a |
| A lend whose group is not the second read; `lent` on another operation | none | Lean rejects J1, the Zig reader refuses the file; both refuse | n/a |

**Proposed design text (§9, entries 45 to 48; not written into the design document).**
* 45 (§5, J2): `trap-holder`: an owned value that holds loans (a non-empty set of roots) and is live on
  an edge into a trap block is live at the block's meet. Replaces the narrower `trap-group` of entry 44's
  neighbours. Reason: the meet intersects the live sets.
* 46 (§5): the meet of a trap block unites the roots and the open takes of its edges, and the edge fits only
  if its roots and takes are contained in the meet's (`trap-roots`, `trap-pending`); the first edge alone is
  unsound (fixtures `bad_trap_meet_take_first`, `bad_trap_meet_roots_swapped`).
* 47 (§5): the trap-only region is a chain of jumps; a block with a closing update or a lend is not in it
  (`bad_trap_closing`); a chain block does not jump to a block with a live phi; a branch block is checked
  like any other (`bad_trap_branch_chain`, `bad_trap_chain_phi`). A re-read of a parameter is allowed.
* 48 (§8): assumptions A13 to A15 of `AXIOMS.md` (a holder consumed by an instruction that is not a
  constructor ends its loans; slot-level ends and forward-take views are enforced by the checker only).

**C3.8, loans carried through every consumer (the verdict change approved on both sides).** New cases for the
Zig lane in `fixtures-zig/loans.cert` (Lean's verdicts in `fixtures-zig/expected.txt`; the C6.1 validator
accepts all six): `bad_loan_lost_through_update` (`record_make` of a view of `%0`, `list_push` consuming the
record, `drop %0`: `reject J4 b0 4`), its counterpart `ok_loan_through_update` (the list dropped first:
accept), `bad_loan_lost_through_call` (a call that consumes the holder and returns an owned value:
`reject J4 b0 4`), `bad_holder_with_its_root` (a call consumes the holder and the owner it borrows from:
`reject J4 b0 3`), `take.cert` (a take that really holds a view: `reject J4`; the `noloans` take: accept). The change is (a) for Zig: carry the loans of every consumed owner into an owned
result that is not a take, and make `loan-outlives-root` exempt a consumed holder only when its loans end
with it (no owned result, or a take).

## The null owner is never read (lane FX12, 15 November 2026)

An `undef` of a managed type is the null owner: its state is `immortal`, so a join may take it on an edge where nothing is
owned, a store may put it into a taken slot and a drop of it is a no-op. It points at nothing, so no operation may read
it. Both checkers now refuse a read of one with J3 (Zig `Checker.nullOwner` in `src/core/validate_ownership.zig`; Lean
`CCtx.nullOwner` and the instruction check `read-null-owner`, `#guard rej badNullOwnerRead`). Before, `usable` let an
immortal value be read anywhere, and a `match mut` binding lowered to the null owner reached a runtime helper that read
through it (`experiments/audit-work-20261111/FX12.md`). The soundness proof does not use the check.
