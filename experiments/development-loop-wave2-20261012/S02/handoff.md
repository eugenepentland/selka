# S02 wave 2 handoff: live lifecycle qualification

B0: `c1857310e0bf623545380c8de24515f1b9970021`.
Process implementation: `32faf6077dfa8693bd91ef3850c3fb103c83be74`.
Harness/evidence implementation: `264fa127db54521b0382624f33ba0c66ed807809`.
Owned files are `scripts/verification_process.py`, its test, new
`scripts/verification_live_lifecycle.py`, and this S02 experiment directory.
Coordinator-owned source changes are exclusively the exact proposed
[coordinator-parent-death.patch](coordinator-parent-death.patch); the coordinator
applied that adapter independently. No second claim system, peer edits, push,
main merge, compiler/runtime/ABI change, slot increase, cache clearing outside
this fixture, or Guardian FEEDBACK write occurred.

## Reproduced defect and fix

A hard parent/coordinator crash left its independently sessioned launcher,
inner supervisor, worker and detached child alive. The bounded pre-fix proof is
[crash-baseline/result.json](crash-baseline/result.json). The process fix arms
Linux `PR_SET_PDEATHSIG(SIGTERM)` in the owned launcher and inner supervisor.
`arm_parent_death(parent_pid, parent_start)` checks actual parent PID and birth
*after* registration, closing the pre-registration death/replacement race.
A lost parent cannot begin work; kernel notification covers subsequent death.
[Fixed direct proof](crash-fixed-direct.json) records all four processes gone
within the 0.3-second observation. This is operational behavior, not a calibrated
latency claim.

The coordinator adapter supplies expected parent PID/birth only in wrapper
Popen environment. The encoded action environment and common evidence keys do
not contain volatile parent identity. Existing `build-slot.sh` queue polling
already checks these markers, so orphan queued wrappers retire. The admitted
child arms/checks parent death before handshake. Descriptor inheritance,
subreaping, the two-second natural closeout window and at least 0.5-second
watchdog grace remain unchanged. Other request work remains independently owned.

## Live production path and limits

The harness launches real OS processes through byte-for-byte copied production
`cache_session.py` / `verify_cache.py`, real shared admission, watched snapshots,
existing `fuzz_campaign_store` family locks, guarded receipts and publication,
and actual process supervision. Actions use a small deterministic fixture driver
and one-member inventory; compiler binaries/component payloads are stand-ins.
These cases do not qualify the native 46-group inventory or compiler correctness.
No coordinator/store/admission mocks or alternative ownership implementation are
used. Store lookup is the production `Store.load_success` API.

The current ownership model serializes request contenders. It has no shared
in-flight worker subscription count. Canceling a waiter preserves the owner;
canceling/crashing an owner aborts its lineage, and the surviving waiter executes
fresh work after the authoritative lock releases. This does not demonstrate
continuation of an in-flight shared worker after its owning request disappears.

One disposable private fixture retains prepared artifacts and inventory across
cases, and resets only its local action receipts/shared evidence after every
coordinator has joined. Compatible preparation still conservatively regenerates
when v1 one-shot/retained loaded-code identity or execution controls differ.
No shared production store is mutated. Crashes are isolated to fixture-owned
PIDs; cleanup checks kernel births using pidfds. A harness-local subreaper reaps
adopted crash wrappers. Admission readiness is bounded at 15 minutes separately
from the 0.25-second explicit worker deadline. Parent validation is distinct from
worker execution: admitted held time cannot substitute for worker_seconds.

## Evidence

`source /home/epentland/.config/mylang/dev-env.sh` supplies pinned Zig, private
Zig local cache, shared global cache and on-disk TMPDIR. No native build/full gate
or timing window was launched by this worker. Production fixture commands own
admission and run directly; pure Python process tests run directly.

The final private-TMP process command was:

```console
python3 -m unittest discover -s scripts -p verification_process_test.py
```

It passed all 35 cases (35 executed, zero reused/partial), including independent
session survival, CPU/blocked/thread-owned/detached/forking children, startup
cancellation, publication interruption/retry, parent identity mismatch and hard
parent crash. [Raw final log](process-tests-final.log). The implementation commit's
normal whole-tree Guardian hook passed all 88 checks. No feedback log was changed.

The production fixture command was:

```console
python3 scripts/verification_live_lifecycle.py --production-root /home/epentland/ai/canopy/mylang-dl-wave2-20261012-integration --output experiments/development-loop-wave2-20261012/S02/live-production
```

The immutable copied scripts originated at integration HEAD
`c80a31e777283297c3084e457c471025b9b837aa` plus the explicitly recorded dirty
adapter/measurement changes. Exact source hashes and dirty status are in
[live-production/results.json](live-production/results.json); the authoritative
120-file copy is [frozen-script-manifest.json](live-production/frozen-script-manifest.json).
The five main source digests match that manifest. The exact harness that ran is
[harness-at-run.py](live-production/harness-at-run.py).

