# Performance feedback: no hidden costs, findings at the line, work you can test (plan, 2026-10-20)

Status: written on 20 October 2026 against `main` at `bd2783767b`. The user had
asked how the language and compiler could make slow code harder to write, or point at
it and say what to do instead. Codex implements this plan.
- P4, P6 and P7 (§9) change the language or the standard library's surface, so they
  are the user's decisions. The plan recommends them, and they are taken as accepted
  at launch unless the launch text strikes them.
- The other decisions are recommendations, also taken as accepted at launch.
- Every number in §1 can be reproduced from
  [`experiments/perf-feedback-20261020/planning/`](../../experiments/perf-feedback-20261020/planning/README.md).
- **Amendment, 20 October (night): B7, B8 and `W_NEEDLESS_COPY` case (iii) moved.**
  They now belong to the [borrowed results plan](borrowed-returns-plan-2026-10-20.md)
  (its R1, R7 and R6).
  - That plan owns every ownership-checker change after wave 2's stage 4, so two
    runs never edit `single_owner.zig` at once.
  - §3.7 and §3.8 below stay as their design, which that plan implements.
  - This run's remaining batches are B1 item 3, B6, B9 and B10. B9 merges
    selka-projects before or after that plan's R8; whichever comes second merges
    the other's branch first.
  - P4's decision stands; that plan carries it out.

An algorithm that does quadratic work on purpose is legal in any useful language, and
the compiler never sees input sizes. So "impossible" applies only to *hidden* costs.
The plan works at three levels:
1. **No hidden costs.** The short spelling must be free or refused. This is the rule
   of 13 October: "the short spelling must be the one with no hidden cost".
2. **Visible costs named at the line, with a repair,** through a channel agents act
   on.
3. **Work budgets that fail like tests,** counted, never timed.

## 1. What the measurement found

Probes ran on `main` at `f9a7513ed1` with release guest builds and `--counters`, at
n = 2,000 and 8,000. Times are single runs, read only as growth ratios.

| Spelling | Today | Cost |
| --- | --- | --- |
| `s = s + x` and `s += x` in a loop | appends in place | none extra |
| `xs + [x]` on lists | refused (`E_TEXT_OPERATOR`) | — |
| `xs = sorted(xs)`, `groups[k].append(v)`, `text[i]` | in place, no copy | none extra |
| `out.print(f"row {i}: value={i * 3}")` | the f-string becomes a list of copied pieces and a join | 6 allocations and 2 text copies per line. `out.print("row", i, …)` makes none |
| `lists.pop_at(mut queue, 0)` on a `str[]` | the standard library shifts by copying each element | 504,501 allocations to drain 1,000 strings. The native `queue.pop(0)` makes none per shift |
| `const ys = xs` of a parameter | refused; the repair wraps `xs` in `.copy()` | the copy survives optimization: 16 MB for 2,000 calls on an 8 KB list |
| `bag = with_item(bag, v)`, copying `bag.items` inside | accepted | quadratic: 16 MB copied at n = 2,000 and 256 MB at 8,000. The `mut` version copies nothing |
| `lists.contains` in a loop, `pop_at(q, 0)` as a queue, a sort every iteration | accepted, nothing reported | time ×5, ×8 and ×11 for 4× n. No lint, no `mylang cost` row and no counter shows it |

Five findings set this plan's order:

1. **The language forces copies, and its own repair teaches them.** In three
   selka-projects (kicad-convert, http-server, markdown), each of the 147 `.copy()`
   calls was deleted in turn and the module re-checked.
   - 11 could go.
   - 136 are required by the checker: 74 returns, 36 stores, appends and
     constructor arguments, and 26 bindings. About 20 of the bindings are read-only
     aliases such as `const path = args[1].copy()`.
   - `E_SINGLE_OWNER_BORROW` is the most frequent error in the agents' friction
     logs. Its `fix.edits` inserts the copy, even where a view (`xs[0:len(xs)]`)
     would be accepted and free.
2. **Two short spellings still hide a cost:** f-strings (6 allocations for two
   holes), and `lists.pop_at` and `lists.insert`, which copy every shifted element.
3. **The feedback channel is drowned.**
   - 1,510 agent `mylang lint` runs printed a median of 125 findings each.
   - A full project lint prints 327 to 521 findings, all report-only.
   - A 7-line program that imports `strings` gets 133 findings, every one about
     the standard library.
   - A new report-only rule would disappear in this.
