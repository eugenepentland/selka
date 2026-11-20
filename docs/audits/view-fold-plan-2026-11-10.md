# One shape for text, bytes and lists: the view fold (plan, 10 November 2026)

Status: **a gated plan, not scheduled. The recommendation is to build nothing now.** The user asked for this plan on 10 November
after the coordinator recommended "fold views into ordinary lent values". Writing the plan showed that recommendation was wrong
in three ways (section 1), so this plan starts with a measurement and a stop, and says what a fold would really cost and buy.
Nothing here is decided. The companion plan is `docs/audits/proof-steps-plan-2026-11-10.md`.

Sources: `experiments/ownership-matrix-20261109/SPIKE-O4.md` (the spike of 10 November), `docs/ownership-rules.md` ("Current
limits"), `docs/audits/test-loop-plan-2026-11-09.md` (Part B, 9.3 to 10.4), `proofs/ownership/AXIOMS.md`, and a reading of the
compiler at main `7791bcc52`. Every hour figure is an estimate. A line marked "inferred" was reasoned from the code and not built.

## 1. What was recommended, and what was wrong with it

The recommendation of 10 November: a slice or a `from` result of text, bytes or a list is a separate kind of thing (a view) from
a lent whole value; folding the two would remove the last exception to "a bare name lends" (24 cells), fold the V rules into the
R rules, and remove four of the proof's unproved assumptions; a full fold was "unpriced".

| Claim | What the record says |
| --- | --- |
| A full fold is unpriced | The spike priced it the same day: 80 to 150 lane-hours, an estimate by analogy (`SPIKE-O4.md`, E-global) |
| It removes proof assumptions A13, A14, A15 and A18 | It can remove A18's frame-block clause (inferred). A13 to A15 are about slots and takes in the Lean model and do not move. The local form adds proof work: a verifier exception, a validator condition and Lean fixtures |
| It is a simplification | Only the global form is. The local forms add a rule: an aggregate that holds a view cannot be passed whole to a function |
| (not said) | The spike found no site in the port in these positions, recommended building neither shape, and the user decided on 10 November (D7) to leave these cells as documented limits |

What stays true: there are two mechanisms, and the 24 cells are the only place a bare name is refused inside a function.

## 2. The two mechanisms today (read from the code)

| | A whole value, owned or lent | A view |
| --- | --- | --- |
| What it is | one 8-byte pointer to a runtime block: a 32-byte header (kind, length, capacity, reserved), then the data (`src/core/runtime/core_rt.c` `myl_block`) | a pointer and a length, `{ptr, i64}`, "in SSA only; it has no storable memory layout" (`src/core/ir.zig` `str_view`, `bytes_view`, `list_view`) |
| Where it can sit | a local, a parameter, a field, an element, a dictionary value, an option payload | a local, a plain parameter, a call result under `from` |
| Lent inside an aggregate | yes: `borrowed T` has `T`'s layout and holds the owner's block pointer (borrowed records B9, collections of borrows) | no: `verify_ir` refuses "a view has no aggregate or function storage representation", and the checker refuses first with `E_SLICE_ESCAPES` (V2) |

- A plain `str`, `bytes` or list parameter is passed as a view, so a caller's slice is not copied (`build.zig` `viewParameter`).
  Text and lists also pass their owner; bytes do not.
- Where a view parameter must sit in a borrowed record or a collection of borrows, a frame block turns it into a block once per
  call: the caller's block when the argument was a whole value, a shallow copy otherwise (a slice, or any bytes argument). It is
  freed before every return, a function that holds one is never inlined, and it is trust point A18.
- A slice or a `from` result is not a parameter, so it has no frame block. Those are the 24 cells: 2 sources (`p[0:2]`,
  `first_text(r)`) by 4 local positions (a record, an option, a list, a dictionary) by 3 types (text, bytes, `int[]`).

## 3. What a fold has to be

| Way | Cells taken (of 24) | New rule for users | Lane-hours (estimates) |
| --- | ---: | --- | ---: |
| A view kept as a field of a local record's SSA value (the spike's third way) | 6 | yes: that record is read in place and cannot be passed, stored or returned | 3-6 |
| One shape, view or owner, in local aggregates only (E-local) | 24 | yes: the same limit for records, lists and dictionaries | 23-49; the 6 option cells were not priced |
| One shape for every text, bytes and list member (E-global) | 24 | no | 80-150 |

