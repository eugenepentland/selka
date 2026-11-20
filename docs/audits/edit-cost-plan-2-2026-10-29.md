# Edit cost, part 2: finishing the paused cache work (plan, 2026-10-29)

**For:** an implementing agent working on the mylang (Selka) compiler in `~/ai/canopy/mylang`.
**Written by:** Claude, from the handoffs of lanes P, Q and R. They were paused on 28 October when the user moved the
compiler dev loop ahead of this work (`docs/audits/compiler-dev-loop-plan-2026-10-28.md`).
**What this is about:** the time an edit to a large *Selka program* takes to rebuild with `mylang build`. That's the loop
an agent porting the 669k-line EDA lives in. This is not the compiler's own test loop; that has its own plan,
`docs/audits/compiler-dev-loop-plan-2-2026-10-29.md`.

## 1. Goal and where it stood

The packages come from `docs/audits/resident-build-server-plan-2026-10-28.md` §8. A resident build server was measured
(S0) and dropped: it saved only about 20%, because the rest of an edit build scales with the program. These packages cut
that per-program work in ordinary one-shot builds instead.

**Last full measurement** (main b3e5d71ed, 27–28 Oct, ReleaseFast compiler, one-line edits, median wall):

| Edit | 99k port | 400k port |
| --- | --- | --- |
| comment in the hub module | 1.04 s | 4.19 s |
| leaf function body | 0.86 s | 3.08 s |
| body in the hub module | 1.11 s | 3.60 s |
| added function | 0.94 s | 3.32 s |
| type change (new enum variant) | 2.19 s | 6.7 s, or 14–30 s when it falls back to a whole-tree retry |

**Where a 400k one-line edit's CPU went** (S0 profile, `experiments/resident-server-s0-20261028/REPORT.md` §3):
- keys and digests of unchanged records: about 23% of CPU (the lowering key's declaration walk alone was 12%);
- whole-module validation (ownership cache validate, allocation contracts): about 14%;
- lowering walk and restore: about 11%;
- emission lookups: about 8.5%;
- optimizer bookkeeping: about 6%.

**Targets** (from §8):
- a 400k one-line edit from about 3.5 s to about 2.3 s, and 99k from about 1.0 s to about 0.7 s;
- a new-shape type edit with no whole-tree retry, and under 4 s at 400k and 1.5 s at 99k.

**Since then main changed under this work.** Re-measure before relying on any number above:
- **M1, stage-scoped compiler identities** (21b2d61fe): stage-store scopes keyed by the identity of their stage, a
  stage table in `src/core/stage_scopes.zig`, and pack format v2.
- **M1b** (a961cc425): a much cheaper pack-catalog and codec read path (`stage_pack.zig`, `persist_codec.zig`), and
  per-scope stage tallies in reports (`MYLANG_PROFILE_DIR`, `storage.scopes`).
- **The debug compiler's allocator** is now `DebugAllocator` in thread-safe mode, about 8% slower. Measure with
  ReleaseFast pins regardless.
- **The shared stage store is opt-in** (`MYLANG_STAGE_SHARED_CACHE`). Keep it unset.
- **The compiler's inner loop is the edit check** (`python3 scripts/edit_check.py`, `CLAUDE.md` "Fast loops"). Use it
  while iterating on compiler code. The complete gate stays the landing check.

## 2. What exists on the paused branches

| Branch | Worktree | State | Merges into main |
| --- | --- | --- | --- |
| `edit-cost/t1` (lane P) | `~/ai/canopy/mylang-fix` | Step 1, position-independent lowering keys (48ae42c2b), committed but not measured or gated. Step 2 is an uncommitted patch. Design C (optimizer) is written. | cleanly |
| `edit-cost/s2` (lane Q) | `~/ai/canopy/mylang-w2-r` | One WIP commit (3389dc8b9) with three exact speedups. Its tests are written but have never been compiled or run. | cleanly |
| `edit-cost/k` (lane R) | `~/ai/canopy/mylang-edit-k` | Two perf commits (14c385bc1, 7c7425026), measured at 99k only. | conflict in `src/core/stage_store.zig` (M1 and M1b) |

Each branch's `experiments/edit-cost-20261028/{P,Q,R}/status.md` ("Session handoff") and `DECISIONS.md` hold the
details. Evidence is in `~/ai/canopy/mylang-evidence-archive/experiments/edit-cost-20261028/{P,Q,R}/`, including lane P's
`step2-refs-memo.patch` and `integration-layout-test.patch`.

A clean textual merge doesn't mean the code still fits. M1 moved the lowering, optimizer and emission scopes onto stage
identities, and M1b changed the pack read path. Every branch must be merged with main, rebuilt and re-measured before
anything else.

## 3. Packages

Run them in three parallel lanes, split by file, so no two lanes edit the same code:
- **Lane A (lowering and optimizer):** T1a, then L2, then C.
- **Lane B (front end):** S2, then B4.
- **Lane C (stage store and keys):** K.

D5's time exit needs both B4 (lane B) and C (lane A).

### T1a. Land position-independent lowering keys (lane A, 4–8 h)

**What it is:** lane P's step 1 (48ae42c2b).
- The lowering key names the discovery counts instead of a running hash over every discovery delta.
- Each artifact records the prefix functions and compounds it names. A restore is refused when one of them differs.
- The scopes are bumped (`lowered-function-v11`, `lowered-header-source-v5`).

**Measured on 99k** (a new-shape type edit, where a record gains a defaulted field): re-lowered functions fell from
3,481 to 140, with output equal to `--no-cache`. The whole-tree retry still runs once; B4 removes it.

1. Merge main into `edit-cost/t1`. Check that the bumped scopes appear in `stage_scopes.zig`'s stage table with the
   right stage; its test fails on an unrouted scope. Rebuild the ReleaseFast pin.
2. **Cost check:** one-line edits at 99k (comment, leaf, hub body, added function) with the main pin and the branch pin.
   The prefix validation on every restore must cost at most about 3% CPU. If it costs more, fix it first.
3. **Type edits:** new shape and same shape at 99k (`experiments/edit-cost-20261028/P/repro_t1.py` on the branch), plus
   one 400k cycle. Report the re-lowered count, fallbacks and stage times.
4. `experiments/frontend-edit-loop-20261026/exact.sh` on both trees; the port's 1,250 tests
   (`mylang test src --jobs 4 --max-frames 30000 --max-steps 4000000000 --max-memory 2G` in the 99k copy); the complete
   gate.

### L2. Memoized declaration references (lane A, 3–6 h)

**What it is:** lane P's step 2 (`step2-refs-memo.patch` in the archive) memoizes each declaration's direct references,
so the lowering key's reach walk (12% of a 400k edit's CPU in S0) stops re-walking shared declarations for every
function.

