# Ownership rules: one written rule set the compiler implements (plan, 2026-10-24)

The ownership model becomes a numbered rule set that the compiler implements exactly.
Every ownership refusal names its rule, each rule is checked in one layer, a function's
signature says what its result borrows, and every move of a named binding is spelled
`own`. This is the first step toward machine-checked proofs: the rule set is the object
a soundness proof targets, and a rule decided by one function's signature can be
checked one function at a time.

**Inputs.**
- The rule set, its code map, the 27 prototype refusals and the 13 gaps:
  [`docs/design/ownership-rules-2026-10-24.md`](../design/ownership-rules-2026-10-24.md),
  a copy of the Claude Doc <https://claude.ai/artifact/Efx4k4nepPqwYWRcL8s2N6>. Rule
  ids below (B3, R4, …) and prototype row numbers refer to it.
- The user's decisions of 24 October, D1 to D4 (§8).
- The borrowed-returns plan
  ([`borrowed-returns-plan-2026-10-20.md`](borrowed-returns-plan-2026-10-20.md)). Its
  decision R1, "the borrow set is inferred and displayed, not written", was the user's
  to strike, and D2 strikes it.

## 1. Summary

| # | Change | Decision | Breaking | Package |
| --- | --- | --- | --- | --- |
| 1 | Every ownership refusal carries a rule id; prototype refusals become rules, lifted limits, internal errors or deletions | D4 | No, except where a lift accepts more | O1, O5 |
| 2 | Core owns the move and borrow rules; the front-end copies retire | D1 | No (it may accept more) | O2 |
| 3 | A borrowed result is declared in the signature: `-> Json from doc` | D2 | Yes, `mylang fix` migrates | O3 |
| 4 | `own` marks every move of a named binding; a binding without `own` borrows | D3 | Yes, `mylang fix` migrates | O4 |
| 5 | A living rules reference with an accepted and a refused example per rule, run by `test-docs` | all | No | O5 |

Estimate: 70 to 110 hours of Codex time across O0 to O5.

## 2. The rules after this plan

The draft rules stand except for these changes. O5 writes the final text.

- **B2 Moves (D3).** A managed value held by a named binding moves only where `own`
  says so: `mut ys = own xs`, `const ys = own xs`, `xs = own ys`, `r.items = own xs`,
  `rows[i] = own row`, `d[k] = own v`, `Row(items=own xs)`, `Some(own xs)`,
  `[own a, own b]` and `f(own x)`. `return x` needs no marker, and `return own x` is
  refused with the certain fix that deletes `own`. A fresh value (a call, a literal,
  `copy(...)`, an operator result) never takes `own`, and neither does a scalar.
- **B8 No partial moves (D4 rows 9, 27).** A field leaves a record only by consuming
  the record: `own r.f` hands the field on, makes `r` unavailable, and destroys `r`'s
  other fields at that point. This is today's carrier rule without its sibling and
  position restrictions. A record that stays usable gives up a field only by `copy` or
  by assigning the field a new value. Lifting the straight-line restriction (row 27)
  needs Core to place a conditional consumption. If that does not fit within §10's
  bound, keep the restriction under Z3 and log it.
- **B9 `const` borrows (D3).** `const x = place` borrows read-only for every place,
  including a bare local or `own` parameter. The borrow lasts until `x`'s last use in
  its block. Storing, returning, moving or passing `x` as `mut` or `own` is refused,
  with the repairs `const x = own y` (when `y` is a bare binding) and `copy(...)`.
