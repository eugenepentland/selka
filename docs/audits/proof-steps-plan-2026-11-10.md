# Specifications that pay off: the proof steps (plan, 10 November 2026)

Status: **a plan, not scheduled.** The user asked on 10 November what should change so that proofs become an ordinary part of
writing Selka, and then asked for this plan. It builds on the concept note `docs/audits/proofs-concept-2026-10-22.md`. Its tier 1
(memory safety) is built: the ownership validator and the Lean proof. This plan is its tiers 2 and 3, in steps that each pay off
alone. The companion plan is `docs/audits/view-fold-plan-2026-11-10.md`; neither depends on the other.

Read at main `7791bcc52`. Every hour figure is an estimate. "Probe" means a small program run with the installed compiler on
10 November; "inferred" means reasoned from the code and not built.

## 1. Where things stand

**The language is well placed, and that is worth protecting.** A `mut` borrow is exclusive and is never stored or returned (a
result under `from` is read-only), there are no closures and no shared mutable identity, and every effect arrives as a
capability parameter. So a checked function can be read as an ordinary mathematical function of its arguments, with each `mut`
parameter as one more result. Verifiers for Rust carry heavy machinery for returned mutable borrows; nothing here needs it.

**Contracts exist and nobody writes them.**

| Where | `@requires` | `@ensures` | `@invariant` |
| --- | ---: | ---: | ---: |
| `tests/lang` | 6 | 11 | 3 |
| `examples/` | 1 | 1 | 4 |
| `src/stdlib`, `bench/`, `selfhost/` | 0 | 0 | 0 |
| The port (755 `.my` files; 173,088 lines under `src`) | 0 | 0 | 0 |

- The port does state properties: it has 1,633 `assert` statements, 1,613 of them in test files.
- **No guide mentions contracts.** `docs/primer.md` never names `@requires`, `@ensures`, `@invariant` or `assert`, and
  `contracts` is not in its list of topics. The port's `docs/PORTING.md` is silent too. The port was also translated from Zig,
  which has no clauses to translate.

**The compiler already proves some clauses, and tells nobody.**

- A clause becomes an ordinary branch to a trap block (`src/core/build.zig` `assertStatement`). When Core's facts decide the
  condition, the branch folds and the fact certificate states the trap block dead (check F5). A Debug compiler validates that
  certificate, and `proofs/facts` proves, under its listed assumptions, that a block an accepted certificate states dead is
  never entered.
- Probe: both halves of `@ensures(result >= 0 and result < 3)` on a three-way `clamp` fold to true.
- **Nothing reports it.** `mylang cost` counts arithmetic and bounds checks ("checks 1 kept / 3 proved") and no clause.
- **A clause the facts refute gets no diagnostic.** Probe: `@ensures(result >= 1)` on a function that returns 0 folds to false,
  builds with no message, and traps `R_ENSURES` when run.
- **A caller never uses a callee's postcondition.** Probe: `xs[clamp(i - 3)]` with `xs` of length 3 keeps its bounds check,
  although `clamp` proves `0 <= result < 3`. The return interval is computed without the branches that dominate each `ret`
  (`src/core/facts.zig` `returnRange`).
- A precondition reaches the callee's body as a branch, so `@requires(i >= 0 and i < len(xs))` proves the bounds check of
  `xs[i]` (probe). It reaches callers only through a whole-program parameter interval.

**Other facts the steps rest on.**

- A clause is checked in every build, release included, and `old(...)` deep-copies an aggregate at entry.
- `mylang cost --sites` lists allocation and copy sites with their source origin through inlining. It lists no check. There are
  about 40 run-time trap codes in three forms: checked operations (153 emission sites by a grep for `.check = .exact`), flagged
  trap blocks, and traps inside C helpers.
- `@noalloc` is judged on the lowered body after ownership expansion and before the facts and the optimizer
  (`src/core/allocation_contract.zig`), so its verdict does not depend on the build mode.
- A `public record` can be built by any importer. Probe: `auth.AuthedUser(id=5)`, `auth.AuthedUser()`, a field write, `replace`
  and `take` all work from outside the module.
- Four Lean developments run in the gate on one pinned toolchain (Lean 4.35.0, no Mathlib). `proofs/facts` models integer,
  boolean and list operations of Core IR; records, text and dictionaries are opaque there. Nothing models what a source program
  computes.
- No switch makes a lend a copy. A program cannot observe an address or identity; it can observe cost (`testing.allocations()`).

