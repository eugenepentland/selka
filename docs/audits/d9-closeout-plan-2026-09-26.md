# D9 close-out plan (handoff), 2026-09-26

This is a self-contained plan for finishing [D9](../adr/D9-value-semantics-then-rc.md): value semantics, then a reference-counted runtime. It's written for an agent with no prior context. Take one **work package** (WP) at a time, follow the common rules, and report in the format at the end.

## 1. Read first

1. `CLAUDE.md`: build, fast test loops, Guardian rules and the full gate.
2. [`docs/adr/D9-value-semantics-then-rc.md`](../adr/D9-value-semantics-then-rc.md): the direction, why the order matters, and each stage's gate.
3. This plan: §3 (common rules), then your WP in §5.
4. The evidence your WP names in §7.

## 2. Where things stand (main `60b668cf`)

**On `main`, every item full-gated before merging:**

| Item | What | SPEC tags / docs |
|---|---|---|
| N1 | `--unchecked` removed; every build keeps overflow, cast and bounds checks | `RELEASE-CHECKED-1` |
| N2 | `@requires`, `@ensures` (`result`, `old()`), `@invariant`, checked in every mode | `CONTRACT-*`, `docs/contracts.md` |
| N3 | Error return traces; LLVM calls the recorders through `preserve_most` twins | `ERROR-TRACE-1..6` |
| N4 | Deterministic stand-in capabilities; test capability parameters; `--seed` | `TEST-CAPS-1..4` |
| N5 | `set[T]`, any hashable dict key, O(1) dict removal | `SET-*`, `HASH-KEYS-*`, `DICT-REMOVE-1`, `docs/sets.md` |
| N6 | Property tests with shrinking | `PROPERTY-TEST-1..5` |
| N7 | Generated `.api` interface files, `mylang api --write/--check` | `API-FILE-1..3` |
| D9 stage 2 | Runtime-independent ownership analysis (move/borrow/copy, copy-on-write placement with loop hoisting); record copy elision; borrowed-root elision; `check --explain-ownership` | `OWNERSHIP-*`, `QBE-MOVE-ELIDE-1`, `QBE-BORROW-ROOT-1`, `docs/tooling/ownership.md` |
| Perf fixes | Scan plans attached to type descriptors; `str`/scalar dict keys compared without a call | `GC-SCAN-PLAN-1/2`, `ERROR-TRACE-6` |

**D9 stage 1 (agent A/B) passed its gate.** Both arms were correct on 18 of 18 runs, with no wrong answers that exit 0. The value arm needed somewhat fewer repair rounds (2.22 against 3.11), within noise. Details: §7, P4.

**Performance baseline for stage 3.** Main `60b668cf` against main `4d54b210`, measured over 116 program × backend runs (27 parity programs, schematic, 13 Lox scripts on both engines, 2 `Result` programs, each on LLVM and QBE):
- Instruction geomean 0.9903 on LLVM and 0.9940 on QBE.
- Every output correct.
- Data: `experiments/perf-gc-dict-20260925/results.json` on main. The side named "new" there is this tree.

**Stage 3 status.** All three sub-stages were paused mid-work on 2026-09-25. Each worktree is at `/home/epentland/ai/canopy/mylang-worktrees/d9-stage3{a,b,c}` on branch `d9/stage3{a,b,c}`, based on `60b668cf`.

| Sub-stage | State |
|---|---|
| **3a**, switch and checker rules | 4 commits (`51dba1bd`..`7f827049`), nothing uncommitted. Next: run the new tests, the full gate, and the switch-cost measurement. |
| **3b**, copy-on-write on the GC | No commits. 17 modified and 7 new files (`native_cow.c/.h`, `qbe_cow.zig`, `cow_plan.zig`, `cow_test.zig`, `tests/native_cow_test.c`, …), mid phase 1. |
| **3c**, recursive value types | No commits. 34 modified and 2 new files (`recursive_boxes.zig`, `tests/lang/recursive_values.my`). It was about to write its Zig tests. |

Backups of the uncommitted work are in `/home/epentland/ai/canopy/mylang-worktrees/_wip-backup-d9-20260926/`:
- `stage3{b,c}-tracked.patch`: `git diff HEAD`;
- `stage3{b,c}-untracked.tgz`: the new files;
- `stage3{b,c}-untracked.txt`: their list.

Both are based on `60b668cf`. If a worktree is lost, restore it with `git worktree add -b d9/stage3X <path> 60b668cf && git apply stage3X-tracked.patch && tar xzf stage3X-untracked.tgz`.

