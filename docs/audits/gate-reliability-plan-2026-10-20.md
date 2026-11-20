# Gate reliability and agent-sized output: plan (2026-10-20)

Status: **proposed** on 20 October. G1 to G9 (§7) are recommendations, taken as
accepted when the user launches the run. Codex implements it. Written against
`main` at `272dcd5f54`, while language wave 2 runs in `~/ai/canopy/mylang-wave2`.

## 1. Summary

Long Codex runs end for reasons that have nothing to do with the code they are
writing. This plan removes four of them:
- the gate can hang;
- the gate can fail falsely;
- its output fills an agent's context;
- the disk fills up.

It changes no language behaviour.

Evidence from 20 October:
- **A test hung a gate for over five hours.** The wave 2 session's 04:46 gate
  (`scripts/build-slot.sh gate zig build test`) had CLI shard 1/6 blocked in
  `accept()` from 04:52 until it was found at 10:05. Its `mylang` child was a
  zombie, and the gate slot stayed held the whole time.
  - The test was NETWORK-ENDPOINT-1 in `test/integration.zig` (`acceptPayload`,
    `acceptBanner`, around line 6618). It accepts with no deadline, and the guest
    had exited, probably because it failed to build against stdlib files that were
    being migrated.
  - Nothing stopped it. A plain `zig build test` has no deadline per test or per
    step, and `verify_cache.py --gate-timeout-seconds` is off by default.
- **A false failure the agent had to learn to ignore.** Wave 2's handoff says that
  editing an embedded stdlib file "can leave a stale `.mylang-cache/core-tests/<test>`
  suite cache that raises `SourceChanged` — delete that directory before believing a
  failure". A changed input should be a cache miss, never an error.
  - The suite cache is `src/core/test_paths.zig` `suiteCache`. The likely place is
    `src/core/tool_identity.zig`, which returns `error.SourceChanged` when a
    refreshed generation differs from a hinted or memoized one (lines 141–144,
    338–349, 651–652).
- **Gate output fills an agent's context.**
  - That one gate's log is 1.6 MB, 20,819 lines, with 120 `failed command:`
    blocks. The pinned Zig build runner prints that block for any step that writes
    to stderr, green or not.
  - The wave 2 session ran 30 complete verifications in about 6.5 hours (00:30 to
    07:03), roughly one every 13 minutes, then stopped because its context was
    exhausted.
  - Its handoff told the next session to run both `zig build test --summary all`
    and `verify_cache.py --profile complete` per batch. The last verification
    executed 40 of 48 actions in 187 s, so each landing may pay for the same tests
    twice.
- **Flaky tests.** Recent reports record failures that passed on rerun:
  - `verification_measurement_test`'s holder-loss case (wave 3 fixes);
  - `verify_cache_test`'s shared-store determinism mismatch (wave 3 fixes) and its
    gate-slot timeout (wave 3);
  - `fuzz_coverage_test`'s worker-cancel timeout (wave 3);
  - a `facts.shape` general-protection fault in a busy `test-core` run (CE, 8
    October).
- **The disk filled to 95%,** below wave 2's 25 GB hard stop. Three causes:
  - The per-user store's retention timer has not fired since 16 October 21:14.
    `scripts/systemd/mylang-core-store.timer` schedules only with `OnBootSec` and
    `OnUnitInactiveSec`. After the systemd user manager restarted on 16 October
    21:26, the service had never gone inactive under the new manager, so
    `systemctl --user list-timers` shows no next trigger. The store is 12 GB
    against its 10 GiB cap, and `units-v1/work` holds 475,075 idle claim files.
  - `scripts/prune-caches.sh` removes claims with one bash loop iteration per
    file, so on that directory its store phase did not finish in 15 minutes.
  - 88 worktrees carry `prune-keep` markers with no owner, reason or expiry, so
    the pruner can never reclaim them.
  - **Both systemd services had also lost their checkout.** The installed
    `mylang-core-store.service` and `mylang-nightly-integration.service` run from
    the detached checkout `~/ai/canopy/mylang-services`, and it no longer existed.
    The nightly integration failed at 03:02 on 20 October with `203/EXEC`.
  - **What was done on 20 October,** at the user's request:
    - recreated the checkout (`git worktree add --detach … main`, at `791e706c47`);
    - gave it a `prune-keep` marker with an owner and a reason;
    - ran the store service once, which succeeded in 23 s and gave the timer a next
      trigger.
  - That run removed nothing. It reported `inventory_complete: false`,
    `skipped_incomplete: true` and `unmet_budget: true`: it inventoried 1,272,442
    entries (6.9 GB), changed 19,554 ledger rows, and evicted nothing because the
    inventory was incomplete.