## 2. The idea: one clause, a ladder of evidence

A clause is written once. The tools take it as far up this ladder as they can, and a report says how far it got.

| Level | Evidence | Today |
| --- | --- | --- |
| 1 | stated: part of the interface, `api-diff` reports a change | built |
| 2 | checked at run time | built |
| 3 | exercised by tests and property tests | built, not counted per clause |
| 4 | proved by the compiler's facts, check removed | happens, not reported |
| 5 | proved by a prover | not built |

Proofs become ordinary when levels 2 to 4 are visible and cheap, so that a clause pays off the day it is written. Level 5 comes
last and is decided by a spike, not assumed.

## 3. Exits

| # | Exit | Target |
| --- | --- | --- |
| P1 | The guides | the primer teaches `assert` and the three clauses; `contracts` is in its topic list |
| P2 | The trial | two modules carry clauses; minutes, run-time cost, clauses proved and clauses that could not be written are reported |
| P3 | Clause status | one command lists every clause as proved, refuted or kept, with counts; a refuted clause is a build warning |
| P4 | Postconditions cross a call | the probe's `xs[clamp(i - 3)]` bounds check is proved [kept today] |
| P5 | A strong clause is affordable | a clause marked for tests costs nothing in other builds, and still appears in the interface and the report |
| P6 | Traps | kept checks are listed per site; a function can promise it cannot trap, and a broken promise fails the build |
| P7 | Sealed types | the forging probe (construct, default, field write, `replace`, `take` from another module) is refused |
| P8 | The prover | a spike report on one real module, with a recommendation and its costs |
| P9 | Lend equals copy | the language suites give the same verdicts and output with every read-only lend replaced by a copy |
| P10 | The gate | complete gate green at each landing; nothing accepted today is refused |

## 4. Stages

### S0. The guide and a trial (6-10 lane-hours)

- **Guide.** A short section in `docs/primer.md` on `assert` and the three clauses, with one runnable example each, and
  `contracts` added to "Where to read more". Fix the `@invariant` wrong-target message, which still names the removed `domain`
  form (`docs/audits/language-surface-audit-2026-10-19.md`).
- **Trial.** One agent adds clauses to one standard-library module and one port module (a scratch clone), with the guide and no
  other help. It records: minutes; clauses by kind; clauses it wanted and could not write, and why; instructions of a release run
  with and without them; how many clauses the facts fold (`mylang dump-ir --facts`); and any defect a clause found.
- Write-up: `experiments/proof-steps-20261110/TRIAL.md`.

The trial is the baseline for every later claim. If it shows clauses are cheap and mostly provable, S3 moves later; if it shows
most wanted clauses cannot be written, S7 moves earlier.

### S1. The clause report (8-14 lane-hours)

- Each clause keeps an identity through lowering (function, kind, position in source), carried on its trap block beside the
  existing kind and message index, and through inlining by the existing origin frames (`src/core/inline_origins.zig`).
- After Core's passes each clause has a status:
  - **proved**: every copy of its branch folded to true;
  - **refuted**: a copy folded to false;
  - **kept**: a run-time check remains.
  The report gives counts for the function itself and for its inlined copies.
- Surfaces: rows in `mylang cost` (as `--sites` prints allocation rows, with `--json`), and one total in `--stats`.
- A refuted clause is a warning with its source position. It is not an error: the facts use whole-program intervals, so the
  statement is "this clause fails whenever this program reaches it".
- The fact certificate already states the dead block, so the validator and `proofs/facts` do not change.
- Confirm that the language gate's `--verify-facts` run would catch a clause folded wrongly; if it does not cover a dead trap
  block, add that check here.
- `mylang check` computes no facts, so the report needs a build. The guide says so.

### S2. A postcondition is known to the caller (5-9 lane-hours, then a decision)

- **Step 1 (3-6 h).** The return interval takes the branches that dominate each `ret`, so an `@ensures` on an integer result is
  an interval every caller knows. The certificate's return line and its check exist already; this makes the claimed interval
  narrower, not a new kind of claim (inferred; confirm against `validate_facts.zig` first).
- **Step 2 (a costing, 2-3 h).** Relational postconditions (`result < len(xs)`, `len(result) == len(xs)`) need a new line in the
  certificate, a validator rule and a Lean lemma. Step 2 prices that and stops for decision PD2.