**Not part of D9, but it affects every merge:** another session prepared `merge/devspeed-into-main`, report `docs/audits/merge-devspeed-into-main-2026-09-24.md` on that branch. It merges the `devspeed/integration` work: the build loop, per-module compilation 1a–1d, the fix tool, expression fidelity, dict comprehensions and more. It is based on `a5f5435d` and has **not** landed; the user approves it. Whichever of it and a stage-3 branch lands second must merge `main` and rerun its gate. A note from that session says arenas will be removed. **D9 keeps arenas** ("Arenas remain the bulk-release tool"); don't remove them without a new decision.

## 3. Common rules (every WP)

- **Where to work.** Use your own git worktree off `main`, or the WP's existing worktree, under `/home/epentland/ai/canopy/mylang-worktrees/`. Never edit the main checkout (`/home/epentland/ai/canopy/mylang`); it's another session's dirty branch.
- **Building.**
  - Use the Debug compiler (`zig build`). Guest binaries are identical to a ReleaseFast compiler's, so never build ReleaseFast.
  - Run at most one full `zig build test` at a time, and keep at most about 4 build-heavy agents on the machine.
  - Never kill processes you didn't start: no broad `pkill` patterns.
- **Scratch space.** `/tmp` is a tmpfs with a per-user quota. Keep scratch under your worktree (`.tmp-*`, never committed) and delete large intermediates. If a step fails with `DiskQuota`, free your scratch and rerun it; don't treat it as a code failure.
- **Guardian rules.** Guardian runs inside `zig build`/`zig build test` and blocks:
  - every added behavioural line under `src/` needs a test carrying `// spec: TAG`, plus a `- [TAG] …` bullet in `SPEC.md`;
  - exactly one `// spec:` test per bullet; further tests use `// spec-case: TAG`;
  - structs have at most 7 fields, functions at most 6 parameters;
  - every `pub` declaration has a `///` doc comment;
  - test bodies are straight-line (no top-level `if`/`while`/`switch`) and contain an `expect`;
  - no import cycles, and new files must be reachable from a `guardian.toml` root;
  - the type-size ratchet must not grow. If it legitimately must, follow `CLAUDE.md`'s accept procedure and say so.
- **Documentation gate.** Every feature slug in `src/features.json` needs `{kind, summary, doc}`, and the doc anchor must contain a runnable example. `mylang doc-coverage .` and `mylang doctest .` must pass. Runnable doc blocks run without `--value-semantics` unless the block uses 3a's per-block doctest directive.
- **Full gate.** It must be green before you report done:

  ```bash
  zig build test --summary all
  zig build test-qbe --summary all
  zig build test-qbe-build --summary all
  zig build fmt-check
  ```

  If something also fails on untouched `main`, show that evidence rather than hiding it.
- **Commits and merges.**
  - Make small commits ending with `Co-Authored-By: <your model> <noreply@anthropic.com>`, or your tool's equivalent.
  - When you bring in `main`, make a **real two-parent merge commit**, never a squashed one. Merge the latest `main` before your final gate.
  - **Don't merge into `main` and don't push.** The orchestrator (the user or their designated session) runs the gate again and fast-forwards `main`.
- **Measurement.**
  - Use the harness `experiments/perf-gc-dict-20260925/scripts/pc.py` on `main` (`build` / `measure` / `summary` subcommands, documented in its header). Prepare Lox with `scripts/prepare_lox.sh`.
  - `perf stat -e instructions:u`, median of 3, is primary. The machine is busy, so treat wall time and cycles as secondary.
  - Compare against the baseline in §2.
- **Report files.** Some agent harnesses refuse to let subagents write report `.md` files. If yours does, put the report in your final reply instead.

## 4. Order and parallelism

```text
3a finish ─┬─> 3b phase 2 (needs 3a on main) ─┐
           ├─> 3e (needs 3a on main)          ├─> 3f flip default ─> 4pre ─> 4 (RC runtime) ─> 5 (concurrency)
3b phase 1 ┘                                  │
3c finish ───> 3d remove class (needs 3c) ────┘
T1–T6, Q1–Q3 (independent, any time)
```

- **Can run now, in parallel:** 3a finish, 3b phase 1, 3c finish, and any T/Q item.
- **After 3a is on `main`:** 3b phase 2 and 3e.
- **After 3c is on `main`:** 3d.
- **After 3b, 3d and 3e are on `main`:** 3f.

## 5. Work packages