1. Apply the patch. Split the 253-character line Guardian rejected.
2. Add the missing test: one session used for two functions gives the same keys as two fresh sessions.
3. Measure the lowering-key share with an LBR profile (`perf record --call-graph lbr`, P-core events) at 99k and 400k.
   Land it only if the share drops. Exactness and the gate as in T1a.

### B4. The omission decision sees reached layouts (lane B, 8–14 h, after S2)

**Problem:** after a new-shape type edit, about 140 bodies (at 99k) keep a valid front-end receipt, because their own
names didn't change, but their lowering key did, because they reach the changed record. So the front end omits them,
lowering then needs them, and `src/core/build.zig` (about line 152, `queries.omitted(id)`) turns that into a whole-tree
retry. Lane P's `DECISIONS.md` has a "B4 handoff" section with the measured facts and code pointers.

**Approach (decided):** base the omission on what the previous build's lowering recorded, not on a new closure in the
front end.
- When lowering remembers a function, it also records the names of the records and types the function reached, and a
  digest of each record's typed declaration.
- After declaration collection and before bodies, the front end computes those digests for the current program. An
  omission is valid only when every recorded digest still matches.
- A body whose receipt is valid but whose reach changed is materialized by replaying its stored checked body, not
  re-checked. If replay isn't possible for some body, re-check it and log which happened.

**Keep the whole-tree retry as the safety net,** and keep counting it.

**Exit:**
- New-shape type edits with fallbacks = 0: ten cycles at 99k and three at 400k, from fresh states, with programs equal to
  `--no-cache`.
- Tests:
  - lane P's `integration-layout-test.patch` ("a record that gains a defaulted field re-lowers its users without a
    whole-tree retry");
  - a body with a valid receipt and a changed reach is replayed, not re-checked (counters);
  - an unrelated record change omits as before.

### C. Optimizer reuse across a layout change (lane A, 8–16 h, after T1a)