- The report gains one column: at how many call sites a callee's `@requires` is proved.

### S3. What a clause costs (6-10 lane-hours, after PD3)

- A clause can be marked for tests. It is compiled and checked under `mylang test`, property tests included, and not in other
  builds. It stays in the interface, in `api-diff` and in the report, and a proved one is reported proved in every build.
- This is a per-clause marker in the source, not a build mode: an unmarked clause is checked in every build, as today.
- `docs/contracts.md` says today that no mode removes a clause. It gains two sentences: a proved clause has no check, and a
  clause marked for tests is checked only there.

### S4. Kept checks, and the promise not to trap (12-22 lane-hours; step 2 after PD4)

- **Step 1 (4-8 h).** `mylang cost --sites` lists every kept check: its kind (overflow, bounds, division, shift, conversion,
  missing key, text bounds, assertion, clause), its source position through inlining, and its loop depth. A call into a C helper
  that can trap is a row of its own, from an audited table like `@noalloc`'s allow-list.
- **Step 2 (8-14 h).** A function attribute that promises no trap: after Core's passes, no kept check and no live trap block in
  the function or anything it calls, except its own `@requires`. Resource limits (memory budget, step and frame limits, timeouts)
  are not traps for this purpose. It reuses `@noalloc`'s root lowering and backward propagation
  (`src/core/allocation_contract.zig`).
- Two design points step 2 must settle in its `DECISIONS.md`. `@noalloc` avoids both because it is judged before the facts:
  - the promise rests on the facts, so `--unoptimized`, which runs no pass, cannot check it;
  - whole-program parameter intervals would let a new call site in one module break a promise in another. The promised
    function has to be judged with its parameters unknown except for its own `@requires`.

### S5. Sealed types (10-18 lane-hours, after PD5)

A public record whose values only its own module can make. Fields stay readable. Outside the module and its test files, these are
refused: a constructor call, construction from defaults, a field write, `replace`, and `take` (which builds a default).

- With `@invariant`, holding a value of the type is then evidence that the module's own functions built it: "no record is read
  without a login" becomes a compile error, with no prover.
- The boundaries that build records without a constructor need a written rule each: typed JSON and cases files, property-test
  generation, and `copy`. Recommended: decoding and generation of a sealed type are allowed only in the module's own test files;
  `copy` is allowed.
- It is additive: no program accepted today changes.
- Scalar domains, removed on 14 October, had private members. This brings back only the privacy, on records.

### S6. The prover spike (14-24 lane-hours, no landing)

Two routes, tried on the module of S0's trial, each on the same ten clauses the facts could not prove.

- **A. Export to Lean.** A prototype turns the typed program (`mylang dump-typed`: functions, blocks, loops and clauses are
  explicit) into Lean definitions: 64-bit integers that trap, lists as arrays, records as structures, a `mut` parameter as an
  extra result, a loop as a recursive function. Each clause becomes a theorem statement. An agent writes the proofs. A
  differential run compares the Lean definitions with the compiled program on property-test inputs.
- **B. A solver.** Verification conditions for the same clauses go to an SMT solver, with loop invariants written as `assert`
  statements in the loops.
- Measured for both: clauses discharged with no help; annotations or proof lines per clause; minutes per clause; whether a rerun
  gives the same answer; what is trusted; what the toolchain gains (a solver binary to pin, against a Lean toolchain the gate
  already has).
- Write-up: `experiments/proof-steps-20261110/SPIKE.md`, with one recommendation. Building the chosen route is a later plan.

The spike may use scripts under `experiments/`. A built prover must follow the no-Python rule and must not run in the edit loop.

### S7. Vocabulary (after S6; not designed here)

What a clause can say depends on the route. Known facts for that decision:

- `all` and `any` take a `list[bool]`, and the generator forms are retired, so a quantified clause ("every element is ...")
  needs a helper function with a loop today. That works at run time and suits route A; route B wants a bounded quantifier.
- A loop annotation needs no new keyword: `@vectorize` already attaches an attribute to a `for` statement, so a loop invariant
  and a decreasing measure can be attributes.
- A new statement kind touches the parser, `ast.zig`, `typed.zig`, about 15 tree walkers and `src/syntax_layout.txt`; a new
  keyword also touches the self-hosted lexer's tables.

### S8. Lend equals copy (8-14 lane-hours, a costing first)

