# Caching follow-up: fast-forward main, then close the open rows (2026-10-14)

Prepared 14 October 2026 as the execution handoff for one coordinator and up to
ten workers, F01 to F10. It follows the
[caching closeout](caching-closeout-10-agent-plan-2026-10-13.md), whose
[acceptance report](../../experiments/caching-closeout-20261013/acceptance.md)
and closing companion
(`/home/epentland/ai/canopy/mylang-caching-closeout-20261013-w10/.tmp/w10-rounds/closing/acceptance.md`)
recorded K3 and K5 passed, K1, K2, K4, K6, K7 and K8 failed, and K9 not
qualified on integration commit
`1aabd7bd063527e34fe53e77a20c3f8046710073`. This plan first puts that commit on
`main`, because the host already runs its store layout, then fixes the causes
the closing evidence points to.

## Why main moves first

The closeout installed a store-maintenance timer that migrated 1,262,340 unit
objects into `units-v1/<ab>/<key>` shards and removed their flat names. The
store now has 256 shard directories and one flat file. Compilers built from
`main` (`76180573b`) look objects up only at `units-v1/<key>`
(`src/core/unit_cache.zig` `Store.path` on main), so every agent building with a
main compiler has lost its warm unit cache, and anything such a compiler writes
is moved and its flat name removed on the next timer run, every 15 to 18
minutes. The integration compiler reads the sharded path, then the flat one.
Both systemd services also run scripts from the closeout's integration
worktree, and the nightly service verifies that branch, not `main`.

## Step 0 — coordinator, before any worker starts

1. Confirm local `main` is still `76180573b5c2cd8081cf8218e374166eb9677c44` and
   that `claude/caching-followup-plan-20261014` is `1aabd7bd0` plus this
   document. If `main` has moved, stop and ask the user.
2. In the main checkout `/home/epentland/ai/canopy/mylang-debug-speedup-main`,
   record `git status --short`, then
   `git merge --ff-only claude/caching-followup-plan-20261014`. The checkout
   carries another party's uncommitted `docs/README.md`,
   `docs/audits/zero-rc-closeout-10-agent-plan-2026-10-11.md` and untracked
   `docs/audits/zero-rc-closeout-10-agent-plan-2026-10-12.md`; the fast-forward
   does not touch them. Confirm the same three entries afterwards. Do not stash,
   commit or modify them. Nothing is pushed.
3. Create a service worktree that only the timers use:
   `git worktree add --detach /home/epentland/ai/canopy/mylang-services main`.
   Reinstall both units from it with `scripts/systemd/install-core-store-timer.sh`
   and `scripts/install-nightly-integration-timer.py`, so `ExecStart` and
   `WorkingDirectory` name the service worktree. Until F08 makes the services
   refresh it themselves, the coordinator moves the service worktree to `main`
   (`git -C /home/epentland/ai/canopy/mylang-services checkout --detach main`)
   after every fast-forward, so the nightly run verifies `main`.
4. Run each service once by hand (`systemctl --user start …`), keep the logs,
   and check `systemctl --user cat` shows only the service worktree. The
   closeout integration worktree is then unreferenced; leave it in place until
   the user removes it.
5. Record in `status.md` and the final report that compilers built before the
   fast-forward still miss the sharded store and should be rebuilt from `main`;
   frozen measurement compilers hit again once F08 lands (below).
6. Pin `C1` = the new `main` commit and create
   `experiments/caching-followup-20261014/status.md` (base, owners, claimed
   files and functions, fixed commits, rounds, evidence, open rows).

## What the closing evidence shows

