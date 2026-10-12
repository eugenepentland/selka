# S09 handoff

C0: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Implementation/evidence commit: `5f9020ce43b7c709608c725deb0b0617d5ca6ada`.
External port audited read-only: `dff9304b9cd7bc72e66f9feb20f1b05281d67333`.
Owned files: only `experiments/development-loop-closeout-20261012/S09/*`.
The final handoff commit also normalizes one terminal blank line in the raw
native log and refreshes its hash; no source or test outcome changes.

## Delivered behavior and contracts

Frozen stage/seed/producer inventory, exact source hashes and 18-vs-25
coordinator test inventories are in `source-audit.json`. The exporter reads
immutable git objects; its output was regenerated and compared byte-for-byte.
`bridge-contract.md` records the seven stage modes and actual body schema11,
current seed pin, source/embedded/seed/tool/flags/native target closure, required
S04 conservative fallback, port-vs-development admission mismatch, and explicit
shared-file patch request. C0 already adopts test-index/cache-plan; the port adds
five frontend boundaries. None of those five have been integrated by S09.

`timing_bridge.py` provides a concrete experiment guard for direct current
exclusive timing admission. It authenticates inherited fd8/fd9 against live
canonical admit/timing lock files and current-process exclusive FLOCK ownership,
checks declared affinity, and returns provenance. Seven adversarial fixtures
pass. It acquires no locks and is not wired into source builds or installed
commands. Production migration also needs configured shared-slot-directory
comparison and launcher/tool hash recording, owner transfer, and a real direct
launcher qualification before strict ratio evidence is accepted.

S04 chose tooling-units as its first qualified narrow producer. Components keep
whole-compiler fallback until adapters prove full closure; no competing producer
store or compiler port was introduced. S01/S02 telemetry/budget wiring into new
frontend stages awaits their actual adoption. A07/A08/A10 remain ABI/cache/rollout
owners; S10 coordinates timing with A09. No runtime/default or Python-free source
build contract was changed.

## Executed checks and evidence

`commands.md` lists exact commands; `qualification-results.json` records statuses
and scopes. All reported execution statuses were zero:

- Timing bridge: 7/7 synthetic contract tests; log `timing-bridge-tests.log`.
- Frozen source exporter and exact regeneration comparison: passed.
- Pinned native component-builder + component-support: 6/6 steps, 10/10 tests;
  log `component-support.log`. Builder LLVM ReleaseSafe, native target;
  SHA256 `dc06d1a1c7c5f9b0430a6bbb8f87da17fd14564bdd54a4dfad844edbaeef59ba`.
- Existing component coordinator: 18/18 mocked seed/toolchain fixture tests;
  log `component-coordinator-tests.log`. This is corruption/recovery/cache proof,
  not a genuine seed/deployment parity run.
- Normal implementation commit hook: whole-tree Guardian 88/88 checks passed.
- Final whitespace check: passed after terminal blank-line normalization.

Tool Zig `0.17.0-dev.1683+5ceec001b`, SHA256
`1d314883fd8cf4490c1c29dd73ad8b64e319a8a53c4d9087d1135b52977df37f`.
Native commands used shared build admission, worktree-private `.zig-cache`,
shared Zig global cache, and worktree-local on-disk `.tmp-s09` TMPDIR. No explicit
CPU pinning, legacy gate lock, independent timing window, full gate or seed
provisioning was requested. The scratch TMPDIR was removed after completion.
`artifact-hashes.json` binds source audit, fixture, documents and logs.

Native support action executed 10 tests; coordinator executed 18 mocked cases;
bridge executed 7 cases. No complete-verification count or reuse claim follows
from their sum. Native build's queue was 31 seconds; coordinator compile was
18 seconds/546 MiB MaxRSS and support action 392 ms/5 MiB process peak RSS.
These are ordinary operational observations; no cold/warm/edit speedup,
aggregate concurrent RSS, isolated median/p95 or reduced-work claim is qualified.

## Ownership and integration order

S06 safe independent files: test_runner_discover/batch/work.zig, unchanged
between C0 and port. Directory runner has frontend authentication/discovery
changes; coordinate it with the port. S07 keeps golden ownership and requests
no component harness edits. Port test_components.py remains externally owned;
test_component_native.py is unchanged but its fresh no-cache/fact/leak controls
must remain fresh. This was reported to coordinator/S06/S07.

Integrate the implementation/evidence commit, then this handoff commit. All
files are unique experiment files; no build/manifest/runner source transfer is
required for this evidence-only change. Coordinator must apply any production
migration serially after obtaining explicit port ownership transfer.

## Acceptance still open

S09 completes this refreshed audit and bridge-fixture milestone only. DL7 stays
open. No accepted stage integration patch, genuine source-edit/seed/ABI mutation
matrix, real installed stage facts/leaks parity, seed→stage1→stage2→stage3 chain,
complete semantic ownership or strict selfhost ratio is qualified here.
`qualification-matrix.json` names required cases and remaining live executions.

Before adopting new frontend stages, obtain the shared-file transfer, run the
existing port harnesses on an authenticated frozen deployment, and qualify mode,
ABI, source/seed replacement, publication mutation, revert and second worktree.
The external snapshot's schema11 supersedes schema10 assumptions. Several port
documents remain stale; correct them through their owner rather than using their
prose as producer authority.

Before measuring, migrate the legacy ratio guard to the current compatible
exclusive launcher, preserving authentication and provenance. S10 then schedules
all 36 mandatory rows with enough repeated samples and declared estimator.
Every median and nearest-rank p95 must be ≤1.5× frozen Zig; historical B2/B3/B4
compiler/test failures stay visible. Full compiler and per-workload acceptance
cannot be inferred from body slices, mocked fixture checks or passing guest
runtime rows. Required complete gate and formatting pass belong to the exact
integrated candidate and remain coordinator/S10 work.
