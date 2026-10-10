# Wave 6 qualification

Baseline: `b2de7b2f0`, with local main `1d202d41b` already integrated. This clone
has no remote. Work is on `codex/selka-cache-wave6`; the primary dirty checkout
was not changed.

## Final qualification

Wave 6 is qualified. The final gate passed **124/124 build steps**, including
format checks, all Python drivers, and **2,652 native tests**. The 29 native
result records report zero failures and zero actual skips. The unchanged warm
run then passed with every eligible group reused from the shared store.

| Verification run | Reused groups | Selected groups | Build admission | Gate held |
| --- | ---: | ---: | ---: | ---: |
| Full | 0 | 41 | 0 s | 343.34 s |
| Warm | 30 | 11 | 0 s | 19.08 s |

The 11 selected groups retain their explicit freshness contracts: component,
input and environment discovery, SPEC history, physical/runtime Juice,
compiler identity qualification, coverage discovery, guest/language effect
eligibility and Guardian. Eligible native core, unit and CLI suites reused their
verified receipts. Warm verification took 34.52 seconds end to end, including
5.27 seconds waiting for admission and about 10.08 seconds of preparation/lookup
outside admission. These admission observations were collected during ordinary
shared-server operation and do not constitute an isolated latency comparison.

The warm verifier still read 2,305,968,547 bytes across 28,403 files and enumerated
2,247 directories. This snapshot arrangement reported zero digest-session reuses;
the overlap optimization's measured benefit belongs to the separate overlapping
snapshot fixture and the Juice invocation. A restarted command still validates
content, so there is substantial scope to improve the remaining no-op cost.

All 30 changed source/configuration/documentation files matched the frozen input
manifest after both successful runs. The retained native Juice record also
matched the digest in its qualified report. See
[qualification-summary.json](qualification-summary.json),
[full verification report](verification.json), [full raw log](verification.log),
[warm report](verification-warm.json), and [warm raw log](verification-warm.log).
Guardian feedback logging was not required and no feedback entry was written.

## Implemented boundary

Verification, fuzz and Juice accept an explicit shared local evidence directory.
Immutable payloads deduplicate and exact action receipts can be reused independently
of their private coordinator cache. Mutable inventories, working files and fuzz
corpus catalogs remain private. Keys retain path and execution dependencies.

The versioned store has atomic publication, workflow leases, explicit bounded GC,
persistent retention pins and deterministic-conflict poisoning. Collection skips
active stores. It reclaims idle per-key lock files only under the exclusive global
lease, keeping the global lock inode permanent. Recognized interrupted writes are
recoverable; malformed protected metadata fails closed. Byte policies report when
pins/conflicts prevent reaching the requested budget.

Forced deterministic refresh suppresses reuse while preserving comparison evidence;
failed refresh does not revive the old success. Shared fuzz publication promotes
retained private corpus bytes back into shared storage before publishing. Physical
Juice observations keep their existing first-valid-observation policy.

## Warm-path measurements