Only E-global removes a mechanism. The other two add one, which is the opposite of what the question asked for. So "the view
fold" in this plan means E-global, and the two local ways are not planned.

### What E-global is (a sketch; stage V1 would settle it)

Every field, element, dictionary value and option payload of type `str`, `bytes` or `T[]` holds `{data, length}` (16 bytes; 24
if an owner word is kept). A view and an owner then have one layout, and which one a member is stays what it is for whole values
today: a fact the checker knows, not a run-time flag. Inferred consequences:

- Text and bytes blocks are immutable, so a member's length never changes. A list member's length has to be stored back after
  every growth.
- An owner's block is found from its data pointer (32 bytes before it), so dropping needs no extra word.
- An option of text stays free of a tag by using a null data pointer for `None`.

### What it would remove (inferred unless marked)

| Goes away | Why |
| --- | --- |
| The 24 refused cells | a member takes a view as it takes a block |
| Frame blocks: the op, the once-per-call copy for a slice or bytes argument, the inlining restriction, A18's frame-block clause | a field takes the parameter's view directly |
| The build-time refusal of a view lent where a block is wanted (`hiddenViewBorrow`, Z3) | nothing wants a block |
| Rule ids V2, V4, V5 and W4 as separate rules, and V3 | they become R1, R3, R4, R6 and R2 applied to a slice |
| The code `E_SLICE_ESCAPES` | 28 Zig test files and 72 matrix rows name it today (counted) |
| Perhaps the port's 53 sites at the frame-block limit, where the value is returned under `from` | frame storage never returns; a member that is a view has no frame storage. Not checked |

### What it would not change

- **The port's real slice friction.** F-RA-1 (547 marked sites in the port's `FRICTION.md`): a token and a syntax node hold
  slices of the source, and each copies its text. Those values leave their function and are stored in owners, which is the
  Escape rule, not a layout limit. The `Span` library idiom stays the answer.
- **The port's 38 sites** (a new collection returned under `from`) and **R5** (a `from` function that returns a borrow on one
  path and a fresh value on another). Both need a run-time owner word and the proof work that withdrew RB2's form.
- **Trust points A13, A14 and A15.**
- **Proofs about user programs.** Layout is invisible to source-level reasoning; the proof-steps plan does not depend on this.

### What it would cost

- **80 to 150 lane-hours**, an estimate by analogy with the record-borrows plan's design B. It touches the C runtime (12,972
  lines), emission (27 files, 13,118 lines), lowering (31 files, 11,201 lines), every stored stage and cache format, and the
  ownership validator's class table.
- **Every program pays for it.** Each text, bytes or list member grows by 8 bytes, and a list of text doubles its element size.
  The effect on run time and memory is unmeasured, and the runtime-parity goal (1.10 times Zig and Rust) is at risk from it.
- **A possible gain, also unmeasured:** a length read from the member instead of the block header, and no frame-block copies.

## 4. Recommendation

**Build nothing now.** The fold buys regularity in 24 cells that no measured program uses, and it does not touch the slice
friction the port logged. At 80 to 150 lane-hours it competes with the proof steps, runtime parity and compile cost.

If the regularity is still wanted, run stage V0 only (6 to 10 lane-hours). It answers the one question the spike could not:
whether the wider layout is free at run time. Everything after V0 waits for that answer.

## 5. Stages, if it goes ahead

**V0. Measure before deciding (6-10 lane-hours, no landing).**
1. Check section 3's inferred rows against the code: can frame blocks go; are the port's 53 sites accepted; which sentences of
   the reference change. A table, with what was read (2-3 h).
