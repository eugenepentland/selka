# Plan for the small items of the two audits (11 November 2026)

**Status (as of 15:03 UTC on 12 November 2026, main `d3e87de82`): all eleven lanes of section 3 have landed on main, the last
(W3, its second half) at 14:30 UTC; W7 ended at its count, by the user's decision to leave the rule off.** The plan was
approved on 12 November 2026 and the first three lanes (W24, W8, W9) started at 00:40 UTC from main `675d63299`. The user's
words: "Ok you can start the lanes, I agree with your decisions". That answered P1, P2 and P3 of section 6 as recommended;
Q6 and the `old(x)` question were answered on the same day. Section 3 now records, for each lane, when it started and
landed and what it took; section 8 lists the lanes the plan did not have (N4, N5, FX, FX2, W11, W19a) and every decision
with its answer. The numbers in sections 1 and 5 are the plan's estimates and counts as written on 11 November; where a
lane's write-up (`experiments/audit-work-20261111/`) says otherwise, the write-up is the record.

Written on 11 November at the user's request ("come up with an implementation plan so you can be ready to use sub agents to
start these tasks; we can do the easiest ones first"), against main `ab4971751`, while lane VL of the proof round was still
in flight. Lane VL has since landed, so line numbers in this plan are from before it.

It covers section 9.1 of `language-goals-audit-2026-11-11.md`: W1 to W10, W24 and the small defects of its section 8. The
medium and large items (W11 to W23) are not planned here; section 7 says what comes next.

Before writing it, three read-only searches located every item in the compiler and counted what each would break in the
repository and in the three projects (the 99k port, protobuf, the SQLite binding). Nothing was built or run for this plan.

## 1. Short version

- **Eleven lanes, three at a time**, easiest first. About 66 to 125 lane-hours in all; every number here is an estimate.
- **Five lanes refuse nothing that is accepted today** and can start on a plain go-ahead: W24, W8, W9, W2 and W10.
- **Three lanes are small but each reverses a rule that was decided on purpose**, so each needs one answer first: W1, W5, W6.
- **Three lanes begin with a count**, because the search showed nobody knows how much they break: W3, W7, W4.
- The search changed the list. W6 is far larger than the audit said and is narrowed here. W10 covers about 60 functions,
  not 6. W5 and W7 undo decisions of October. One "defect" is intended behaviour and is dropped. Section 2 has all of it.
- Ready now: the lane rules (`~/ai/.home-cache/aw/RULES.md`) and the briefs of the first three lanes
  (`~/ai/.home-cache/aw/BRIEF-W24.md`, `BRIEF-W8.md`, `BRIEF-W9.md`). The other briefs are written from section 5 when their
  slot opens, because main will have moved by then and line numbers go stale.

## 2. What the search changed

Each row corrects or sharpens something the audits said. The audits' text is left as written; this table is the newer word.