| Row | Closing value | Cause the evidence points to |
| --- | --- | --- |
| K1 | 687.7 s median (C0 623.7 s; R1 227.9 s and R2 243.6 s passed) | Every test-binary compile was cached, so the time is test execution. Load average was 13–16 from processes outside admission (a headless Chrome at about 7 cores, a netlisp server) before the request began and reached 58 on 20 CPUs when all 18 shard roots started together at 250 s; every shard ran 2–2.5× its R3 time, and core shard 5 started only at 551 s. The verifier adds `--maxrss 8 GiB` but no `-j`, Zig's runner does not enforce aggregate RSS for resumed jobs, and each shard's own lanes (`src/wiring/core_runner.zig` `lanesFor`) and every `mylang` child use the full CPU count. Golden checks took 151 s (R3 55 s). Receipt publication inside the gate slot took 50.7 s (R3 0.8 s) |
| K1, K2 | publication 50.7 s | `finalize_gate` (`scripts/verify_cache.py` around `:1700-1730`) passes `publication_unchanged` (`authority()` and `check_all(snapshots)`, a full snapshot revalidation) to `fuzz_campaign_store.publish_success`, which calls it two or more times per group, for about 41 groups. With sharing off (R3) the shared path never ran |
| K2 | 18.5 s, zero admissions | Each warm request hashes 29,178 files (2,338,626,807 bytes) and makes 3,245,730 metadata observations, with zero digest and zero snapshot reuse (`C1-summary.json` `snapshot_statistics`) |
| K4 | default 9/10, scheduler 0/10, 0/41 groups attempted exactly once | Default admission has no in-flight deduplication; the opt-in scheduler failed because mocked coordinator fixtures inherited the scheduler mode, Guardian refused watch authority (three requests reported inotify watch exhaustion with `max_user_watches` already 1,048,576), and a shadow transition and two elapsed bounds failed with unresolved causes |
| K6 | installed edit 7.4 s gated, 7.3 s ungated; watch 1.25–1.40 s | Ungated is as slow as gated, so Guardian is not the cost; the private Guardian makes gated edits 12.5 s; watch mode already meets about 1 s |
| K7 | 10,750,502,313 B against a 10,737,418,240 B cap | Eviction stops at the cap, so builds between runs push the point-in-time inventory just over it |
| K8 | 7/10 consecutive gates; recurring opt-in worker failures | The same two coordinator assertions and 12 errors in two opt-in workers (fixture isolation, as K4); a fuzz-family helper readiness failure (`crashed=True`); the large-diff hook passes only with the Guardian branch |
| — | unit shard balance 1.46–1.55 (target 1.25) | The plan is built from one run's weights |

## Targets for this round

K1 to K9 keep their definitions with three clarifications, which the user
approves by approving this plan:

- **Timing qualification under external load.** Processes outside admission
  cannot be stopped. A timed sample qualifies only if, in the 60 s before it
  starts, the host's one-minute load average is below 4 and CPU pressure
  `some avg60` is below 10 %; record both through the sample. Otherwise wait, up
  to two hours, and report the sample as not qualified rather than accepting it.
- **K6.** The supported inner loop is `zig build --watch -fincremental` per
  worktree, with a clean build before gating: a one-line compiler edit installs
  in at most 1.5 s. The ordinary `zig build` after a one-line edit is reported
  and must be at most 5 s.
- **K7.** The bound is held after every maintenance run: eviction removes down
  to 90 % of the cap whenever the inventory exceeds it.

## Ownership and operating rules

Unchanged from the closeout plan: the coordinator alone edits `build.zig`,
`build_test_inputs.zig`, `build_verification.zig`, `build_identity.zig`,
`guardian.toml`, `SPEC.md`, `CLAUDE.md` and the development-loop docs;
`scripts/verify_cache.py` is claimed by function as listed below; only F06
changes `guardian-zig`, on its own branch, and nobody updates the sibling
checkout; one worktree and branch per worker from `C1`
(`codex/caching-followup-20261014-fNN`) and one integration branch
(`codex/caching-followup-20261014-integration`); `source
~/.config/mylang/dev-env.sh`, private `ZIG_LOCAL_CACHE_DIR`, on-disk `TMPDIR`;
builds through `scripts/build-slot.sh build`; `verify_cache.py` run directly;
fixed SHAs and a `handoff.md` per worker under
`experiments/caching-followup-20261014/FNN/`; nobody pushes; only the
coordinator integrates.

Merging the follow-up integration branch into `main` at the end is authorized
as a fast-forward when R4 passes its complete verification, and only as a
fast-forward. Merging the Guardian branch into `guardian-zig` stays the user's
decision.

## Workers

| Worker | Rows | Responsibility |
| --- | --- | --- |
| F01 | K1 | Gate CPU budget and shard order |
| F02 | K1, K2 | Batched receipt publication |
| F03 | K2 | Warm-path digest reuse |
| F04 | K4, K8 | Scheduler backend correctness and the shadow day |
| F05 | K4, K8 | Coordinator subscription and fixture isolation |
| F06 | K6, K8 | Guardian branch |
| F07 | K6 | Installed-edit path and the watch loop |
| F08 | K7 | Store policy and compatibility with older compilers |
| F09 | K1–K9 | Measurement, load qualification and test reliability |
| F10 | — | Independent review of every reuse or publication change |

If fewer than ten sessions are available, run F01/F02/F03/F09 first, then
F04/F05/F08/F10, then F06/F07.

### F01 — Gate CPU budget and shard order (K1)