### WP-3a: finish the value-semantics switch and checker rules
- **Start:** worktree `d9-stage3a`, branch `d9/stage3a` (4 commits). Read its commits and `docs/value-semantics.md` first.
- **Scope, as already designed:**
  - **The switch:** `--value-semantics` on `check`/`build`/`run`/`run-project`/`test`, and `"value_semantics": true` in `mylang.json`. Default off, and part of every cache identity.
  - **Transfers:** under the switch, `list`/`dict`/`set`/`byte_buffer` and aggregates holding them are independent values. Assignment, non-`mut` argument passing, stores and returns never alias.
    - Read-only arguments are lent without copying.
    - Other transfers copy unless stage 2 classifies them as a move or a borrow.
    - All copies go through **one copy hook**, which 3b replaces.
  - **`mut`:** `mut` parameters are `inout`, and `mut` record parameters allow field writes that reach the caller.
  - **Errors:** writes through loop/`enumerate`/`zip`/`reversed`/`d.values()`/`d.items()`/`case` bindings are `E_VALUE_BINDING_WRITE`; writes into a call result are `E_VALUE_TEMPORARY_WRITE`.
  - **Overlap:** `E_MUTATION_OVERLAP` never fires for non-`mut` arguments (exclusivity between two `mut` arguments stays). A read-only argument that a same-call `mut` argument could reach gets a real copy.
  - **Wording:** diagnostics use value-semantics wording. The "`x` is declared `mut` but never written" hint suggests storing the copy back.
  - **Unchanged in this stage:** `class` and `Cell` stay shared references.
- **Acceptance:**
  - With the switch off, emitted IL is byte-identical to `main` on the 44 parity files, and `tests/lang` results are unchanged.
  - Every rule has guest, Zig or CLI tests, including one run of `tests/lang` with the switch. List the tests that fail only because they assert aliasing; don't edit them, since 3f does that.
  - Switch-cost table (on vs off, instructions) for parity, schematic and Lox. This is informational, with no gate.
  - The full gate is green.