## 2. Design

### 2.1 No hangs: deadlines at three levels

1. **Per test, in the protocol proxy.** `scripts/verification_native_telemetry.py`
   already sits between the build runner and every compiler test binary. It sees
   `test_started` and `test_results` and knows each test's name.
   - Give it a deadline for one test's interval. When the deadline passes, the
     proxy:
     1. writes one line to stderr:
        `test deadline: <root>::<test> ran <N> s (limit <L> s); killed`;
     2. kills the whole process tree, starting the child with
        `start_new_session=True` and using `killpg`, so a test's `mylang` and `sh`
        children die too;
     3. records the test as `timed_out` in its telemetry document;
     4. exits non-zero.
   - The proxy's docstring promises that the runner owns verdicts. This changes that
     promise, and the docstring must say so.
2. **Per step, in `build-env project`.** Every test-graph command runs through
   `withTools` → `build-env project` (`build_env.zig`), including the Python
   drivers, guest suites and Guardian. Give it a wall-clock deadline per command
   that kills the process group and prints the step's command in one line. This
   catches what the proxy cannot see.
3. **Per gate, in the coordinator.** `verify_cache.py` gets a default
   `--gate-timeout-seconds` and `--build-timeout-seconds` (G3). `0` keeps the old
   unbounded behaviour.

Deadline values come from the run's own telemetry, not guesses (G1, G2).
- **Environment variables:** `MYLANG_TEST_DEADLINE_SECONDS` and
  `MYLANG_STEP_DEADLINE_SECONDS`, with `0` meaning off. Add them to
  `src/environment_identity.zon` as placement variables, so changing a deadline
  never invalidates a receipt.
- **Hitting a deadline:** it is a failure, never a skip.

The tests themselves must also fail fast, without waiting for the deadline:
- NETWORK-ENDPOINT-1's accept helpers poll the listening socket with a timeout and
  check whether the guest has exited, through one shared helper.
- Audit every blocking wait in `test/` and in the Zig test roots under `src/`:
  `accept`, a read from a child's pipe, `wait` on a child, and lock acquisition.
  Bound each one the same way. Record the audit's list in `status.md`.

`scripts/build-slot.sh` gets a status listing: each held slot's holder, command,
worktree and age. A stuck gate is then visible in one command.

### 2.2 No false failures from a changed input

1. Reproduce the wave 2 symptom as a named test:
   1. build the affected core test;
   2. edit an embedded stdlib file;
   3. rerun the test;
   4. require the fresh result, not `SourceChanged`.
2. Find the cause, then fix it under one rule: a changed input is a miss and is
   recomputed. `SourceChanged` is kept only for a file that changes during a
   single capture, and even then the capture retries once before reporting it.
3. Search the other caches the gate uses for the same pattern: suite caches,
   receipts and inventory hints. Log each one you check.

### 2.3 Output an agent can read

- **One command is the gate for agents:** `python3 scripts/verify_cache.py --zig
  "$ZIG" --profile complete`.
  - Its inventory must cover everything `zig build test` runs; the verification
    registry already fails when an action is unregistered.
  - Measure whether running `zig build test` first saves or doubles work (B0).
    Then write the rule in `CLAUDE.md`'s "Full gate" section and in
    `docs/tooling/many-agents.md` (G5).
  - `zig build test` stays supported for people.
- **Default terminal output (G4):**
  - The coordinator streams the build output to a log under
    `.mylang-cache/verification-v3/last-logs/` and prints a summary.
  - **A green run** prints at most 30 lines: the verdict, elapsed time, actions
    reused and executed, the slowest three actions, and the log path.
  - **A red run** prints at most 60 lines, plus 10 for each further failure. For
    each failing action it shows: the action ID, the failing test names, the first
    assertion or error lines with `file:line`, the test-deadline line if any, and
    the log path.
  - `--verbose` restores the full stream.
- **Green steps write nothing to stderr.** Find every step that writes to stderr on
  success (B0 counts them) and send that text to its log instead. Add a test that
  fails when a green step's stderr is non-empty. That way the build runner's
  `failed command:` block appears only for a real failure, in both
  `zig build test` and the coordinator.
- **Plain `zig build test` logs:** `scripts/gate_summary.py LOG` prints the same
  summary for a log someone already has. This is a reader, not a second gate.