2. The cost of wider members without building them. A script adds one integer field after every text, bytes or list field of
   every record, in the parity suite and in a scratch clone of the port. Release builds, timing windows, run time and peak
   memory against the unpadded programs. List elements cannot be padded in source: count the port's lists of text, bytes and
   lists and their sizes at run time, and report the bytes that would double (3-5 h).
3. A table for the user: run time, peak memory, what goes away, what does not (1-2 h).

**Gate after V0 (decision DV2).** Recommended bar: median run time within 1% and no program worse by more than 3%; peak memory
within 5%. A miss ends the plan, and the 24 cells stay documented limits.

**V1. The design, with a prototype on text fields of records (10-16 lane-hours, no landing).** `DECISIONS.md` settles: 16 or 24
bytes; how a drop finds the block; how a list member's length is kept; options, unions and dictionary slots; static and empty
values; the runtime's C interface; the validator's class table; which trust points change. A18 loses a clause, which is an edit to
a trust point and is the user's decision (DV3). The prototype widens text fields of records only, builds the language suites, and
measures the same programs as V0. V1 replaces the 80-to-150 estimate with one costed against the code.

**Gate after V1 (decision DV4).** Build, or stop with the design on a branch.

**V2. Build it, one landing per step, the complete gate at each.** The split is V1's to confirm:

| Step | Delivers |
| --- | --- |
| a. Text and bytes members of records | layout, drops, equality, hashing, `copy`; no rule changes yet |
| b. List elements and dictionary values | the same for containers |
| c. List members | the length stored back after growth |
| d. Options and unions | the tag-free option form |
| e. The checker | a slice and a `from` result lend like a whole value in borrowed records and collections; the 24 matrix rows move |
| f. Frame blocks removed | the op, its runtime call, the inlining restriction; A18's text |
| g. Rule ids and the code folded | the reference, `mylang reference`, tests; old ids kept as aliases in the reference |

No program accepted today is refused by any step, so there is no `mylang fix` migration.

## 6. Exits

| # | Exit | Target |
| --- | --- | --- |
| F1 | Bare names in the matrix's function-local positions | 312 of 312 accepted [288 today] |
| F2 | Frame blocks | none in the compiler; A18 without its frame-block clause |
| F3 | Run time and memory | the parity suite and the port within the bar of DV2, measured against the pre-fold compiler |
| F4 | Nothing accepted today is refused | the matrix's 1,018 accepted cells, `tests/lang` and the port's `check` unchanged |
| F5 | The reference | V2 to V5 and W4 filed as applications of R1 to R6; one Escape code fewer |
| F6 | The gate | complete gate and `ownership-proof` green at every landing |

## 7. Stops

- V0 or V1 misses the bar of DV2.
- A step needs a new trust point, or a change to the Lean proof beyond fixtures. Report it with its cost; do not decide it.
- A check or a build that accepted a program before a step refuses it after.
- 1.5 times a step's estimate.

## 8. If the aim is a smaller number of rules

Two changes lower the count without touching the compiler's behaviour. Neither needs the fold.

| Change | Ids after | Lane-hours (estimates) | Note |
| --- | ---: | ---: | --- |
| Retire the nine ids that refuse nothing (T1, B4, B5, W1, V1, V7, P5, Z1, Z2) | 45 | 2-4 | D6 of 9 November kept them; this asks again |
| Move the eleven application rules (T2, T4, W3, P1 to P4, K1 to K3, L1) to their own feature pages | 34 | 3-5 | the ownership reference then lists 30 checks under three rules, three limits and C2 |

## 9. Decisions for the user

- **DV1. Go or no go.** Recommended: no go; the 24 cells stay documented limits, as decided on 10 November. The alternative is V0
  alone.
- **DV2. The bar after V0**, if V0 runs. Recommended: section 5's.
- **DV3. Editing trust point A18**, if V1 runs.
- **DV4. Build or stop after V1.**
- **DV5. The two changes of section 8.** Recommended: both, as one small lane, whenever the reference is next edited.
