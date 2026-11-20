# Language wave 3 fixes: view regressions, one position unit, honest docs (plan, 2026-10-19)

Status: written on 19 October 2026 at the user's request, with the launch
instruction in §9. Written against `main` at `2352375fe7`. Codex implements it.
The decisions in §7 are the recommendations of the review, taken as accepted
when the user launches the run.

Source: a review of [language wave 3](language-wave3-plan-2026-10-19.md) and its
report (`experiments/language-wave3-20261019/REPORT.md`). The review re-ran the
complete verification on `main` (PASS) and found that it does not cover:
- five shapes that compiled before wave 3 and now fail;
- one silent build failure;
- search positions that use a different unit from slicing;
- an escape rule that is not uniform;
- guides that still describe the old model.

Every repro below was run on the install of `main`'s compiler
(`~/.cache/selka-projects/compilers/wave3-bb58ca0da6`, no `src/` change since). Each
was compared with the pre-wave-3 pin `~/.cache/selka-projects/compilers/23c63cf50a`.

## 1. Summary

**Stage A, regressions.** A program that compiled before wave 3 compiles again,
with the same output, unless a refusal carries a certain `mylang fix` repair. No
build ever exits non-zero without a message. A generated matrix of view shapes
guards the whole class, so a missing corpus shape cannot hide the next one.

**Stage B, consistency.** It makes four things uniform:
- the escape rule, for list slices too;
- module imports, for the scalar helpers too;
- source sites, for the new trap too;
- the guides, which describe the byte model.

**Stage C, one position unit.** `find`, `rfind`, `index` and `rindex` return byte
offsets, and ranged arguments are byte offsets, as in Go. The migration has wave 3's
two phases.

**Stage D, the projects.** The selka-projects migrations are carried forward, the
projects' `COMPILER` pin moves to the fixed compiler, and the `wave3` branch merges
into that repository's `main`.

## 2. The defects, with repros

### 2.1 Regressions (stage A)

**R1. A view-returning call merged at a phi emits invalid LLVM.**
- Check passes, then clang fails (`'%v8' defined with type '{ ptr, i64 }' but
  expected 'ptr'`) with exit 2. The old compiler prints `hell`.
- The same failure occurs in a loop (`mut best = ""; for w in words: best =
  head(w)`), and with a deferred `const` assigned `head(a)` in one branch and
  `head(b)` in the other.
- **Cause:** `src/core/view_materialize.zig` `admitted` returns `.phi => true` for
  every phi, while `verify_ir.textViewUse` admits a phi only when its type is
  `.str_view`. The builder also stores a `str_view` call result into a `str` slot
  without a copy. `verify_ir` runs only in Debug compilers (`verify_ir.zig:42`), so a
  ReleaseFast compiler passes the bad IR to clang.

```text
func head(t: str) -> str:
    return t[0:4]

func main(out: Stream) -> int:
    const a = "hello"
    mut h = "none"
    if len(a) > 3:
        h = head(a)
    out.print(h)
    return 0
```

**R2. Check passes, then build and run exit 1 with no message.** This happens when
the result of a view-returning call outlives a mutation of its source. The source
can be mutated:
- in a loop;
- through a `mut` call (`bump(mut s)`), including through a record (`const h =
  head(r.name); bump(mut r)`);
- under a branch, when the source is live afterwards;
- by a dictionary value replacement (`const h = head(d["k"]); d["k"] = grow(50)`).

The old compiler prints the value.
- **Cause:** `src/single_owner.zig` `origin`'s `.call` arm follows only view types.
  It never consults `signature.inferred.view_source`, so the checker does not know
  that `h` borrows `s`. Core's `own.zig` `dropOwned` then returns `error.Unsupported`
  ("a consuming use must be the last use"), and the refusal reporter in
  `pipeline.zig` prints nothing.