### 2.4 Flakes

Handle each recorded flake (§1) the same way:
1. Reproduce it under load, for example several copies at once, a CPU hog, or a
   slot held elsewhere.
2. Fix the cause. These are mostly wall-clock timeouts in tests of the
   coordinator's own concurrency, so replace a sleep or deadline with an event.
3. Add a test that drives the race deterministically.

If a flake cannot be fixed within the bound, quarantine it:
- it is skipped with a reason that names its `DECISIONS.md` entry;
- it still runs in the nightly integration timer.

Log the quarantine. The gate never reruns a failure until it passes.

### 2.5 The disk

- **The timer** gets an activation-relative trigger (`OnActiveSec=`) or a calendar
  one (`OnCalendar=*:0/15`), so it always has a next run. Add a test that parses
  every unit in `scripts/systemd/` and refuses a timer whose triggers all depend on
  a prior run.
  - Installing the fixed unit on this machine is not part of the run. Put the
    one-line install command in `REPORT.md` (G7).
- **Claim pruning** moves out of the bash loop into the leased Python collector
  (`scripts/core_store_gc.py`), in batches. Add a fixture of 500,000 idle claims
  that it must clear in under 60 s.
- **Keep markers** carry `owner=`, `reason=` and `until=YYYY-MM-DD`.
  - `scripts/prune-caches.sh --list-kept` prints each kept worktree with its
    marker, last activity and cache size.
  - A marker past its date, or one with no fields, is reported. It is never
    deleted.
  - Existing empty markers stay; the report lists them for the user.
- **The store must reach its cap.**
  - Find out why the inventory stays incomplete, and how many timer runs it takes
    to complete, using the service journal (`journalctl --user -u
    mylang-core-store.service`). Make scheduled runs converge within a day, still
    under their leases.
  - A run that ends incomplete or over budget must say so in one line that the
    pruner's report and `--list-kept` show.
- **A service whose checkout is missing fails loudly.**
  - `scripts/systemd/install-core-store-timer.sh` and the nightly installer
    register the checkout through `scripts/service_worktree.py`.
  - The pruner never removes a registered service checkout.
  - The installed units on this machine predate that lease and run their scripts
    directly. Reinstalling them is the user's step; put the command in `REPORT.md`.

## 3. Batches

| Batch | Contents | Lands when |
| --- | --- | --- |
| B0 | Measure, with nothing changed: lines and bytes printed by a green and a seeded-red run of `zig build test --summary all` and of the complete verification; the steps that write stderr on green; per-test intervals from telemetry (maximum and 99th percentile per root); the cost of `zig build test` followed by the complete verification, against the verification alone, after a real `src/` edit | the numbers are in `status.md` and choose G1 to G4 |
| B1 | §2.1: proxy deadline, step deadline, coordinator defaults, the accept helpers and the blocking-wait audit, the slot status listing | an injected hang fails within its deadline with the one-line message, leaves no process behind, and releases the slot; complete verification passes |
| B2 | §2.2 | the repro is a named test with the fresh result; complete verification passes |
| B3 | §2.3 and the docs | a green complete verification prints at most 30 lines; a seeded failure prints the test name, `file:line` and log path within the budget; no green step writes stderr; complete verification passes |
| B4 | §2.4 | each flake is fixed with a deterministic test, or quarantined and logged; the coordinator's own tests pass 20 consecutive runs on a loaded machine |
| B5 | §2.5 | the timer test passes; the 500,000-claim fixture clears in under 60 s; `--list-kept` lists every kept worktree; the store's scheduled runs reach a complete inventory and its cap, measured from the journal; a missing service checkout fails with one clear line; complete verification passes |

Order: B0, B1, B3, B2, B4, B5. B1 removes the costliest failure and B3 the
context cost. Each batch lands on its own.

## 4. Done criteria

- **K1.** No hang outlives its deadline. A test that blocks forever, a driver that
  blocks forever and a guest that never connects each fail with one line naming
  them, and no process is left behind.
- **K2.** No input change is reported as `SourceChanged`. The stdlib-edit repro is
  a named test.
- **K3.** Output fits G4's budget. Agents have one gate command, written in
  `CLAUDE.md` and `docs/tooling/many-agents.md`.
- **K4.** Every recorded flake is fixed or quarantined with a logged reason.
- **K5.** The store timer always has a next trigger, scheduled runs bring the store
  under its cap, claim pruning is bounded, a missing service checkout fails loudly,
  and every kept worktree's marker is listed.
