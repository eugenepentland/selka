# Closing out the caching work: lanes H1 to H6 (2026-10-13)

Status: review candidate with open acceptance criteria; see the outcome below.
Originally proposed on 13 October 2026 as the output-keyed shared receipts
integration (`claude/lane-a-env-identity-20261012` at `71ec484ba`, lanes A to F,
C2, G1 to G5) was merged into local `main` as `fcd00eb60`. It names what is left to make the
development loop as fast as the audit said it can be, as lanes with acceptance
criteria, so that the caching program can be declared closed and the
self-hosting plan can start without carrying it. Every number below is from the
measured cohorts and gate rounds recorded in the
[receipts plan's outcome](output-keyed-shared-receipts-plan-2026-10-12.md#outcome-12-october)
and the [development-loop guide](../tooling/development-loop.md); none is a
projection unless marked.

Execution: [coordinator plus ten workers](caching-closeout-10-agent-plan-2026-10-13.md).
A read-only survey of `main` at `76180573b` on 13 October corrected several
facts in §4 (three budget sweeps rather than 46, 59 per-test cache directories,
an existing scheduler, eleven always-fresh groups); the execution plan's first
table is authoritative where they differ.

## 1. Where the loop stands

| Workflow | Before the plan (12 October morning) | Now | Closeout target |
| --- | --- | --- | --- |
| Compiler comment edit, then `mylang test tests/lang` | 78 s, nothing reused | 14.15 s, 1,544 of 1,549 from receipts | unchanged |
| Unchanged complete verification, request / gate occupancy | 33.5 to 36.8 s / 23 to 28 s | 24 to 37 s (median 29.9 s) / 14.4 s | at most 10 s / no gate slot taken |
| Compiler edit, then complete verification | 596 to 1,034 s | 763 s: every guest and language group reused, 19 Zig roots and drivers rerun | at most 300 s |
| Second worktree at the same commit, first verification | 600 to 1,000 s, nothing reused | 88 s request, 58 s gate, 33 of 35 actions reused | at most 60 s request, 35 of 35 |
| Ten worktrees verifying one commit at once | ten full gates | one full gate, nine requests reuse after admission (G5) | one execution per group, nine hits, no gate slot for the nine |
| Gate admission wait | mean 81 s, max 41 min; timing windows drain every build and gate | unchanged | small jobs never wait on a timing window |
| `zig build` after a one-line compiler edit | 2 to 7 s, plus about 1 s Guardian and a 239 MB install copy | unchanged | about 1 s warm |
| Per-user object store | 1.87 M files in one directory, 27 GB, no running eviction | unchanged | sharded, bounded, prune on a timer |

What the integration delivered is the sharing multiplier: for many agents on
one base commit the cold gates have become one. What it did not touch is the
single-agent cost of a compiler edit, which is now almost entirely Zig test
roots, and the admission scheduler that serializes everything through one gate
slot and stops the machine for timing.

## 2. Open findings from the qualification

| Finding | What it is | Lane |
| --- | --- | --- |
| F15 | `tooling_unit` and `text_scalar_unit` producer identities bind test-binary bytes that carry the DWARF compile directory; the only two action keys that differ between worktrees | H3 |
| F17 | 94 of 1,589 `tests/lang` tests are refused by `shareable()` (host capabilities, error traces, C externs, function values); their execution receipts, keyed on program bytes that are now identical across roots, live only in the private cache | H3 |
| Default sharing | `default_sharing` and `DEFAULT_SHARING` are off; two tests assume it (`test_store_roots_follow_the_compiler_resolution`, `compiler_shared_cache_test` suppression) | H3 |
| G5 races | The gate slot is released before receipts are written; the pre-queue miss path can invalidate a peer's fresh receipt. Extra work, never a wrong verdict | H2 |
| F19 residue | Waiting on in-flight identical work; receipts published inside the slot | H2 |
| F10, F11 | Load-sensitive tests (`component_protocol_test` 10 ms deadline, `verification_measurement_test` settle, `durable_test` SIGKILL recovery, a CLI property timeout); timing measurements starve admission for 30 minutes or more | H2, H6 |
| Pre-existing | `verification_revalidation_test.py` fails two `test_deferred_*` tests on `main`; `verification_process_test.py` passes only from the repository root; Guardian's commit hook cannot diff a merge whose base is far behind (64 MiB output limit) | H6 |
| F16 | Snapshot identities record absolute `../guardian-zig` paths; equal across `canopy/` worktrees, not for a checkout elsewhere | H3 |
| F2 | `function_digest` binds the compiler identity, so five `application_cache.my` tests rerun on every compiler edit, by design | none; documented |
| `--integration` | Implemented and tested, never run live | H3 |

## 3. Done criteria

The program is closed when every row holds on `main`, measured in exclusive
timing windows with the cohort protocol:

| # | Criterion | Measured by |
| --- | --- | --- |
| K1 | A one-line compiler edit, then a complete verification, is green in at most 300 s on one worktree | cohort C3 |
| K2 | An unchanged complete verification answers in at most 10 s and takes no gate slot when every action is reused | cohort C1 |
| K3 | A fresh worktree at a known commit reuses 35 of 35 cacheable actions and at least 99 % of guest tests | cohort C4, matrix row 7 |
| K4 | Ten simultaneous requests at one commit: one execution per group, nine hits, none of the nine takes a gate slot; a timing window pins its CPUs and never blocks a build | cohort C5 |
| K5 | Sharing is on by default for one user on one machine; the full gate passes with the default stores; a nightly `--integration` run is green | gate, nightly log |
| K6 | `zig build` after a one-line edit is about 1 s warm; a new `-Dtest-filter` compiles no new test binary; development installs are not gated | development-loop guide measurements |
| K7 | The object store is sharded and bounded, eviction runs on a timer, and a fresh worktree's first build shares unit objects | store statistics, cohort C4 snapshot work |
| K8 | No test in the gate fails under load twice in a week; the two revalidation tests pass; large merges commit through the hook | gate history |
| K9 | The cohorts and the compile-edit gate are re-measured on the closing commit and recorded; the progress dashboard shows them | plan outcome, `progress/` |

## 4. Lanes

Each lane runs in its own worktree and branch from `main`, never pushes, and
merges onto one integration branch gated by the complete verification. Lanes
H1, H3 and H6 touch disjoint files and start together; H2 follows H3 (it changes
how receipts are published); H4 follows H2 (it depends on the scheduler knowing
a request is fully reused); H5 is independent.

| Lane | Scope | Acceptance | Estimate |
| --- | --- | --- | --- |
| **H1 Cold gate** (audit 9 and 8) | Declare observed peak RSS instead of 2.5 GiB per unit shard and 1 GiB per core shard; assign tests to shards by Guardian's recorded per-test walls (LPT) instead of `index % N`; build once and exec the binary per budget at the 46 `.again` sites in `native_execute.zig`; replace per-test temporary `--cache-dir` with a shared warm cache in the 43 core test files that use one | K1; unit shard maximum from 153 s to about 55 s; the cold gate runs more than 2.2 steps at a time | 1 to 2 days |
| **H2 Admission and deduplication** (audit 4; G5) | An event-driven scheduler built on `scripts/verification/scheduler.py`: priorities, fair share, identical-key deduplication with subscribers so a request waits on in-flight work instead of repeating it, one token pool for `zig cc`, link and test, a cpuset for timing so measurements pin their CPUs and stop draining the machine; receipts published inside the slot; the pre-queue invalidation fixed; `build-slot.sh` becomes a thin client; one admission directory | K4; gate admission mean wait from 81 s to under 10 s for warm requests; C5 one execution, nine hits | 2 to 3 days |
| **H3 Finish sharing** (F15, F17, F16, default flip, `--integration`) | Producer identities for the two unit roots by recipe, or test binaries without the compile directory; execution receipts published to the shared store under the same validation as the IR tier; relative `guardian-zig` paths in snapshot identities; fix the two tests and flip `default_sharing` and `DEFAULT_SHARING`; run `--integration` live once and install it nightly | K3, K5 | 1 day |
| **H4 Warm path** (audit 7) | Key Guardian on its binary, toml, in-scope bytes and merge base; key spec-history on commit ids; move the juice collectors to a qualification profile; skip admission when every group is reused; attribute the remaining request time | K2 | 1 day |
| **H5 Inner loop and fixed costs** (audit 13 and 10) | `zig build --watch -fincremental` per worktree with a clean build before gating; `-Dtest-filter` passed to the test runner at run time; `-Dgate-install=false` for development installs; retire `stage.sh` for `affected-compiler`; runtime source out of unit keys; stat fast paths before rehashing replay sources; reflink the program and `zig-out/verification` copies; cache `component_build` on its inputs | K6; a runtime `.c` edit no longer recompiles every unit | 1 to 2 days |
| **H6 Stores and hygiene** (audit 5, quick wins, F10, pre-existing) | `units-v1/ab/<key>` sharding with a size ledger and lease-free LRU; the prune on a systemd user timer covering stage packs, `core_rt` variants and lane Zig caches; the flaky tests given deterministic budgets or quarantined with a named owner; the revalidation and cwd-dependent tests fixed; `GUARDIAN_AGAINST` chosen by the hook for large merges; `git worktree remove` in lane hand-off | K7, K8 | 1 day |

With three or four agents in parallel the wall time is about a week, most of it
gates and admission, which H2 itself shortens as it lands.

## 5. Measurement

Every lane re-measures the rows of §1 it touches, before and after, in exclusive
timing windows with the cohort runner (`experiments/output-keyed-receipts-20261012/cohorts.py`),
five samples where the protocol says five, queue time recorded beside each
sample, machine identity recorded, nothing claimed from a run beside a gate. The
closing commit gets the full set: C1 to C5 and the compile-edit gate, written
into the development-loop guide and the receipts plan's outcome, and into the
progress dashboard once lane S7 of the self-hosting plan exists.

## 6. Rollout order

1. H3 flips sharing on once its gate passes with the default stores (week 1).
2. H2 runs the scheduler beside `build-slot.sh` for one day of agent traffic,
   then replaces it; timing windows pin CPUs from the first day.
3. H4's "skip admission when everything is reused" lands after H2 so the
   scheduler, not the client, decides.
4. H5's ungated development install is opt-in by flag; the gate still installs
   through Guardian.

## 7. Coordination

The codex closeout plan of 12 October (S01 to S10) overlaps this plan. One owner
per item, decided by the user, or two versions will land:

| Codex item | This plan |
| --- | --- |
| S03 split the remaining broad native test roots | H1 |
| S06 reduce work in fresh guest-test actions | H1 |
| S07 reduce repeated golden and component fixture preparation | H4 |
| S08 reduce retained-session validation cost | H4 |
| S04 narrow producer identity with a real adopted boundary | H3 |
| S02 qualified budgets and reliable cancellation | H2 |
| S09 integrate the existing self-hosting work | the self-hosting plan, after this one |

## 8. Exit

When K1 to K9 hold on `main`, the caching program is closed: the receipts plan
and this plan get a closing outcome with the final cohort numbers, the audit's
ranked list is marked done or deferred item by item, and the self-hosting plan's
lanes S0, S2, S6 and S7 start.


## Outcome: review candidate

The coordinator and W01–W10 implemented the execution plan on separate branches
from C0 `a63da04eb0d31f9af267ca6011e736c8db9fbaf7`. The implementation is on
`codex/caching-closeout-20261013-integration`; neither main nor the separately
published origin/main was merged or updated. No branch was pushed. Guardian is
a separate review branch at `5ad883fa0ad35d7c5ed3f20bec42b4fec275abdb`; the
existing sibling checkout remains unchanged, with compatibility fallbacks.

The [acceptance report](../../experiments/caching-closeout-20261013/acceptance.md)
retains all baseline/round measurements, failures, fixes and original denominators.
It identifies the exact-commit closing acceptance companion and artifact manifest.
Those closing measurements are collected after the report commit, without a later
integration commit or amend. They supersede the source-stage values for final
acceptance; a functional pass alone does not establish a timing target.

R3 unchanged verification improved from the measured C0 median 25.559 s to
18.356 s (28.18%), with all 41 cacheable actions reused and no admission, but
missed 10 s. Fresh consumers improved from 79.075 s to 27.298 s (65.48%); each
reused all 41 actions and the separate native probe reused 5,544/5,544 supported
tests. These R3 sharing probes used explicit qualification stores. R2 compiler-edit
verification passed at median 243.593 s; R3 regressed to one green 337.033 s
attempt and one failed 393.024 s attempt, so it has no all-green median. The
approximately-one-second normal build target also failed in both Guardian scopes.

Default sharing was enabled only after three successful default-store gates.
The corrected live default-policy integration passed, and R4 installed bounded
core-store maintenance and nightly integration user timers. The host records and
closing companion distinguish installation, actual maintenance, a manual installed
service run and an observed scheduled firing. The scheduler remains in shadow
mode; a qualifying day on the final implementation and a week of reliability
cannot be inferred from short fixtures or ten gate passes. All failed or
unqualified rows remain open. The caching program is not declared closed on main.
No `progress/` dashboard exists in this checkout; that conditional update is not
applicable.