```text
func head(t: str) -> str:
    return t[0:4]

func main(out: Stream) -> int:
    mut s = "wxyz" + str(1)
    const h = head(s)
    for i in range(3):
        s += "abcdefgh"
    out.print(h)
    return 0
```

**R3. A deferred `const` initialized from a slice in only one branch is refused,
and `mylang fix` cannot repair it.**
- `const h: str`, then `h = s[0:2]` in one branch and `h = "zz"` in the other, gives
  `E_SLICE_ESCAPES: a slice view must borrow from a known local owner`.
- Slices of one immutable source in both branches (`h = s[0:2]` / `h = s[1:3]`) are
  refused as "invalidated by a ... branch".
- The list form is refused the same way.
- The old compiler accepts all three.
- **Causes:**
  - `sema.zig` `markViewBindings` marks the slot a view if any initialization is a
    slice.
  - `single_owner.zig` `checkStore` rejects a non-slice value with no fix (around
    lines 747–760).
  - `merge` (around line 1388) makes the slot unavailable when `view_definition`
    differs between branches.
- This contradicts D23 (views through a phi are allowed) and D29 (no new refusal).

**R4. A dead view blocks a later mutation of its source in a loop.**
- `mut s = "abc"; const k = s[1:3]; out.print(k)`, then `for i in range(3): s += "x"`
  gives `E_SINGLE_OWNER_LOOP: 'k' is moved inside a loop`. That is the wrong code
  and the wrong message, with no fix, although `k` is never read again.
- The old compiler prints `bc` then `abcxxx`.
- **Cause:** the slice-view store sets `.borrowed = false` (`single_owner.zig`, around
  line 758), and `loopBack` (around line 1393) treats an invalidated view as a lost
  owner without asking whether the view is still live.
- A live view invalidated in a loop gets the same wrong message:
  `const h = s[0:4]`, then `s += …` in a loop, then `out.print(h)`. It must be
  `E_SLICE_ESCAPES` with the `.copy()` repair.

**R5. A slice of a `match` payload returned from the arm is refused.**
- In a function whose single borrowable parameter is `sh`:
  `match sh: case Shape.named(name=name): const h = name[0:4]; return h` gives
  `E_SINGLE_OWNER_OVERLAP: 'h' borrows from 'sh'`.
- The old compiler accepts it. `mylang fix` repairs it with `.copy()`, but the copy
  should not be needed: a payload of the borrowable parameter is part of it, as a
  record field already is.

### 2.2 Inconsistencies (stage B)

**B1. List slices escape silently.**
- A list slice stored into a record (`R(xs=xs[0:2])`, including in a `return`), or
  appended to a list, is accepted and copied. This holds whether the slice is bound
  first (`const v = xs[0:2]; out_list.append(v)`) or written inline.
- The same stores of text and bytes slices are `E_SLICE_ESCAPES` with the `.copy()`
  repair.
- D43 and the report say the rule is uniform over text, bytes and lists. It is not.

**B2. The scalar helpers need no import.**
- `strings.char_count(s)` works without `import strings`.
- `strings.split(s)` without the import is `E_UNKNOWN_TYPE: type is not declared`,
  which does not name the missing import.

**B3. `R_TEXT_BOUNDARY` has no source site.**
- It prints `<runtime>:0:0` and `in <runtime>`.
- `R_LIST_BOUNDS` on the same shape prints the line and the function.

**B4. The guides describe the old model.**
- `docs/text.md` opens with "indexed by Unicode scalar value ... `len` counts scalar
  values and `text[0]` answers a one-scalar `str`". The same paragraph says "a slice
  copies its octets" and mentions the removed `managed_allocation` effect.
- `docs/text.md` "Slices are new strings" says a slice is a copy.
- `docs/text.md` "Indexing long text that is not ASCII" says `text[i]` turns a scalar
  position into an octet offset, and it recommends `for ch in text`.
- `docs/text.md` around line 254 says a list slice "is an independent copy".
- `docs/python-syntax.md:160-163` says "Indexing and length count Unicode scalar
  values" and "Strings also support slices and iteration".