**Problem:** a new-shape type edit at 99k spends about 2.8 s more in the optimizer than a same-shape edit (3.17 s against
0.39 s). The cause is that `optimizer_shortcut.zig`'s `Candidates.load` and the post-fusion `catalog.layout` check compare
a digest of the *whole program's* compounds and signatures. Any type change anywhere disables every optimizer entry.

**The design is lane P's `DECISIONS.md` §C:** each optimizer entry records the identities of the compounds and signatures
its output mentions, closed over children, plus its callees' signatures. Reuse validates those at their indices,
replacing the whole-program gate.

**This is correctness-sensitive, so before writing code:**
1. Answer §C3's three open questions with code evidence:
   - does the optimizer read any compound or signature that its output doesn't mention by index (for example a layout
     query through a callee, a sized container, or the ownership plan)?
   - does `validDemandSummary` read whole-catalog facts?
   - must the fusion catalog's runtime declarations be part of the reach?
2. Write the answers into `DECISIONS.md`. If any answer can't be covered by the recorded reach, **stop and get the
   owner's review before implementing**.

**Exit:**
- §C4's tests:
  - a green is reused after an unrelated compound changes;
  - a green is refused after a compound it mentions changes;
  - both with output equal to `--no-cache`.
- With B4 landed, D5's time exit: a new-shape type edit under 1.5 s at 99k and under 4 s at 400k, with programs equal to
  `--no-cache`.

### K. Cheaper keys and store reads (lane C, 6–12 h)

**What it is:** lane R's two commits.
- 14c385bc1: stage keys built in a stack buffer; emission receipt hits handled on the coordinator thread; payloads
  backed by a block are not re-hashed on load.
- 7c7425026: buffered BLAKE3 for canonical, emission and stage keys.

At 99k these cut the targeted samples by 26–43%. The halving target wasn't met. M1b has since rewritten the pack read path,
and R's remaining items overlapped it.

1. Merge main into `edit-cost/k` and resolve the `stage_store.zig` conflict: keep M1's stage-identity keys and R's buffered
   stream. Re-run the stage-store, emission and BLAKE3 tests.
2. **Re-profile on today's main first** (LBR at 99k). Keep only R's commits that still win against M1b. Drop the rest.
3. **Decisions R was waiting on:**
   - **D4 (approved):** skipping the payload re-hash for block-backed records is sound, because `loadBlock` verifies the
     block checksum on every read from disk. Keep the test.
   - **D5 (approved, with a test):** skip the per-load `sequence` refresh within one build, so a build reads one consistent
     view. Test that a record another process writes becomes visible on the next build, and that a miss stays a miss.
   - **D3, the 400k exit method:** absolute LBR sample counts from three or more repetitions with ReleaseFast pins. Lane
     O's in-process hooks are not on main.
4. **Exit:** at 99k and 400k, the targeted group's CPU at least halved against today's main (not against b3e5d71ed);
   `exact.sh` on both trees; the port's tests; the gate.

### S2. Whole-program passes (lane B, 6–12 h)

**What it is:** lane Q's WIP commit 3389dc8b9, three exact changes:
- an empty body skips the walks in `call_views` and `frontend_storage_rules`;
- a per-build memo of ownership-proof keys in `ownership_cache`;
- `sema_summaries.invalidateConsumers` as one compressed table.

They measured 15–25% off the S2 phases at 99k in one window, and nothing at 400k.

1. Merge main into `edit-cost/s2`, compile, and run the three tests:
   - `test-core -Dtest-filter=ownership`;
   - `test-units -Dtest-filter=invalidation`;
   - the `declared call views` filter.
2. On a quiet machine, measure the S2 phases (`--timings=json`) at 99k and 400k, three repetitions each. Keep each change
   that saves at least 10% at both sizes; drop the others.
3. **Re-scope from lane Q's per-pass analysis** (its `DECISIONS.md` D1–D5):
   - Attribute `stand_in_planning`, the largest S2 phase (about 0.27 s at 400k), with phase timers inside `Plan.init` and
     `prepareDemand`.
   - Memoize per-function pass results keyed by the typed body digest.
4. **Lane Q's D5 finding:** an added function invalidates every typed ownership proof, because `Catalog.prefix` hashes
   all declarations. It lives in the ownership cache's key, so fix it in lane B if the fix stays within the front end and
   ownership-cache files. If it needs a change to the lowering key, hand it to lane A.