A switch for tests only makes lowering copy wherever it lends read-only (the `borrow` emission sites, `list_view_of`,
`list_slice_view`, a view passed to a plain parameter) and drop the copy when the loan ends. The language suites run both ways.

- Verdicts and output must be equal. Excluded by name: tests that read `testing.allocations()` or `steps()`, `@noalloc`
  functions, and memory-budget tests.
- It is evidence, not a proof, that borrowing cannot be observed, which is what licenses reading a function as mathematics. The
  Lean proof shows no memory fault, which is a different property.
- A difference is a compiler defect or a hole in the Exclusion rule. Stop and report it.
- The first 2 hours price it: copies inside borrowed records and collections may make it larger than estimated.

## 5. Not in this plan

- Building the prover. S6 decides the route; the build is its own plan.
- A verified compiler, information-flow types, or proofs about task interleavings.
- Removing the run-time check of an unproved clause by build mode.
- The view fold. It changes layout, which no source-level proof can see.

## 6. Order, lanes and estimates

| Stage | Lane-hours | Needs | Delivers |
| --- | ---: | --- | --- |
| S0. Guide and trial | 6-10 | nothing | P1, P2 |
| S1. Clause report | 8-14 | S0 | P3 |
| S2. Postconditions cross a call | 5-9 | S1 (same files) | P4, the price of step 2 |
| S3. Clause cost | 6-10 | PD3 | P5 |
| S4. Kept checks and the promise | 12-22 | S1; PD4 for step 2 | P6 |
| S5. Sealed types | 10-18 | PD5 | P7 |
| S6. Prover spike | 14-24 | S0 | P8 |
| S8. Lend equals copy | 8-14 | nothing | P9 |
| **All but S7** | **69-121** | | |

- At most three lanes. S1, S2 and S4 share `src/core/facts.zig`, `cost.zig` and the trap flags: one lane, in that order. S3 and
  S5 share the parser's attributes and `sema`: one lane, S5 first. S6 and S8 land nothing shared and take the third lane.
- Each landing: the lane's own gate, a fast-forward of local main, the main gate. Evidence stays out of git.
- The smallest useful start is S0 and S1: 14 to 24 lane-hours, no language change, and the first report of what the compiler
  already proves.

## 7. Stops

- A clause reported proved whose check can fail at run time.
- A change to the fact validator's rules or to a theorem of `proofs/facts` (S2 step 2). Report it with its cost; do not decide it.
- A change to the ownership validator, the ownership proof or a trust point.
- A step that refuses a program accepted today, outside S5's sealed types (which no program uses yet).
- 1.5 times a stage's estimate.

## 8. Decisions for the user

- **PD1. A standing design rule.** Never add returned or stored `mut` borrows, capturing closures, shared mutable identity or
  ambient effects. They are what would make a function stop being a mathematical function. Recommended: adopt it.
- **PD2. S2 step 2**, after its costing: a new certificate line and validator rule for relational postconditions.
- **PD3. The tests-only marker** (S3): its spelling, and that it is per clause and not a build mode. Recommended: a named
  argument on the clause.
- **PD4. The promise** (S4 step 2): its name, which traps count, and judging it without whole-program intervals.
- **PD5. Sealed types** (S5): the spelling (one word on the declaration is recommended over per-field privacy), readable fields,
  and the rule for decoding and generation.
- **PD6. The prover route**, after S6. Today's lean is route A, because the gate already runs Lean and a Lean proof does not
  change its answer between runs. That is an expectation, not a finding.
- **PD7. Vocabulary**, after S6.

## 9. The start (10 November)

The user started S0 and S1 on 10 November ("Start S0 and S1"). Nothing else in this plan is started, and PD1 to PD7 are open.

