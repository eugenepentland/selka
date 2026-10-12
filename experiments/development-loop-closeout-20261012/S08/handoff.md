# S08 snapshot validation handoff

C0: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Implementation and primary evidence commit: `9a91cabdc7764e8a363d89411929760f04026f81`.
Branch: `codex/dl-closeout-20261012-S08`.
Owned production files: `scripts/verification_snapshot.py`,
`scripts/verification_snapshot_test.py`, `scripts/verification_snapshot_profile.py`.
This directory contains owned qualification fixtures and evidence. No shared file,
other worktree, external branch, rollout default or Guardian feedback was edited.

## Changes and authority

`Snapshot.stability_diagnostics(role="inputs")` returns a detached advisory object:
`{version: 1, status: observed|unknown, reasons: [{role, facet, name, reason}], unknown, truncated}`.
The agreed S01 facets are `path`, `watch`, `authority`, and `host`; this provider uses
the first three. `name` identifies the watched or metadata path when available.
Each captured field has a 512-character limit and at most 64 distinct causes are
retained. Unknown event history, forked/closed/inactive authority, and unattributed
dirty state remain unknown. Reporting performs no filesystem reads, cannot clear
dirty state, and survives cleanup of a retained borrower. Watch events, metadata
identity changes, missing-path transitions and construction races have captured
causes. Queue overflow stays failed even after later reads recover.

An already-dirty watcher returns false after its ordinary drain, without performing
a metadata sweep that cannot restore its authority. Watch failures still raise.
Clean validation still observes every recorded path and missing path and drains
before and after those observations. One-shot and retained paths share this logic.

Snapshot construction now remembers the actual file resolved during its first
required-file watch installation. Hash preparation does not repeat that complete
resolution. Every file still receives fresh path/open/final hashing identity
checks, and final full metadata/watch validation remains. Parent and alias watches
are installed before bytes are read. Construction scratch is cleared on success
and failure and is never retained digest authority. Content identity format and
receipt semantics are unchanged; implementation hashes continue to invalidate
changed coordinator code.

No production metadata memo or `validation_batch` helper landed. A proposed
cross-snapshot memo reduced an exploratory overlapping fixture's warm observations
but cannot establish metadata-only mount/remote-filesystem changes between
consumers. Independent pre/post watcher drains do not repair this limitation.
`rejected-memo.py` demonstrates a cached metadata observation accepting the second
consumer after such a simulated change; the ordinary fresh check rejects it.
The production regression `test_metadata_checks_remain_fresh_without_watch_events`
protects this conservative fallback.

## Caller integration patch requests

The coordinator should call `snapshot.stability_diagnostics(role)` on failed gates
without another `unchanged()` call. It can pass captured reasons/flags through
S01's `verification_telemetry.stability_diagnostics` for aggregate reporting.
S01 implementation contract was provided at
`277089d1831895c99697e5abbfd5862f67ac7552`; this provider has no import dependency on
that module and uses the agreed shape directly.

In `build_test_inputs.zig`, the `verification_cache` array must add:

```zig
    "scripts/verification_snapshot_profile.py",
```

Place it after `scripts/verification_snapshot_test.py`. That test imports the
profile fixture. `verification_session` already declares `scripts/`.
No additional build step is required. The coordinator/S04 must review final
configuration qualification after shared build wiring; this session did not
refresh a fingerprint. Keep ordinary `check_all` validation; do not apply the
rejected batching proposal.

## Focused evidence

All commands ran in the assigned S08 worktree. Final scratch used
`TMPDIR="$PWD/.tmp/s08-tmp"`; snapshot test fixtures also use worktree `.tmp`.
No native build or compiler artifact was needed. `manifest.json` records exact
source/helper hashes, Python executable/hash/version, pinned Zig version,
inherited CPU affinity, command statuses and the absence of qualified timing/RSS.