- **Evidence:** §7 P3 (the rules' origin) and P4 (the misleading hint).

### WP-3b: copy-on-write on the tracing GC
- **Start:** worktree `d9-stage3b` (uncommitted work; backup in §2). Read `src/qbe_cow.zig`, `src/cow_plan.zig`, `src/native_cow.c` and `tests/native_cow_test.c` first.
- **Design:**
  - Each copy-on-write payload (`list`, `dict` including sets, `byte_buffer`) carries a **shared bit**. A value transfer that stage 2 classifies as a real copy sets the bit and shares the pointer, which is O(1). Moves and borrows do nothing.
  - Every mutation is preceded by a uniqueness check at stage 2's copy-on-write sites, hoisted out of loops where stage 2 allows. If the bit is set, the payload is shallow-copied into a fresh unshared one (setting the bit on nested payloads it now shares) and the owning slot is redirected.
  - The bit is sticky: both holders copy on their first write. Measure how often that happens.
  - Nested paths make each level unique.
  - Arenas: a copy allocates in the current region.
  - With the switch off, nothing changes.
- **Phase 1 (now):**
  - the runtime mechanism, with the header bit fitting the existing header if possible;
  - `mark_shared` and `make_unique` for each payload kind, plus nested paths;
  - C tests, including GC-stress cases;
  - codegen for the uniqueness checks and hoisting, behind an internal switch, with IL-shape tests;
  - a written design for plugging into 3a's copy hook.
- **Phase 2 (after 3a is on `main`):** merge `main`, replace the copy hook with `mark_shared`, enable the checks under `--value-semantics`, and make every 3a test pass.
- **Acceptance (D9 stage 3 performance gate):**
  - With `--value-semantics`, parity (`my` LLVM arm and QBE), schematic and the Lox VM stay **within 1.05× geomean, with no program over 1.3×**, of main `60b668cf` without the switch, in instructions. Lox needs P3's `lox-port.patch` (see §7).
  - Report counters (zero cost when off): mark-shared events, uniqueness checks executed, copy-on-write copies made.
  - With the switch off, IL is identical.
  - Outputs are identical to 3a's eager implementation, including under `--gc-stress`.
  - The full gate is green.
- **Evidence:** §7 E2b (hoisting was essential: matmul was 60× without it; 0 copy-on-write copies actually happened in parity) and P3 (eager copying was 1.80×, the borrow arm 1.11–1.21×).

### WP-3c: recursive value types
- **Start:** worktree `d9-stage3c` (uncommitted work; backup in §2). Read `src/recursive_boxes.zig` and `tests/lang/recursive_values.my` first.
- **Design:**
  - A `record` or `union` that refers to itself (directly, mutually, or through `Option`, tuples or fixed arrays) is a legal **value** type. Recursion through `list`/`dict` already has indirection; make sure it works too.
  - A field that would make the type infinitely large is stored in a hidden, GC-managed, **immutable** box.
  - Construction, field reads, `match`, `==`, hashing (recursive types built only from hashable fields are hashable), printing, `replace`, typed JSON, the test harness boundary, property generators (size-bounded, shrinking toward leaves) and `.api` rendering all behave as if the value were inline.
  - A write through a boxed path uses **path copying**: new boxes along the path, with old ones untouched. This works with or without the switch, since records are values in both.
  - Equality, hashing, printing, JSON and GC scanning must not overflow the native stack on very deep values (for example a 1,000,000-long chain). Use explicit work stacks, or a documented limit with a clean trap.
  - Arenas follow the existing rules.
- **Acceptance:**
  - Guest tests and Zig diagnostic tests, with every rule spec-tagged (`RECURSIVE-VALUES-*`).
  - A `binary_trees` variant in `bench/parity` built on a recursive union, compared with the `class` variant (instructions and peak RSS, both backends), with any large gap explained.
  - One `class`-based tree in the repo migrated with unchanged results.
  - Docs in `docs/records-and-unions.md` and a feature slug.
  - The full gate is green.

### WP-3d: remove `class` (and decide `Cell`)
- **Depends on:** 3c on `main`.
- **Scope:** replace every `class` with records plus recursive value types, or with `pool` ids for real graphs, then retire `class` and decide `Cell`'s fate (a shared mutable box conflicts with value semantics).
  - **Inventory** (§7 P1): 80 declarations. `tests/lang` has 53, the Lox port 16, `experiments/sexpr-port` 3, `bench/parity` 3 (the `_class` variants), the stdlib 2, trial T2 2, and the schematic 1. 24 are graph-shaped and 10 type-recursive.
  - **Retirement plan to propose:** a deprecation window behind the switch, with an error or warning, a fix-it naming the replacement, and a migration note.
- **Acceptance:** no `class` left in the repo's own code (tests that pin `class` behaviour are rewritten or moved to a legacy note), outputs unchanged, the Lox VM still passes its 13 scripts, and the full gate is green.
- **Design decisions to write down first:** what replaces `Cell`, and whether `class` becomes a compile error or a deprecation warning during the window.

### WP-3e: migration diagnostic and `mylang fix`
- **Depends on:** 3a on `main`.
- **Scope:** turn the P1 census (the `--probe-aliasing` export plus `census.py` on `exp/e2-value-semantics`, see §7) into a real checker pass.
  - Without the switch, a warning (for example `W_ALIAS_DEPENDENT`) marks every site whose meaning changes under value semantics, with its category: local alias, `class` graph, store, or across a call.
  - `mylang fix` rewrites the mechanical cases, for example writes that relied on aliasing through a local, which become a store-back or a `mut` parameter.
- **Acceptance:** on the P1 corpora, the warning finds the census's 101 sites with ≥ 95% agreement (report the disagreements); the fixed Lox port runs identically with and without the switch; and the full gate is green.

### WP-3f: flip the default
- **Depends on:** 3b, 3d and 3e on `main`.
- **Scope:**
  - Make value semantics the default and remove the switch, or keep an opt-out for one release.
  - Rewrite the docs that describe sharing: `docs/managed-memory.md`, the effects/mutation contracts in `docs/effects.md`, `docs/records-and-unions.md`, and the "Where the language differs from Python" section of `CLAUDE.md`.
  - Rewrite the `tests/lang` tests that assert aliasing (3a lists them).
  - Update Zig tests with embedded source that assume sharing.
  - Account for the velocity suite's CPython oracle, which now differs on list aliasing: mark or adapt those idioms.
  - Mark the 2026-09-17 aliasing decision superseded and update D9's status.
- **Acceptance:** the full gate is green with the new default, and the stage 3 performance gate holds against the §2 baseline (≤ 1.05× geomean, none over 1.3×).

### WP-4pre: cross-function borrow inference
- **Scope:** a function's result that aliases a parameter (the checker's `return_origin`) becomes a per-function fact that codegen can use, with a cache-key entry so edits invalidate correctly. That lets element or record reads returned from accessors be borrowed rather than counted.
- **Why:** E2b's schematic cost (1.29×) was count traffic on records returned by value. On the GC with shared bits it matters little; for stage 4 it's required.
- **Acceptance:** explain-surface output, tests, and a measured reduction in RC-relevant transfers on the schematic.

### WP-4: reference-counted runtime
- **Depends on:** 3f and 4pre on `main`.
- **Scope:** replace the tracing collector with counting plus copy-on-write once the heap is acyclic by construction. Arenas stay. Start from the E2b prototype (§7): its runtime `src/native_rc.c`, its per-function plan and inline fast paths, and the list of what it refused.
- **Acceptance (D9):** ≤ 1.0× the GC geomean, no program over 1.3×, and lower median peak RSS. This time it must also be measured on graph-heavy programs rewritten in stage 3, such as the Lox port.