- **Lane G (S0's guide)** and **lane R (S1, the clause report)** run in parallel. S1 uses none of S0's results: the "needs S0" of
  section 6 was the trial's numbers, which only S3 and S7 wait for.
- **Lane T (S0's trial)** starts when the guide is on main, as a fresh agent that has the guide and nothing else, so that the
  trial measures what the guide teaches.
- Each lane works in its own worktree on its own branch. A landing is the lane's green complete gate, a fast-forward of local
  main by the coordinator, and the main gate. Nothing is pushed.
- Decisions a lane makes are logged in `experiments/proof-steps-20261110/DECISIONS.md`; what each stage found is added below.

### 9.1 What the stages found

**S0, the guide, landed (10 November, `244dc9785`).** The primer has a 40-line section, "Stating what code expects and
promises", with one runnable example of `assert` and the three clauses, and its topic list names `contracts`. The `@invariant`
wrong-target message had already lost `domain` on 20 October (`b9edc5bd3`); what it still named was `class`, also retired, and
that is gone, with a test that pins the text. **P1 is met.** Lane G's gate passed (402.5 s, 31 actions executed). Lane T, the
trial, starts from this commit and learns from that section alone.

**S0, the trial, landed (10 November, `30856b42d`). P2 is met.** One Sonnet agent, with the primer section and
`docs/contracts.md` only, put 115 clauses on two modules: the port's `src/sexpr/tokenizer.my` (392 lines, 61 clauses) and a copy
of `src/stdlib/binary.my` (274 lines, 54 clauses). The write-up is `experiments/proof-steps-20261110/TRIAL.md`; lane T's gate
passed (728.6 s). What it measured:

| | result |
|---|---|
| Writing | 11 agent-minutes for 115 clauses (69 `@ensures`, 27 `@requires`, 6 `@invariant`, 13 `assert`); about 8 of the 11 went on three compiler defects |
| Could not write | 55 wanted and not written; 37 of them cannot be said: a postcondition of the `fail` path (15), a loop invariant (9), a quantifier (4), others (9) |
| Run-time cost | 1.84x instructions on the tokenizer driver, 1.04x on the binary codec driver (`--release`) |
| Proved today | Core proved 10 of the 115 clauses in every copy, and 32 of 287 check sites (by S1's report; a recount of the LLVM text had given 6 and 14) |
| Build cost | `check` unchanged; a debug build +10 to 14% CPU, inside the run-to-run spread |
| Guide | 6 questions the primer section did not answer |

- **The count of proved clauses was first reported as none.** The lane counted trap blocks, and Core leaves a decided clause's
  block in its output behind a constant branch. `trial/tools/decided.py` counts the blocks that cannot be reached; the write-up
  carries the correction. That recount gave 6 clauses and 14 sites; S1's report, which reads the facts, gives 10 and 32, because
  a chained comparison the facts decide keeps its branch in Core's output.
- **Writing is cheap and proving is rare.** 9% of clauses are proved with no help. S1 will therefore print "kept" for almost
  every clause until S2 (postconditions cross a call) and S6 raise the share; S1's value on this evidence is the cost side
  (which clause is checked where) more than the proved side.
- **The cost is one predicate, not the clauses in general.** A `tokenizer_valid(self)` predicate used in nine clauses is 31 of
  the tokenizer's 84 points, and the ten clauses of the once-per-token `finish_token` are 60. Range clauses on the codec cost 4%.
  This is the case S3 (a clause checked in tests only) is for.
- **The largest gap in what can be said is the `fail` path**, then loop invariants, then quantifiers. All three are S7's
  (vocabulary), which this plan leaves undesigned and behind S6. The first needs no prover. Whether to bring it forward is the
  user's (PD7).
- **Three compiler defects, each reproduced on main's compiler** (repros under the evidence archive's `trial/repro/`):
  D1, `@ensures` on a `-> Unit fails E` function panics `mylang build` in `src/core/build.zig` `typeOfRef` (`check` passes);
  D2, an `@invariant` on a record with a managed field makes every field store through a `mut` parameter
  `E_SINGLE_OWNER_BORROW`, which rules out invariants on most real records; D3, a body local named `result` beside an
  `@ensures` makes a trailing `return result` `E_UNKNOWN_NAME`, against `docs/contracts.md`. None is fixed; none is in a stage.
- **Guide gaps to close when the primer is next edited:** an invariant is checked after every field write (a two-field update
  traps midway; `replace(...)` is the way), `old(...)` takes a field and a clause may call a function, a clause has a run-time
  cost, and there is no loop invariant, quantifier or `fail`-path postcondition.

**S1, the clause report, landed (10 November, `7e3e69102`). P3 is met for the report; the build warning is not built.**
`mylang cost ENTRY [FUNCTION] --clauses [--asserts] [--json]` lists every clause as proved, refuted or kept, with its copies in
the function's own body and inlined (JSON document `cost-clauses-v1`, feature `contract-clause-report`). `build --stats` and
`run --stats` print the totals and one line per refuted clause. On the probe, `clamp`'s clause is proved and `wrong`'s is
refuted ("fails whenever this program reaches it"); the coordinator reran it. Lane R's gate passed (690.6 s, 31 actions
executed) in 2.7 lane-hours against the 8 to 14 estimated.

- **Nothing was added to the IR.** A clause's trap already carries its kind, its message and the span of its condition, and
  the inliner keeps them, so the report reads the final IR and the facts. Emitted code and every cache format are unchanged:
  the exactness check gave 1,392 identical and 0 different of 1,504 builds (112 fail both ways, the corpus's baseline).
- **What the statuses mean.** Proved: the facts state the copy's trap block unreachable, the dead block of the fact certificate
  (F5), which a Debug compiler validates. Refuted: the trap is reachable and the block the check passes to is not. Kept:
  anything else. A fourth count, unused, holds copies in a function nothing calls after inlining; they decide no status.
- **Counts.** `tests/lang` (379 of 398 programs built): 17 clauses, 11 proved, 6 kept, none refuted; `assert` copies 11
  proved and 448 kept. The port (202 of 222 programs built, no clauses): `assert` copies 15 proved and 1,443 kept. The
  trial's two drivers: 10 of 115 clauses proved, 32 of 287 copies.
- **Soundness.** `src/core/validate_facts.zig` and `proofs/facts` are unchanged. A fault-injection test shows the validator
  refuses a kept clause whose trap block is stated dead, and a `--verify-facts` build traps `R_CORE_FACT` at run time when a
  test reaches such a copy.
- **Open: the build warning for a refuted clause (the user's decision).** An ordinary development build with a release
  compiler never loads the final body of an unchanged function, so a warning computed from the bodies would appear on a cold
  build and vanish on the next warm one. A warning that survives needs the refuted copies stored in the final-stage record, a
  format change the lane's brief forbade. Lane R's estimate: 3 to 5 lane-hours, and one cold optimizer stage per worktree when
  the format version moves. Until then a refuted clause is visible in `cost --clauses` and `--stats` only.
- **Open, smaller.** `mylang test` prints no clause report. An invariant's row is placed by searching the source for its
  text. A proved chained comparison (`0 <= x <= 255`) keeps its branch in the emitted code: folding every decided boolean in
  `facts.mark` would remove it, and that changes emitted code, so it belongs with S2 and needs the exactness check.
- **For S2.** The report is `src/core/clause_report.zig`, computed wherever the cost totals are. S2's exit can now be read off
  it: the share of proved clauses on `tests/lang` and on the trial's drivers, before and after.

**The three contract defects are fixed (11 November, `c099a32e1`).** The user approved the work ("Yes, fix them") and then the
landing. Lane F's gate passed (531.3 s, 31 actions executed); the exactness check gave 0 different of 1,504 builds, and the
port's release output is byte-identical. The write-up is `experiments/proof-steps-20261110/FIXES.md`.

- **D1** was in the lowering: `armBody` (`src/core/build.zig`) asked for the type of a `Unit` payload, which has no
  instruction. A plain `case Ok(v):` on a `Unit fails E` value crashed the same way with no clause. One guarded line.
- **D2** was in the checker's own invariant check: it moved the updated record into a hidden `self`, so the single-owner
  checker no longer saw an in-place write. `checkAfterStore` (`src/sema_contracts.zig`) leaves the write as it is and checks
  every invariant on its chain afterwards against the written place, through borrowed reads. No record is copied: allocation
  and copy counts are the same with and without the invariant. Nested stores, list, dictionary and fixed-array elements,
  `match mut` bindings, a narrowed option and `+=` are fixed with it. No ownership rule, validator or proof changed.
- **D3** was at a block's end: the checker dropped the name of every local made in the block, the postcondition's hidden
  `result` holder among them, and that took the body's own `result` with it. A block now drops only the names it bound.
- **One shape accepted before is now refused, by the user's decision of 11 November.** A function with `@ensures` that
  declares a local `result`, returns it from an inner block and declares `result` again in the same outer block is
  `E_SHADOWING`. The same function without its `@ensures` line was already refused; the defect had hidden the first
  declaration. No such code exists in the repository, the port or the trial, and there is no certain `mylang fix` repair (it
  would rename the second local).
- **Real use.** The port's tokenizer, with two of the invariants the trial had to emulate declared as `@invariant` on
  `Tokenizer`, passes its 41 tests; main's compiler before this change refused the module.
- **Open, found by this lane: `take` and `exchange` on a field never run the record's invariant**, before this change and
  after it. The coordinator confirmed it: taking a list out of a record whose invariant says the list is not empty raises
  nothing. It is a hole in what an invariant promises, it is in no stage, and closing it is the user's decision.
- The primer can now say that an invariant works on a record with managed fields; that edit waits for the next change to the
  guide, with the gaps listed above.

**Every in-place write to a field now runs the record's invariant (11 November, `9c3f63d2e`).** The user approved "the
`take`/`exchange` fix plus the guide gaps". Lane I's gate passed (821.3 s, 31 actions executed); the exactness check gave 0
different of 1,504 builds, and the port's release output is byte-identical. The write-up is
`experiments/proof-steps-20261110/TAKE.md`.

- **Cause.** `take` and `exchange` are a place-exchange node, not a record update, so neither the store check nor the
  construction wrapping saw them. The same held for every in-place update through a receiver and for a call or callback
  given `mut t.field`.
- **Fix.** `checkAfterPlaceWrite` (`src/sema_contracts.zig`) keeps the expression and then checks every invariant on the
  written path, innermost first, through borrowed reads. No record is copied; allocation counts are the same with and without
  the invariant. Now checked: `take` and `exchange` on a field (also nested, on a list element and on a `match mut` binding),
  `append`, `lists.pop`, `lists.clear`, an element write `t.items[i] = v` or `t.map[k] = v`, `dicts.add`, `sets.add`,
  `f(mut t.items)` and a callback. Nothing is newly refused at check time. At run time a program that breaks an invariant by
  one of these writes now traps `R_INVARIANT` there; an invariant with a loop now runs that loop after every `append`.
- **A regression of the defect-fix landing, on main for about two hours, is repaired with it.** Since `c099a32e1` a field
  store into a record with an invariant was refused with `E_UNBOUND` when the record was a local of an inner block, or a
  `match mut` binding whose other arm falls through. The compiler before that landing accepted it; the coordinator reproduced
  the refusal on a pin of `e4beb1f99` and its absence on this branch. No lane's suite had the shape; `tests/lang/contracts.my`
  has it now. Nothing was pushed in between.
- **Open.** `match mut t.opt: case Some(v): v = 0` is still not checked (a check on every path out of the arm, estimated at 2 to
  4 lane-hours). An element write whose key is not a literal or a local (`xs[i + 1]`) is not checked. Both are holes of the
  same kind as the one closed, and neither is in a stage.
- **The guide.** The primer's section gained ten lines for the six gaps the trial found: an invariant is checked after every
  field write, it works on records with managed fields, `old(...)` takes a field and a clause may call a function, a clause
  costs run time unless proved (`mylang cost FILE.my --clauses`), and what cannot be said (loop invariants, quantifiers, the
  `fail` path). Found on the way: `cursor = replace(cursor, low=cursor.low + by)` on a record with a list field is refused by
  Core (rule Z3), on main before this change too, so the primer computes the new values first.

**S2 step 1 landed (11 November, `815917b6b`). P4 is met; the counts on real clauses did not move.** The user approved step 1.
A function's return interval is now the hull, over each reachable `ret`, of the returned value's view at its block: its
interval narrowed by the branches that dominate the return. That is the view the validator's return rule (F6) already reads,
so the claim is the same kind as before, only narrower. Lane S's gate passed (608.8 s, 31 actions executed) in 2.1 lane-hours
against the 5 to 9 estimated.

- **P4.** On the plan's probe, `xs[clamp(i - 3)]` goes from 1 check kept and 1 proved to 0 kept and 2 proved; the coordinator
  reran it. A callee whose bound comes only from a kept `@ensures` narrows its callers too: the clause's trap ends the failing
  path, so whatever returns has passed it. The coordinator's probe of that case still traps `R_ENSURES` in the callee, in
  debug and in `--release`.
- **The counts did not move.** `tests/lang`: 15 of 23 clauses proved before and after. The trial's drivers: 10 of 115 before
  and after. The port's entry: checks kept and proved went from 5,586 and 14,525 to 5,585 and 14,526. Emitted code changed
  in 6 of 754 corpus programs, all six read: bounds and overflow checks proved, one `@requires` folded, one narrower
  division. The coordinator's expectation that this step would raise the proved share was wrong.
- **Why.** The integer postconditions the facts keep are chained comparisons (`0 <= result <= 255`), which the checker lowers
  to a block whose `bool` reaches the clause's branch through a phi that the narrowing cannot read, or they are relational.
  Splitting a chain into one branch per link, as `and` already is, would let a kept chained clause narrow its callers under
  the same validator. Lane S prices it at 2 to 4 lane-hours; it changes the blocks of every chained condition, so it needs
  its own exactness pass. It is the first lever after this stage and is not started.
- **Soundness.** No validator rule and no theorem changed. A return interval narrower than the branches give is refused by
  F6, by hand and for every narrow-return mutant; a verify build with sabotaged intervals traps `R_CORE_FACT`. All 12,179
  functions of 753 corpus certificates are accepted before and after.
- **An old gap, shown and not closed.** A caller's call interval that is narrower than the callee's certificate states is
  assumed, not refused, and has been since October's return intervals. A fault in the new narrowing is not hidden by it (the
  callee's own certificate states the same interval and F6 checks it). Closing it changes what the exporter states; lane S
  prices it at 2 to 3 lane-hours. The user's decision.
- **No stale caller.** Every key that covers a caller's facts already holds the callee's return interval by value. A new
  cross-module test widens a callee by an edit: the warm build equals the cold one byte for byte, the bounds check comes
  back, and `--verify-cache` passes. No stage, replay or record format changed.
- **Edit cost.** A one-line edit build of the 99k port costs the same instructions to 0.05% (2,099 against 2,100 million).
- **The report** now counts, per `@requires`, the call sites where it is proved, refuted or kept (`call_sites` in
  `cost-clauses-v1`; members were only added).
- **For S3.** A clause that is not checked in some build must not narrow callers in that build. The tests-only marker has to
  switch this narrowing off wherever it switches the check off.

**S2 step 2, priced and not built (decision PD2).** Relational postconditions are three separate additions, 36 to 60
lane-hours in all by lane S's estimate: a relational return line (14 to 22 h; it proves at most 2 of the trial's clauses), exit
intervals of `mut` parameters (12 to 20 h; the 13 kept `position >= 0` requires and their call sites), and a rule that two
computations of one value are equal, which `old(...)` clauses need (10 to 18 h; 31 of the trial's clauses). Lane S's order:
the chained-comparison split first, then the `mut` exit intervals, then the equality rule, then the relational line.

**A chained comparison is one branch per link (11 November, `3d1f217cf`). Checks are proved; the clause counts still do not
move.** The user approved this follow-up to S2. A chain of integers or booleans used as a condition (`if`, `while`, `assert`,
a clause, inside `and`, `or` or `not`) now lowers to one branch per link on that link's own comparison, in
`src/core/build_chain.zig`. It recognises the block the checker already builds and replays the same statements in the same
order; any other shape, a chain used as a value, and chains of other operand types lower as before. Lane C's gate passed
(418.7 s, 31 actions executed) in 1.7 lane-hours against the 3 to 6 estimated.

- **Meaning is unchanged.** Evaluation order, evaluate-once and short-circuit are tested in `tests/lang/chain_conditions.my`,
  and an operand's overflow and bounds traps keep their positions (`test/core/chain_traps.my`). The coordinator's probe, a
  chain of calls that print, gives the same output from the compiler before and after, in debug and in `--release`. No
  validator rule, proof, trust point or format changed.
- **What moved.** Checks kept and proved: the tokenizer driver 85 and 97 to 63 and 119; the codec driver 55 and 181 to 46 and
  190; the port's entry 5,585 and 14,526 to 5,561 and 14,549. Run-time instructions: the tokenizer driver down 0.53%, the
  codec driver down 1.69%, three port commands unchanged to 0.06%. Emitted code changed in 19 of 756 corpus programs, all 19
  read: the chain's phi is gone, 11 of them prove more checks, and none got longer (LLVM lines down 0.37%). A one-line edit
  build of the 99k port costs the same instructions to 0.02%.
- **What did not move.** `tests/lang`: 17 of 26 clauses proved before and after. The trial's drivers: 10 of 115 before and
  after. The split proves checks after a chained test and in callers; a clause's own status depends on what the facts know
  inside its function, and the chained clauses still kept are on values the facts do not bound, or they are relational.
- **What would move them is decision PD2.** Exit intervals of `mut` parameters would unblock the 13 kept `position >= 0`
  requires at their 17 call sites, and the rule that two computations of one value are equal would unblock 31 clauses that
  use `old(...)`. Neither is built. Folding every decided boolean (D-S2-8) is still priced, not built.