**Own:** `lanesFor` and lane selection in `src/wiring/core_runner.zig`, the
`native_execute` lane count, `parse_options` defaults in `verify_cache.py`,
`scripts/verification_shard_plan.py`, and patch requests for `build.zig`
(`-j`, shard registration order, per-shard environment).

Bound total CPU demand to the CPUs admission allows: choose the Zig runner's
`-j` and each shard's `MYLANG_UNIT_JOBS`/`MYLANG_JOBS` so the product of
concurrent roots and their lanes stays within the allowed CPUs, instead of 18
roots each sized for the whole machine. Register the longest roots first so
they start first, and stop the late start of a long shard (core 5 at 551 s).
Rebuild the shard plan from the median of at least three runs' per-test times,
not one run.

**Accept:** on an otherwise idle host (F09's qualification), compiler edit to
green complete verification at most 300 s in two of two samples; load average
during the gate within 1.5× the allowed CPUs; unit, CLI and core shard ratios
at most 1.25 or bounded by their largest single test; exact-once coverage
unchanged.

### F02 — Batched receipt publication (K1, K2)

**Own:** the publication block of `finalize_gate` in `verify_cache.py`, the
batch path of `publish_success` in `scripts/fuzz_campaign_store.py` (its
`commit_blob` staging), and their tests.

Publish all groups of one gate as one batch: validate inputs once before the
batch and once after it under the same guard, and stage every receipt behind a
commit blob so a failed revalidation publishes nothing. Keep the existing
per-key conflict and rollback contracts for fuzz callers.

**Accept:** publication inside the gate slot under 2 s with default stores
(from 50.7 s); a source change during publication publishes no receipt; an
interrupted batch leaves only misses; fuzz-store tests unchanged.

### F03 — Warm-path digest reuse (K2)

**Own:** `scripts/verification_snapshot.py`, `scripts/verification_warm.py`,
`scripts/verification_git_tree.py` and their tests.

Reuse a file's recorded digest when its device, inode, size, modification and
change times (nanoseconds) all match a per-worktree digest record, and rehash
any file whose recorded times are within the filesystem's timestamp
granularity of the record's own write (the racy-timestamp rule Git's index
uses). Never reuse across any stat difference; `--verify` rehashes everything.
This is not the mtime-only memoization S08 rejected; state the difference in
the handoff with tests for ABA rewrites, same-size edits, `touch -d`, renames
over a file, and edits within one timestamp tick.

**Accept:** five unchanged complete requests at most 10 s each with zero
admissions; at most 1 % of the 29,178 files rehashed on an unchanged tree; every
mutation test invalidates; F10 signs off.

### F04 — Scheduler backend correctness and the shadow day (K4, K8)

**Own:** `scripts/verification/scheduler.py`, `scripts/build-slot.sh`,
`scripts/build_slot_legacy.sh`, `scripts/build_admission.py`, their tests, and
Guardian watch use in admission.

1. Find and fix the missing shadow transition and the two elapsed-bound
   failures from the closing default C5; keep the failing runs as regression
   fixtures.
2. Guardian watch authority under concurrent requests: one shared watcher per
   tree or a non-failing fallback, so ten requests never exhaust inotify watches
   or refuse authority. Do not change host limits.
3. After F05's fixes are integrated, run a 24-hour shadow day on ordinary agent
   traffic with the decision log, audit it, and switch the default backend only
   if the audit shows no starvation or decision divergence. The coordinator
   approves the switch.

**Accept:** opt-in C5 10/10 green; shadow audit published; default switched or
the reason it was not.

### F05 — Coordinator subscription and fixture isolation (K4, K8)

**Own:** the admission and subscription functions of `verify_cache.py`
(`run_admitted`, the admitted child, `recheck_after_admission`, scheduler
submission), the coordinator test fixtures in `verify_cache_test.py`, and
nested child diagnostics.

Isolate mocked coordinator fixtures from the inherited admission backend so no
test's mock escapes into a real worker gate; retain nested child stdout and
stderr in failure reports. Make identical concurrent requests subscribe to one
keyed execution through the scheduler and wait without a gate slot.

**Accept:** the two recurring assertions and 12 errors gone in ten opt-in
worker runs; C5 with the scheduler: every group executed once, nine requests
coalesced or reused, none of the nine admitted to a gate slot.

### F06 — Guardian branch (K6, K8)

**Own:** the guardian-zig branch (`codex/caching-closeout-20261013-w01`,
`5ad883fa0ad35d7c5ed3f20bec42b4fec275abdb`) in its own guardian-zig worktree.