### WP-5: concurrency
Design first, starting from `docs/concurrency-proposal.md` and Weft's structured tasks with atomic counts only on values that cross a task boundary. Don't implement before WP-4.

### Independent items, any time

| ID | Item | Evidence |
|---|---|---|
| T1 | `mylang check` on a library module with no `main` fails with `E_MAIN`; make it type-check the module (or give an explicit mode) | 36 of 36 P4 runs hit it, 46 times |
| T2 | `mylang fmt --check` says only "formatting differs": show a diff or location. Ship starter and example files already `fmt`-clean. | P4 FRICTION logs |
| T3 | `x != []` infers its type against a local but fails with `E_LIST_INFERENCE` through a field/index chain | 11 P4 hits |
| T4 | `mylang test FILE` silently finds 0 tests when they're in a sibling `FILE_test.my`: include it or say so | P4 |
| T5 | Document `E_EXPLICIT_DISCARD_REQUIRED` (`_ =` for ignored non-unit results) and `E_PRIVATE_INTERFACE` (public record exposing a private type) in the primer | P4 |
| T6 | `fmt` enforces the module-header rule on `_test.my` files but `test` doesn't (`E_MODULE_HEADER`, 8 hits); make them agree | P4 |
| Q1 | Contract trap codes travel as an `assert`-message prefix, so an `assert` whose message starts with `R_REQUIRES: ` is misreported; give contracts a dedicated runtime entry | N2 report |
| Q2 | A function whose body builds an invariant-carrying value always misses the checked-body cache; decoded (JSON/wire) records skip invariants | N2 report |
| Q3 | Decide on the list-element write-back (`xs[i].f = v` in place). It gave nbody 0.68–0.77× on QBE but 1.06× under LLVM full LTO (alias classes), so stage 2 removed it. Investigate the LTO interaction or drop it. | stage 2 report, `qbe_moves.zig` |

## 6. Report format (every WP)

- Commits (hash and subject) and the branch.
- What was built, with any deviation from this plan and the reason.
- Acceptance criteria: each met or not, with evidence.
- Full-gate results with step and test counts.
- Measurements, if the WP has a performance criterion.
- Anything undone, uncertain, or found broken elsewhere.

Be factual; don't claim a check you didn't run.

## 7. Evidence index

| Name | Where | What |
|---|---|---|
| Experiment plan | `exp/e2-value-semantics`: `docs/audits/value-semantics-experiment-plan-2026-09-24.md` | E2a/E2b questions and pre-registered decision rules |
| P1 census | `exp/e2-value-semantics`: `experiments/value-semantics-20260924/p1/` (`summary.md`, `census.py`, `sites.jsonl`, `patches/lox-mut-markers.patch`), plus `src/alias_probe.zig` on that branch | 101 meaning-change sites in 31k lines; the `class` inventory |
| P2 agent records | `exp/e2-value-semantics`: `…/p2/findings.md`, `incidents.jsonl` | No silent aliasing mistakes in recorded sessions; the overlap check is the friction |
| P3 eager copies | `exp/e2-p3-value-copies`: `…/p3/` (`summary.md`, `USING.md`, `lox-port.patch`, `scripts/prepare_lox.sh`) | The origin of 3a's rules; eager 1.80× / borrow 1.11–1.21× |
| P4 agent A/B | `exp/e2-value-semantics`: `…/p4/results.md`. Kit: `/home/epentland/ai/trials/value-semantics-20260924/`; runs: `/home/epentland/ai/trials/lang-trial-20260924/runs/` | Stage 1 gate met; the T1–T6 tooling findings |
| E2b RC prototype | `exp/e2b-rc-runtime`: `…/e2b/summary.md`, `src/native_rc.c`, `src/qbe_rc*.zig` | RC+COW 0.989× on parity, 1.29× on schematic; refused `class`/arenas |
| Perf check | `perf/check-20260925`: `experiments/perf-check-20260925/summary.md` | Base vs new; causes of the fixed regressions |
| Baseline and harness | `main`: `experiments/perf-gc-dict-20260925/` (`results.json`, `scripts/pc.py`, `scripts/prepare_lox.sh`) | Stage 3 baseline data and the measurement harness |
| Stage 3 WIP backups | `/home/epentland/ai/canopy/mylang-worktrees/_wip-backup-d9-20260926/` | 3b and 3c uncommitted work as patches and tarballs |
