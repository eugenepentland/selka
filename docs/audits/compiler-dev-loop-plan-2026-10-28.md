# Compiler dev loop (plan, 2026-10-28)

**Status:** written on 2026-10-28 at the user's request: "speed up the compiler dev loop first, and then we can continue
with the cache work after that". The edit-cost lanes (P, Q, R of
`docs/audits/resident-build-server-plan-2026-10-28.md` §8) are paused at committed checkpoints with handoff notes, and
resume after this plan.

## 1. The loop today

An agent changing the compiler edits `src/`, rebuilds, runs focused tests a few times, then runs the complete gate
before its change can land.

| Step | Time | Source |
| --- | --- | --- |
| `zig build` after an edit | 6–14 s | gate profile 28 Oct; lane N's runs |
| Focused test (`focused_test.py`, `affected_tests.py`) | 8–14 s | EC0, 25 Oct |
| Complete gate after a compiler edit | 207 s median (25 Oct); 448 s at load 6–8; 741 s in lane N's only passing run | EC0; `gate-profile-20261028`; `gate-schedule-20261028` |
| Complete gate, unchanged tree | 16 s | 25 Oct |

The gate is the cost that matters, and on a busy machine it is also unreliable. Of six compiler-edit gates on
28 October, one passed. Four failed on the 300 s per-test deadline and one hit the 90-minute gate deadline. Package G
(below) is already fixing that.

What the gate spends its time on (25–28 October measurements):
- About 75% of test-seconds are tests that start `mylang`: guest suites, the golden replay, doctest examples, CLI
  and core tests that build programs.
- Every compiler cache key includes the compiler identity, a token digest of all compiler sources. After any token
  edit, every test program's front end and Core passes run cold. Unit objects are content-keyed and survive when their
  LLVM text is unchanged. A narrower runner identity already exists (`build_identity_rules`), so subset identities are
  an established pattern here.
- Schedule: core shards started at about 150 s and CLI shards at 366 s, because steps declared far more memory than
  they use. Shard times were imbalanced (core 46–288 s), and the doctest took 378 s at load 6–8.
- Test selection by coverage (the edit-check plan, paused by the user on 25 October) measured a median single-file
  edit at 44% of test time, bimodal.

## 2. Goal

- A compiler-edit gate on an ordinarily busy machine passes every time, with no deadline failures, and takes under
  300 s (from 450–740 s).
- An edit confined to one stage (for example the back end) takes under 200 s.
- These are estimates; M0 sets the real targets.

## 3. Packages

| Package | Work | Exit | Estimate |
| --- | --- | --- | --- |
| **G** | **A gate that passes under load** (running: lane S, `docs/audits/gate-reliability-plan-2026-10-20.md` §9). The golden replay is split, deadlines are on CPU progress with a wall backstop, the doc-example limit is raised, slow core tests are split, lane N's lower memory reservations land, and shard plans are regenerated. | As in §9: three consecutive compiler-edit gates pass under ordinary load. | in progress |
| **M0** | **Measure where a compiler-edit gate goes**, on G's branch. One gate inside a timing window (quiet) and one under ordinary load. Per action: wall, CPU and the critical path (what ends last, and what it waited for). Per test: the top 50 by CPU. For guest suites, golden and doctest: each program's CPU split into compiler (front end, Core passes, LLVM, link) and running it. The share that is cold only because the compiler identity moved: rerun the same gate with the same new compiler and warm compiler caches but forced verdicts (`--force`), and take the difference. | A ranked table of levers in seconds of wall time and CPU, with M1 and M2 sized. | 3–5 h |
| **M1** | **Stage-scoped compiler identity**, if M0 shows cold rebuilds are a large share. Each cache is keyed by the identity of the code that produces it. Front-end records use the front end's import closure, lowering and optimizer entries use theirs, emission its own. Unit objects stay content-keyed. Closures come from the Zig import graph, like the runner identity, and a file shared by two stages is in both. | A back-end-only edit keeps the front-end records warm through a gate, and an edit to a shared file moves every identity that includes it (tests). Output equals `--no-cache` on the corpus and both port trees. Gate wall time and CPU saved, by M0's method. | 16–30 h |
| **M2** | **The long poles** M0 names, for example the doctest (one driver, 378 s at load), the language suites' two runs (debug, and release with leak checks) and golden. Use run receipts keyed by program bytes and runtime identity, as `mylang test` already has, so an example whose program did not change does not run again. Split whatever is on the critical path. | Each change: its seconds saved on the critical path, the same tests run, and the same failures caught (a mutated program still fails). | 8–16 h |
| **M3** | **Test selection for the inner loop** (edit-check EC2–EC5). It never replaces the landing gate. | Paused by the user on 25 October; resumed only if the user asks. | — |