| Item | The audit said | What the code says |
| --- | --- | --- |
| W1 | `try` picks the first enum case that fits | So does `fail "text"` in a function that fails with an enum. One helper (`typed.wrappingCase`) with four callers decides both. |
| W1 | breaks only an enum with two cases of one payload type | Seven such enums are used after `fails`: five in the standard library (`argparse`, `csv`, `http`, `process`, `strings`) and two in protobuf (`pjson`, `wire`). None in the port or the SQLite binding. How many conversions fire needs the compiler. |
| W3 | `check` tries a template with `int` only | True, and it skips every standard-library template, so all 70 of them are never judged at their declaration. The port has 78 templates. |
| W4 | the hidden-copy check runs only in a Debug compiler or under `--verify-facts` | It runs under `--verify-facts` or `--verify-written-copies`; the language suites already run with it. The search found no tie to a Debug compiler; the lane confirms with a probe. |
| W4 | `cost --sites` and the check use different lists | `cost --sites` already counts a frame block as an unwritten copy; the check leaves it out, and the two also disagree on which blocks are reachable. |
| W4 | `old(x)` becomes `old(copy(x))` | One program in the repository and none in the projects writes `old` of a managed value. A shared type is already refused with that advice. |
| W5 | `debug` dropping its arguments is a defect | It is specified (`DEBUG-LINE-1` in `SPEC.md`) and a test asserts it. Changing it reverses a decision. |
| W5 | the gate compares build modes | Nothing compares them, and release builds are out of the gate by the decision of 28 October. |
| W6 | a small rule, rarely breaks | The opposite is documented and tested ("a declared function shadows the prelude inside that module"). Counts of prelude names used as other things: `import bytes` 189 times (166 in the port), a local named `list` 172 times, 41 functions in the repository and 10 in the port. The standard library has modules named `sort` and `bytes`. |
| W6 | one prelude | Two tables that disagree: 40 names in `src/operations.zig`, 22 in `src/prelude_builtins.zig`, ten of them not among the 40. |
| W7 | the dead-write error "no longer exists" | It was removed on purpose on 9 October; the spec text that replaced it says a mutable local copy whose last value is unused is legal. |
| W7 | `mylang fix` inserts a copy that later writes go into | Confirmed: the copy repair has no test for a later write. This half is small and refuses nothing. |
| W9 | the interface keeps a body for four reasons | Six roles; five keep a body (`foreign` is the fifth). The oracle is front-end only and never runs Core's ownership pass. |
| W10 | six `dicts` functions and `parallel.map` | About 60 library functions lower to a builtin method and never run their body, plus two in `testing`. Whether `parallel.map`'s body runs in some builds is not confirmed. |
| Defects | a typed hole fails `check` and passes `build` | Intended and documented (`docs/typed-holes.md`). Dropped from the defect list; it stays a named exception in the register. |

## 3. The queue

