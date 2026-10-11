# Application caching and durable recovery — Waves 7b and 7c

Implementation branch: `codex/selka-cache-wave7`, following Wave 7a commit
`2d00dc3da`. This worktree leaves the primary integration checkout untouched.

The new embedded Selka libraries are `hashes`, `cache_record`, `persistent_memo`
and `durable`. The native compiler supplies actual-callable closure identities;
the native filesystem provider supplies bounded reads and complete listings,
atomic synchronized writes, directory sync and exclusive crash-released leases.
Cache admission, canonical records, eviction, checkpoint ordering, verification,
recovery and final publication policy are implemented in Selka.

`persistent_memo` retains completed byte snapshots for exact integer/text/byte
keys. Its fixed byte result format and compiler-issued identities avoid trusting
manual implementation versions or arbitrary serializers. Zero entries force
execution; missing authority and oversized values bypass retention. Provider
errors remain errors; malformed bounded records are recomputed.

`durable` runs captured byte chunks through a pure byte-state callback. It
retains artifacts before committing their hashes in a journal, checks the entire
committed prefix before reuse, collects only uncommitted artifacts/private temps,
and publishes final bytes atomically. Incompatible or corrupt committed state
fails closed. Both resumed published runs and persistent hits synchronize their
directory before acknowledging a prior potentially uncertain publication.

## Qualification

- Focused callable identity Core group: 5 passed.
- Two additional native test-receipt regressions passed in shared and per-test
  key modes: identity-query roots execute fresh, ordinary roots reuse, a broader
  compatible-target edit turns the affected test from passing to failing in
  agreement with forced execution, and neither individual nor whole-report
  receipts hide that failure after batching/filter changes.
- Frontend/native callback group: 10 passed, including Debug and Release.
- Both negative callback-boundary groups: 8 passed each (one selected named test
  plus seven shared unnamed checks).
- Native provider Core group: 2 passed. It exercises actual partial writes,
  zero progress, file and directory sync errors, file-size limits, simultaneous
  writers, SIGKILL, lock release, symlink/special-file refusal, more than 256
  directory entries, partial-list read errors and ambiguous physical grants.
- New Selka library Debug group: 8 passed, covering independent SHA-256 vectors
  at padding boundaries, canonical records, corruption, disabled retention,
  request bounds and refusal of a nondurable memory provider.
- Full native application matrix: **155 invocations, 12 actual SIGKILL cases**
  passed against independently generated CSV output and independently decoded
  records. Source, callback, schema and input changes/reverts; restored timestamps;
  tagged arguments; committed-prefix reuse; competing recovery; corruption;
  orphan GC; captured-input mutation and uncertain publication are covered.
- Additional large-journal native run: 260 chunks and 262 retained directory
  entries; cold 260 fresh, warm zero fresh / 260 reused, exact independent CSV,
  state, digest and journal-chain checks passed (`large-prefix.json`).
- Additional Debug native pipeline: 5 invocations and one actual SIGKILL;
  committed prefix one resumed with five fresh steps, then all six reused on a
  duplicate recovery (`debug-pipeline.json`).
- Complete repository verification passed: all 42 groups selected, 126/126 gate
  build steps succeeded, including formatting, documentation and the permanent
  application recovery smoke matrix (12 invocations and one SIGKILL).
  Guardian's configured 88 checks passed.
- Unchanged verification passed: 31 groups reused, including `application_cache`,
  and 11 freshness-required groups selected. No build admission was needed;
  observed gate admission was 23.336 seconds, versus 647.494 seconds for the cold
  verification. These are coordinator observations, not isolated performance
  benchmark results. Input snapshots remained stable in both runs.

The final gate records are `verification-cold.json`, `verification-warm.json`,
`verification-complete.log` and `verification-warm.log`. Final application
qualification comprises 162 native invocations and 13 actual SIGKILL cases across
`application-native/summary.json`, `large-prefix.json` and `debug-pipeline.json`.
All three qualify compiler SHA-256
`bb8670209330f84006b66dbd1b3e33af854480f93eab91aa9680ee30dbfcc465`;
`source-hashes.json` records the 48 implementation and documentation inputs.
Other logs retain earlier implementation and qualification iterations.

The permanent `test-application-cache` gate invokes the bounded smoke matrix from
`tests/application_cache.py`. The full matrix uses the same driver without
`--smoke`; `qualify.py` is only a developer wrapper. Python is not required by
source installation, installed compiler commands or application recovery.

## Boundaries

This qualifies **process-crash recovery**, including killed native processes.
Actual power-loss durability has not been experimentally established. Storage
must use a stable dedicated local directory; external directory replacement or
hostile writers are outside cooperative ownership. Integrity checks are not
authentication. Network/database effects and distributed recovery are outside
this byte-pipeline API.

Compiler/runtime/toolchain/build changes can conservatively invalidate all
callable identities. Different checked effect ceilings and source location
changes can also prevent reuse. Tests that reach `function_digest` require fresh
individual execution: the ordinary test key cannot yet represent all observable
identity-query dependencies or live batch membership. This prevents a cached
passing verdict from hiding a changed digest; ordinary test roots remain eligible.
A durable journal with an incompatible identity is retained and rejected; use a
new run directory for a changed workflow.

Persistent bounds: 0..256 entries, 0..1 MiB raw key plus value per entry. Durable
bounds: at most 1,024 chunks, selected 1..8 MiB input, cumulative chunk bytes,
cumulative output and individual state snapshots. Native listing permits up to
4,096 entries and detects incomplete enumeration. These bounds do not make an
arbitrary callback terminate or replace the application's runtime memory budget.