5. **Exit:** the S2 phase group under 0.15 s at 400k for a one-line edit (0.66 s in S0); diagnostics, warnings and programs
   unchanged on the gate corpus and both trees.

### Later: use the cores

`resident-build-server-plan-2026-10-28.md` §4 package C: split the per-function key, lookup and restore work, and the
per-module passes, across cores, with byte-identical output at any thread count. Start it only after the packages above
land, because it changes the same code.

## 4. How to measure

- **Compilers:** ReleaseFast pins built with
  `scripts/build-slot.sh build zig build -Doptimize=ReleaseFast --prefix ~/.cache/mylang/edit-loop-pins/<label>-<sha>`.
  Build one for main at the start and one per package.
- **Trees:** private copies of `~/ai/.home-cache/cache-quick-wins/eda/stage2/mylang` (99k) and
  `~/ai/.home-cache/cache-quick-wins/n24` (400k). Never run two drivers on one copy.
- **One-line edits:**
  `python3 experiments/frontend-cache-audit-20261026/measure.py eda|n24 TREE OUT --bin PIN --timing --reps N --cmds build --scenarios comment_hub,leaf_body,hub_body,type_edit,add_func`.
  Use 3 repetitions at 99k and 2 at 400k, and make tables with `experiments/frontend-edit-loop-20261026/table.py`.
  Iterate at 99k; measure 400k at each package's exit.
- **Exactness:** `experiments/frontend-edit-loop-20261026/exact.sh MYLANG TREE CACHE`, through
  `scripts/build-slot.sh build`. It must print `IDENTICAL program`, `IDENTICAL diagnostics` and `verify-cache exit 0`.
- **Timing:**
  - Time guest builds inside `scripts/build-slot.sh timing …`.
  - Never run `verify_cache.py` inside a timing window: it deadlocks admission. Use its own
    `--timing-window-seconds` instead.
  - Record load with every number, and prefer CPU and P-core instructions over wall time on this shared machine.

## 5. Rules for the implementing agents

- **Setup.** Use the lane's own worktree from §2 (claim it with `git worktree lock --reason`), or a fresh one from main.
  `source ~/.config/mylang/dev-env.sh` before every build. Builds and focused tests go through
  `scripts/build-slot.sh build …`. Read `CLAUDE.md` first: its Guardian rules (≤7 struct fields, ≤6 parameters, `///`
  on pub declarations, straight-line tests, no import cycles, the type-size ratchet) block commits.
- **Every change.**
  - A behavioural change under `src/` ships with its test in the same diff.
  - Every cache key changes exactly when its inputs change. A new key encoding bumps its scope string, and a new scope
    is routed in `stage_scopes.zig`.
  - When unsure whether a key covers an input, include more: a miss, never a stale hit.
- **Before a package is ready:**
  1. `exact.sh` on both trees;
  2. the port's 1,250 tests;
  3. the complete gate (`python3 scripts/verify_cache.py --zig "$ZIG" --profile complete`, never under a slot);
  4. `python3 scripts/edit_check_shadow.py --gate-log PATH` on its log.
- **Landing.** Don't land or push without the owner's go-ahead. Fast-forward main only after a green gate, with main as
  an ancestor.
- **Notes and evidence.** Decisions go in `experiments/edit-cost-20261029/{A,B,C}/DECISIONS.md`, with the question,
  options, evidence, choice and whether it can be reversed. Progress goes in `status.md`. Logs and data go to
  `~/ai/canopy/mylang-evidence-archive/experiments/edit-cost-20261029/`, never into git.
- **Waiting.** Wait for long jobs in the foreground with a bounded wait (`timeout 590 tail --pid=PID -f /dev/null`).
  Report results, not "still running" notices.
- **Shared machine.** Other agents share it. Never kill a process by a pattern that could match theirs. Keep
  `MYLANG_STAGE_SHARED_CACHE` unset. Don't touch timers or the `mylang-services` worktree.
- **Hard stops (report and wait):**
  - any output differing from `--no-cache`;
  - an optimizer or omission rule that can't be shown to cover every input it reads (package C §C3);
  - free space on `/home/epentland/ai` under 25 GB;
  - the machine actively swapping (sustained `vmstat` si/so, not merely full swap).
- **Forbidden files:** `SPEC.md`, `src/core/validate_ownership*.zig`, `proofs/`, untracked files in the primary checkout.