4. **Agents did not write the textbook quadratics.** 27,000 lines of agent code
   contain no `lists.contains`, `index`, `remove`, `pop_at` or `insert`, and no list
   re-sorted as it grows. The one sort inside a loop (`selfhost/components/cache_plan/graph.my`)
   sorts a fresh list once per batch. Those projects are parsers and servers, so loop
   rules are cheap insurance, not the main lever.
5. **Opt-in promises go unused.** `@noalloc` already names the allocating line, but
   the agent projects hold no attribute at all. What changes agent output is
   defaults, warnings in `check`, gate refusals and failing tests.

Two defects turned up on the way:
- `const part = xs[1:3]` followed by `return Bag(items=part)` passes `check`, then
  the build fails with `E_CORE_INVALID_IR` (exit 2).
- `lists.insert` does not compile for a `str[]`.

## 2. Principles

- **No hidden cost.** Make the costly short spelling free (f-strings, list shifts)
  or refused. Never add a check-time error for a pattern whose cost depends on sizes
  the compiler cannot see.
- **Name a visible cost at its line.** When the repair is certain, ship it as a
  `fix` that `mylang fix` applies. When the finding is a heuristic, give a hint.
  Block only at `--gate`, and block heuristic findings only in code changed against
  a base, so old code never walls the gate.
- **Count work, never time it.** Steps, allocations and copies are deterministic
  for a compiler and build mode; wall time flakes.
- **Make cheap spellings legal.** A copy that the checker forces for a read-only use
  is a language cost, not an agent's mistake.

## 3. Design

### 3.0 B0: the baseline

- Copy `planning/idioms/` into `experiments/perf-feedback-20261020/idioms/`. Add a
  firing and a non-firing shape for every rule of §3.4, and an idiom for every fix
  of §3.1 and §3.2.
- Record `baseline.json` for each idiom: counter totals at n = 2,000 and 8,000,
  their growth for 4× n, and a class (constant, linear or super-linear).
- Rerun the copy census and the idiom scan on selka-projects with its pinned
  compiler. Record a lint census: findings per rule for each project entry, with
  the project's own code and `@stdlib` counted apart.
- Record the edit-loop latency and the complete verification's wall time on an
  unchanged tree, for §5's G11.
- Never run selka-projects' `tools/mylang` wrapper, which appends to committed
  friction logs. Call the pinned compiler directly, with caches under `~/.cache`.
- **Done:** `BASELINE.md` and `baseline.json` are committed. The counts reproduce
  §1, or `BASELINE.md` explains each difference by a compiler change since
  `f9a7513ed1`.

### 3.1 B1: the defects

1. **A bound slice store passes `check` and fails the build** (`planning/repros/slicestore2.my`).
   - The inline form, `Bag(items=xs[1:3])`, is refused at check with
     `E_SLICE_ESCAPES` and its copy repair.
   - Give the bound form the same refusal and repair for text, bytes and lists. That
     covers stores into record fields, list elements and dictionary values, and
     returns.
   - No escaping view may reach Core's IR verifier.
   - This is the wave 3 leftover that wave 2's batch W (item 3 of §3.W in its plan)
     was meant to close. Read that item and wave 2's `DECISIONS.md` first.
2. **Project lint reports the standard library** (`planning/repros/imp.my`).
   - Drop findings whose subject is a standard-library module before modes resolve,
     as generated files already are, unless the linted entry is in the standard
     library itself.
   - Judge `naming` on the source name, not the specialized one (`contains[i64]`).
3. **`lists.insert` and `lists.pop_at` copy every shifted element, and
   `lists.insert` does not compile for a managed element type**
   (`planning/repros/popstr.my`, `insertstr.my`).
   - Both must lower to the native `insert` and `pop_at` operation kinds, which
     shift without copying, as `queue.pop(0)` already does (`planning/repros/popnative.my`).
   - Wave 2's 2b owns `src/stdlib/lists.my` while it gives `lists` its compiler-side
     homes (the rest of its duplicate-homes work, then the method families). Do this
     item after that has landed on `main`. If it already made them native, add only
     the tests.

Each repro becomes a named test with its required result:
- guest behaviour in `tests/lang/`;
- refusals in the diagnostic tests of `src/root_test.zig`;
- lint in `src/lint_test.zig`;
- item 3's "no copy per shift" through a counting build in the `src/core` tests, or
  through B5's `testing` module if it exists by then.

If item 1 or 2 is already on `main` when B1 starts, skip it and log that.

### 3.2 B2: f-strings without hidden costs

- **Today.** `checkFormat` in `src/sema_collections.zig` desugars
  `f"row {i}: value={i * 3}"` into four things:
  - each hole converted to a separate `str`;
  - each literal piece copied ("so the list owns what it holds");
  - a `str[]` of the pieces;
  - a `join`.

  That is 6 allocations and 2 text copies, even when the string is only printed.