Find why the branch makes a gated installed edit 12.5 s against 7.4 s with the
current Guardian, and fix it. Keep its shard plan, runtime filter and 256 MiB
diff capture; report a diff over the limit as a size error, not
`GitSpawnFailed`.

**Accept:** with the branch, gated edit no slower than the current Guardian; a
new test filter compiles no new binary; the 68,224,123-byte large-diff hook
passes; mylang still passes with the current Guardian. Present the branch for
the user's merge decision.

### F07 — Installed-edit path and the watch loop (K6)

**Own:** patch requests for the install graph in `build.zig`, the watch
documentation in `docs/tooling/development-loop.md` and `CLAUDE.md` (through
the coordinator), and measurement scripts under its experiment directory.

Attribute the 7.3 s ungated edit (Zig compilation of the compiler, install
copies, `component_build`, Guardian, configuration) and cut what is not the
compiler's own compilation. Make `zig build --watch -fincremental` the
documented inner loop, including how to get a clean build before gating and
how the watch interacts with admission.

**Accept:** watch edit at most 1.5 s in five samples; ordinary edit at most
5 s; the documented commands work from a fresh worktree.

### F08 — Store policy and compatibility (K7)

**Own:** `scripts/core_store_gc.py`, `scripts/systemd/core-store-maintenance.sh`,
`scripts/prune-caches.sh` and their tests.

1. Evict to 90 % of the cap whenever the inventory exceeds it.
2. Keep flat aliases (hardlinks, no extra bytes) of objects used within the
   retention age, so compilers built before the sharded reader, including frozen
   measurement compilers, still hit; remove a flat alias only when its object
   ages out.
3. Measure each maintenance run's cost (it inventories about 1.08 M entries
   every 15 to 18 minutes) and make it incremental if a run costs more than a
   few seconds of disk time.
4. Make both services move their worktree to the current `main` commit before
   they run (`git checkout --detach main`, refusing if the worktree is dirty),
   through the installers, so no manual step follows a fast-forward.

**Accept:** inventory at most the cap after every run for a day; a main-era
compiler's rebuild of an unchanged program hits the store; run cost recorded.

### F09 — Measurement, load qualification and test reliability (K1–K9)

**Own:** `experiments/caching-followup-20261014/` measurement, the cohort
runner, the load-qualification rule above, and the reliability fixes: the
fuzz-family helper readiness failure (`crashed=True`) from closing attempt 8
and any test that fails twice under load.

Measure `C1` before anything is integrated, each round, and the final commit,
with load and pressure recorded beside every sample. Run the ten-gate sequence
at the end.

**Accept:** every K row has a qualified `C1` value, per-round values and a
final value, or is reported not qualified with the load record; ten
consecutive complete gates green.

### F10 — Independent review

Review F02, F03, F05 and F08 before integration for false reuse, lost
publication and stale-hit paths. Write adversarial tests where the review finds
a gap, and block integration until they pass. Read-only on the other branches;
tests go in F10's own branch for the coordinator to integrate.

## Rounds

1. **R0 (hours).** Step 0, then F09's `C1` baseline. All workers start.
2. **R1 (day 1).** Integrate F02, F03 and F08 after F10's review; complete
   verification once. F09 measures K2 and K7.
3. **R2 (day 1–2).** Integrate F01 and F07. F09 measures K1 and K6 under the
   load rule.
4. **R3 (day 2–3).** Integrate F05 and F04's fixes; start the 24-hour shadow
   day; switch the default backend after the audit. F09 measures C5 (K4).
5. **R4 (day 3–4).** F06's branch for the user's decision; final freeze; ten
   consecutive gates; all K rows on the exact commit; fast-forward `main` to
   the integration commit if the complete verification passes; reinstall the
   units from the service worktree once so F08's self-refresh takes effect.

## Handoff and report

Each worker's `handoff.md` gives `C1`, fixed SHAs, owned files and patch
requests, what changed, commands with exit statuses and logs, before and after
counts, timing only from F09's qualified windows, and open items. The
coordinator's final report gives every K row as passed, failed or not
qualified with its value, the `main` SHA before and after, the service
worktree and unit files, and the Guardian branch for review.

## Copy-and-paste instruction for the coordinator