- `mylang docs` ships these guides, and agents read them first. Doctest passes
  because only examples are executed, never prose.

### 2.3 Two units in one value (stage C)

`find`, `rfind`, `index` and `rindex` return scalar positions (D14), and ranged
arguments (`find(sub, start, end)`, `count(sub, start, end)`,
`startswith(prefix, start)`) take scalar positions. `len`, `s[i]` and `s[a:b]` are
bytes. Both are `int`, so nothing can see the mismatch:

```text
func main(out: Stream) -> int:
    const s = "λλb"
    const i = s.find("b")
    out.print(i, s[i:])
    return 0
```

This prints `2 λb`, where `b` is right. D14's own byte-offset recipe,
`len(text[0:found])`, traps `R_TEXT_BOUNDARY` on `"λb"`. Go, the model wave 3
follows, returns byte offsets from `strings.Index`.

The corpus has about 92 `.find(`, 13 `.rfind(`, 6 `.index(` and 2 `.rindex(` calls
outside `experiments/`. Some are on `bytes`, which are already bytes, and some
`.index(` calls are on lists.

### 2.4 Housekeeping (stage D)

- **selka-projects.** Its checkout was left on the local `wave3` branch (tip
  `69e749f`), while its `COMPILER` file still pins `23c63cf50a`, which cannot
  compile wave-3 sources. Anyone running those projects' tools now fails.
- **The checked-docs run** has landed its compiler work on `main`. Its D5 pilots wait
  for the selka-projects migration. Stage D finishes that migration, then hands D5 a
  `main` that holds it.

## 3. Design

### 3.1 Stage A: regressions