The table is the queue as planned, with what happened to each lane on 12 November (all times UTC; the lane's start and landing
are from the coordinator's roadmap, `~/ai/.home-cache/aw/roadmap/lanes.json`). Three lanes ran at a time. "Refuses?" is the
plan's column: whether the lane makes `check`, `build` or `test` refuse a program that was accepted; the lane's write-up says
what it did. "Time" is the lane's running time; W10 and W3 waited for a decision (about 4 and 5 hours) and that wait is not in
it. The estimates are the plan's; the roadmap sums a lane's two parts (W3 2-4 then 6-12 is 8-16, W7 3-5 then 6-12 is 9-17).

| Order | Lane | What | Agent | Estimate (h) | Refuses? | Needs from you, and the answer | Started, landed | Time |
| ---: | --- | --- | --- | ---: | --- | --- | --- | --- |
| 1 | W24 | The gate checks the goals register | sonnet-lane | 4-8 | no | go | 00:40, 01:28 | 48 min |
| 2 | W8 | Advice the compiler refuses, and five small defects | sonnet-lane | 8-14 | no | go | 00:40, 02:10 | 1 h 30 min |
| 3 | W9 | Locality is tested: the role list pinned, the oracle covers ownership | opus-lane | 6-12 | no | go | 00:40, 01:46 | 1 h 6 min |
| 4 | W1 | `try` and `fail` convert an error only when one case fits | opus-lane | 4-8 | yes | P1: yes | 01:28, 02:40 | 1 h 12 min |
| 5 | W5 | `debug` evaluates its arguments in every build | sonnet-lane | 3-6 | no | P2: yes | 01:45, 02:54 | 1 h 9 min |
| 6 | W2 | Ownership refusals name their cause; `mylang fix` stops offering a lossy copy | opus-lane | 8-14 | no | go | 02:04, 03:29 | 1 h 25 min |
| 7 | W6 | A module function cannot take a builtin's name (narrowed) | opus-lane | 4-8 | yes | P3: the narrowed rule, narrowed again (refused only when its own module uses the name bare); a re-export gets the same rule | 02:38, 05:07 | 2 h 29 min |
| 8 | W10 | Library functions with no running body are declared as such | opus-lane | 6-12 | no | go, then its design: all five parts as recommended | 05:44, 12:36 | 2 h 47 min |
| 9 | W3 | Generic bodies judged at their declaration: count, then build | opus-lane | 2-4, then 6-12 | yes | the count's result: yes, in two steps | 03:28, 14:30 | 5 h 34 min |
| 10 | W7 | A write nothing reads: count, then decide | opus-lane | 3-5, then 6-12 | yes | the count's result: leave the rule off | 02:54, 06:58 | 4 h 4 min |
| 11 | W4 | One meaning of "hidden copy" in the tools | opus-lane | 6-10 | `old(x)` only | Q6: keep the dictionary-key copy; `old(copy(x))` required | 05:05, 07:19 | 2 h 14 min |

Every lane took less time than the low end of its estimate. What each landed, from its write-up:

- **W24.** The gate action `goals_register` (`zig build test-goals`) checks the page and its pins. Run against the page as
  written it found six faults of form, none a goal without evidence.
- **W8.** Six pieces of advice fixed, five defects fixed, and a gate test over 111 advice entries (the plan's brief estimated
  about 45); the test found nine more pieces of refused advice in the tables themselves.
- **W9.** The six-role list is pinned and the interface oracle compares Core's ownership refusals; no new difference was found.
- **W1.** An ambiguous `try` or `fail` is refused (`E_ERROR_CASE_AMBIGUOUS`), `fail` with a fix that names the first case. No
  real code was affected: the two ambiguous sites were the register's own pins.
- **W5.** `debug` evaluates its arguments in all six build modes. A release build also refuses a typed hole reached only
  through a `debug` argument, which the user kept.
- **W2.** A refusal about a borrowing local names the line that caused it, `mylang dump-typed` shows each local's status, and
  `mylang fix` no longer inserts a copy that would lose a later write.
- **W6.** A function or re-export with a prelude name is refused when its own module uses the name bare, with an automatic
  rename. The port needed 4 renames and protobuf 2; the repository's programs were migrated.
- **W10.** The 90 library functions the compiler supplies are declared `public builtin func` with no body, and every spelling
  of a call runs the same operation. A `simd` operation used as a function value is now an error, which the user approved.
- **W3.** `check` refuses a generic body at its declaration when it is wrong for a text, a record with a managed field or a
  list, with an automatic fix. The count that preceded it was 68 newly refused (8 library, 52 repository, 7 docs, 1 port; the
  fix repairs 60). A template's verdict is kept: a check after a one-line edit of the port costs 1 percent less than before,
  a cold check 3 percent more.
- **W7.** The count is on main as the lint rule `dead-write`, off unless asked for (`mylang lint FILE --rule=dead-write`). It
  found 160 such writes; of 30 read by hand none was a bug, 2 were dead code and 28 were deliberate. The user chose to leave it
  off, so the second half was not needed.
- **W4.** `mylang cost --sites` and the hidden-copy check read one list of copy sites and label each written, a named
  operation or implicit; the dictionary-key copy reads implicit. `old(x)` of a managed value is refused until written
  `old(copy(x))`, with an automatic fix; the repository's one program was migrated by `mylang fix`, its documentation
  examples and 4 Zig-embedded test programs by hand, and the three projects had no site.

**Why this order.** W24 goes first because every later lane has to update the register, and from then on the gate checks
that it did. W8 and W9 change no behaviour. W1 and W5 are the two smallest changes of behaviour and move to the front of
the queue as soon as P1 and P2 are answered. The last three start with a measurement.

**Which lanes cannot run together** (they edit the same files):

- W8, W6 and W10 all edit `src/parser.zig` and the tables of removed names. One at a time, in that order.
- W2 and W3 both edit `src/core/single_owner.zig`. W2 first.
- W10 adds a kind of declaration that the interface must classify, so it starts after W9 has pinned the role list.
- W4 edits `src/core/verify_ir.zig`, which has a Lean copy since 11 November (`verify-ir-proof`). If the copy has to change,
  that is a Stop.
- Every lane touches `CHANGES.md` and `docs/goals.md`; the rules say how to merge them.

## 4. How every lane runs

The rules are the ones the lanes of 10 and 11 November ran under, with one section added for this work
(`~/ai/.home-cache/aw/RULES.md`). The parts that matter here:

- **A lane works in its own worktree and branch** (`audit/<item>`), never in main. Free worktrees today: `mylang-editcheck`,
  `mylang-gate`, `mylang-services`, `mylang-checkbuild`. Each is checked for a lock and a clean tree, then locked with the
  lane's name. Scratch is `~/ai/.home-cache/aw/<item>/`.
- **The probe comes first and last.** Each item has a probe program from the audits. The lane runs it before the change and
  after, and the hand-back quotes both.
- **Shapes outside the brief.** Each lane tries at least six shapes its brief does not name. On 11 November a lane's tests
  followed the brief and the projects then found 41 false refusals.
- **The three projects are swept** with the lane's compiler on clones: a lane that should refuse nothing reports zero new
  refusals, and a lane that refuses reports how many sites, how many `mylang fix` repaired and how many needed a hand edit.
- **A refusal ships with its migration**: a structured fix on the diagnostic, a pre-change corpus under
  `test/fixtures/fix-migration/` and a test beside `FIX-MIGRATION-1`.
- **The register moves with the change.** A fixed exception turns its pinned example from `X` to `H` and updates
  `docs/goals.md` in the same branch.
- **Landing, one lane at a time:** the lane merges main and passes the complete gate; I read the diff and rerun its probes
  myself; main is fast-forwarded; the main gate runs; the other lanes are told main moved. Nothing is pushed.
- **A Stop** is a hand-back with a question. Every lane has the same standing ones: a refusal the brief did not describe, a
  change to a validator, a proof or a trust point, a change of a stage or record format, and 1.5 times the estimate.

Known risks on this machine: swap is full, and in that state the unexplained fault F22 fails about one run in 70 of one test
(the rules say to rerun once). Three lanes together kept the load near 30 on 11 November, so elapsed time will be several
times the lane-hours.

## 5. The lanes

Line numbers are from main `ab4971751` and are a starting point, not a contract.

### W24. The gate checks the goals register

- **Today.** `docs/goals.md` names theorems, tests, gate actions and files, and nothing confirms they exist. Its 51 pinned
  examples run only when someone types `mylang doctest test/fixtures/goals`.
- **Change.** One gate action that fails when: a pinned example fails; a path named as evidence does not exist; a theorem
  named with its file is not declared there under that namespace; a gate action named is not in the verification inventory;
  an example id cited in the page has no example, or an example has no citation; an exception count in the summary table
  differs from the entry's list.
- **Where.** A driver step in `build.zig` (model: `test-docs`), a new input list in `build_test_inputs.zig` (model:
  `doctest`), and a Python driver under `tests/` (Python is allowed in gate drivers, never in the install graph). Theorems are
  confirmed by text, not by running Lean; the proof actions already run Lean.
- **Done.** The action is in `zig build test` and the complete gate; six deliberately broken copies of the register each
  fail with a message that names the line; the page's "How this page is checked" section states the format the checker reads.
- **Not in scope.** Changing any goal's level or wording.

### W8. Advice the compiler refuses, and five small defects

- **Today.** Six messages advise a spelling that is refused (audit A, S2): the `del` hint (`src/parser.zig`, the hints
  table; the real answer is `lists.pop_at`), the `mutates(...)` hint (prose says `name: mut T`, its own fix writes
  `mut name: T`), the generic "write `copy(...)`" for `sets.add` followed by a warning against that copy
  (`src/core/escape_message.zig`, `src/needless_copy.zig`), `&&` answered as `&` (`src/removed_names.zig`), `try` inside an
  expression reported as a type error (`src/parser.zig`, `boundaryExpression`; the position rule's message exists), and
  signatures printed as `list[bool]`, `Option[int]` and `-> None` (`src/buffer_operations.zig`; `typed.surfaceTypeName`
  already gives the accepted spelling).
- **Change.** Fix the six. Add a gate test that takes every backquoted replacement in the three message tables (about 45
  lines of advice in `src/retired_methods.zig`, `src/removed_names.zig` and the parser's hints table), builds the smallest
  program around it and requires it to check clean. The roughly 150 advice strings scattered through other files are listed
  in the write-up, not tested, in this lane.
- **The defects** (audit A, section 8): the doubled "yet" in the task message (`src/core/pipeline.zig` wraps the reason of
  `src/core/build_task.zig`); `mut domain = 1` saying "expected a newline" (`src/parser.zig`, the `mut` binding path);
  `p.norm()` on a record reporting an unknown type (`src/sema.zig`, the call-owner path); `docs/primer.md` line 78;
  `docs/python-syntax.md` line 598. The sentence in `mylang docs operations` goes to W6, which owns the prelude tables.
- **Done.** Each of the six probes prints advice that compiles; the new test fails when a table entry is given a refused
  spelling; pinned example G14-X9 becomes a "holds" example; no program is newly refused.
- **Watch.** `src/ownership_rule_sites_test.zig`, `tests/parser_hints.py` and `velocity/friction/classifier.json` pin
  message text.

### W9. Locality is tested

- **Today.** Nothing fails when someone adds a reason for an interface to keep a function's body. The interface oracle
  (`mylang interfaces oracle`, gate step `test-interfaces`) compares front-end results only.
- **Change, part 1.** A test pins the role list of `src/module_interface.zig` (six roles, five of which keep a body) and
  the rule that decides a role (`roleOf` in `src/module_interface_build.zig`), with a comment that says a new role is a
  decision for the user.
- **Change, part 2.** The oracle also compares Core's ownership verdict: for every module of `tests/lang`, the refusals
  (code and position) of `single_owner` when the module's dependencies are interfaces against when they are full sources.
- **Done.** Both tests are in the gate; a deliberately added role fails part 1; a deliberately body-dependent verdict (the
  lane builds one as a mutant) fails part 2; the gate's CPU cost rises by at most 60 CPU-seconds (the oracle costs about 160
  today).
- **Stop.** The oracle finds a real difference on main. That is a finding about goal G7, not a bug for the lane to fix.

### W1. `try` and `fail` convert an error only when one case fits (needs P1)

- **Today.** `typed.wrappingCase` (`src/typed.zig`) returns the first case whose payload fits. Its callers are the checker
  for `try` (`src/sema_expressions.zig`), for `fail` (`src/frontend_failures.zig`), generic bodies
  (`src/generic_bodies.zig`) and lowering (`src/core/build.zig`, `tryValue`).
- **Change.** The helper says none, one or several. Several is an error that lists the cases and asks for one by name.
- **Step 0.** With the compiler, count the conversions that fire in the seven enums of section 2. Hand back the count before
  anything is refused if it is over 40.
- **Migration.** `fail "text"` gets a certain fix: name the first case, which keeps today's behaviour. For `try` the lane
  finds the shortest accepted spelling that names the case. If none fits on one line, that is a Stop with the options (new
  syntax is the user's decision).
- **Done.** Probes `try_converts_error.my` and `try_converts_error_reordered.my`: the second is refused; pinned examples
  G9-X1 and G9-X2 are re-pinned; `docs/results-and-options.md` states the rule; the standard library and protobuf build.

### W5. `debug` evaluates its arguments in every build (needs P2)

- **Today.** `drop_debug` is set for a `build --release` binary only (`src/core/pipeline.zig`), and `printNode`
  (`src/core/build.zig`) then returns before it lowers the arguments. `run --release` and `test --release` keep them.
- **Change.** In every build the arguments are evaluated, so a trap or a write inside them happens. The release binary
  drops only the formatting and the write to standard error.
- **Done.** Probes `debug_release.my` and `debug_argument_writes.my` give the same result in all modes; pinned examples
  G10-X1 and G10-X2 become "holds"; the test that asserts today's behaviour (`src/core/cli_flags_test.zig`) asserts the new
  one; a count of `debug(` calls in the three projects, with the release run time of the port before and after if it has any
  in a loop.
- **Not in this lane.** The comparison of the language suites across build modes. It needs release builds in the gate,
  which the decision of 28 October took out. It is written down as W5b and waits for that decision to change.

### W2. Ownership refusals name their cause; `mylang fix` stops offering a lossy copy

- **Today.** When a later statement makes a borrowing local need to own its value, `finishFunction`
  (`src/core/single_owner.zig`) discards the refusal raised at that statement, checks the function again as if the local
  owned, and reports that second refusal on the earlier line. The later statement's position is in hand just before it is
  overwritten.
- **Change (a).** The refusal keeps its code and position and gains a note at the statement that forced ownership. When
  the cause is a record field's default, the note says which field. A diagnostic has one note slot today; the lane decides
  how two notes are carried and records it.
- **Change (b).** `mylang dump-typed` prints each local as owning or borrowing, and from what. `mylang context` is
  front-end only and cannot see this; the lane says so in the docs.
- **Change (c), the small half of W7.** The copy repair for `mut x = xs[i]` is not offered as a fix when `x` is later
  written or passed with `mut` (`annotateElementBinding`, `offerBorrowRepair`). The message says a copy would lose the
  writes and offers the write-back when it can be proved.
- **Done.** The five borrowing probes of audit A (R2) each print a note on the right line; no program is newly refused or
  newly accepted; `lost_update_on_copy.my` is no longer produced by `mylang fix`.

### W6. A module function cannot take a builtin's name (needs P3)

- **Narrowed rule.** A top-level function in a user module cannot have the name of a prelude function. Locals, parameters
  and imports are left alone: the search found hundreds of them and no silent change of meaning (calling a local or a module
  is already an error).
- **First.** One table of prelude names; today `src/operations.zig` and `src/prelude_builtins.zig` disagree. The sentence
  `mylang docs operations` prints about names appearing once is corrected here.
- **Where.** The four places that let a module name win: `preludeName` (`src/sema_builtins.zig`), `writerFunction`
  (`src/sema_collections.zig`), `topLevelSpelling` (`src/module_names.zig`) and the parser's own handling of `len`.
- **Migration.** A rename fix on the model of `src/builtin_type_names.zig`, which renames a declaration with every
  reference and withholds the fix when it cannot find them all.
- **Breaks.** 41 functions in the repository (several are tests that assert shadowing, to be rewritten), 10 in the port,
  none in protobuf or the SQLite binding. The standard library's own `math.abs` and the like are exempt: they are reached
  by a qualified name.
- **Done.** Probe `builtin_replaced.my` is refused with a fix; pinned example G7-X7 becomes "holds"; G7-X8 (an import hides
  a builtin) stays an exception; `docs/results-and-options.md` states the new rule.

### W10. Library functions with no running body are declared as such

- **Step 1, an inventory.** For every function of `src/stdlib`, whether its body ever runs, in which builds. Known so far:
  about 60 functions that lower to a builtin method (`src/retired_methods.zig`, `home`), the `parallel.map` family
  (`src/core/build_parallel.zig`) and two in `testing`.
- **Step 2, the form. A Stop with a proposal.** A declaration with no body and a word that says the compiler supplies it,
  allowed only in the trusted standard library (the mechanism behind `E_INTERNAL_NAME`). The parser's model is `extern func`.
  The spelling and the interface role are the user's decision; W9 will have pinned the role list by then.
- **Step 3.** Convert the functions, and add a test that each such declaration's signature matches the compiler's table,
  since the bodies were the only check of that today.
- **Done.** No library function has a body that never runs; `mylang list-interfaces` shows which are supplied by the
  compiler; nothing is newly refused in user code.

### W3. Generic bodies judged at their declaration (a count first)

- **Today.** `probeTemplates` (`src/sema_specialize.zig`) tries each template with `int`, skips the standard library, and
  ownership is then judged per instance (`single_owner.checkEvery`), with the error inside the template and no instance named.
- **Step 1, report only.** Behind a switch, try a text, a record, a list and (where the bound allows) a move-only type as
  well. Count what would be newly refused among the 70 library templates, the port's 78 and the tests. Hand back the count
  and the kinds.
- **Step 2, after the answer.** Refuse at the declaration, naming the kind of argument. An error only one instance shows
  is reported at the call and names the instance, as `refuseUnlendable` does today for `E_BORROW_SOURCE`.

### W7. A write nothing reads (a count first)

- **Step 1, report only.** A `mylang lint` rule for a write to a local, or to a field or element of a local, that no later
  read can see. Count it over the repository and the three projects and classify thirty of the hits by hand: a bug, dead
  code, or deliberate.
- **Step 2, after the answer.** An error, a warning or a lint. An error reverses the rule of 9 October, so it is the
  user's decision with the count in hand.

### W4. One meaning of "hidden copy" in the tools (needs Q6)

- **Change.** One list of copy sites and one test of reachability for `mylang cost --sites` and the check
  (`src/core/copy_sites.zig`, `src/core/cost.zig`, `src/core/verify_ir.zig`). `cost --sites` labels each site written, a
  named operation, or implicit; a dictionary-key copy and an `old` copy are implicit. The check counts frame blocks and
  prints the count under `--stats`, and refuses nothing new.
- **`old(x)`.** A managed value is written `old(copy(x))`, with a certain fix. One program in the repository changes.
- **Not in this lane.** Refusing frame-block copies. That is decision Q8 and waits for W18.

## 6. What I need from you

Three new answers, numbered P1 to P3 so they do not collide with Q1 to Q10 of the audit. Each has my recommendation.

**Answered on 12 November 2026: the user agreed with all three recommendations.**

| # | Question | Recommended | Answer |
| --- | --- | --- | --- |
| P1 | W1: may `try` and `fail` refuse a conversion when two cases fit? It touches five library enums and two in protobuf. | Yes. | Yes |
| P2 | W5: may a release binary evaluate the arguments of `debug`? `DEBUG-LINE-1` specified the opposite. | Yes: one meaning in every build. Leave the cross-mode comparison until release builds return to the gate. | Yes, as recommended |
| P3 | W6: the narrowed rule (functions only), the full rule (also locals, parameters and imports, hundreds of renames including `import bytes`), or leave it documented as it is? | The narrowed rule. | The narrowed rule |

Still open from the audit and needed later in this queue: Q6 (the dictionary-key copy) before W4.

**Answered on 12 November 2026, for W4.** Q6: "You can keep your recommendation" (the dictionary-key copy stays, labelled
by the tools). Whether a managed value in `old(...)` must be written `old(copy(x))`: "Require it".

Not needed to start: W24, W8, W9, W2 and W10 change nothing that is accepted today.

## 7. After these

By the audit's order: W11 (sealed types), W12 (the written idiom for state machines on `@linear` records) and W15 (a
promise about `mut` arguments on failure), with the spike of W19 beside them. Each gets the same treatment as here before it
starts: a search, a count, then a brief.

## 8. What the run added (as of 15:03 UTC on 12 November 2026)

### Lanes the plan did not have

The plan listed eleven lanes. Six more were started while they ran, from what the lanes found and from decisions the user
gave; times are UTC and come from the roadmap's `lanes.json`.

| Lane | What | Agent | Estimate (h) | Started, landed | Time |
| --- | --- | --- | ---: | --- | --- |
| N4 | `sqrt`, `floor`, `ceil` and `trunc` join the builtin names W6's rule covers | opus-lane | 1-2 | 12:35, 13:28 | 53 min |
| N5 | The hidden-copy check runs in every build (W4's step beyond the plan) | opus-lane | 1-2 | 11:10, 13:18 | 2 h 8 min |
| FX | The compiler defects the lanes found on the way (a crash on a Simd built from a Simd, `lists.stride` on a view, `debug` in a generic body, `buffers.append_range`, two paths of `check` that disagreed) | opus-lane | 5-9 | 13:41, 15:03 | 1 h 22 min |
| FX2 | The messages, `mylang fix` rough edges and documents the same lanes found; this lane also brought this plan up to date | sonnet-lane | 3-6 | 14:30, running | |
| W11 | Sealed types: a record only its own module can make (the first of the next set: W11, W12, W15) | opus-lane | 10-18 | 13:41, not landed | 33 min so far |
| W19a | A reference meaning of Selka in Lean: the spike that precedes W19b | opus-lane | 10-15 | 14:16, running | 47 min so far |

- **N4** found, with a probe, that a declared `sqrt` or `export lib.sqrt` captured a bare `sqrt(...)` like the 50 names W6
  listed; the table went from 50 names to 54. One site in the repository needed the rename (a C example) and none in the
  projects.
- **N5** measured the check at +0.27 percent of the instructions of a one-line edit of the port (+0.15 percent for a cold
  build), turned it on in every build, and found one wasted copy in the compiler (`strings.char_stride` on a text parameter),
  now fixed.
- **FX** refuses nothing that worked before: items 2, 3 and 5 accept programs that were refused, item 1 turns a crash into a
  diagnostic, item 4 changes comments and documents.
- **W11** stopped at its investigation with a proposal (an attribute `@sealed`, sixteen rules). Today another module can make
  or change a public record in 24 of the 26 ways it tried; in the port 701 of 1,174 public records are never built or
  changed outside their module. Building it waits for the user.
- **W19a** lands nothing: it ends with a finding on how many language tests a small Lean interpreter can run, whether it
  finds a disagreement with the compiler, and what the full version (W19b, 60 to 120 hours) would cost.

The roadmap also holds lanes that are not part of this plan: the three lanes that built the site that shows the roadmap (SITE,
STORE, LIVE, all landed) and the queue after these (FR1 running; FR2 to FR5, W15 and W12 queued).

### Decisions and their answers

Recommendations are as written when each question was asked. "Open" means the user has not answered.

| Id | Question | Recommended | State and answer |
| --- | --- | --- | --- |
| P1 | May `try` and `fail` refuse a conversion when two cases fit? | Yes | Answered: yes (12 Nov). Landed as W1 |
| P2 | May a release binary evaluate `debug` arguments? | Yes | Answered: yes (12 Nov). Landed as W5 |
| P3 | How far the rule on builtin-named functions goes | Functions only | Answered: narrowed again on 12 Nov, so a function is refused only when its own module uses the name bare |
| Q6 | The dictionary-key copy: keep it, or require `copy(k)` | Keep it, labelled by the tools | Answered: keep it (12 Nov). W4 labels it |
| W4 | Must `old(x)` on a managed value be written `old(copy(x))`? | Require it | Answered: require it (12 Nov) |
| W5 | A release build refuses a typed hole reached only through a `debug` argument | Keep the refusal | Answered: keep it (12 Nov). Landed with W5 |
| N3 | A re-export (`export module.NAME`) can bring a builtin's name in bare, so a bare call stops being the builtin (found by W6) | Treat the re-export like a declaration: refuse it when that module uses the name bare | Answered: the same rule (12 Nov). Built by W6 |
| W3 | Refuse a generic body where it is declared, for every kind of type argument? The count: 68 would be newly refused; an automatic fix repairs 60 | Yes, in two steps: repair the library's 8 bodies and the set operations by hand, then refuse with the automatic fix | Answered: yes, in two steps (12 Nov, "Go with all of them") |
| W7 | What a write that nothing reads becomes: an error, a warning, a lint on by default, or stay off. The count: 160 hits, 137 of them in the language tests; of 30 checked by hand, 0 bugs, 2 dead code, 28 deliberate | Leave it off: the rule exists for whoever asks | Answered: leave it off (12 Nov, "Go with all of them"). W7 is done |
| W10 | How a library function the compiler supplies is declared: the word, its interface role, whether all 67 are supplied in every call form with a simd function value refused, whether the three dictionary views are exempt from the signature test, whether the 14 helpers with no declaration get one | `builtin func`; the existing role "declared"; supplied everywhere and the simd function value refused; exempt the three; declare the 14 | Answered: all five as recommended (12 Nov, "Go with all of them") |
| N4 | `sqrt`, `floor`, `ceil` and `trunc` are builtins that neither old list named, so a module's own `sqrt` still silently wins (found by W6) | Add them to the list of builtin names, so the same rule covers them | Answered: add them (12 Nov, "Go with all of them"). Landed as N4 |
| N5 | Run the hidden-copy check in every build, not only when asked. W4 measured it: 0.2 percent more instructions on a one-line edit of the port, and nothing refused in any test suite or project | Turn it on: it costs almost nothing and makes the goal checked in every build | Answered: turn it on (12 Nov, "Go with all of them"). Landed as N5 |
| Q8 | Refuse the hidden copy of a slice or bytes argument by default | Yes, after W18 and a look at the port's five sites | Open. W4 now counts and labels these copies; nothing is refused |
| Q10 | The order of W11, W12 and W15 | Sealed types, then the failure promise | Answered: the user asked for the next set on 12 Nov; they were queued in the recommended order, W11, then W12, then W15 |
| Q4 | Which large refactor goes first | The spike of W19, then W20 | Open. The spike is queued as lane W19a; its result decides the rest |
| W11 | Sealed types, five parts: the spelling, the sixteen rules, that `take` is refused while `copy` and `exchange` are allowed, that test inputs of a sealed record are built only in its own module's tests, which library records are sealed first | All five as proposed | Open. The user holds up building sealed types |
| N1 | `debug` writes to standard error with no capability (found in the sweep; it had no decision) | Keep it as a documented exception | Open |
| N2 | A one-line way to name the case on a `try` (new syntax, raised by W1) | Not now; no real code needs it | Open |

Still open from the audit and not tied to a lane above: Q1, Q2, Q3, Q5, Q7 and Q9 (`~/ai/.home-cache/aw/roadmap/decisions.json`
has each question and recommendation).
