# Wave 11 qualification

Baseline: `5c4d4235f`. Pinned Zig: `0.17.0-dev.1683+5ceec001b`.
The changed sources and installed compiler are recorded in `source-hashes.json`.

Wave 11 retains live watched input inventories across sequential developer
requests and coordinates matching native work across processes. Native source
builds and installed commands retain their Python-free contract. The explicit
Python session is developer tooling, with JSON Lines input and completions;
normal tool output goes to stderr.

`native-summary.json` records nine successful real-process scenarios. Parent
locks and Linux's blocked-lock records synchronize these probes; sleeps and
elapsed durations are not treated as concurrency or performance evidence.

| Scenario | Observed result |
| --- | --- |
| Two cold builds in separate project roots | Four units compiled once in total; one link; both outputs correct |
| Same private program cache, different sharing settings | One link and one reuse; no unit compilation; distinct correct outputs |
| Reversed source/import order | Overlapping unit batches finish without deadlock |
| Same portable test in two roots | One executed pass and one cached pass |
| Held test claim, different test key | Independent test finishes while the first key remains blocked |
| Corrupt shared success | Fresh execution repairs the receipt |
| Source edit while waiting | Request fails with `SourceChanged` |
| Forced owner killed after invalidation | Old success stays invalidated; follower executes and passes; GC skips active work |
| Actual failing test | Both requests execute and fail; no cached success |

Focused checks passed: 62 snapshot tests, 15 session/protocol tests, 46 verification
coordinator tests, 35 fuzz coordinator tests, 39 Juice cache tests, and 5 retention
CLI/pruner tests. The complete Guardian scan passed all 88 checks. Their logs are
included alongside this report. Native claim and retention unit tests are also
part of the final gate.

Full inventory and warm-session qualification: **passed**. All 43 inventory
groups qualified, including `test` and `fmt-check`: 127/127 steps succeeded,
2748 Zig tests passed, and 24819 shard exclusions were reported as skipped.
The unchanged warm request succeeded with 44/44 steps, reused all 32 reusable
groups and executed the 11 required fresh groups. Both reports recorded stable
inputs. `qualify_session.py` submitted both requests through one live session;
`session-summary.json` also records a clean stop.

| Work | First request | Unchanged warm request |
| --- | ---: | ---: |
| Files hashed | 28525 | 0 |
| Bytes hashed | 2214978034 | 0 |
| Directories enumerated | 2261 | 0 |
| Retained snapshots reused | 0 | 5 |
| Metadata observations | 1029221 | 174126 |
| Verification groups reused | 0 | 32 |
| Build admissions | 1 | 0 |
| Gate admissions | 1 | 1 |

These counters cover coordinator input snapshots, excluding the independent
startup runtime guard. The first request starts a fresh session without valid
action receipts for these inputs; it does not clear Zig or native build caches.
The warm request still validates metadata and executes required fresh cohorts.
The fake fully reusable coordinator tests independently verify zero admission.
Observed admission occupancy was 5.902s build + 575.739s gate for the first
request, and 0s build + 35.898s gate for the warm request. These are operational
observations on the shared server, not isolated timing benchmarks or a measured
Wave 10 versus Wave 11 speedup.

The first full gate exposed an existing corruption fixture that treated every
entry in a program-cache directory as an artifact. The helper now skips
directories and control files, preserving its two-artifact corruption assertion.
Its focused regression passed, followed by the complete green run above.
Reinstallation after this test-only correction preserved the compiler digest
used by the nine native concurrency scenarios. Final source/compiler digests
were checked against the frozen manifest with no differences.

Scope and limits:

- Reuse retains watches and identities in one process. Reset, close, fork,
  eviction, mutation or event loss removes authority. Active borrowers remain
  attached to their original revision. No metadata-only proof is persisted.
- Defaults retain at most 16 snapshots and 262144 accounted metadata, inventory,
  declaration and watch entries. Long text consumes additional accounting units.
  Oversized/busy requests remain transient, and reset closes transient watches.
- Path metadata checks and provider resolution still run. Changed scopes are
  conservatively reconstructed; this is not a compiler AST daemon or automatic
  attachment from one-shot commands. A supervisor queues requests on one stream.
- Startup assumes a trusted Python installation, rejects preloaded coordinator
  helpers, and guards subsequent source/runtime/library changes. A change to
  loaded implementation code requires restart.
- Native claims protect exact reusable work, with sorted batches and receipt
  checks after waiting. Foreign C uses manifest-family claims followed by its
  existing dependency checks. Cold unit batches hold descriptors for missing
  keys; resource exhaustion reports an error and releases acquired claims.
- Upgraded native drivers and pruners cooperate through retention leases. Shared
  v2 collectors and legacy pruning reclaim idle work locks under exclusive
  ownership while preserving permanent lease inodes. Private test receipt hits
  retain their existing reuse semantics.
- Counters establish eliminated work. Gate/admission durations are operational
  observations on the shared machine, not isolated speedup measurements.