Order: G and M0 now; M1 and M2 after M0 reports, chosen by its numbers. Total, without M3: about 30–50 agent hours
beyond G.

## 4. Lanes and rules

- Claude coordinates Haiku lanes and lands their work. Lane S keeps G in `~/ai/canopy/mylang-gate`. Lane T runs M0
  in `~/ai/canopy/mylang-devloop` on branch `devloop/m0`, built on `gate/reliability`; then M1 or M2 by Claude's
  choice.
- Decisions and status go in `experiments/compiler-dev-loop-20261028/` (`DECISIONS.md`, `status.md`, `REPORT.md`).
  Evidence goes in `~/ai/canopy/mylang-evidence-archive/experiments/compiler-dev-loop-20261028/`.
- A timed gate runs inside `scripts/build-slot.sh timing …`; one timing window at a time across the machine. Lane S
  also measures gates, so record which windows were whose.
- Lanes don't land. Claude reviews, gates and lands. A behavioural change ships with its test. Guardian rules,
  machine rules, forbidden files and hard stops are as in `docs/audits/frontend-edit-loop-plan-2026-10-26.md` §7.
- A change that makes a real failure pass (a skipped test, a hidden rerun, a weaker check) is a hard stop.

## 5. After M0 (decided 2026-10-28)

**Where things stand.**
- The stage-store lock fix (304dac54e) and G (483319a71) are on main.
- M0 measured a compiler-edit gate at 235 s on a quiet machine, using 2,088 s of CPU
  (`experiments/compiler-dev-loop-20261028/`, branch `devloop/m0`).
- About 530 s of that CPU is cold only because the compiler identity moved, whichever stage the edit touched.
- Test programs spend about 600 s compiling and about 4 s running. So M2's run receipts are dropped, and M2 becomes a
  shard-balance check: core ended at 263 s and CLI at 245 s, against a floor of about 105 s on 20 threads.
- The user chose to run M1 and test selection in parallel, plus the balance check.

**Lane T (balance and compile split, first).**
1. A timed compiler-edit gate on main (`verify_cache.py --timing-window-seconds`). It compares the shard end times
   with M0's G1b under G's regenerated plans. If one root still ends far after the others, the lane proposes a split.
2. The per-suite compile split for M1: of the compiler-process CPU after a compiler edit, how much each suite starts
   (core, unit, CLI, language debug and release, golden, doctest, guest), and per stage (front end, Core passes, LLVM
   emission, `zig cc`, link). Take it from `--report` and `--timings` of the spawned builds, or from a
   `MYLANG_TEST_COMPILER` shim.

**Lane V (M1, stage-scoped compiler identity).**
- First step: write the design in `DECISIONS.md`, using lane T's split, and wait for Claude's review before changing
  any cache key. The design covers:
  - the stages and the caches each one produces;
  - each stage's closure over the Zig import graph, from a root file per stage, and how injected implementations
    (callbacks, vtables, options passed at run time) are included;
  - which keys move from the compiler identity to a stage identity;
  - the cache-format scope bumps;
  - how a missing file in a closure would show up.
- Validation: every file whose code runs during a stage is in that stage's closure. Check this against lane W's
  per-test coverage map, or a stage-tagged coverage run.
- Exit (§3): a back-end-only edit keeps the front-end records warm through a gate; an edit to a shared file moves
  every identity that includes it; output equals `--no-cache` on the corpus and both port trees; the gate time and CPU
  saved, measured by M0's method.

**Lane W (test selection, EC2–EC5 of `docs/audits/edit-check-plan-2026-10-25.md`).**
- It builds on branches `edit-check/ec1` (coverage variant, collection, map) and `edit-check/ec0` (replay set,
  inventory, timings), merged with main.
- The coverage map is refreshed at current main first. The map of 25 October was built at 6edf34922.
- EC2 (impact tool), EC3 (`zig build edit-check`), EC4 (replay and mutants) and EC5 (workflow) follow, as written.
- Changes to that plan:
  - Selection is reported by test time as well as by count.
  - EC4's binding speed target is the median edit check from save to verdict, at most 60 s on a quiet machine.
  - Until Claude approves Guardian's exact test-list option (D4), Zig roots use `--guardian-test-filter`; nothing in
    `../guardian-zig` changes without that approval.
  - EC5's `CLAUDE.md` change is proposed in `DECISIONS.md` and made by Claude after EC4's targets hold.

Lanes T, V, W and U (the take_first crash) are the machine's four build-heavy agents.