- **K6.** No gate is relaxed and no test is deleted or weakened without a logged
  reason. Complete verification and formatting pass at every landing.

## 5. How it fits

- **Wave 2 is running** in `~/ai/canopy/mylang-wave2` and lands on `main` often.
  - It edits the front end, the stdlib, `tests/lang`, `test/fix_cli_test.zig` and
    generated migrations across the corpus.
  - This run edits the build and verification scripts, `build.zig`,
    `build_test_inputs.zig`, `build_env.zig`, `src/environment_identity.zon`,
    `src/core/tool_identity.zig`, `test/integration.zig`'s accept helpers,
    `scripts/systemd/` and the tooling docs.
  - The overlap is small; merge `main` before each landing.
  - Never touch wave 2's worktree, and never kill its processes. One exception:
    the hung 04:46 gate (pid 980889), which wave 2 was told to kill. If it is still
    alive when B1 starts, report it; do not kill it.
- **The checked-docs follow-up** (`docs/audits/checked-docs-followup-plan-2026-10-20.md`)
  runs after wave 2. Its F1 makes `release check` reuse test receipts. This run
  does not touch `release check`.
- **Guardian** is `../guardian-zig` and stays untouched. The per-test deadline
  lives in the proxy, not in Guardian's runner, for that reason.

## 6. Risks

- **A deadline that is too tight fails a slow but healthy test.** G1 sets it from
  measured maxima with a wide margin, and the variable can raise it.
- **Killing a process group can reach too far.** Only the proxy's or step's own
  child session is killed, never a process outside it. Add a test that a sibling
  survives.
- **A summary can hide the line that matters.** The log path is always printed,
  `--verbose` streams everything, and the summary's extraction is tested against
  real failure logs from B0.
- **Quarantine can become permanent.** Each quarantine names its decision and runs
  nightly. `REPORT.md` lists them.

## 7. Decisions (recommended, accepted at launch)

- **G1.** Per-test deadline: 3× the slowest test observed in B0, with a floor of
  300 s, set per test root if the roots differ widely. The variable is
  `MYLANG_TEST_DEADLINE_SECONDS`, and `0` turns it off.
- **G2.** Per-step deadline: 3× the slowest step observed in B0, with a floor of
  30 minutes. The variable is `MYLANG_STEP_DEADLINE_SECONDS`.
- **G3.** Coordinator defaults: a gate timeout of 90 minutes and a build timeout of
  20 minutes, both excluding queue time. `0` turns either off.
- **G4.** Output budget: 30 lines for green; 60 lines for red, plus 10 per further
  failure; full logs on disk; `--verbose` for the stream.
- **G5.** The complete verification is the one gate command for agents. This run
  may edit `CLAUDE.md`'s "Full gate (run before finishing)" and "Caches and
  worktrees" sections, and no others.
- **G6.** A flake is fixed or quarantined, never auto-rerun to green.
- **G7.** Systemd units are fixed and tested in the repo. Installing them on this
  machine, and any change under `~/.config/systemd`, is left to the user.
- **G8.** Keep markers carry owner, reason and expiry. The pruner reports expired
  markers and never deletes a kept worktree.
