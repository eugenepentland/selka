# Borrowed results: functions that hand back a borrow (plan, 2026-10-20)

Status: written on 20 October 2026 against `main` at `d68bfb6d63`. Codex implements
this plan.
- R1 and R3 (§9) change what a program may write, so they are the user's decisions.
  The plan recommends them, and they are taken as accepted at launch unless the
  launch text strikes them. The other decisions are recommendations, also accepted
  at launch.
- This plan takes over three items of the
  [performance feedback plan](performance-feedback-plan-2026-10-20.md): its B7 (a
  borrowed `const`, P4 there), its B8 (copy diagnostics) and `W_NEEDLESS_COPY` case
  (iii). That plan's amendment of 20 October says so. All three change the ownership
  checker, which this plan owns once wave 2's stage 4 has landed.
- The measurements in §1 are reproducible from
  [`experiments/borrowed-returns-20261020/planning/`](../../experiments/borrowed-returns-20261020/planning/)
  and from the performance feedback plan's planning directory.

The language makes every copy explicit, but it also forces copies that nothing needs.
A function cannot hand back a borrow into its argument, so every accessor copies what
it returns. That includes the standard library's own accessors, which wave 2 is
making the one home for each operation. This plan lets a function return a borrow
whenever every return is a place inside its parameters, with the same checks a `for`
loop variable already gets.

## 1. What the measurement found

- **The standard library's accessors copy.**
  - `dicts.find` makes 21 allocations per lookup of a 20-string list: the list and
    each string.
  - `pool.get` makes 10 per lookup of a record with eight strings.
  - `lists.last` copies the same way.
  - Each one copies because it has to: `return Some(mapping[key].copy())`.
  - The spellings they replace borrow for free: `d.get(k, x)` and
    `if k in d: d[k]` (`planning/dict_index_borrow.my`).