1. **R1, phi and merge.**
   - `view_materialize.admitted` mirrors `verify_ir.textViewUse` exactly: a phi is
     admitted only when its type is a view type.
   - A view value flowing into an owned slot is materialized (copied) at that store:
     a `mut` variable, a deferred `const` with any owned initialization, or a phi of
     owned type.
   - When every value reaching a merge is a view of a live source, the merge stays a
     view (wave 3's V5).
   - This applies to text, bytes and list views alike.
2. **R2, a call's view source.**
   - `single_owner.origin` follows `signature.inferred.view_source` for a call, so
     the checker knows the result borrows that argument.
   - From then on the existing invalidation rule applies to call results exactly as
     to slice bindings (X1): a move, mutation or replacement of the source while the
     result is live is `E_SLICE_ESCAPES`, with the `(…).copy()` repair on the call.
   - This turns straight-line code that compiles today, such as `const h = head(s);
     s += "x"; out.print(h)`, into a refusal with a certain fix. The caller currently
     copies the whole source before each such append, a hidden cost.
   - The corpus and the selka-projects branch migrate with `mylang fix` as generated
     commits.
3. **R3, mixed initialization.**
   - A deferred `const` (or a `mut`) is a view only when every initialization is a
     slice, or a view-returning call, of a source that stays valid until its last
     use.
   - Otherwise the binding is owned, and each slice initialization is materialized at
     its store. That is no refusal, and it matches the old value.
   - Slices of one immutable source in both branches stay a view through the phi.
4. **R4, liveness.** Invalidation refuses only a view that is used after the
   invalidating event. `loopBack` and every other invalidation site ask liveness
   first. A live view invalidated inside a loop reports `E_SLICE_ESCAPES` with the
   `.copy()` repair, never `E_SINGLE_OWNER_LOOP`.
5. **R5, payloads.** A `match` payload binding, or a field, of the single borrowable
   parameter counts as part of it for the one-parameter return rule, so a slice of it
   returns as a view.
6. **No silent failure.**
   - Every refusal that reaches the user carries a located diagnostic.
   - A Core `error.Unsupported` with no recorded refusal becomes `E_CORE_UNSUPPORTED`,
     naming the function, the operation and the source site, and a test forces one.
   - A driver-level test asserts that `check`, `build`, `run` and `test` never exit
     non-zero with empty standard error over the failing fixtures of the gate.
7. **The verifier in every compiler under `--verify-facts`.** `verify_ir` runs when a
   build asks for `--verify-facts`, whatever the compiler's own build mode. The
   gate's release run of `tests/lang` uses that flag, so a ReleaseFast compiler and a
   project's `release check` can then catch invalid IR before clang does.
8. **The view-shape matrix.** This is a generated, committed set of guest programs.
   It crosses:
   - **producers:** a direct slice, a view-returning call, a slice of a record field,
     a slice of a `match` payload, and a slice of a slice; each for text, bytes and
     lists;
   - **consumers:** a straight-line read, a phi after `if`/`else`, a loop-carried
     `mut`, a deferred `const`, a `return`, a store into a record, list or
     dictionary, and a `mut` argument;
   - **source events:** none, before the last use, after the last use, inside a loop,
     through a `mut` call, under a branch, and a move.

   For each cell:
   - **accepted:** it must print the pre-wave-3 copy-semantics value in debug and in
     release with `--verify-facts` and the leak check;
   - **refused:** it must carry a certain fix, after which the fixed program prints
     that value.

   The generator is a script under `tests/` (Python is fine there). A test fails when
   the committed set is stale. The accepted cells run under `mylang test` from
   `tests/lang/view_shapes/`, and the refused cells run from a Zig test beside
   `test/fix_wave3_text_test.zig`. Each repro of §2.1 is a named cell.

### 3.2 Stage B: consistency

1. **B1.** `E_SLICE_ESCAPES` covers list slices stored into a record field, a list
   element or literal, a dictionary key or value, or a returned value, under the
   one-parameter rule. The repair is the same `(…).copy()`. The corpus and the
   selka-projects branch migrate with `mylang fix`. Census first; log the count.
2. **B2.**
   - The `strings.char_*`, `strings.chars`, `strings.bytes` and `lists.stride`
     helpers require their module's import, like every other module function.
     `mylang fix` adds the missing `import` line, so the 709 corpus calls migrate
     mechanically.
   - A qualified call to a standard-library module that is not imported reports
     `E_MODULE_NOT_IMPORTED` (or the existing code that means this, if one exists),
     naming the module, with the `import` fix. It no longer reports `E_UNKNOWN_TYPE`.
3. **B3.** `R_TEXT_BOUNDARY` carries the same constant site record as the other
   emitted checks (kind, line, column, width, operation, function), so it prints the
   source position and the frames.
4. **B4.** Rewrite the stale passages of `docs/text.md` and `docs/python-syntax.md`
   for the byte model:
   - `len` is octets, `s[i]` is a byte, `s[a:b]` is a byte range and a view;
   - iteration goes through `strings.chars` or `strings.bytes`;
   - the scalar helpers and their cost;
   - after stage C, the position unit.

   Every factual claim in those paragraphs gets a `# doc: expect` example beside it,
   so the next drift fails `doctest`. Grep the other live guides (`docs/` minus the
   historical directories) for `scalar`, `copy`, `for ch in`, `TextView` and `.borrow`
   and fix what is stale.

### 3.3 Stage C: byte positions (two phases, as wave 3)

- **Phase 1.**
  - On `str`, `find`, `rfind`, `index` and `rindex`, and every ranged position
    argument of `find`, `rfind`, `index`, `rindex`, `count`, `startswith` and
    `endswith`, are refused with `E_TEXT_SCALAR_POSITION`.
  - The certain fix rewrites each one to a scalar helper with the same meaning:
    `strings.char_find`, `char_rfind`, `char_index`, `char_rindex`, and ranged forms
    of `char_count_of`, `char_startswith` and `char_endswith`, or the names D-logged
    by the run.
  - `bytes` methods are untouched: they are already bytes.
  - Unranged `count(sub)`, `startswith(prefix)` and `endswith(suffix)` are untouched:
    they carry no position.
  - The corpus migrates as a generated commit, and so does the selka-projects branch.
- **Phase 2.**
  - Once an audit query finds zero unmigrated sites, the refused forms return with
    byte meaning: results are byte offsets of the match start, and ranged arguments
    are byte offsets.
  - A ranged endpoint that cuts a scalar traps `R_TEXT_BOUNDARY`, like a slice.
  - `-1` still means "not found" for `find` and `rfind`.
  - The `strings.char_*` search helpers stay, for programs that want scalar
    positions.
- `docs/text.md` states the single rule: every position the `str` type takes or
  returns is a byte offset, and the `strings.char_*` helpers are the scalar spelling.

### 3.4 Stage D: the projects

In `~/ai/canopy/selka-projects`:
1. Carry the B and C migrations (`mylang fix`) forward on the `wave3` branch and run
   every project's `check.sh` with `SELKA_COMPILER_PREFIX` pointed at a ReleaseFast
   install of the final `main`.
2. Install that compiler under `~/.cache/selka-projects/compilers/<short sha>` and
   write it to `COMPILER`.
3. Merge `wave3` into `main`: a fast-forward when `main` is still `91cefd2`,
   otherwise a merge commit.
4. Leave the checkout on `main`.
5. Teach `http-bench` to take the compiler from `COMPILER` or `--selka-bin` and never
   reuse a stale binary silently, the friction the wave 3 report recorded.
6. Do not cut or edit `release-docs`: the checked-docs run owns D5, and it starts
   after this stage.

## 4. Order and batches

| Batch | Contents | Lands when |
| --- | --- | --- |
| A | §3.1 in full; the matrix; the generated corpus migration for X1 | the matrix is green and complete verification passes |
| B | §3.2; the generated migrations for B1 and B2 | complete verification passes |
| C1 | §3.3 phase 1 and its generated migration | complete verification passes |
| C2 | §3.3 phase 2 | the audit finds zero; complete verification passes |
| D | §3.4 | every project's `check.sh` is green on the new pin |

One building agent at a time is enough. The stages are sequential, and each is
about a day or less. Parallel lanes in their own worktrees are allowed when two
items share no file. If they are used, list them in `status.md`.

## 5. Gates and done criteria

| # | Criterion |
| --- | --- |
| H1 | Every repro of §2.1 to §2.3 is a named test and gives the specified result: the old value where §3 says accepted, a located refusal with its certain fix where §3 says refused |
| H2 | The view-shape matrix is green in debug and release, with `--verify-facts` and the leak check. Its generator is current |
| H3 | No command exits non-zero with empty standard error over the gate's failing fixtures; `E_CORE_UNSUPPORTED` is tested |
| H4 | Every new refusal (X1's call results, B1, B2, phase 1 of C) has its certain fix and a `FIX-MIGRATION-1`-style test. The corpus migrates only through generated commits (`migration (generated): …`). Hand edits are listed |
| H5 | Behaviour preserved: every existing test passes under its old name. kicad-convert's 989 oracle comparisons, markdown's 652 spec examples and `http-server`'s guest and concurrency tests pass on the new pin. FR-108's walk stays a view (well under 10 ms) |
| H6 | `docs/text.md` and `docs/python-syntax.md` describe only the byte model, each claim with a runnable example. `doctest .` and `doc-coverage .` pass |
| H7 | Complete verification and formatting pass for each batch, and the parity rows stay within their thresholds |

## 6. How it fits with the other work

- **Checked-docs run** (`docs-gate/*`). D1 to D4 are on `main`. Its D5 pilots wait.
  Do not start, edit or cut anything for it. When stage D lands, its D5 can branch
  `release-docs` from selka-projects' `main`, which then holds the migrated projects.
  Its own plan's §7 rule already allows that.
- **Self-hosting stage 1.** Its P0 lanes A, C and D share no file with this plan.
  Its lane P (Core performance) waits for batch A, because both edit `src/core/`.
  P1 (the lexer and parser over `bytes`) is unaffected by stage C, because `bytes`
  positions do not change.
- **D41, the release slice pass,** stays as it is. This plan deletes nothing.
- **Wave 2** (methods on built-ins) comes after this plan. Its fix migrations must
  cover the `strings.char_*` helpers this plan relies on.

## 7. Decisions

Recommended by the review and taken as accepted when the user launches the run.

1. **X1. A view-returning call's result follows the slice-binding rules.** An
   invalidating move, mutation or replacement of its source while the result is live
   is `E_SLICE_ESCAPES`, repaired with `(…).copy()`. The alternative, copying the
   whole source before the mutation as straight-line code does today, hides an O(n)
   cost and keeps two rules.
2. **X2. A mixed merge is owned.** A binding that is not a slice on every path is an
   owned value, and its slice initializations copy; an all-view merge stays a view.
   The alternative, refusing mixed merges with a fix, adds a refusal for no gain.
3. **X3. The escape rule covers lists** (B1), so text, bytes and lists behave alike.
4. **X4. The scalar helpers need their import** (B2), with the `import` fix and a
   diagnostic that names the missing module.
5. **X5. Every `str` position is a byte offset** (stage C), in two phases, with the
   `strings.char_*` search helpers as the scalar spelling. The alternative keeps D14:
   two units in one `int`, and silent wrong answers on non-ASCII text.
6. **X6. `--verify-facts` turns on the IR verifier** in every compiler.
7. **X7. Stage D bumps the selka-projects pin and merges `wave3` into its `main`.**
   The user owns that repository and asked for the fix run.

## 8. Risks

- **X1 adds refusals to code that compiles today.** Each has a certain fix, and the
  census goes in `DECISIONS.md`. If the corpus count exceeds 100 sites, log it and
  continue: the migration is generated.
- **Stage C's phase 2 changes meaning silently** for any site phase 1 missed. The
  audit query and phase 1's refusal of every scalar position form are the guard, as
  in wave 3.
- **Materializing at an owned merge (X2) copies** where a smarter analysis could
  borrow. That is the old cost, not a new one; the matrix keeps the shapes visible
  for a later optimisation.
- **The generic case.** A function returning a slice is judged per instantiation:
  `pick[T](t: str, x: T) -> str` is accepted for `T = int` and refused once called
  with `T = str`. That is out of scope here. Log it as a follow-on, because generic
  bodies should be judged once.

## 9. Operating rules and launch instruction for Codex

The default is **decide, log, continue**. Write every decision to
`experiments/language-wave3-fixes-20261019/DECISIONS.md`: the question, the
options, the evidence, the choice, and whether it can be reversed. Commit at every
step, with a progress section in `experiments/language-wave3-fixes-20261019/status.md`.
Investigate and fix a gate failure within the run, for up to about 6 to 8 h. Early
measurements are checkpoints; only the final ones bind.

**Hard stops.** Stop and ask only for:

1. **A language change beyond X1 to X7 and §3.** For example:
   - a different meaning for an operation;
   - a new surface spelling other than the helpers named or D-logged under §3.3;
   - a refusal with no certain fix.
2. **Relaxing a gate on `main`, or any of H1 to H7.**
3. **A broken premise.** For example, an accepted matrix cell whose pre-wave-3 value
   cannot be reproduced without a semantic change.
4. **A failure that cannot be fixed within the bound.**
5. **Anything outside this plan's branches.** The exceptions are selka-projects'
   `wave3`, `main` and `COMPILER` under §3.4. Never touch:
   - pushes and `origin`;
   - `claude/*`, `docs-gate/*`, `projects/*` and `selfhost/*` branches;
   - selka-projects' `release-docs`;
   - another run's worktree;
   - `../guardian-zig`.
6. **Resources:** free space on `/` under 25 GB, or the machine swapping.

**Forbidden files:** `selfhost/`, `bench/selfhost/`, `src/syntax_dump.zig`,
`docs/bootstrap-v1.md`, `CLAUDE.md` (propose text in `REPORT.md`) and `SPEC.md`
(frozen).

**Branches and landing.**
- Integration happens on `wave3-fixes/integration` in the worktree
  `~/ai/canopy/mylang-wave3-fixes`, branched from `main`.
- Land each batch of §4 by fast-forward from the primary checkout,
  `git -C ~/ai/canopy/mylang merge --ff-only wave3-fixes/integration`, after
  `python3 scripts/verify_cache.py --zig "$ZIG" --profile complete` passes. Do this
  only when `git -C ~/ai/canopy/mylang status --porcelain` lists no tracked change.
  An untracked file another session left there is not this run's and stays
  untouched.
- If `main` has moved, merge it, verify again, then fast-forward.
- Corpus migrations are generated commits, regenerated after every merge of `main`.

**Machine rules from `CLAUDE.md`.**
- **Environment:** run `source ~/.config/mylang/dev-env.sh` in every compiler tree.
- **Admission:** builds and focused tests go through `scripts/build-slot.sh build …`,
  and timing through `scripts/build-slot.sh timing …`. `verify_cache.py` owns its own
  admission.
- **The lane check:** `python3 scripts/patch_gate.py --parallel`.
- **Paths:** caches, `TMPDIR` and install prefixes go under `~/.cache/`, never `/tmp`.
- **Tests:** a behavioural change under `src/` ships with a test change in the same
  diff. Guest behaviour goes in `tests/lang/*.my` where possible. Fix migrations get a
  `FIX-MIGRATION-1`-style test. `SPEC.md` is frozen.
- **Evidence:** keep committed evidence under 10 MB.
- **Processes:** never kill a process this run did not start.

**Finish** with `experiments/language-wave3-fixes-20261019/REPORT.md`. It covers:
- H1 to H7 with their evidence;
- each repro's before and after;
- the matrix's size and cell counts (accepted and refused);
- every new code and fix, with its migration counts;
- stage C's audit result;
- the selka-projects pin, merge commit and `check.sh` results;
- the decisions logged.

```text
You are implementing docs/audits/language-wave3-fixes-plan-2026-10-19.md on main
in ~/ai/canopy/mylang: the fixes the review of language wave 3 found. Read the plan
fully, then CLAUDE.md, docs/audits/language-wave3-plan-2026-10-19.md and
experiments/language-wave3-20261019/REPORT.md and DECISIONS.md (D14, D23, D29, D41,
D43). Decide, log in experiments/language-wave3-fixes-20261019/DECISIONS.md, and
continue; stop only for the hard stops in section 9. Create the worktree
~/ai/canopy/mylang-wave3-fixes on branch wave3-fixes/integration from main. Run the
batches of section 4 in order: A (the five regressions R1 to R5, no silent exit,
the IR verifier under --verify-facts, and the generated view-shape matrix), B (list
slices in the escape rule, imports for the scalar helpers, the R_TEXT_BOUNDARY site,
the text guides), C1 and C2 (every str position becomes a byte offset, in two
phases), then D (selka-projects: carry the migrations on wave3, bump COMPILER to a
ReleaseFast install of the final main, merge wave3 into its main, leave the
checkout on main). Every new refusal carries its certain mylang fix repair and a
FIX-MIGRATION-1-style test; corpus migrations are generated commits. Land each batch
on main after a green complete verification, fast-forwarding only from the primary
checkout as section 9 says; leave untracked files there alone. Never push. Do not
touch selfhost/, ../guardian-zig, CLAUDE.md, SPEC.md, any docs-gate/* branch or
selka-projects' release-docs. Commit at every step with a progress section in
status.md. Finish with REPORT.md.
```