- **After.**
  - An f-string stays one typed node, its pieces, all the way to Core.
  - **Printing or writing an f-string** (`out.print(f"…")` today, `print(out, f"…")`
    after wave 2's 2b) writes the pieces in order into the stream's buffer. Literal
    bytes go as they are, and each hole goes through the renderer and format-spec
    code it uses today.
  - Integer, float, bool, `str` and `bytes` holes then allocate nothing. A hole
    whose rendering allocates today (a record, a list) may keep that allocation, but
    nothing is joined.
  - **An f-string used as a `str`** makes one allocation. Its size comes from the
    literal lengths, the text holes' lengths and an upper bound for each scalar
    rendering, and the pieces are written in place.
- **Output bytes do not change** for any value or format spec.
  - The existing tests (`src/python_format_test.zig`, `tests/lang/format_specs.my`)
    pass unchanged.
  - A new matrix test crosses hole types × specs × (printed, stored).
- **Counts.** Printing an f-string with scalar, text or byte holes makes 0
  allocations; building one makes 1. A counting-build test asserts both.
- **Scope.** Change the f-string's semantic node and its Core lowering only. Wave 2
  is migrating `out.print(…)` to `print(out, …)`. Both spellings reach one Core print
  path, which this batch extends rather than forks.

### 3.3 B3: work you can see

1. **Counters.** Counting builds (`--counters`) gain:
   - `blocks` per function, the executed basic blocks, so work done in mylang code
     shows up (for example `lists.contains`'s scan);
   - `element_moves` and `element_move_bytes`, for elements shifted by insert and
     remove;
   - `sort_compares`.

   Document them in `docs/tooling/counters.md`, with tests beside
   `src/core/count_test.zig`.
2. **Work per test.** Every test child already counts steps for its step ceiling
   and bytes for its memory ceiling.
   - Report per test:
     - `steps`, the executed blocks of program functions;
     - `allocations`, the managed-block allocations, if the ceiling accounting can
       count them at no measurable cost (otherwise log why not);
     - `peak_bytes`.
   - These go into `mylang test --json` and into the test's receipt, so a cached
     result carries them.
   - A plain `mylang test` prints one line for each test whose steps or allocations
     changed by 2× or more, in either direction, since the last run of the same
     test in the same build mode, for example
     `work: http::test_framing steps 41,200 → 168,900 (4.1×)`. Nothing else new is
     printed.
   - The previous values live in a small per-worktree store under the cache
     directory.
3. **`mylang cost --sites`.** One row per allocation or copy site after the build's
   Core passes:
   - the source origin's `path:line:column`, kept through inlining as the counters
     already keep it;
   - the function;
   - the kind: `copy`, `construction`, `conversion`, `growth` or `unresolved call`;
   - the loop depth (0 outside any loop);
   - a one-line hint for that kind.

   `--json` writes `cost-sites-v1`. The data is the allocation classification in
   `src/core/cost.zig` and the witness spans in `src/core/allocation_contract.zig`,
   which `@noalloc` already uses.

Each of the three gets its documentation (`docs/tooling/cost.md`, `counters.md`,
`guest-tests.md`) and a `src/features.json` entry with a runnable example.

### 3.4 B4: findings at the line

1. **Lint output an agent can read.**
   - Two kinds of finding print in full in every run, with or without `--gate`:
     findings of rules in `block` mode, because those refuse under `--gate`, and
     findings in declarations changed against `--against REF`.
   - Findings of report-only rules print as one line per rule with a count, for
     example `L_UNTESTED_EXPORT: 108 findings (mylang lint --all lists them)`.
   - `--all` lists everything. `--json` is unchanged and always complete.
   - `--against REF` scopes the per-declaration rules to changed declarations
     without `--gate` too. Today only `change-without-test` reads it, and only under
     `--gate`.
   - Target: a selka project's default `mylang lint` output is at most 30 lines when
     nothing blocks.
2. **`W_NEEDLESS_COPY`**: a checker warning with a certain repair that deletes the
   copy. It fires when:
   - (i) the copy is an argument to a read-only parameter, an f-string hole or a
     printed value, so the callee only reads it;
   - (ii) the copied value is an owned local and this is its last use, so a move
     gives the same value;
   - (iii) after B7, a `const` is bound to a copy that is only read while its source
     does not change.

   How it is reported and applied:
   - It fires only where the copy-free form provably checks. A false positive is a
     defect.
   - `check` prints it like `W_UNUSED_IMPORT`, and `mylang fix` applies it.
   - The lint rule `needless-copy` (`L_NEEDLESS_COPY`) reads the checker's warnings,
     the way `noalloc-allocates` reads `E_NOALLOC_ALLOCATES`, and blocks under
     `--gate`.
   - A copy that is the point of the code, such as a test of copying, takes a waiver
     with a reason.

   The same batch applies the repair to the checked corpus as a generated commit
   (`migration (generated): …`). It excludes `selfhost/`, `experiments/` and
   fixtures, and generates waivers for tests whose subject is copying. Without that,
   projects that set `warnings: "deny"` would fail.
3. **Loop rules.** These are lint rules on the typed tree, for exact shapes only.
   Each blocks under `--gate` in declarations changed against `--against REF`,
   reports elsewhere, takes a waiver with a reason, and names its rewrite.
   - **`L_LINEAR_SEARCH_IN_LOOP`:** a list membership, index or remove search
     (`lists.contains` and its remaining spellings) inside a loop, on a list declared
     outside that loop which the loop also appends to (the "seen list"). The rewrite
     is a `set` or `dict` kept alongside. A search on a list the loop does not change
     only reports.
   - **`L_SHIFT_IN_LOOP`:** removing or inserting at index 0 of a list declared
     outside the loop. The rewrite is B6's `deque`, or an index cursor.
   - **`L_SORT_IN_LOOP`:** sorting, inside a loop, a list declared outside it that
     the same loop appends to, so the list is re-sorted as it grows. The rewrite is
     one sort after the loop, or B6's `heap`. A list created inside the iteration
     and sorted once there, as in `selfhost/components/cache_plan/graph.my`, is the
     rule's negative test.
   - **`L_ALLOC_IN_LOOP`:** a construction or conversion site at loop depth 1 or
     more, taken from B3's sites, such as an f-string stored in a loop or
     `strings.split` per line. It reports only in changed declarations, never
     blocks, and gives a hint by kind.
   - Wave 2's `L_COPY_FOR_STORE` keeps its definition. Item 1 summarizes it like
     any report-only rule.

Each rule gets:
- positive, negative and waiver tests in `src/lint_test.zig`;
- a row in `docs/tooling/lint.md`;
- a code in `src/diagnostic_codes.zig`;
- an entry in `src/features.json`.

Log a review by hand of at least 30 findings across the corpus and the projects, or
all of them if there are fewer. The blocking shapes must show no false positive.

### 3.5 B5: work in tests, the `testing` module

```text
import testing

# Builds a document of n paragraphs, renders it and returns the output's length.
func render_paragraphs(n: int) -> int:
    ...

public func test_render_is_linear() -> bool:
    return testing.linear(render_paragraphs, 1000, 4000)
```

- **Measurements.** `testing.steps(work, n) -> int` and
  `testing.allocations(work, n) -> int` run `work(n)`, a `func(int) -> int`, and
  return the executed blocks or the managed allocations it took.
  `testing.growth(work, small, large) -> float` returns the larger of the two
  counts' growth ratios without judging it.
- **`testing.linear(work, small, large) -> bool`** runs both sizes.
  - It fails when either count grows by more than 1.5 × (large ÷ small). The
    failure is an assertion whose message names the counter, both values and the
    ratio.
  - At a 4× step from 1,000 to 4,000, an n log n workload passes (about ×4.8
    against a limit of ×6), and a quadratic one (×16) fails.
  - A count that is zero at both sizes passes.
- **`testing.constant`** allows 1.5× growth plus a small fixed slack.
- **How they read the counts.** Two runtime helpers read the test child's counters;
  they are reachable only from `testing` (`E_INTERNAL_NAME` elsewhere). Without step
  accounting (`--max-steps 0`) they trap with `R_NO_STEP_ACCOUNTING`.
- **Build modes.** Counts differ between optimized debug and release. Tests compare
  growth, or assert zero only where both modes agree.
- **Budgets.** Both sizes run inside the test's step budget (1,000,000 by default).
  `limits.test.max_steps` in `mylang.json` raises it; the docs say so.
- **The idiom suite becomes gated guest tests,** in
  `tests/lang/performance_idioms.my`.
  - Each fixed idiom asserts its class. After B2, printing an f-string makes no
    allocation. After B1 item 3, `lists.pop_at(…, 0)` on a `str[]` grows linearly.
  - Each quadratic idiom asserts, through `testing.growth`, that `linear` would fail
    on it.
- **Registration.** The new module needs:
  - standard-library registration;
  - entries in `mylang docs operations`;
  - a "How work grows" section in `docs/tooling/guest-tests.md`;
  - `src/features.json` entries.

  Names follow wave 2's naming policy; log the final ones.

### 3.6 B6: fast spellings in the standard library (after wave 2's 2b)

- **`deque`:** a ring buffer.
  - Operations: `create`, `push_back`, `push_front`, `pop_front`, `pop_back`,
    `front`, `back`, `count`, `get`, and `items` (a snapshot list to loop over).
  - Each is amortized O(1). Popping an empty deque traps the way popping an empty
    list does.
- **`heap`:** a min-heap of values ordered by an `int` key.
  - Operations: `create`, `push(mut h, key, value)`, `pop(mut h) -> T` (the smallest
    key; traps when empty), `peek_key(h) -> int?` and `count`.
- **After wave 2's stage 4,** the storing operations take their value `own`, as
  `append` does.
- **Each module gets:**
  - guest tests, with `testing.linear` for the growth claims;
  - a section in `docs/standard-library.md`;
  - entries in the operations table and `src/features.json`.
- **The hints.** B4's `L_SHIFT_IN_LOOP` and `L_SORT_IN_LOOP` name these modules once
  they exist.

### 3.7 B7: a borrowed `const` (P4, after wave 2's stage 4)

- **The rule.** `const name = place`, where the function cannot move `place`, binds a
  read-only borrow. Loop variables and match payloads already work this way. Such a
  place is:
  - a parameter;
  - an element or field reached through a parameter;
  - an element, field or dictionary value of a local owner.
- **What the borrow allows.**
  - `name` can be read, printed, compared, and passed to read-only parameters.
  - Storing, returning or moving it, or passing it `mut` or `own`, is refused with
    today's code and its copy repair. B8's message explains why.
  - While `name` is live, its owner cannot be changed, moved or replaced. That is
    `E_SINGLE_OWNER_OVERLAP`, as for an iteration borrow today
    (`planning/repros/loopborrow.my`).
- **What does not change.**
  - `mut name = place` still needs its own value.
  - `const name = local_owner` still moves.
  - Slices are already views.
  - Only forms that are refused today become legal, so no accepted program changes
    meaning and nothing needs migrating.
- **Core.** The binding lowers to the same borrowed place that a loop variable or a
  borrowed argument uses, with no copy operation.
- **Tests.** Generate a matrix like wave 3's view-shape matrix, and run it under
  `--verify-facts` and the leak check too. It crosses:
  - owners: a parameter, a local list, a local record, a dictionary;
  - places: the whole value, an element, a field, a nested place;
  - uses: read, print, a plain argument, a `mut` argument, an `own` argument, store,
    return, append;
  - owner events: none, change, move, replace, branch, loop.

  Each cell expects acceptance or a named refusal.
- **Then** `W_NEEDLESS_COPY` case (iii) turns on. Its generated repair removes the
  binding copies that are no longer needed; the census predicts about 20 in the
  projects.

### 3.8 B8: copy diagnostics name what they copy (after B7 and wave 2's stage 4)

- When the certain repair of `E_SINGLE_OWNER_BORROW`, `E_SLICE_ESCAPES` or
  `E_SINGLE_OWNER_OVERLAP` is a copy, the message names what it copies (name and
  type). It also gives whichever copy-free alternative applies at that site:
  - binding it `const` (after B7);
  - taking the parameter `own` (wave 2's stage 4), when every caller can give the
    value up;
  - finishing the borrow first;
  - a `mut` parameter for a helper that changes it.
- The repair stays the copy, so `mylang fix` keeps working and meaning is preserved.
- The element-read message ("bind 'path' with .copy() or use pop()") becomes, for a
  `mut` binding: "a `mut` binding needs its own value; bind it `const` to read it,
  or copy it".
- Add message tests. Update `docs/managed-memory.md`, `docs/value-semantics.md` and
  `docs/performance.md`.

### 3.9 B9: selka-projects (after wave 2's batch P)

- Work on a `perf-feedback` branch:
  - Apply `mylang fix`.
  - Add one `testing.linear` test on each project's main path: kicad-convert
    converting n symbols, markdown rendering n paragraphs, and http-server framing n
    requests.
  - Record any super-linear result as a ledger item of class `perf`, with its
    counts. Fix it only if the fix is trivial.
  - Get `check.sh` green, bump `COMPILER`, and merge into the project's `main` the
    way wave 2's batch P does.
- Rerun the copy census, the idiom scan and the lint census.

### 3.10 B10: final measurement and report

On the final `main`, rerun:
- B0's baseline;
- the parity and runtime suites;
- the edit-loop latency;
- the complete verification's wall time.

Then write `REPORT.md` (§10).

## 4. Order and batches

| Batch | Contents | Waits for | Lands when |
| --- | --- | --- | --- |
| B0 | §3.0, the baseline | — | committed with B1 |
| B1 | §3.1 items 1 and 2; item 3 once wave 2's 2b has given `lists` its compiler-side homes | — | every repro is a named test with its required result, and complete verification passes |
| B2 | §3.2 | — | complete verification passes |
| B3 | §3.3 | — | the same |
| B4 | §3.4, with `W_NEEDLESS_COPY` cases (i) and (ii) and their corpus repair | B1, B3 | the same, and zero `W_NEEDLESS_COPY` in the checked corpus |
| B5 | §3.5 | B3 | the same |
| B6 | §3.6 | wave 2's 2b on `main` | the same |
| B7 | moved to the borrowed results plan's R1 (amendment of 20 October) | — | — |
| B8 | moved to the borrowed results plan's R7 | — | — |
| B9 | §3.9 | B4 to B6, and wave 2's batch P | every project is green on the new pin |
| B10 | §3.10 | everything | `REPORT.md` |

- **Wave 2's progress.** Learn what it has landed from `main`'s log and from
  `~/ai/canopy/mylang-wave2/experiments/language-wave2-20261019/status.md`. Read
  that file only.
- **Waiting.**
  - When the next batch waits for wave 2, run any later batch whose dependencies are
    met.
  - When every remaining batch waits, commit a "Waiting" section in `status.md`
    naming the wave 2 batch, and stop.
  - That is a pause, not a failure. The user restarts the run when wave 2 lands.
- **Size.** About 65 to 100 hours of work:
  - B0 and B10: 2–3 h each;
  - B1: 4–8 h;
  - B2: 6–10 h;
  - B3: 8–12 h;
  - B4: 10–16 h;
  - B5: 6–8 h;
  - B6: 6–8 h;
  - B7: 12–20 h;
  - B8: 3–4 h;
  - B9: 6–8 h.

## 5. Done criteria

| # | Criterion |
| --- | --- |
| G1 | B1's three repros are named tests with their required results |
| G2 | f-strings: output bytes are identical across the hole × spec × use matrix; printing one with scalar, text or byte holes makes 0 allocations; building one makes 1 |
| G3 | `--counters` reports `blocks`, `element_moves` and `sort_compares`. `mylang test --json` reports `steps`, `peak_bytes` and, where logged as feasible, `allocations` per test. The `work:` line appears exactly when the 2× threshold is crossed. `cost --sites` lists the idiom suite's sites with their loop depth |
| G4 | Lint: `planning/repros/imp.my` reports nothing. Each selka project's default output is at most 30 lines when nothing blocks. `--all` and `--json` still list everything |
| G5 | Every new rule has positive, negative and waiver tests. The logged review finds no false positive in the blocking shapes. After the generated repair, the corpus checks clean and every test result is unchanged |
| G6 | `testing.linear` passes on the linear idioms and fails, with a message naming the counter, on the quadratic ones, in both gate modes |
| G7 | Draining 1,000 strings with `lists.pop_at(…, 0)` makes no copy per shift. `lists.insert` compiles for `str[]`. `deque` and `heap` pass their growth tests |
| G8 | Borrowed `const`: the matrix is green under `--verify-facts` and the leak check. Every existing test passes under its old name. The binding copies found by case (iii) are gone from the corpus |
| G9 | Each copy diagnostic names what it copies and the alternative that applies; message tests pin the wording |
| G10 | selka-projects: each project has a growth test, `check.sh` is green on the new pin, and super-linear findings are in its ledger |
| G11 | No regression. The parity and runtime suites stay within their thresholds. The edit-loop latency (check plus two tests after a helper edit, warm) stays within 5% of B0's. Complete verification on an unchanged tree stays within 10% of B0's |
| G12 | Complete verification and formatting pass for each batch |

## 6. Risks

- **False positives cost trust.** A wrong blocking finding teaches agents to waive.
  Only exact shapes block; heuristic findings report, and only in changed code.
- **`W_NEEDLESS_COPY` against `warnings: "deny"`.** A new warning fails `check` in
  projects that deny warnings. So the corpus repair lands in the same batch, and the
  report tells project owners to run `mylang fix`.
- **Counts depend on the build mode and the compiler.** Tests compare growth, or
  assert zero only where both modes agree. The `work:` line compares runs in one
  mode.
- **The borrowed `const` extends ownership checking,** so a hole in it is a
  memory-safety bug. The generated matrix, `--verify-facts` and the leak check
  guard it, with wave 3's view work as the model.
- **Merging with wave 2.** Wave 2 rewrites call forms across the corpus (2b) and
  the ownership code (stage 4). Merge `main` before every batch. Regenerate
  generated commits after each merge; never hand-merge them.
- **Gate time.** The idiom suite and the new tests add to the gate. Keep each new
  test file's work under a second, and check G11.

## 7. How it fits with the other work

- **Language wave 2** runs in `~/ai/canopy/mylang-wave2`, on branch
  `wave2/integration`.
  - At planning time, 2b had landed four families: fallible signatures, option
    presence, bit operators and the `strings` search words. Next were the rest of
    the duplicate homes (`lists.index_of` and `remove`, the view words, the prelude
    overlaps) and the method families. The re-seed script was committed on its
    branch.
  - Never touch that worktree, its branch or its processes.
  - Its stage 4 adds `own` and the report-only `L_COPY_FOR_STORE`, which B6's
    operations and B8's messages use. §4 lists the dependencies.
- **Gate reliability** has landed (`bd2783767b`). Use the complete verification's
  short summary.
- **Self-hosting.** Make no `selfhost/` edits. `selfhost/components` is excluded from
  the generated repairs.
- **selka-projects:** B0 reads it; B9 changes it, after wave 2's batch P has merged
  its `wave2` branch.
- **Withdrawn sessions.** On 20 October two separate sessions were proposed for
  B1's items 1 and 2, then withdrawn in favour of this plan. If either fix is on
  `main` anyway, skip it.

## 8. Not in this plan

- **Borrowed returns of a parameter's parts, and views inside returned aggregates**
  (`return Some(text.copy())`, `return names[i].copy()`).
  - This is the largest group of forced copies: 74 returns in the census, about half
    of them constructors that legitimately own their text.
  - It needs a parent-set return rule and views inside records. That is a separate
    ownership plan, which should start from this plan's census.
- **Field-level moves and borrows** (FR-107, FR-350): the 23 overlap sites.
- **Consuming loops** (`for own x in xs`).
- **Complexity types or annotations,** which cannot be checked in general.
- **Allocation as a capability parameter.** Most functions would carry one, and
  `@noalloc` with B3 and B4 gives the same visibility.
- **Wall-time budgets in tests,** which flake.

## 9. Decisions

Taken as accepted at launch. P4, P6 and P7 are the user's to strike.

1. **P1. Where findings appear.**
   - A certain finding is a checker warning with its `fix` (`W_NEEDLESS_COPY`).
     `check` prints it, and `lint --gate` refuses it.
   - A heuristic finding is a lint rule. It blocks under `--gate` only in
     declarations changed against `--against REF`, and reports otherwise.
   - No performance finding is ever a `check` error.
2. **P2. Lint output.**
   - The standard library is never reported in a project.
   - Report-only findings print as one count line per rule unless `--all` is given.
   - Findings of rules in `block` mode, and findings in changed declarations, print
     in full in every run.
   - `--json` is unchanged.
3. **P3. f-strings.** Printing or writing one writes its pieces, and building one
   makes one sized allocation. The surface does not change, and output bytes are
   identical.
4. **P4 (user). A borrowed `const`** (§3.7). If declined, skip B7 and
   `W_NEEDLESS_COPY` case (iii), and B8 drops the `const` alternative.
5. **P5. Copy diagnostics** keep the copy as their certain repair, and their messages
   name what is copied and the copy-free alternative.
6. **P6 (user). A `testing` module** with work counts and growth checks (§3.5).
7. **P7 (user). `deque` and `heap` modules** (§3.6).
8. **P8. Counters and work per test:**
   - counters `blocks`, `element_moves` and `sort_compares`;
   - `steps`, `allocations` and `peak_bytes` for each test;
   - a `work:` line at 2× change.
9. **P9. `mylang cost --sites`,** in the format `cost-sites-v1`.
10. **P10. Thresholds.**
    - `linear` allows 1.5 × the size factor.
    - `L_LINEAR_SEARCH_IN_LOOP` blocks only for a list that the same loop appends
      to.
    - Lint output targets at most 30 lines when nothing blocks.
11. **P11.** §8 stays out of this run.

## 10. Operating rules and launch instruction for Codex

- **Autonomy.** Decide, log in `experiments/perf-feedback-20261020/DECISIONS.md` (the
  question, the evidence, the choice and whether it can be reversed), and continue.
  - Commit at every step, with a progress section in `status.md`.
  - Investigate a gate failure for up to about 6 to 8 h.
- **When your context runs low,** commit a "Session handoff" section in `status.md`
  and stop. That is a handoff, not a blocked run.
- **Hard stops.** Stop and ask only for:
  1. a language change beyond P1 to P11, or a repair that changes a program's
     output or result;
  2. relaxing a gate on `main`, or any of G1 to G12;
  3. a broken premise, for example a borrowed `const` that cannot be checked without
     lifetime annotations;
  4. touching another run's worktree, branch or processes, `../guardian-zig`, or
     selka-projects outside B0's reads and B9;
  5. a failure that cannot be fixed within the bound;
  6. free space on `/` under 25 GB, or the machine swapping.
- **Branches and landing.**
  - Work in the worktree `~/ai/canopy/mylang-perf-feedback` on branch
    `perf-feedback/integration`, created from `main`.
  - Land each batch by fast-forward from the primary checkout,
    `git -C ~/ai/canopy/mylang merge --ff-only perf-feedback/integration`. Do it
    only after `python3 scripts/verify_cache.py --zig "$ZIG" --profile complete`
    passes, and only when `git -C ~/ai/canopy/mylang status --porcelain` lists no
    tracked change.
  - If `main` has moved, merge it, verify again, then fast-forward. Never push.
  - Commit only in your worktree. Stage named paths only; never `git add -A` or
    `git add .`.
  - Corpus repairs are generated commits (`migration (generated): …`), regenerated
    after every merge of `main`.
- **Files.**
  - `CLAUDE.md` may be edited only in "Where the language differs from Python" (for
    P4) and "Measuring guest programs" (for B3 and B5).
  - `SPEC.md` is frozen.
  - No `selfhost/` edits.
  - Untracked files in the primary checkout belong to other sessions; leave them
    alone.
- **Machine rules from `CLAUDE.md`.**
  - Run `source ~/.config/mylang/dev-env.sh` in the worktree.
  - Builds and focused tests go through `scripts/build-slot.sh`, and the lane check
    is `python3 scripts/patch_gate.py --parallel`. Never wrap `verify_cache.py` in a
    slot.
  - At most four agents build the compiler on this machine. Wave 2 is one of them,
    so build one thing at a time.
  - Caches, `TMPDIR` and install prefixes go under `~/.cache`, never `/tmp`.
  - A behavioural change under `src/` ships with a test change in the same diff.
  - Keep committed evidence under 10 MB.
  - Never kill a process this run did not start.

**Finish** with `experiments/perf-feedback-20261020/REPORT.md`. It covers:
- G1 to G12, with their evidence;
- before-and-after tables for the idiom suite, the copy census and the lint census;
- every new code, rule, counter and option, with its tests;
- the generated repairs and their counts;
- the selka-projects pin, merge commit and `check.sh` results;
- the decisions logged.

```text
Implement docs/audits/performance-feedback-plan-2026-10-20.md on main in
~/ai/canopy/mylang: f-strings and list shifts without hidden costs, the two defects
it found, work you can see (counters, work per test, cost --sites), performance
findings at the line with repairs and agent-sized lint output, a testing module for
work growth, deque and heap, and a borrowed const. Read the plan fully, then
CLAUDE.md, docs/tooling/lint.md, docs/tooling/cost.md, docs/tooling/counters.md,
docs/tooling/guest-tests.md, docs/performance.md and
experiments/perf-feedback-20261020/planning/README.md. P1 to P11 are accepted.
Decide, log in experiments/perf-feedback-20261020/DECISIONS.md, and continue; stop
only for the hard stops in section 10. Create the worktree
~/ai/canopy/mylang-perf-feedback on branch perf-feedback/integration from main.
Run the batches of section 4: B0 to B5 now (B1's item 3 once wave 2's 2b has given
lists its compiler-side homes), B6 after language wave 2's 2b has landed on main, B7
and B8 after its stage 4, B9 after its batch P, then B10. Language wave 2 is running
in ~/ai/canopy/mylang-wave2: never touch that worktree, its branch or its processes;
read its status.md to learn what has landed. If every remaining batch waits for wave
2, commit a "Waiting" section in status.md naming the batch and stop. Every certain
finding carries its mylang fix repair and a test; no repair may change a program's
output. Land each batch on main by fast-forward from the primary checkout after a
green complete verification, merging main first. Commit only in your worktree, stage
named paths only (never git add -A), leave untracked files in the primary checkout
alone, and never push. Edit CLAUDE.md only in the two sections section 10 names; do
not touch SPEC.md, selfhost/, ../guardian-zig, or any other run's branch. When your
context runs low, commit a "Session handoff" in status.md and stop. Commit at every
step with a progress section in status.md, and finish with REPORT.md.
```