The isolated Debug native `juice plan` fixture hashes the complete running
236 MB compiler executable. Three sequential warm-machine baseline samples were
21.58, 21.60 and 22.20 seconds; three final samples were 0.16 seconds each (GNU
time's centisecond resolution). Median peak RSS was 16,776 KiB before and
16,736 KiB after. Every final plan's executable digest matched an independent
SHA-256, and other plan fields matched after normalizing only the running
executable's path and identity.

The speedup comes from compiling the standard SHA-256 implementation in a separate
optimized native object. Reads remain streaming and consume every input byte.
The first attempted module-only optimization left the rounds in Debug code and
measured about 21.6 seconds; those results are retained explicitly as an ineffective
attempt. See [hash-summary.json](hash-summary.json), its raw time/plan files, and
[the reproduction command](hash-plan.sh). The compiler remains Python-free.

A separate paired benchmark constructs four overlapping snapshots of the same
236 MB input. A bounded digest session reduced actual content reads from four to
one, with all identities equal. Five samples per arm gave median snapshot times
of 0.511 seconds without the session and 0.129 seconds with it. Median peak RSS
was 30,816 and 30,688 KiB respectively. This includes snapshot discovery and
validation, not process startup or an entire verification command. See
[snapshot-benchmark.json](snapshot-benchmark.json) and
[its driver](snapshot_benchmark.py).

Timing used reserved CPU 2 while holding normal exclusive gate admission, with
queue time excluded. The native experiment was sequential rather than paired;
neither experiment establishes a speedup for the whole toolchain or reduced
server admission time. Snapshot sessions preserve active watch authority and
do not carry metadata-only digest claims across command restarts.

## Path-sensitive native sharing

The existing native object store was exercised with identical programs in two
separate project roots and private compiler caches. Absolute entry paths compiled
two units in each project. Relative entry names compiled two units in the first
project and reused one of two units in the second. Both outputs printed `42` and
exited successfully; the remaining unit and link still ran. See
[absolute-path reports](native-sharing.json),
[relative-path reports](native-relative.json) and [the driver](native_sharing.py).

This demonstrates the eligibility boundary: physical sharing does not remove
observable source/debug paths from keys. This wave does not promise interchangeable
test verdicts or whole programs across arbitrary checkout paths.

## Safety qualification and remaining boundaries

Focused regressions cover concurrent publication, process death while holding an
unpublished input, blocked per-key waiters during collection, pins, corrupt and
foreign formats, interrupted GC, conflicting deterministic results, forced refresh,
evicted shared corpus replay, watch event loss, restored timestamps, aliases and
closed or inherited digest sessions. Raw logs and final gate evidence are retained
beside this report.

An initial full verification was cancelled to address two review findings:
discarded deterministic comparison evidence during force, and missing shared blob
promotion after corpus eviction. Its partial log is retained as
[verification-interrupted-review.log](verification-interrupted-review.log); it is
not a passed gate. A preliminary real shared Juice capture succeeded before those
fixes and is labeled accordingly. A second verification was cancelled to fix
shared forced-refresh serialization across distinct private cache directories;
its partial log is `verification-interrupted-refresh-review.log`. Neither
interrupted gate qualifies the final tree.

Collection remains explicit and conservatively skips a whole active store.
Supported cross-worktree reuse requires exact compatible identities; native packed
frontend/revision indexes remain private. Persistent pins are cache-retention
roots, not durable application journals. Remote producer trust, a persistent
workspace service, broader path remapping, and application restart guarantees
remain separate work.

## Real shared Juice qualification

The final native Selka fixture completed a two-sample historical instruction
capture, then served the same request from the shared store:

| Run | Executed | Reused | Server admissions | Qualified |
| --- | ---: | ---: | ---: | --- |
| Cold | 1 | 0 | 1 | yes |
| Warm | 0 | 1 | 0 | yes |

Both reports mark success and stable inputs. The warm command still hashed
918,616,525 bytes across 20,419 files, reused 15 digests within the invocation,
and enumerated 1,379 directories. Its observed end-to-end time was 11.80 seconds
and peak RSS 167,776 KiB. These are operational observations alongside other work,
not an isolated latency benchmark. They expose the remaining one-shot validation
cost despite zero workload executions and zero server admissions.

See [cold report](shared-juice-cold.json), [warm report](shared-juice-warm.json),
their logs/time files, and [the retained native record](shared-juice-raw/record.json).
The measured compiler was the frozen optimized-hash Debug executable identified
in `hash-summary.json`; it was not substituted with a fake collector. An explicit
collection request while verification held its workflow lease returned
`skipped_active: true` in [shared-gc-active.json](shared-gc-active.json).

## Reproduction

The final gate and its warm repeat use the same command and environment:

```bash
export PYTHONDONTWRITEBYTECODE=1 PYTHONPYCACHEPREFIX=/dev/null
export TMPDIR="$PWD/.mylang-cache/cache-wave6/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache"
export ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache
python3 scripts/verify_cache.py \
  --zig /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig \
  --shared-cache-dir .mylang-cache/cache-wave6/shared-evidence \
  -- -j3 --maxrss 8589934592
```

The coordinator owns admission. The source manifest in
[qualified-inputs.json](qualified-inputs.json) records SHA-256 values for all 30
changed implementation/configuration/documentation files outside this evidence
directory at the start of the final gate.

## Gate failure investigated

The next complete gate kept its input snapshot stable and ran all 2,652 native
tests successfully, but failed one Python cancellation fixture:
`Supervision.test_outer_group_cancel_reaps_separate_sessions_and_grandchildren`
in `scripts/juice_worker_test.py`. The native test runner reports 29 result rows
with zero failures and zero actual skips; Zig's larger skipped count is the
normal shard partitioning. The failed gate was 121/124 build steps successful,
with one failed step and blocked dependents. No successful verification receipts
were published from this failed run.

The fixture published its middle process's JSON directly at the readiness path.
Its parent waited for path existence and immediately parsed it, allowing an
empty or partially written file to terminate startup. This is separate from the
worker's cancellation/descendant cleanup behavior. The failure evidence is
[the raw log](verification-failed-worker-readiness.log) and
[the coordinator report](verification-failed-worker-readiness.json).

Once all workflows exited, an explicit zero-budget GC dry run scanned 237 entries,
identified 785,557 reclaimable bytes and 134 reclaimable per-key lock files, and
retained the permanent global lock. It made no deletions. See
[shared-gc-idle.json](shared-gc-idle.json). Active-store and idle-store behavior are
therefore both exercised on the real shared evidence directory, alongside the
focused eviction/pin/crash regressions.

The fixture fix closes a separate temporary file before each atomic readiness
publication. A deterministic regression holds the middle process's empty
temporary file open, verifies the public path is still absent, then releases the
write and checks cancellation/reaping of the complete three-process tree.
Production supervision code and cancellation deadlines are unchanged.
The pre-fix 29-file source manifest is retained as
`qualified-inputs-pre-readiness-fix.json`; the final 30-file manifest additionally
covers this test-only repair.

The focused supervision suite passed 12/12 after the repair. The independent
[old-handoff reproduction](worker-readiness-repro.py) deterministically exposed
an empty public readiness file and a reader `JSONDecodeError`, then showed that
the closed file parsed correctly; see [its result](worker-readiness-repro.json)
and [focused command/output](worker-readiness-focused.txt). The failed gate did
not retain child stderr, so its immediate cause cannot be established from the
log alone; the race is independently reproduced and removed.

The final focused native hash qualification is
[hash-object-focused-final.log](hash-object-focused-final.log): 12/12 build
steps and 10/10 Juice tests passed. `hash-object-focused-initial-error.log`
is an earlier compile-time enum spelling error corrected before this run.
The final object installation passed 14/14 steps in `hash-object-install.log`.
The post-failure shared-store inspection found three Juice receipts and zero
verification success receipts; see
[failed-gate-publication-check.json](failed-gate-publication-check.json).