| Command | Exit | Evidence |
| --- | --- | --- |
| `TMPDIR="$PWD/.tmp/s08-tmp" python3 scripts/verification_snapshot_test.py -v` | 0 | `snapshot-tests.log`: 74 named tests pass |
| `git show fbfcaa7a923186a8e773c3760f81c10aa345a432:scripts/verification_snapshot.py > .tmp/s08-baseline/verification_snapshot.py` | 0 | Baseline source SHA-256 in raw counters |
| `TMPDIR="$PWD/.tmp/s08-tmp" python3 scripts/verification_snapshot_profile.py --module .tmp/s08-baseline/verification_snapshot.py` | 0 | `baseline-counters.json` |
| `TMPDIR="$PWD/.tmp/s08-tmp" python3 scripts/verification_snapshot_profile.py` | 0 | `candidate-counters.json` |
| `TMPDIR="$PWD/.tmp/s08-tmp" python3 experiments/development-loop-closeout-20261012/S08/rejected-memo.py` | 0 | `rejected-memo.json`: unsafe memo accepts, fresh check rejects |
| `git diff --check` | 0 | No whitespace errors |
| Normal implementation `git commit` with configured pre-commit hook | 0 | `implementation-commit.log`: Guardian 88 checks passed |

The 74 tests comprise the existing 62 snapshot/digest/retention cases plus 12
new work/diagnostic regressions. Existing cases cover source ABA, symlink
retargeting, directory membership and PATH sentinels, overflow, reset/fork,
bounds/eviction and active borrowers. New cases verify rejection without local
events, no duplicate construction resolution, alias replacement between resolution
and hashing, diagnostic bounds/detachment, missing-path explanations, retained
borrower cleanup, overflow persistence and unknown causes. The profile fixture
also confirms complete warm identity agreement and rejects all eight edited
closures.

## Deterministic work results

Paired fixture: eight distinct snapshot closures, 128 shared files and one unique
file per closure. Private scratch root has nine path components, recorded because
ancestor observations depend on path depth. These are instrumented metadata
observations, not a complete syscall trace or a real complete-verification action
inventory. Exact content-inventory hashes match across baseline/candidate.

| Scope | C0 | Candidate | Result |
| --- | ---: | ---: | --- |
| Cold metadata observations | 28,216 | 15,824 | 12,392 fewer, 43.9% reduction |
| Cold files / bytes hashed | 1,032 / 15,480 | 1,032 / 15,480 | Same work and inventory |
| Cold directories enumerated | 16 | 16 | Same inventory discovery |
| Warm metadata observations | 2,256 | 2,256 | No improvement claimed |
| Warm files hashed / directories enumerated | 0 / 0 | 0 / 0 | Qualified fixture reuse preserved |
| Warm snapshot reuses / validation calls | 8 / 16 | 8 / 16 | Same complete fixture checks |
| Edited metadata observations | 1,128 | 0 | Already-rejected authority avoids all redundant scans |
| Edited rejected closures | 8 / 8 | 8 / 8 | Same rejection |

`comparison.json` records equal inventories/warm work and exact differences.
Cold, warm and edited latency, median/p95, peak RSS and large-input heap growth
are **not qualified**. Test runner durations in raw logs are operational only.
Additional construction scratch is O(declared files) and clears before retention;
dirty reasons are bounded separately. Watch/fd installation and retained-session
limits did not change.

## Open requirements and integration order

1. Integrate the fixed implementation commit, then the evidence/handoff commit.
2. Apply the small declared-input patch and coordinator/runtime failure-report
   wiring; run their focused tests and review the final configuration fingerprint.
3. S10 must remeasure real retained-session metadata/watch cost on the exact
   integrated candidate. The old 175,677 count is historical, not a new baseline.
4. S10 must run complete required gates and the real edit/failure matrix, including
   independent execution and host changes, plus isolated timing/RSS/large inputs.
5. Reducing **unchanged warm** metadata validation remains open. Any next memo
   proposal needs complete local filesystem/mount/event authority or a different
   proof; metadata-only host changes must keep fresh checks or fail unknown.
6. Ordinary-loop latency targets and self-hosting DL7 acceptance remain outside
   this session's evidence. Neither a focused pass nor these counters close them.