Seven cases passed: concurrent matching retained requests execute once/reuse;
waiter cancellation leaves owner/detached work running; owner cancellation lets
a waiter retry; explicit timeout reaps the lineage and the same-limit retry
passes; removing private receipts still permits shared-store reuse; hard crash
after admission reaps the lineage and permits waiter retry; hard crash before
handshake retires the wrapper and permits retry. Raw request logs and final/failure
reports are archived alongside results. In the timeout row, queue was 50.5082s
and worker (including cleanup) was 0.342729s for the explicit 0.25s deadline;
queue time did not consume the deadline or authorize publication.

The first publication case correctly canceled and rolled back its partially
written local receipt, but the harness then mistakenly called nonexistent
`Store.lookup_success`. Its raw failure is preserved. The corrected case uses
`Store.load_success` to reject shared success, then exercises a fresh retry.
The corrected publication case passed with status 0: cancellation returned143,
local/shared success was rejected, and fresh retry returned0 (three gates).
[live-publication-final/results.json](live-publication-final/results.json) and
its logs preserve that check. All copied script hashes exactly match final
`5e6180689b5b837aa60bd5a43f60b0981c58b638`, even though its source snapshot was
copied while those exact bytes were still uncommitted.

Other prototype runs failed before dispatch because of an omitted literal config
fixture or were intentionally interrupted while queued to replace repeated cold
setup with coordinator-approved preparation reuse. They are not lifecycle
acceptance or latency observations. Their short raw logs are retained as context.

## Open acceptance

- The primary seven-case run used frozen v1 bytes. Exact finalv2 transition
  follow-up now passes matching retained requests plus hard coordinator crashes
  before and after admission. Final publication is separately qualified on exact
  finalv2 bytes. These proofs cover the changed runtime/namespace integration;
  v1 timeout/waiter/owner/shared-only cases retain their explicitly bounded scope.
- Actual compiler/native full-inventory concurrency, cold code generation,
  aggregate RSS, isolated startup overhead and latency/p95/headroom remain
  unqualified. S10 owns those gates/windows. No calibrated automatic hard policy
  or ceiling change was introduced.
- Shared in-flight subscriber continuation is unsupported by the current
  serialized ownership model, rather than proved by these contender cases.
- Bootstrap/memory workstreams retain their source/ABI ownership and acceptance.

## Final source audit and follow-up

The final source candidate is `5e6180689b5b837aa60bd5a43f60b0981c58b638`.
[Process AST audit](process-final-function-audit.json) establishes all 18 top-level
functions/classes exactly match the implementation commit, with no additions,
removals or changed definitions. [Store audit](store-final-function-audit.json)
first verifies the captured source matches B0's hash, then establishes every store
function/class definition unchanged. Module differences are canonical loaded-code
bindings/imports. Remaining script hashes changed across the v1→v2 integration;
see [exact script comparison](live-production-final-diff.json). These AST audits
prove code-body equivalence, not independent full integration execution.

The coordinator approved the minimum finalv2 runtime follow-up:

```console
python3 scripts/verification_live_lifecycle.py --production-root /home/epentland/ai/canopy/mylang-dl-wave2-20261012-integration --output experiments/development-loop-wave2-20261012/S02/live-v2-followup --case matching_complete --case crash_after_admission --case crash_before_admission
```

It returned status0 with all three cases passed. Two real retained sessions
execute once/reuse; a hard admitted-owner crash reaps worker/detached/inner/launcher
and its waiter executes; a hard pre-handshake crash retires/reaps its owned
wrapper and retry succeeds. [Results](live-v2-followup/results.json), raw request
logs and copied script manifest preserve the exact final source hash and a clean
source status. Preparation still owns production admission; no full native gate
was launched. All captured script hashes were checked against the frozen final
commit. Corrected publication was also independently hash-matched to that commit.

Final bounded case accounting:

| Case | Outcome | Qualifying source scope |
| --- | --- | --- |
| Concurrent matching complete retained requests | One execution, two status0 verdicts, valid reuse | v1 and exact finalv2 |
| Cancel serialized waiter | Waiter143; owner/detached work survives and passes | v1, unchanged process/store definitions |
| Cancel owner with waiting contender | Owner143; lineage reaped, waiter runs fresh and passes | v1, unchanged process/store definitions |
| Explicit admitted timeout/retry |124, no success; same-limit fresh retry0 | v1, unchanged process/store definitions |
| Shared-only reuse | Private receipts removed; valid shared success reuses | v1, unchanged store definitions |
| Late publication interruption |143; local rollback/shared rejection, fresh retry0 | exact finalv2 |
| Hard owner crash after admission | -9; all owned lineage reaped, waiter executes0 | v1 and exact finalv2 |
| Hard crash before handshake/admission | -9; wrapper retires/reaps; retry0 | v1 and exact finalv2 |

Counts are bounded fixture outcomes, not the native test inventory. Primary cohort
was7 passed/1 harness error; corrected publication was1 passed; finalv2 follow-up
was3 passed. Process suite was35 passed. No fixture omission, reused observation,
partial coverage or p95 proxy is presented as a full native gate.

The harness/evidence implementation commit ran its normal whole-tree Guardian
hook: status0, all88 checks passed. Raw output is [harness-commit-hook.log](harness-commit-hook.log). `git diff --check` passed. Worktree is clean after the evidence handoff commit.
