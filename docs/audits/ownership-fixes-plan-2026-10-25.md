# Ownership rules: fixes from the post-landing review (plan, 2026-10-25)

The ownership rules run (`docs/audits/ownership-rules-plan-2026-10-24.md`, landed on
`main` at `f65a6f37a`) delivered its plan. A review on 25 October found no program the
checker accepts that runs unsoundly. It did find the defects below. Two need fixing
before anything builds on task groups. One makes `mylang fix` change a program's result.
This plan fixes all of them, plus one older checker gap the review found.

**Inputs.**
- The final reference `docs/ownership-rules.md` and registry `src/ownership_rules.zig`.
- The run's ledgers in `experiments/ownership-rules-20261024/`: `REPORT.md`,
  `DECISIONS.md`, `O2-DISAGREEMENTS.md`.
- The review's probe programs. Read them, do not edit them. They are under
  `/home/epentland/.cache/mylang/review-core/p/` (Core: `kt_*`, `fv*`, `e7*`, `s2b`,
  `s18`, runner `../r.sh`) and `/home/epentland/.cache/mylang/review-tooling/`. The
  short repros in §3 are enough on their own.
- The user's decision of 25 October, U1 (§6).

## 1. Summary

| # | Defect | Severity | Package |
| --- | --- | --- | --- |
| 1 | A `const` alias passed to `g.submit` no longer builds, since O4. Two tests that passed at O3 are now "unsupported", and "unsupported" does not fail the gate | Regression | F1 |
| 2 | Core does not hold an alias declared inside a task group until the group ends. `xs = [1]` while a task reads `xs` through the alias passes `check`; only defect 1's build refusal keeps it from running | Checker hole | F1 |
| 3 | A function with a `from` result passed to `g.submit` passes `check`, then fails the build with an internal error | Checker gap | F1 |
| 4 | A binding named `own` before `-` parses as the marker, and `mylang fix` deletes it: `own - 1` becomes `- 1`, and the result changes from 9 to −1 | Wrong fix | F2 |
| 5 | Uncalled generic functions are no longer checked for writability (B1): `values[0] = item` on a plain `T[]` parameter passes `check`. Retiring the duplicate checks in `generic_bodies.zig` removed it, as the earlier plan's O2 step 6 told the run to | Regression | F3 |
| 6 | `api-diff` calls removing a whole `from` clause compatible. A caller that returns the result under its own `from` then fails with `E_BORROW_MIXED`. The earlier plan's Q3 allowed this reading | Wrong verdict | F4 |
| 7 | Every existing v1 `api-diff` baseline reports all its declarations as breaking with nothing edited, because the interface hash changed | Tooling | F4 |
| 8 | `return x` needs no marker but `fail x` needs `own` (U1) | Inconsistency | F5 |
| 9 | Diagnostics: the overlapping-`mut` (M5) message lost its specific advice, and its test MUT-EXCLUSIVE-3 was deleted; other messages are stale or wrong; repairs are offered in the wrong order | Quality | F6 |
| 10 | `mylang fix` makes no edit inside a generic function even where the moved value's type does not depend on a type parameter | Migration gap | F6 |
| 11 | Small `from` gaps: a scalar result, duplicate names, `from` after `fails`, `from` in a function type | Quality | F6 |
| 12 | Older than the run: the checker ignores loans inside f-string pieces, so `f"{t[0]}{g(mut t)}"` passes `check` and fails the build | Checker gap | F6 |
| 13 | The earlier run's `REPORT.md` calls defect 1's unsupported tests limits "already present in O4"; they are new in O4 | Report accuracy | F7 |

Estimate: 25 to 45 hours of Codex time.

## 2. Packages

### F0. Start: failing tests first

1. Copy §1 into `status.md` as the checklist.
2. Turn every repro in §3 into a test that fails on `main` today, in the place
   CLAUDE.md's test rule says:
   - guest behaviour in `tests/lang`;
   - diagnostics and fixes in Zig tests;
   - CLI behaviour in `test/integration.zig` or `test/fix_cli_test.zig`.
   Commit them marked as expected failures only if the test framework supports that.
   Otherwise keep them on the branch and land each with its fix.