```text
Use docs/audits/caching-followup-10-agent-plan-2026-10-14.md as the execution
plan. It is on branch claude/caching-followup-plan-20261014 (the caching
closeout integration commit 1aabd7bd063527e34fe53e77a20c3f8046710073 plus this
plan), checked out at /home/epentland/ai/canopy/mylang-caching-followup-plan-20261014;
read it there but do not work in that worktree.

Do Step 0 first and alone: confirm local main is still 76180573b, then
fast-forward main to claude/caching-followup-plan-20261014 in
/home/epentland/ai/canopy/mylang-debug-speedup-main with git merge --ff-only,
leaving that checkout's three uncommitted documentation files untouched; create
the detached service worktree /home/epentland/ai/canopy/mylang-services, reinstall
both systemd user units from it, run each once, and pin C1 at the new main.
If main has moved, stop and ask the user. Nothing is pushed.

Then run one coordinator and workers F01–F10 as assigned, each on its own
worktree and branch from C1, with the ownership rules of the plan: the
coordinator alone edits build.zig, build_test_inputs.zig, build_verification.zig,
build_identity.zig, guardian.toml, SPEC.md, CLAUDE.md and the development-loop
docs; verify_cache.py is claimed by function; only F06 changes guardian-zig, on
its branch; never update the sibling guardian-zig checkout.

F09 measures C1 before anything is integrated and applies the load rule to
every timed sample. F10 reviews F02, F03, F05 and F08 before they are
integrated. Integrate in rounds R0–R4 with one complete verification per round.
Switch the default admission backend only after the audited 24-hour shadow
day. At R4, fast-forward main to the integration commit if its complete
verification passes. Report every K row as passed, failed or not qualified with
its measured value, and present the Guardian branch for the user's decision.
Do not push, do not clear shared caches, and do not edit other sessions'
worktrees.
```

For a manually opened worker session, give it this plan, `C1`, its worktree
and the instruction: "Execute FNN only; follow its ownership and acceptance
contract; commit fixed SHAs and return the handoff."

## Outcome (15 October 2026)

The user closed this program at R2 on 15 October. Neither of the last two
rounds ran:

- **R3:** its complete verification and its ten-client cohorts. The
  fresh-consumer cohorts needed 55 GB free; the last readiness check found 54 GB,
  and less was free afterwards.
- **R4:** the Guardian comparison, ten consecutive gates, the main fast-forward,
  the service refresh and the default-backend switch.

The integration branch `codex/caching-followup-20261014-integration`
(`afc46598d`) was merged with language wave 1 on `claude/main-merge-20261015`.
That merge's complete verification was the first one for the R3 scheduler and
watcher-pool code, and it hung. `verification_measurement_test`
(`test_cleanup_waits_for_owned_shadow_observer_after_window_release`) holds the
shadow log's lock while it requests timing admission. Commit `c2b0fdf5e`, from
R3, added a blocking `_log('request', ...)` to the admission path in
`scripts/build_admission.py`, so the admission waits forever on the test's
lock. Until that write is bounded or made non-blocking, a locked shadow log
stalls every admission request. The R3 code stays in shadow mode, and the
default admission backend is unchanged. The full record is
`experiments/caching-followup-20261014/status.md` on the integration branch.

| Row | C1 | At close (R2, qualified) | Target | Result |
| --- | --- | --- | --- | --- |
| K1 edit to green | 394.9 s median | 322.4 s median (334.8 s, 310.0 s) | 300 s | failed; shard balance also missed |
| Publication inside the gate | 14.7 s | 2.6 s | under 2 s | failed, from 47 s at R1 |
| K2 unchanged request | 16.1 s | 14.5 s, zero admissions | 10 s | failed |
| K3 fresh worktree | 40 of 41 actions reused | unchanged | all actions | failed; Guardian has no input-closure contract |
| K4 ten simultaneous requests | ten Guardian admissions | not measured | one execution per group | not qualified; the R3 cohort did not run |
| K5 nightly integration | failing (stale Guardian prebuilt) | prebuilt rebuilt 15 October | green | not qualified until a nightly passes |
| K6 install after an edit | 6.2 s | 5.9 s | 5 s | failed |
| K6 watch loop | 1.5 s, stale compiler identity | 1.15 s, identity confirmed every edit | 1.5 s | passed |
| K7 store | private probes passed | actual-store day not run | bounded, evicting | not qualified |
| K8 consecutive gates | — | not run | ten | not qualified |

The open items are follow-up tasks, each small enough for one worker:

- **K1:** shard balance.
- **K2:** the remaining warm-path cost.
- **K3:** Guardian's input-closure contract.
- **K4:** the deduplication measurement, with fewer clients than ten so it fits
  on disk.
- **The default admission backend:** switch it after an audited shadow day.

The F06 Guardian proposal (`83f1588a` on `codex/caching-followup-20261014-f06`
in `guardian-zig`) stays unmerged, because the F07 comparison that would justify
it never ran.