- **Agent code pays the same tax.** In three selka-projects, 74 of the 136 copies the
  checker requires are in `return` statements. 29 of them return a value rather
  than construct a record:
  - About 20 return a place inside a parameter: the parameter itself (about 10), a
    field, element or dictionary value (3), or a match payload (7, all in
    kicad-convert's `as_atom`, `as_text` and `text_or` accessors). This plan
    removes those.
  - A few, such as markdown's `escape_html`, return the parameter on one path and a
    new value on another. Their copy stays, now visible (R3).
  - The rest return part of an owned local, which needs a move, not a borrow.

  The other 45 construct a record that stores a slice of the input, such as an AST
  atom holding text from the parse buffer. They need `own` parameters or views
  inside records, which are not in this plan (§8).
- **A return that is a borrow on one path and new on another copies on every call.**
  The markdown converter's `line_at` returns its input slice unless the line holds a
  NUL. It is the converter's largest allocation site: 92,000 copies for 260 KB of
  input. The copy is invisible in the source.
- **Only `str` can return a view today.** `sema.zig` infers `view_return_source` when:
  - the result type is `str`;
  - the function has exactly one managed read-only parameter;
  - every return is that parameter, a slice of it, or a view binding rooted in it.

  Everything else falls outside that rule:
  - two borrowable parameters are refused (`planning/two_params.my`: "a returned
    slice must borrow this function's single borrowable parameter");
  - `return node.label` is refused as "outside this prototype"
    (`planning/field_return.my`);
  - a returned `bytes` slice is an owned copy (performance feedback D7);
  - a returned list slice is refused.
- **The call-site rules already exist, for that one case.** A `str` view result is
  checked like a view at the call:
  - changing the source while the result is live is refused, with the copy repair
    (`planning/tmp_arg.my`);
  - a temporary argument stays alive without a copy: `const a = head(make(i))`
    makes one allocation per iteration and no copy (`planning/tmp_only.my`);
  - passing such a function as a value works (`planning/fnvalue.my`).
- **The signature already has a slot for this.** `typed.ReturnOrigin` (`fresh`,
  `params([...])`, `unknown`) is described as a "sound upper bound on the inputs a
  returned value may alias". Built-ins already return a borrow of two roots:
  `borrow_selection.zig` covers `d.get(k, default)`.

## 2. The rule

```text
func label_of(node: Node) -> str:
    return node.label                  # borrows node: no copy

func find_def(refs: Refs, key: str) -> LinkDef?:
    if key in refs.defs:
        return Some(refs.defs[key])    # borrows refs
    return None

func text_or(node: Node, fallback: bytes) -> bytes:
    match node:
        case ast.Node.atom(text=text):
            return text                # a part of node
        case _:
            return fallback            # so the result borrows node and fallback

const label = label_of(tree)           # label borrows tree until its last use
tree.label = "x"                       # refused while label is used later:
out.print(label)                       #   copy(label) keeps an independent value
```

1. **A result borrows when every return yields a place inside the parameters.**
   - The places are:
     - a parameter;
     - a field, element or dictionary value of one;
     - a match payload of one;
     - a slice of any of these;
     - a call result that itself borrows only these places;
     - a binding holding any of these.
   - A return may also wrap such a place: `Some(place)`, or the success value of a
     `fails` function.
   - A return with no managed storage is compatible with a borrowed result: `None`,
     a literal, or a constant.
   - The set of parameters the returns come from is the function's **borrow set**.
   - The parameters may be plain or `mut`. A result that borrows a `mut` parameter
     is read-only.
2. **A borrowed result is used like a `for` loop variable.** The caller may:
   - read it, print it and compare it;
   - pass it to read-only parameters;
   - bind it with `const`;
   - return it, when what it borrows is the caller's own parameters or places inside
     them; the caller's result then borrows those parameters in turn. A borrow of
     the caller's own local cannot be returned.

   The caller may not, without `copy(…)` (that copy is the certain repair):
   - store it;
   - move it;
   - pass it `mut` or `own`.

   While the result is live, the owners of the borrowed arguments cannot be changed,
   moved or replaced. That is `E_SINGLE_OWNER_OVERLAP`, the check an iteration borrow
   already gets.
3. **A temporary argument lives as long as the borrowed result,** as a `str` view
   result's does today, without a copy.
4. **A borrow on one path and a new value on another is refused** (R3), with a new
   code. The certain repair copies the borrowed returns, so the copy every call
   already paid is now written in the source, and the author can restructure.
   `None`, literals and constants are not new values for this rule.
5. **Nothing new is written in signatures** (R1).
   - The borrow set is inferred, then displayed by `mylang list-interfaces`, the
     `.api` files, `mylang docs` and every diagnostic that names it.
   - A change to a public function's borrow set is an API change that `api-diff`
     reports as breaking.
6. **Values with no managed storage stay values.** A result whose type is a scalar,
   or a record of scalars, is an ordinary value with no borrow. That includes a
   generic result instantiated that way, as in `dicts.find` on `dict[str, int]`.

Not covered (§8):
- a borrow stored inside a record, list, dictionary or union;
- a mutable borrow (`entry`-style accessors);
- moving a field out of a local that is dead afterwards (FR-107).

## 3. Design

### 3.0 R0: census, spike and matrix (starts now)

R0 changes no compiler code on `main`.
- **Return-shape census** over the checked corpus, `selfhost/` and selka-projects
  (read with the pinned compiler; never through `tools/mylang`).
  - Count every `return` whose value is a place inside the parameters, with or
    without a copy.
  - Count every function whose returns mix a borrow with a new value, including the
    `str` view-or-new returns that today are silently copied.
  - Count every standard-library function that copies a parameter's part in its
    return.
  - The census sizes R3's migration and R5's work. Mixed returns in
    `selfhost/components` need the seed rule of §7.
- **A spike, on its own branch and never landed.**
  - Return a borrowed pointer to a dictionary value, and an `Option` of one, through
    Core.
  - Check it under `--verify-facts` and `MYL_CORE_LEAKCHECK=1`.
  - Record the Core representation chosen (§3.4) and anything it shows the design
    got wrong.
- **The matrix generator**, in the pattern of wave 3's view-shape matrix. It crosses:
  - owners: a `str`, `bytes`, list, dictionary, record, union or option parameter,
    each plain or `mut`;
  - return shapes: the whole value, a field, an element, a dictionary value, a match
    payload, a slice, `Some(place)`, a `fails` success, a literal, `None`, a new
    value, a mix of these, and two or three parameters;
  - uses: bind with `const`, use inline, store, return onward, pass plain, `mut` or
    `own`, change the source while the result is live, a temporary argument, a loop,
    a branch;
  - modes: optimized debug, release, `--verify-facts`, and the leak check.

  Each cell expects acceptance or a named refusal. Commit the generator with the
  expected table; most cells fail until R4.

### 3.1 R1: a borrowed `const` (the performance plan's B7)

Implement §3.7 of the performance feedback plan as written there:
- `const name = place` binds a read-only borrow when the function cannot move the
  place;
- the owner cannot change while the borrow is live;
- `mut` bindings and owned locals keep today's meaning;
- that plan's owners × places × uses × events matrix becomes part of R0's
  generator.

R2 to R4 build on the same machinery: a borrowed result bound with `const` is a
borrowed `const` whose place sits in the caller's arguments.

### 3.2 R2: inferring the borrow set

- **Inference.** Generalize `sema.zig`'s `view_return_source`, one parameter and
  `str` only, into a borrow set recorded in `typed.Signature.return_origin`
  (`params([...])`).
  - It applies to every managed result type, and to `Option` and `fails` success
    wrappers.
  - It applies to the place shapes of §2 rule 1.
  - `fresh` stays the owned case. A mixed function records which returns borrow,
    for R3's refusal and its repair.
- **Calls and recursion.** A call's result contributes its callee's borrow set,
  mapped through the arguments. Compute the sets in callee-first order, iterating to
  a fixpoint over each strongly connected component of the call graph.
- **Contracts.** Keep today's exclusion of functions with `@ensures`, and log
  whether lifting it is safe.
- **Interfaces.**
  - The borrow set is part of a function's interface digest. A body edit that
    changes it re-checks the dependents; one that does not change it keeps the
    interface cutoff.
  - `list-interfaces`, the `.api` files and `api-diff` show it.
  - Test both the cutoff and the invalidation.

### 3.3 R3: the checker at call sites and returns

- **Results.** A call result whose callee has a borrow set is a borrowed value with
  one root per borrowed argument.
  - Generalize the checker's single `root` to a root set, or represent the result as
    one borrow per root. Changing any root invalidates the result.
  - `borrow_selection.zig`'s two-owner results are the precedent.
  - A root that is a temporary is kept alive to the result's last use, as today.
- **Stores, moves and `mut`/`own` arguments** of a borrowed result are refused, with
  the copy repair on the expression.
- **Returning a borrowed result onward** adds the caller's matching parameters to
  the caller's own borrow set. The checker and R2's inference must agree on that
  set.
- **The mixed-return refusal** (R3). Its certain repair writes `copy(…)` on each
  borrowed return.
  - The corpus, the guides and selka-projects migrate through a generated commit,
    with a `FIX-MIGRATION-1`-style test.
  - `selfhost/components` follows §7.

### 3.4 R4: Core

- **Representation.**
  - A slice result of `str`, `bytes` or a list is a view (pointer and length).
    `str_view` exists; add or reuse the `bytes` and list views wave 3 introduced, so
    a `bytes` slice return is no longer a copy.
  - Any other borrowed result is a borrowed pointer to the value's storage, the way
    a read-only aggregate argument is passed today.
  - `Some(place)` is an option holding that pointer.
- **Ownership pass (`own.zig`).**
  - A borrowed result is never dropped.
  - Every source in its borrow set is kept alive until its last use. Today
    `own.zig` links a view result to its single `view_source`; generalize that to
    the set.
- **Verifier (`verify_ir.zig`).** Replace "a view result has a view source" with "a
  borrowed result has a non-empty borrow set whose sources outlive it".
- **Function values.** A function with a borrowed result passed as a value keeps
  today's adapter, which copies at the boundary. `cost --sites` reports that copy as
  kind `copy`.
- **Lowering helpers.** No pass may hold `&module.functions.items[i]` across a call
  that can declare a helper (performance feedback D7). Audit the passes this batch
  touches.

### 3.5 R5: the standard library and its guides

- **Return borrows.** Rewrite `dicts.find`, `dicts.setdefault`, `lists.last`,
  `pool.get`, and every other standard-library function R0's census lists.
  - Each must make no allocation per call for a managed value. Assert that with
    `testing.allocations`.
  - Record the instruction count before and after on the planning probes
    (`dicts_find_list.my`, `pool_get.my`). A rise is a failure.
- **Docs.** `docs/standard-library.md`'s "a managed value comes back as an
  independent copy" becomes the borrow rule, and `docs/managed-memory.md`,
  `docs/value-semantics.md` and `docs/performance.md` describe borrowed results.
- **Wave 2's migration.** It moves `d.get(k, x)` and the other dictionary methods to
  their homes. After this batch, those homes borrow as the methods did, so a
  migrated call costs no more than the method it replaced.

### 3.6 R6: copies that are no longer needed

- **`W_NEEDLESS_COPY` gains two cases:**
  - case (iii), the performance plan's: a `const` bound to a copy that is only read
    while its source does not change;
  - case (iv): a copy in a `return` that the borrowed-result rule makes unnecessary.
- **Case (iv) changes the function's interface,** so it fires only when every call
  site in the checked program still checks with a borrowed result. For a public
  function, the `.api` change is part of the repair, and `api-diff` shows it.
- **Generated repairs.** `mylang fix` applies both cases across the checked corpus,
  excluding `experiments/`, fixtures and `selfhost/`. Tests whose subject is copying
  get generated waivers with a reason.

### 3.7 R7: copy diagnostics name what they copy (the performance plan's B8)

Implement §3.8 of the performance feedback plan:
- each copy repair's message names what it copies and the copy-free alternative
  that applies at that site;
- the alternatives now include returning the borrow (this plan), binding with
  `const` (R1) and `own` (wave 2's stage 4);
- the repair itself stays the copy.

### 3.8 R8: selka-projects and the final measurement

- **selka-projects**, on a `borrowed-returns` branch:
  - apply `mylang fix`;
  - rerun the copy census;
  - check that `check.sh` is green;
  - bump `COMPILER`, and merge the way wave 2's batch P does.
- **Remeasure** the planning probes and the markdown converter with the
  performance plan's `--counters` profile.
  - After `mylang fix`, markdown's `line_at` carries its repair's written copy.
  - The report says whether restructuring it is worth a ledger item: return the
    slice always, and replace NULs where a line is used.
- **Then `REPORT.md`** (§10).

## 4. Order and batches

| Batch | Contents | Waits for | Lands when |
| --- | --- | --- | --- |
| R0 | §3.0: census, spike, matrix generator | — | evidence committed; the spike branch is never merged |
| R1 | §3.1: a borrowed `const` | wave 2's stage 4 (step 3 of its §4a) on `main` | the borrowed-`const` cells of the matrix pass; complete verification passes |
| R2 | §3.2: inference | R1 | the interface tests pass; complete verification passes |
| R3 | §3.3: call sites, returns, the mixed refusal and its migration | R2 | the checker cells pass; complete verification passes |
| R4 | §3.4: Core | R3 | the whole matrix passes in every mode; complete verification passes |
| R5 | §3.5: standard library and guides | R4, and wave 2's dictionary family (step 4 of its §4a) on `main` | zero allocations per accessor call; instructions down; complete verification passes |
| R6 | §3.6: `W_NEEDLESS_COPY` (iii) and (iv) and their repairs | R5 | zero remaining findings in the checked corpus; complete verification passes |
| R7 | §3.7: copy diagnostics | R6 | message tests pin each message; complete verification passes |
| R8 | §3.8: selka-projects, measurement, report | R7, and wave 2's batch P | every project green on the new pin; `REPORT.md` |

- **Wave 2's progress.** Learn what it has landed from `main`'s log and from
  `experiments/language-wave2-20261019/status.md` (read only).
- **Waiting.**
  - When the next batch waits for wave 2, run any later batch whose dependencies
    are met.
  - When every remaining batch waits, commit a "Waiting" section in `status.md`
    naming the wave 2 step, and stop. That is a pause, not a failure.
- **Size.** About 55 to 90 hours of work:
  - R0: 4–6 h;
  - R1: 10–16 h;
  - R2: 8–12 h;
  - R3: 10–16 h;
  - R4: 10–18 h;
  - R5: 4–8 h;
  - R6: 4–6 h;
  - R7: 3–4 h;
  - R8: 4–6 h.

## 5. Done criteria

| # | Criterion |
| --- | --- |
| G1 | The generated matrix passes in optimized debug, release, `--verify-facts` and the leak check, and every cell that expects a refusal names its code |
| G2 | Every program that checked before still checks, prints the same bytes and passes the same tests, except the mixed returns R3 refuses, which the generated migration repairs |
| G3 | `dicts.find`, `dicts.setdefault`, `lists.last` and `pool.get` make no allocation per call for a managed value (`testing.allocations`), and the planning probes run fewer instructions than before, recorded with the command and build mode |
| G4 | `const label = label_of(tree)`, `text_or(node, fallback)` and `find_def(refs, key)` from §2 check and run without a copy; changing `tree` while `label` is live is refused with the copy repair |
| G5 | A `bytes` slice return is a view: no copy in a counting build |
| G6 | The borrow set is in the interface digest, `list-interfaces`, the `.api` files and `api-diff`; a body edit that keeps the set keeps the cutoff, and one that changes it re-checks the dependents |
| G7 | After R6's repairs the checked corpus has no `W_NEEDLESS_COPY` finding, and the copy census reports how many return copies remain and why |
| G8 | No regression: the parity and runtime suites stay within their thresholds; the edit-loop latency stays within 5% of R0's; complete verification on an unchanged tree stays within 10% |
| G9 | selka-projects: `check.sh` green on the new pin, and the census before and after is in `REPORT.md` |
| G10 | Complete verification and formatting pass for each batch |

## 6. Risks

- **A hole here is a memory-safety bug.**
  - A borrowed pointer into a dictionary entry is valid only while the dictionary
    does not change. Its storage moves when the dictionary grows or rehashes.
  - The checker enforces that. The guards are the matrix, `--verify-facts`, the leak
    check and the spike.
  - Add an address-sanitizer run of the matrix if the toolchain offers one, and log
    whether it does.
- **Inference ties a function's interface to its body.** A body edit can change the
  borrow set and break a caller in another module. The digest, the displayed set
  and `api-diff` make that visible. The diagnostic names the callee and the
  parameter, so the repair is local.
- **The mixed-return refusal breaks code that checks today.** The generated
  migration and its `FIX-MIGRATION-1` test carry it, and R0's census sizes it before
  R3 starts.
- **Merging with wave 2.** Wave 2's stage 4 and its dictionary family touch the same
  checker and standard-library files.
  - This plan starts its checker work only after stage 4 lands, and its standard
    library work only after the dictionary family lands.
  - Merge `main` before every batch, and regenerate generated commits after every
    merge.
- **Gate time.** The matrix is generated. Keep its cells small, and check G8.

## 7. How it fits with the other work

- **Language wave 2** runs in `~/ai/canopy/mylang-wave2`. Its remaining order is
  its §4a: F57, the list family, stage 4, the remaining families, stage 3's patterns,
  then batch P. Never touch that worktree, its branch or its processes.
- **The performance feedback run** waits for wave 2 too. Its B7, B8 and
  `W_NEEDLESS_COPY` case (iii) now belong here, and its plan's amendment says so.
  Its B6 (the fast standard-library spellings) and B9 stay with it. B9 may merge
  selka-projects before or after R8; whichever comes second merges the other's
  branch first.
- **Self-hosting.**
  - Make no edits under `selfhost/` except the generated migration of the
    mixed-return refusal in `selfhost/components`.
  - Make that migration only if the pinned seed accepts the repaired spelling.
  - If it does not, keep the components' mixed returns legal for the seed's
    lifetime with a logged exception, and do not re-seed: re-seeding is wave 2's
    and the self-hosting plan's.
- **The checked-docs follow-up** runs beside wave 2. Merge `main` before every
  landing.

## 8. Not in this plan

- **Borrows inside records, lists, dictionaries and unions.** These are the 45
  constructor copies, such as an AST node that keeps a slice of the input. They need
  records that carry a borrow of their input and a checked lifetime for it: a larger
  design, and its own plan if the census shows the cost matters.
- **Mutable borrowed results** (an `entry` accessor that the caller appends
  through).
- **Field moves out of a dead local** (FR-107) and field-level borrows (FR-350).
- **Consuming loops** (`for own x in xs`).
- **A cheaper mixed return.** A result that is owned on some calls and borrowed on
  others needs a representation that records which, so it can be dropped only when
  owned. If R3's census shows such functions on hot paths, that is a later Core
  change; this plan makes their copy visible first.

## 9. Decisions

Taken as accepted at launch. R1 and R3 are the user's to strike.

1. **R1 (user). The borrow set is inferred and displayed, not written.**
   - This follows wave 3's inferred view returns and the accepted policy of 18
     September: infer, then display.
   - The alternative is a marker in the signature, such as `-> V? from mapping`.
     It is more to write and to migrate, and the checker already enforces every use.
2. **R2. The scope.**
   - Places reachable from plain and `mut` parameters, through fields, elements,
     dictionary values, match payloads and slices.
   - Wrapped in `Some` or a `fails` success, or returned onward from another
     borrowed call.
   - Any number of parameters, and recursion through a fixpoint.
3. **R3 (user). A borrow on one path and a new value on another is refused,** with a
   certain repair that writes the copy. Migrated by a generated commit.
4. **R4. Temporaries live as long as the borrowed result,** as `str` view results do
   today, with no copy.
5. **R5. Function values keep today's copying adapter,** which `cost --sites`
   reports.
6. **R6. This plan owns the ownership-checker work after wave 2's stage 4:** the
   performance plan's B7, B8 and case (iii).
7. **R7. `bytes` and list slice returns become views,** like `str`'s.
8. **R8. The standard library's accessors return borrows,** and its guides say so.
9. **R9.** §8 stays out of this run.

## 10. Operating rules and launch instruction for Codex

- **Autonomy.** Decide, log in `experiments/borrowed-returns-20261020/DECISIONS.md`
  (the question, the evidence, the choice and whether it can be reversed), and
  continue.
  - Commit at every step, with a progress section in `status.md`.
  - Investigate a gate failure for up to about 6 to 8 h.
  - Any batch that claims speed records `instructions:u` before and after
    (`taskset -c 2 perf stat -e instructions:u`, release build), and a rise is a
    failure even when the counters improve.
- **When your context runs low,** commit a "Session handoff" section in `status.md`
  and stop. That is a handoff, not a blocked run.
- **Hard stops.** Stop and ask only for:
  1. a language change beyond R1 to R9 and §2;
  2. a repair that changes a program's output;
  3. relaxing a gate on `main`, or any of G1 to G10;
  4. a broken premise, for example a borrow set that cannot be checked without
     lifetime annotations;
  5. touching another run's worktree, branch or processes, `../guardian-zig`, or
     selka-projects outside R0's reads and R8;
  6. a failure that cannot be fixed within the bound;
  7. free space on `/` under 25 GB, or the machine swapping.
- **Branches and landing.**
  - Work in the worktree `~/ai/canopy/mylang-borrowed-returns` on branch
    `borrowed-returns/integration`, created from `main`. The spike gets its own
    branch, never merged.
  - Land each batch by fast-forward from the primary checkout,
    `git -C ~/ai/canopy/mylang merge --ff-only borrowed-returns/integration`. Do it
    only after `python3 scripts/verify_cache.py --zig "$ZIG" --profile complete`
    passes, and only when `git -C ~/ai/canopy/mylang status --porcelain` lists no
    tracked change.
  - If `main` has moved, merge it, verify again, then fast-forward. Never push.
  - Commit only in your worktree. Stage named paths only; never `git add -A` or
    `git add .`.
  - Corpus migrations are generated commits (`migration (generated): …`),
    regenerated after every merge of `main`.
- **Files.**
  - `CLAUDE.md` may be edited only in "Where the language differs from Python".
  - `SPEC.md` is frozen.
  - `selfhost/` is limited to §7.
  - Untracked files in the primary checkout belong to other sessions; leave them
    alone.
- **Machine rules from `CLAUDE.md`.**
  - Run `source ~/.config/mylang/dev-env.sh` in the worktree.
  - Builds and focused tests go through `scripts/build-slot.sh`, and the lane check
    is `python3 scripts/patch_gate.py --parallel`. Never wrap `verify_cache.py` in a
    slot.
  - At most four agents build the compiler on this machine.
  - Caches, `TMPDIR` and install prefixes go under `~/.cache`, never `/tmp`.
  - A behavioural change under `src/` ships with a test change in the same diff.
    Every breaking change carries its `mylang fix` migration.
  - Keep committed evidence under 10 MB.
  - Never kill a process this run did not start.

**Finish** with `experiments/borrowed-returns-20261020/REPORT.md`. It covers:
- G1 to G10, with their evidence;
- the census before and after, for the corpus, the standard library and
  selka-projects;
- the instruction counts of the accessor probes;
- every new code, rule and repair, with its migration counts;
- the selka-projects pin, merge commit and `check.sh` results;
- the decisions logged.

```text
Implement docs/audits/borrowed-returns-plan-2026-10-20.md on main in
~/ai/canopy/mylang: functions whose every return is a place inside their parameters
return a borrow instead of a copy, with the borrow set inferred, displayed and
checked like a for-loop variable; a borrowed const; mixed borrow-or-new returns
refused with a copy repair; bytes and list slice returns as views; the standard
library's accessors (dicts.find, dicts.setdefault, lists.last, pool.get) returning
borrows; W_NEEDLESS_COPY cases (iii) and (iv); and copy diagnostics that name what
they copy. Read the plan fully, then CLAUDE.md, docs/managed-memory.md,
docs/value-semantics.md, docs/audits/performance-feedback-plan-2026-10-20.md (its
§3.7 and §3.8 are this plan's R1 and R7) and
experiments/perf-feedback-20261020/DECISIONS.md (D7). R1 to R9 are accepted.
Decide, log in experiments/borrowed-returns-20261020/DECISIONS.md, and continue;
stop only for the hard stops in section 10. Create the worktree
~/ai/canopy/mylang-borrowed-returns on branch borrowed-returns/integration from
main. Run R0 now. Run R1 to R4 after language wave 2's stage 4 (step 3 of its §4a)
has landed on main, R5 after its dictionary family, and R8 after its batch P. Wave 2
runs in ~/ai/canopy/mylang-wave2: never touch that worktree, its branch or its
processes; read its status.md to learn what has landed. If every remaining batch
waits for wave 2, commit a "Waiting" section in status.md naming the step and stop.
Every refusal carries its certain mylang fix repair and a FIX-MIGRATION-1-style
test; no repair may change a program's output. Any batch that claims speed records
instructions before and after. Land each batch on main by fast-forward from the
primary checkout after a green complete verification, merging main first. Commit
only in your worktree, stage named paths only (never git add -A), leave untracked
files in the primary checkout alone, and never push. Edit CLAUDE.md only in "Where
the language differs from Python"; do not touch SPEC.md, ../guardian-zig, any other
run's branch, or selfhost/ beyond section 7. When your context runs low, commit a
"Session handoff" in status.md and stop. Commit at every step with a progress
section in status.md, and finish with REPORT.md.
```