- **G9.** No behaviour change to the compiler's output, the language or `mylang
  test` verdicts. The only verdict change is that a hang becomes a failure.

## 8. Operating rules and launch instruction for Codex

- **Autonomy.** Decide, log in `experiments/gate-reliability-20261020/DECISIONS.md`
  (the question, the evidence, the choice and whether it can be reversed), and
  continue.
  - Commit at every step, with a progress section in `status.md`.
  - Investigate a gate failure for up to about 6 to 8 h.
- **When your context runs low,** commit a "Session handoff" section in `status.md`
  and stop. That is a handoff, not a blocked run.
- **Hard stops.** Stop and ask only for:
  1. a change to `../guardian-zig`, or relaxing a gate on `main`;
  2. deleting or weakening a test without a logged reason;
  3. touching another run's worktree, branch or processes, or anything under
     `~/.config/systemd`;
  4. a failure that cannot be fixed within the bound;
  5. free space on `/` under 25 GB, or the machine swapping.
- **Branches and landing.**
  - Work in the worktree `~/ai/canopy/mylang-gate-reliability` on branch
    `gate-reliability/integration`, created from `main`.
  - Land each batch by fast-forward from the primary checkout,
    `git -C ~/ai/canopy/mylang merge --ff-only gate-reliability/integration`. Do it
    only after `python3 scripts/verify_cache.py --zig "$ZIG" --profile complete`
    passes, and only when `git -C ~/ai/canopy/mylang status --porcelain` lists no
    tracked change.
  - If `main` has moved, merge it, verify again, then fast-forward. Never push.
- **Files.**
  - `CLAUDE.md`: only the sections G5 names.
  - `SPEC.md` is frozen.
  - No `selfhost/` edits.
  - Untracked files in the primary checkout belong to other sessions; leave them
    alone.
- **Machine rules from `CLAUDE.md`.**
  - `source ~/.config/mylang/dev-env.sh` in the worktree.
  - Builds and focused gates go through `scripts/build-slot.sh`, but never wrap
    `verify_cache.py` in it.
  - Caches and `TMPDIR` go under `~/.cache`, never `/tmp`.

Launch text:

```text
Implement docs/audits/gate-reliability-plan-2026-10-20.md: per-test, per-step and
per-gate deadlines so a hung test fails within its limit instead of holding the
gate, the SourceChanged false failure, a short default summary from the complete
verification as the one gate command for agents, the recorded flaky tests, and the
disk retention fixes (the store timer that stopped firing on 16 October, bounded
claim pruning, keep markers with owner and expiry). Read the plan fully, then
CLAUDE.md, docs/tooling/many-agents.md and scripts/verification_native_telemetry.py.
G1 to G9 are accepted. Decide, log in
experiments/gate-reliability-20261020/DECISIONS.md, and continue; stop only for
the hard stops in section 8. Create the worktree ~/ai/canopy/mylang-gate-reliability
on branch gate-reliability/integration from main and run the batches in the order
of section 3: B0, B1, B3, B2, B4, B5. Language wave 2 is running in
~/ai/canopy/mylang-wave2: never touch that worktree or its processes, and merge
main before each landing. Land each batch on main by fast-forward from the primary
checkout after a green complete verification; never push. Do not touch
../guardian-zig, SPEC.md, selfhost/, ~/.config/systemd, untracked files in the
primary checkout, or any other run's branch; edit CLAUDE.md only in the sections
G5 names. When your context runs low, commit a "Session handoff" in status.md and
stop. Commit at every step with a progress section in status.md, and finish with
REPORT.md.
```

## 9. Under load (added 2026-10-28)

**Why.** The complete gate fails on this shared machine whenever it is busy. Of six compiler-edit gates on 28 October
(`experiments/gate-schedule-20261028/REPORT.md` on branch `gate/shard-schedule`), one passed (741 s). Four failed on the
300 s per-test deadline, and one hit the 90-minute gate deadline (5,423 s). The golden replay causes most of it: four
tests, each a whole partition of the corpus, take 147–219 s on a quiet machine. Some core tests (`ce2_*`, a semantic-cache
retention test) and up to 32 doc examples at 120 s also ran out of time. A deadline is meant to catch a hang, but here
it catches load.

**Package G** (lane S, Claude with a Haiku lane, branch `gate/reliability` in `~/ai/canopy/mylang-gate`, built on lane
N's `gate/shard-schedule`):
1. **Split the golden replay** so that no single test runs a long partition: one case, or a small bounded group, per
   deadline interval. Keep the coverage test (every recorded case and explicit skip still runs exactly once) and the
   source-preparation reuse.
2. **Deadlines that tolerate load and still catch hangs.** Measure the options and choose: CPU-time limits, limits
   scaled from each test's recorded median, a limit that grows with load, or progress heartbeats that reset the
   interval. Apply the choice to the native tests and the doc examples. A hang must still fail in bounded time, and
   hitting a deadline stays a failure, never a skip or a silent rerun.
3. **Find what makes the core tests and doc examples slow** under load, and split or speed up any that take most of
   their limit on a quiet machine.
4. **Land lane N's reservation change** (`c306d7ca2`, `0de8c2dfc`) with it, after checking every lowered ceiling
   against measured peaks with margin (the doctest driver peaked at 925 MiB under a 1 GiB reservation, which is too
   tight).
5. **Measure:** compiler-edit gates under ordinary load (other agents running) and in a quiet window, before and
   after, recording overlapping gates and timers per run. Regenerate the shard plans once three passing runs exist.

**Exit.** Three consecutive compiler-edit gates pass under ordinary load. No test needs more than half its limit on a
quiet machine. A deliberate hang test still fails within its bound. The before and after wall times, and the core and
CLI shard start times, are reported. The timers in `mylang-services` belong to another session and are not changed
here.