3. **Unsupported guard (Q5).** Add a checked-in list of guest tests expected to be
   unsupported, each entry with its reason. `test-lang` fails on an unsupported verdict
   that is not on the list. The list starts with the unsupported verdicts on `main`
   today, minus defect 1's two tests, which F1 must make pass.

Lands with F1.

### F1. Task groups (defects 1, 2, 3)

1. **Hold lent values until the group ends (defect 2).** A task's argument loan lasts
   until its group's `with` block ends. This covers a value lent directly and one lent
   through a `const` alias declared inside or outside the group: `const s = xs`,
   `const s = xs[0]`, `const s = r.g`, a dictionary value. Any move or write of the
   owner before the block ends is refused (Q1).
2. **Build the lent alias (defect 1).** `build_task.zig` (`passedOwner`, about lines
   94–98) finds the owner a `const` alias borrows and lends that storage, as it does
   for a direct place. The two tests now pass in debug, release and the leak-checked
   release run:
   - `tests/lang/parallel_groups.my::test_lent_borrowed_binding_is_read_after_the_join`
   - `::test_lent_bound_list_element_is_read_after_the_join`

   The advice in `src/sema_tasks.zig:104` and `:230` ("bind it first, as in
   `const item = xs[i]`") then holds again; check both messages against what builds.
3. **Order.** Step 1 lands before or with step 2, never after it. Building the alias
   without the group-long loan turns defect 2 into a use-after-free.
4. **Borrowing callees (defect 3).** A function whose signature has `from` cannot be
   the function `g.submit` runs. It is refused at `check` with `E_VIEW_FUNCTION_VALUE`
   (V4), as other function-value uses already are (`functionValue`, `single_owner.zig`
   about line 2704). `parallel.map` is already covered; add the submit case and a test
   for record, option and list results.
5. **Proof.** Each `kt_*` shape from the review is either refused at `check` with the
   lent-value rule, or accepted and run under the address sanitizer with no error. The
   ASAN mode is `MYLANG_CORE_SANITIZE=address` with `--max-memory=0`; size the data
   above 1 KiB so the runtime's small-block lists do not hide misuse, as the review did.

### F2. The `own` marker in expressions (defect 4)

1. `atOwnArgument` (`src/parser.zig`, about line 409) reads `own` as a marker only
   when the next token is an identifier, the start of a named place (Q2). After any
   other token, `own` is an ordinary name. That includes `-`, `!`, a literal, `[`, `(`,
   `{`, `if`, `match`, `True`, `False` and `None`.
2. A marker before a fresh value can no longer be written, so the "fresh value needs
   no `own`" refusal remains only where the value is an identifier-led expression, for
   example a call `own f(x)`.
3. Tests:
   - `const own = 10` then `own - 1`, `3 + own - 1` and `own - 2 == 8` check and run
     with the O0 results;
   - `mylang fix` makes no edit to them;
   - the existing contextual-`own` cases still pass.
4. **Fix safety.** A fix that deletes a marker must leave the program's parse unchanged
   apart from the marker. Add a unit test that applies each certain `own`-removal fix
   in the fix-migration corpus and compares the parse trees with the marker node
   removed.

### F3. Uncalled generic functions (defect 5)

1. Front-end rules apply to every generic function body, whether or not anything
   instantiates it (Q3). B1 (writability, `E_IMMUTABLE`) is the one that regressed:
   - a plain parameter, whatever its type parameter;
   - a `const`;
   - a loop variable;
   - an immutable match payload.
   Restore it in the front end, not in Core.
2. Core rules (B3 and the other move and borrow rules) stay per concrete instance, as
   decision O2-L3 recorded. State this in `docs/ownership-rules.md`'s "Checking layers"
   section: an uncalled generic function gets front-end rules only.
3. Tests:
   - restore the refusals that `src/effects_test.zig:980` and
     `src/generic_providers_test.zig:175` changed to acceptances, for the writability
     cases;
   - keep the move cases accepted and point them at the documented limit.

### F4. `api-diff` (defects 6, 7)

1. `src/api_diff_baseline.zig` (`sourceNarrowing`, about lines 143 and 171) changes:
   - Changing the sources from a non-empty list to `fresh` (the whole `from` removed)
     is **breaking**.
   - Narrowing to a non-empty subset stays compatible, adding a name stays breaking,
     and reordering stays neutral.
2. Update the test at `test/release_cli_test.zig:222` and `docs/tooling/api-diff.md`.
3. Add a test showing the caller breakage: a callee drops its `from`, and a caller that
   returns the result under its own `from` gets `E_BORROW_MIXED`.
4. **v1 baselines (defect 7).** A baseline recorded before declared sources is reported
   once, as a baseline that predates declared borrow sources, together with the command
   that re-records it. It is not reported as one breaking change per declaration. The
   test records a baseline with the O0 compiler's format, compares it with an unedited
   file, and checks the single message. Document the re-recording step.

### F5. `fail` like `return` (defect 8, decision U1)

1. A bare `fail name` transfers the value with no marker, as `return name` does.
   `fail own name` is refused with `E_OWN_MARKER` (B2), with a certain fix that deletes
   `own`. A field still needs `own`: `fail own r.f`, as `return own r.f`.
2. Update B2's text in `docs/ownership-rules.md` to name `fail` beside `return`, with
   an accepted and a refused example. Also update `CLAUDE.md`'s "Where the language
   differs from Python" section if it mentions returns.
3. **Migration.**
   - A fix-migration fixture and test beside FIX-MIGRATION-1.
   - A generated `migration (generated): …` commit that removes the `fail own name`
     markers the earlier migration added in the repository corpora.
   - Count the external `fail own` sites in selka-projects and the EDA port on scratch
     copies, and report the counts; do not migrate them.

### F6. Diagnostics, fixes and small gaps (defects 9 to 12)

1. **M5 message.** Overlapping `mut` arguments (`nested(mut a, mut a[0])`) name both
   arguments, with a related span on the other one. The message gives the write-back
   rewrite in today's syntax:
   - `mut part = copy(a[0])`;
   - pass `mut part`;
   - then `a[0] = own part`.

   It never suggests a bare `copy(value)` for a `mut` argument. Restore MUT-EXCLUSIVE-3
   in that form.
2. **Stale and wrong messages.**
   - `single_owner.zig:2414` says "outside this prototype". Reword it as rule B8: a
     field leaves a record only by consuming it.
   - `own xs[0].items` and `own pick(l).name` call the value "fresh". Name the real
     reason: an element cannot move out of its container (B7), or the value is a
     borrowed result (R3).
   - `return own b.items` from a `mut` parameter: say the parameter is borrowed (M1).
   - Delete the comments that still mention the retired "borrow set":
     `src/core/own.zig` about line 1003 and `src/core/single_owner.zig` about line 357.
3. **`E_BORROW_UNDECLARED` location.** Point at the first return whose lender the
   signature does not name (`single_owner.zig` about line 3612), not the first borrowed
   return.
4. **Repair order (Q7).** When a named move lacks `own` and the binding is read again
   later, offer `copy(name)`, not `own`. Offer `own` only when the move is the binding's
   last use. Test both, for a binding and for `take(b.items)` followed by a use of
   `b.name`.
5. **Fixes in generic functions (Q8).** `markerFix` and `rejectConstEscape`
   (`single_owner.zig` about lines 1653 and 2470) withhold every edit when the function
   has type arguments. Offer the edit when the moved value's type does not depend on a
   type parameter; the typed node's `type_dependent` flag says so. Test:
   - `mut order = gathered` inside `count[T]` with `gathered: int[]` gets `own`;
   - a `T`-typed move still gets no edit.

   Re-run the census command from the earlier run's O0 on the EDA stage-1 scratch copy
   and report how many hand-migration sites remain.
6. **`from` details (Q6).**
   - `-> int from a` on a non-generic scalar result is refused, with a fix that deletes
     the clause.
   - A duplicate name (`from b, a, a`) is refused, with a fix that removes the
     duplicate.
   - `-> T fails E from a` gets a message saying to write `from` before `fails`.
   - A function type written with `from` gets a message saying function types cannot
     declare borrowed results.
7. **f-string loans (defect 12).** Core treats each f-string piece like a call
   argument for loans. `f"{t[0]}{g(mut t)}"` is refused at `check` (M5 or R2), like the
   same overlap written with `+`. Test the five `e7*` shapes.

### F7. Report

1. Add an erratum at the top of `experiments/ownership-rules-20261024/REPORT.md`:
   - the two unsupported task tests are an O4 regression, fixed by F1;
   - the `api-diff` verdict for removing a whole `from` was wrong, fixed by F4;
   - B1 in uncalled generic functions was lost in O2, fixed by F3.
2. Write `experiments/ownership-fixes-20261025/REPORT.md`:
   - each defect, its fix, its tests and its commit;
   - the unsupported allowlist and its entries;
   - the migration counts from F5 and F6;
   - the decisions logged.
3. Keep it short: a table per package and the evidence links. The earlier report was
   hard to read at its length.

## 3. Repros

Run with the O5 compiler or a build of this branch. Each must behave as stated after
the fix.

```text
# defect 2: refused at check (today: check ok)
mut xs = big()                 # 1000 ints
with parallel.group() as g:
    const s = xs
    const t = g.submit(sum, s)
    xs = [1]
    print(out, t.result())

# defect 1: builds and runs (today: E_CORE_UNSUPPORTED "bytes parameter")
mut xs = big()
with parallel.group() as g:
    const s = xs
    const t = g.submit(sum, s)
    print(out, t.result())

# defect 3: refused at check with E_VIEW_FUNCTION_VALUE (today: internal error at build)
func pick(x: int[]) -> int[] from x:
    return x
...  g.submit(pick, v)

# defect 4: returns 9, and mylang fix makes no edit (today: E_OWN_MARKER, fix gives - 1)
const own = 10
const y = own - 1
return y

# defect 5: E_IMMUTABLE (today: check ok)
func touch[T](values: T[], item: T):
    values[0] = item

# defect 8: accepted; `fail own message` refused with a fix deleting own
func parse(text: str) -> int fails str:
    mut message = "bad: " + text
    if len(text) == 0:
        fail message
    return 1
```

Defect 6's caller breakage, defect 7's v1 baseline, and the F6 cases are described in
their packages.

## 4. Order

F0 and F1 first, landed together. Then F2, F3, F4, F5, F6 and F7, each landed by
fast-forward after complete verification. F5 and F6 both change `E_OWN_MARKER`
behaviour, so land F5's migration commit before F6's repair-order change.

## 5. Done criteria

| # | Criterion |
| --- | --- |
| FX1 | Every §3 repro and every F6 case has a test that failed before its fix and passes after it |
| FX2 | `test-lang` fails on an unsupported verdict missing from the checked-in list. Defect 1's two tests pass in debug, release and the leak-checked release run |
| FX3 | The review's `kt_*` shapes are refused at `check` or run clean under the address sanitizer. None passes `check` and then fails the build |
| FX4 | No certain fix changes a parse tree beyond its stated edit (F2 step 4) |
| FX5 | `docs/ownership-rules.md`, `src/ownership_rules.zig` and the reference contract tests agree after the K1 layer change, the `fail` text and the uncalled-generic note |
| FX6 | Each landing passes complete verification, `fmt-check`, `doctest .` and `doc-coverage .`, and Guardian is clean. No Python is added to `src/` or the install graph |
| FX7 | Rerun the earlier run's OR7 comparison if a change alters generated code outside task groups. The target is the same: within 2% of the O0 baseline. A miss gets one profiled investigation and is reported; it is not a hard stop |

## 6. Decisions

**The user's, 25 October:**
- **U1.** `fail name` transfers without a marker, like `return name`.

**Recommended, accepted at launch unless struck:**
- **Q1.** The lent-value conflict is checked in Core, under K1 with `E_TASK_LOAN`,
  whether the value is lent directly or through an alias. The front end keeps K1's
  argument-kind refusals (`mut`, resource, `Host`). Its own `E_TASK_LOAN` check
  retires, so one layer checks each predicate. The layer table lists K1 as split.
- **Q2.** `own` is a marker only before an identifier.
- **Q3.** Front-end rules check every generic body. Core rules check concrete
  instances. The reference says so.
- **Q4.** `api-diff`: sources to `fresh` is breaking; a non-empty subset is compatible.
- **Q5.** An unsupported guest test fails `test-lang` unless it is on a checked-in list
  with a reason.
- **Q6.** The `from` details are refusals with certain fixes, except the two syntax
  messages, which have no fix.
- **Q7.** A missing `own` is repaired with `copy` when the binding is read later, and
  with `own` otherwise.
- **Q8.** Fixes inside generic functions are offered when the moved value's type does
  not depend on a type parameter.

## 7. Not in this plan

- Rebuilding the primary checkout's `zig-out/bin/mylang`; the user does that.
- Pruning the 1.6 GB evidence archive of the earlier run.
- Migrating selka-projects or the EDA port.
- Core checking of uncalled generic functions.
- The formal model and the destruction certificate.

## 8. Operating rules and launch instruction for Codex

The earlier plan's §10 (`docs/audits/ownership-rules-plan-2026-10-24.md`) applies,
with these changes:
- Decisions go in `experiments/ownership-fixes-20261025/DECISIONS.md`, progress in
  `status.md` and the finish in `REPORT.md`, in that directory. Data goes to
  `~/ai/canopy/mylang-evidence-archive/experiments/ownership-fixes-20261025/`, kept to
  logs and receipts a reader needs. Do not archive source tarballs or full build
  trees.
- Reuse the merged, clean worktree `~/ai/canopy/mylang-ownership-rules`:
  `git switch -c ownership-fixes/integration main` there. Land by
  `git -C ~/ai/canopy/mylang merge --ff-only ownership-fixes/integration` after
  complete verification, only when the primary checkout lists no tracked change.
- The hard stops are the same, with D1 to D4 of the earlier plan and U1 as the
  decisions that may not change.

```text
You are implementing docs/audits/ownership-fixes-plan-2026-10-25.md in ~/ai/canopy/mylang:
fix the defects a review found after the ownership rules run landed. They are:
- task groups: a const alias lent to g.submit does not build, the group-long loan is
  missing for aliases, and a `from` function can be a submit callee;
- `own - 1` on a binding named own is misparsed and mis-fixed;
- writability checking of uncalled generic functions was lost;
- api-diff misjudges removing a `from` clause and v1 baselines;
- `fail x` must not need `own`, like `return x`;
- several diagnostics, fixes and small `from` gaps;
- f-string loans.
Read the plan fully, then docs/ownership-rules.md, CLAUDE.md, and in
experiments/ownership-rules-20261024/ the REPORT.md, DECISIONS.md and
O2-DISAGREEMENTS.md. The review's probe programs are under
/home/epentland/.cache/mylang/review-core/p/ and
/home/epentland/.cache/mylang/review-tooling/; read them, do not edit them. In the
merged worktree ~/ai/canopy/mylang-ownership-rules run
`git switch -c ownership-fixes/integration main` and work only there. Start with F0
(failing tests and the unsupported guard), land F0 with F1, then the other packages in
the plan's order, each by fast-forward after complete verification. Decide, log in
experiments/ownership-fixes-20261025/DECISIONS.md, and continue; stop only for the hard
stops. Keep status.md current, write a session handoff there when your context runs
low, and finish with a short REPORT.md.
```