- **R3, R4, V4 Borrowed results (D2).** A function returns a borrow exactly when its
  signature says `from`. The names are plain or `mut` parameters of managed type, and
  there may be any number of them (lifting rows 6 to 8). Callers read the signature,
  never the body. The function's every return must be a place of the named parameters,
  wrapped or not in `Some` or a `fails` success. A text, bytes or list slice of a named
  parameter is a view return (row 24 and the borrowed-returns plan's R7).
- **R5 One kind of return.** Unchanged in meaning: a `from` function that returns a new
  value on some path is `E_BORROW_MIXED`.
- **M5 Disjoint arguments (D1).** Core's place-path rule is the only overlap rule.
- **Z1 (rows 10, 11).** Lifted: the lowering binds argument-evaluation temporaries
  itself. Arguments are evaluated left to right, and that order becomes a stated rule
  in O5's reference.
- **Z2 (row 25).** Gone: with `mut` and `from` declared, the summaries `origins.zig`
  needs come from signatures, so no whole-program fixed point and no budget remain.
- **X2 (row 26).** Lifted only if dictionary element exchange is on `main` when O5
  starts; otherwise logged and left as a limit.

## 3. Packages

### O0. Start: census, harnesses and coverage (no behaviour change)

1. Copy §2 and the rules doc's prototype table into `status.md` as the checklist.
2. **Census.** Count, per corpus, the sites each migration will touch. The corpora are
   `tests/`, `test/fixtures`, `examples`, `src/stdlib`, `bench`, `benchmarks`,
   `selfhost/components` and the fenced examples in `docs/`. Also count, read-only on
   scratch copies, `~/ai/canopy/selka-projects` and the EDA port tree named in
   `docs/audits/eda-port-status-2026-10-23.md`. Count:
   - functions whose inferred borrow set or view source is non-empty (D2's `from`
     sites);
   - moves of named bindings outside call positions (D3's `own` sites);
   - `const x = y` where `y` is a bare local or `own` parameter and `x` is later
     stored, returned or moved (D3's `const ... = own` sites);
   - field moves under the carrier rule (B8).
   Put the scripts in `experiments/ownership-rules-20261024/census/` and the data in
   the evidence archive.
3. **Layer harness (for O2).** Add a developer switch that turns the front-end copies
   of B3, B5, B6 and M5 into reports instead of refusals. Then run Core on every
   corpus above and list each program where the two layers disagree.
4. **Coverage.** Show whether prototype rows 1 to 5 and the 8 codes with no test can
   fire, with a counter, a build-time probe or the coverage command. Record the result.

Lands when: `status.md` has the counts, the harness lists disagreements, and the
coverage result is recorded. No compiler behaviour changes.

### O1. Rule ids and the prototype refusals that need no new syntax (D4)

1. **Rule ids.** Each ownership refusal carries the id of the rule it enforces.
   - `diagnostic-v1` gains an optional `rule` field. It is additive, and existing
     consumers are unaffected.
   - `mylang reference --query CODE` lists the code's rules.
   - The terminal form names the rule once, in a short note.
   - A Zig test fails when an ownership refusal site sets no rule id.
2. **Deletions.**
   - Rows 1 to 5 and the typed-view machinery behind them: the `TextView` and
     `ByteView` builtins and `isBorrowedView` paths, if O0 shows them unreachable.
     `E_BORROW_VIEWS_REMOVED` keeps refusing the spellings.
   - Row 13.
   - Row 19: `.view()` becomes a retired spelling refused in the front end.
   - `E_ZERO_RC_VIEW_SIGNATURE` and `E_ZERO_RC_VIEW_UNSUPPORTED` retire with these
     rows.
3. **Recoded rules.** Rows 12, 14, 15, 18, 20, 22 and 23 keep their meaning under rule
   codes. Rename `E_ZERO_RC_RESOURCE_ESCAPE` to `E_RESOURCE_ESCAPE` and
   `E_ZERO_RC_RESOURCE_ORIGIN` to `E_RESOURCE_ORIGIN`. `E_ZERO_RC_UNSUPPORTED` retires
   once its last site moves.
4. **Internal errors.** Rows 16, 17 and 21 become compiler-defect errors, the way
   `E_INTERNAL_OPERANDS` is one, with a test only where a crafted typed program can
   reach them.
5. **Stale text.** Fix gap 12's three sentences.

Lands when: OR1 holds for the codes that exist after O1, and complete verification
passes.

### O2. One layer per rule (D1)

1. Assign each rule to a layer as §8's D1 table says.
2. Make Core see every generic instance. If `single_owner.zig` does not already check
   each specialization, it must; this is the premise of retiring `generic_bodies.zig`'s
   copies.
3. Resolve every disagreement from the O0 harness:
   - If Core misses a case the front end caught, fix Core and add a test.
   - If the front end refused a sound program, accept it, log the program in
     `DECISIONS.md` and add an acceptance test.
4. Retire the move-only paths of `E_OWNED_CONSUMED`, `E_OWNED_LOOP` and `E_OWNED_PATH`
   in `sema.zig`, `sema_calls.zig` and `generic_bodies.zig`. The Result paths
   (`E_RESULT_*`) stay.
5. Retire `E_MUTATION_OVERLAP` and the overlap checker in `origins.zig`.
6. Retire the duplicate B1, B3, B5 and B6 checks in `generic_bodies.zig`; it keeps L1
   and typing.

Lands when: OR2 holds and complete verification passes.

### O3. Borrowed results in the signature (D2)

1. **Syntax.** `-> T from a, b`, after the return type and before `fails`, as in
   `-> Json? from doc fails ParseError`. A function with no value (`fails E` only) has
   no `from`. `from` stays a contextual word, as it is in `from x import y`.
   - Add it to the parser, AST, formatter, interface files, `list-interfaces`,
     `context`, `api-diff`, navigation and the incremental interface key (§8 Q5).
   - A new `features.json` slug with a runnable doc example.
2. **Checking.**
   - Core reads the borrow set from the signature for R3, R4 and V4.
   - A return that is a place of a parameter the signature does not name is a new
     code, `E_BORROW_UNDECLARED`. Its certain fix adds the name to `from`, which is the
     migration.
   - A `from` name that is not a plain or `mut` managed parameter is a new code,
     `E_BORROW_SOURCE`.
   - Rows 6 to 8 lift: Core keeps every named owner alive for a `const` binding or a
     read in place.
3. **Views.** `inferred.view_source` retires; a slice return is a view exactly when
   `from` names its source. Text, bytes and list slices are covered (row 24).
   `E_VIEW_FUNCTION_VALUE` covers every `from` function.
4. **No body facts in interfaces.**
   - `api_diff.zig` stops checking bodies to learn borrow sets.
   - The incremental `public-borrow=` key is computed from the signature.
   - `origins.zig` builds its summaries from declared `mut` positions and `from`
     sets, with no whole-program fixed point. `E_MUTATION_LIMIT` retires (row 25).
   - `borrow_set.zig` survives only as the migration fix's source. Delete it after the
     migration or keep it for the fix alone, and log the choice.
5. **Standard library.** Write `from` on every accessor that returns a borrow:
   `json.get`, `json.at`, `json.as_str`, `dicts.get` (`from mapping, fallback`), and
   any other function the census finds. Update their guides.
6. **Migration.**
   - A `FIX-MIGRATION-1`-style corpus under `test/fixtures/fix-migration/` with its
     test in `test/fix_cli_test.zig`.
   - Generated `migration (generated): …` commits for the repository corpora,
     regenerated after every merge of `main`.

Lands when: OR3 holds and complete verification passes.

### O4. `own` on every move (D3)

1. **The marker rule of §2 B2 and B9.**
   - One code, `E_OWN_MARKER`, covers a missing or misplaced `own` at every position;
     `E_OWN_ARGUMENT` retires.
   - The fix is certain wherever today's checker records a move: insert `own`. For a
     `const` that is later stored, returned or moved, insert `own` in its initializer.
2. **Generic instances** follow today's rule for `own` arguments
   (`own_parameters.zig`, `mentionsTypeParameter`): no edit is offered where the
   template is shared.
3. **B8's carrier rule** (§2) with rows 9 and 27.
4. **Migration.** As in O3: a fix-migration corpus with its test, and generated
   commits for every repository corpus.
5. **Docs.** Update `CLAUDE.md`'s "Where the language differs from Python" section,
   `docs/value-semantics.md`, `docs/managed-memory.md`, `docs/functions.md`,
   `docs/python-syntax.md` and every page whose fenced examples move a binding.
   `zig build test-docs` finds them.

Lands when: OR4 holds and complete verification passes.

### O5. Lifts, the living reference and the report

1. **Lifts.** Rows 10 and 11 (Z1) and, if its premise holds, row 26. Retire
   `E_SINGLE_OWNER_UNSUPPORTED`.
2. **The living reference.** `docs/ownership-rules.md` replaces the draft as the
   language-facing reference.
   - Every rule has its final text, the codes that enforce it, its layer, and runnable
     examples: one accepted (`# doc: expect …`) and, for a rule with a refusal, one
     refused (`# doc: expect-error CODE`).
   - The code map and the evaluation-order rule are included.
   - It is linked from `docs/README.md` and the memory guide topic.
   - The draft under `docs/design/` gets a one-line pointer to it and is otherwise
     left as history.
3. **Gap 10.** Show which shapes still reach `R_LIST_ITERATION_MUTATION` at run time.
   If none can, keep the trap and record the argument. Removing the trap is not in
   this plan.
4. **Gap 13.** Sort the `E_CORE_UNSUPPORTED` sites into ownership limits and other
   backend limits, and list them in the report. Fixing them is not in this plan.
5. **Report.** `REPORT.md`, as §10 says.

## 4. Order

O0, then O1, O2, O3, O4 and O5 in that order. Each package lands on `main` before the
next starts, by fast-forward after complete verification (§10). The order matters:
- O1 shrinks `single_owner.zig` before O2 moves rules into it.
- O2 makes Core the one place O3 and O4 change.
- O3 and O4 are separate breaking changes with separate fix migrations, so each
  migration commit can be regenerated alone.

## 5. Done criteria

| # | Criterion |
| --- | --- |
| OR1 | Every ownership refusal carries a rule id naming a rule in `docs/ownership-rules.md`, and a test enforces it. `mylang reference` and the reference doc's code map agree, which a test also checks. |
| OR2 | No rule is enforced in two layers. `E_OWNED_CONSUMED`, `E_OWNED_LOOP`, `E_OWNED_PATH` and `E_MUTATION_OVERLAP` are gone. Core checks every generic instance. `REPORT.md` lists every disagreement the O0 harness found and how it was resolved. |
| OR3 | Whether a result borrows is read only from signatures. `api-diff` and the interface keys use no body facts. `E_MUTATION_LIMIT` and `inferred.view_source` are gone. `from` has a feature slug, a doc example, formatter and interface support, and a fix-migration test. Rows 6 to 8, 24 and 25 are resolved. |
| OR4 | Every move of a named binding outside `return` is spelled `own`, and `const` always borrows. The fix-migration test passes, and the repository corpora are migrated by generated commits. |
| OR5 | All 27 prototype rows are resolved as accepted, or logged with the reason they could not be (rows 26 and 27 have stated fallbacks). |
| OR6 | Every rule in `docs/ownership-rules.md` has an accepted example, and every rule with a refusal has a refused example. Both run in `zig build test-docs`. |
| OR7 | Targets, measured with `scripts/build-slot.sh timing` and reported. Release run time of the parity suite and the Lox benchmarks within 2% of `main` at O0. `mylang check` time on the largest corpus no slower than at O0. A miss gets one profiled investigation within §10's bound; it is not a hard stop. |
| OR8 | Each landing passes complete verification, `fmt-check`, `doctest .` and `doc-coverage .`. Guardian is clean. No Python is added to `src/` or the install graph. |

## 6. Risks

- **The layer comparison finds Core gaps.** That is the comparison's purpose. Each gap
  is a Core fix with a test. If one needs more than §10's bound, it is a hard stop.
- **`own` noise.** D3 adds markers at stores and constructors. The census measures
  how many. The user chose explicitness; the count goes in the report, not into a
  narrower rule.
- **`const` borrowing a local changes when storage dies.** The value now dies at the
  owner's end instead of the borrower's. Programs that relied on the old move are
  exactly the ones the migration rewrites to `const ... = own`.
- **Generic accessors.** A `from` on a generic result whose instance is scalar is
  meaningless. Accept it and ignore it for that instance, as `own` is treated for
  generic parameters, and log the choice.
- **External code.** selka-projects and the EDA port need `mylang fix` after this
  lands. O0 and the report give the counts; migrating them is not in this plan.

## 7. Not in this plan

- A formal model, a proof, or a certificate checker for destruction (gap 11).
- Removing `R_LIST_ITERATION_MUTATION`.
- Fixing the non-ownership `E_CORE_UNSUPPORTED` sites.
- Renaming the `E_SINGLE_OWNER_*` codes.
- Migrating selka-projects or the EDA port.

## 8. Decisions

**The user's, 24 October:**
- **D1. One layer per rule:** Core owns the move and borrow rules. The front end keeps
  the spelling rules: markers, `class`/`Cell`, task scoping and Result obligations.

  | Layer | Rules |
  | --- | --- |
  | Front end | T1–T4, B1, M2, M3, M4 (`E_VALUE_TEMPORARY_WRITE`), R7 (`E_VALUE_BINDING_WRITE`), W2, W3, V6, X2 (the place's shape), K1–K3, L1, C2 |
  | Core | B2–B9, R1–R6, R7 (changes to the iterated collection), M1, M4 (writable owner), M5, M6, W1, W4, V1–V5, X1, X2 (the owner's mutability), P1–P5, C1, C3, Z1, Z3 |

- **D2. Borrow sets in signatures:** `-> Json from doc`. `mylang fix` inserts the clause
  from today's inferred set. This strikes the borrowed-returns plan's R1.
- **D3. `own` on every move:** a binding without `own` borrows, and returns stay
  unmarked. `mylang fix` inserts the markers.
- **D4. The prototype dispositions** in the rules doc: lift 8, make 8 into rules,
  delete 8, and turn 3 into internal errors.

**Recommended, accepted at launch unless struck:**
- **Q1.** `from` follows the return type and precedes `fails`.
- **Q2.** `from` names only plain or `mut` parameters of managed type. Order does not
  matter, and the formatter sorts the names by parameter position.
- **Q3.** `api-diff` treats adding a `from` clause or a name as breaking, and removing
  one as compatible.
- **Q4.** One marker code, `E_OWN_MARKER`; `E_OWN_ARGUMENT` retires.
- **Q5.** The interface key and interface files carry `from`; no interface fact comes
  from a body.
- **Q6.** Codes that retire are removed from `mylang reference`. The reference doc's
  history section names them and what replaced them.
- **Q7.** The final reference lives at `docs/ownership-rules.md`.

## 9. How it fits

- **Other runs.** Concurrency, performance and EDA-port branches may touch
  `single_owner.zig`, `sema.zig` or `origins.zig`. Merge `main` before every landing,
  regenerate the migration commits, and keep both sides' rows in shared tables in
  order.
- **The EDA port is paused.** Its lanes resume on a compiler with `from` and `own`
  moves, so the resume needs a `mylang fix` pass. The report gives the counts.
- **After this plan.** A small formal model of the rules (Lean or Coq) and a
  per-function ownership certificate checked by a small validator. Both build on OR1
  and OR6. Neither is in this run.

## 10. Operating rules and launch instruction for Codex

The language wave 2 plan's §10
([`language-wave2-plan-2026-10-19.md`](language-wave2-plan-2026-10-19.md)) applies, with
these changes:
- Decisions go in `experiments/ownership-rules-20261024/DECISIONS.md`. Progress goes in
  `status.md` and the finish in `REPORT.md`, in the same directory. Data goes to
  `~/ai/canopy/mylang-evidence-archive/experiments/ownership-rules-20261024/`.
- Work happens on `ownership-rules/integration` in the worktree
  `~/ai/canopy/mylang-ownership-rules`, branched from `main`. Land each package by
  `git -C ~/ai/canopy/mylang merge --ff-only ownership-rules/integration` after
  `python3 scripts/verify_cache.py --zig "$ZIG" --profile complete` passes, and only
  when the primary checkout lists no tracked change. Untracked files there belong to
  other sessions; leave them alone.
- `CLAUDE.md` may be edited only in its "Where the language differs from Python"
  section. `SPEC.md` is frozen.

**Hard stops.** Stop and ask only for:
1. a language change beyond D1 to D4 and §2, for example lifetime names, a move
   keyword other than `own`, or a refusal with no certain fix that is not logged as a
   hand migration;
2. a change to D1 to D4;
3. relaxing a gate on `main`, or OR1 to OR6 or OR8 (OR7 is a target);
4. a broken premise, for example:
   - Core cannot check every generic instance;
   - a standard library accessor's borrow cannot be written with `from`;
   - `own` at stores makes an idiom impossible without a run-time copy;
5. a failure that cannot be fixed within about 6 to 8 hours;
6. anything outside this plan's branch and worktree. Never touch pushes, `origin`,
   `claude/*`, another run's branch or worktree, selka-projects, the EDA port tree
   (read-only scratch copies are allowed), `../guardian-zig` or `SPEC.md`;
7. resources: free space on `/` under 25 GB, or the machine swapping.

**Finish** with `REPORT.md`, covering:
- OR1 to OR8 with their evidence;
- the final rule list, its layer table and code map;
- the O0 census and the layer-harness disagreements with their resolutions;
- every new, renamed and retired code;
- the migration counts per corpus and the external counts;
- the hand-migrated sites;
- the `E_CORE_UNSUPPORTED` sort;
- the decisions logged.

```text
You are implementing docs/audits/ownership-rules-plan-2026-10-24.md in ~/ai/canopy/mylang:
make Selka's ownership model one written rule set that the compiler implements exactly.
Every ownership refusal carries its rule id. Core owns the move and borrow rules and the
front-end copies retire. A borrowed result is declared in the signature (-> Json from
doc). Every move of a named binding is spelled own, and const always borrows. The 27
prototype refusals are resolved as the rules doc's table says. Read the plan fully, then
docs/design/ownership-rules-2026-10-24.md (the rules, code map, prototype table and
gaps), CLAUDE.md, docs/audits/borrowed-returns-plan-2026-10-20.md, docs/tooling/fix.md,
docs/managed-memory.md and docs/value-semantics.md. The rules doc's source is
https://claude.ai/artifact/Efx4k4nepPqwYWRcL8s2N6; if you cannot open it, the repository
copy is the same text. Create the worktree ~/ai/canopy/mylang-ownership-rules on a new
branch ownership-rules/integration from main and work only there. Start with package O0
(census, layer harness, coverage) and land the packages in the plan's order, each by
fast-forward after complete verification. Decide, log in
experiments/ownership-rules-20261024/DECISIONS.md, and continue; stop only for the hard
stops in §10. Keep status.md current, write a session handoff there when your context runs
low, and finish with REPORT.md.
```
