# Telemetry placement invalidated unchanged guest tests

Confirmed and fixed on integration source `fe7637e82f58430573d99473e5389a4369bbba7e`.
Coordinator plus S01 and S10 performed this investigation; no additional workers,
compiler ownership transfer, push or main update. All required complete verification
passed, followed by two unchanged complete requests.

| Observation | Previous warm captures | Fixed warm request 1 | Fixed warm request 2 |
| --- | ---: | ---: | ---: |
| Gate occupancy | 41.33–43.80 s | 23.02 s | 27.84 s |
| One-shot request window | 50.49–56.50 s | 33.54 s | 36.84 s |
| Outer action groups reused / fresh | 35 / 11 | 35 / 11 | 35 / 11 |
| Guest/language tests reused / fresh | 0 / 5,412 | 3,616 / 1,796 | 3,616 / 1,796 |

The historical comparison is descriptive, not a randomized paired trial or a p95
claim. Request windows exclude admission queues and final report writing; gate
occupancy excludes preparation outside admission. The previous retained request
window of 47.72 s is a different transport and is not used as the one-shot baseline.
See [capture.json](candidate/capture.json), [final-audit.json](final-audit.json),
and the [previous qualification](../development-loop-wave2-20261012/REPORT.md).
S10 independently verified the final inventory, compiler hash, complete native
telemetry and both warm-request counts. The root evidence hash manifest covers
archived compressed files; original capture hashes refer to decompressed logs.

## Cause and fix

The frozen compiler reproduces a cache miss when only the developer telemetry
output directory changes. Two pure tests execute with directory A, reuse on a
second A request, execute with B, reuse on a second B request, and reuse their
prior successes when A returns. Removing the variable changes identity again.
See [result.json](result.json) and [probe.py](probe.py).

The compiler keys `MYL_`/`MYLANG_` execution variables conservatively. Verification
was supplying a new `MYLANG_TEST_TELEMETRY_DIR` for every selected gate. Only the
Python developer collectors read that transport; native guest receipts hashed it.

The fix uses `SELKA_VERIFICATION_TELEMETRY_DIR` across the coordinator, build
adapter and native collector. Both legacy and new inherited paths are scrubbed;
each request still gets a private temporary directory. Native receipt semantics,
compiler code, source invalidation and force/fact/leak policies are unchanged.

The required fresh subset is 1,790 release fact/leak tests and six metadata
exclusions: three application-cache tests in each ordinary mode. Those tests use
persistent memo/durable callable digests, whose finalization metadata currently
prevents safe receipt keys. They remain fresh. The same ten guest/language suite
members still select 5,412 tests; the complete inventory is unchanged at 46 groups
and 106 registered members, with no unknown actions.

## Correctness and configuration qualification

Coordinator and S01 (delegated configuration-review role for this three-agent
investigation) reviewed the prior 212-file configuration closure. Only the build
adapter's environment-name literal changed. All declarative input consumers,
registration, producer closures and install behavior remain unchanged. The exact
configuration was explicitly qualified as
`6e21ce1c64e0d3e82e2ce1fee75053579b67221706d4aeb46f128691049801c6`.
The previous broad-invalidation fallback remains for later unknown changes.
See [configuration-review.json](configuration-review.json).

- All 89 coordinator, eight native collector and ten Python collector checks passed.
  Regressions cover alias scrubbing, semantic variable preservation, unique private
  directories, cleanup, action reuse, legacy-path isolation and parent sidecars.
- Eleven live compiler controls passed: new diagnostic paths and absence preserve
  keys; unknown `MYLANG_` settings still change keys; force/fact/leak checks run;
  a changed test fails while its unchanged neighbor reuses; reverting the source
  reuses both prior successes. See [controls-summary.json](controls-summary.json).
- Complete verification executed all 46 groups, including formatting: 612.70 s
  request window, 595.68 s gate occupancy, stable inputs, zero outstanding work.
  All 31 native telemetry members remained complete, covering 2,886 executed tests;
  Python collector coverage also remained complete. Unsupported observations retain
  their existing unknown status rather than becoming invented timing coverage.
- Both unchanged requests passed with 35 groups reused and 11 freshly admitted.
  All 46 action keys and the budget context were identical across the three requests.
  The inventory matches the prior capture exactly. The installed compiler still hashes
  to `cc827c4e79243f299dc92327fa86049669307d1f0edfa816a5b641dc443176b0`.
- Normal Guardian commit hooks passed all 88 checks. No feedback log was modified.

## Preliminary experiment limits

The direct-suite experiment used that frozen Debug compiler, private experiment
caches and explicit `--jobs 4`. Preparation ran under build admission; timing ran
under one exclusive 360-second window. A new-namespace primer ran inside the timing
holder because admission kind is itself a keyed setting.

Both variants shared each private per-mode cache. Alternating names could replace
the whole-file manifest and require individual receipt lookup; these observations
are namespace transitions, not homogeneous steady-state samples. Two complete pairs
each selected 5,412 tests per side: old 5,412 fresh / zero reused; new 1,796 fresh /
3,616 reused, with no failures, skips or unsupported tests. Their sequential times
are not complete-gate wall time.

The window expired during the third pair (exit 124). It is archived as incomplete
and excluded from performance qualification; no timeout was silently extended.
See [transition-summary.json](transition-summary.json). The accepted warm-loop
observations above come from separate complete requests against the frozen fix.

## Next work

Use these corrected warm measurements as the persistent-server prototype baseline.
This fix is complete; it does not close the full ordinary-edit matrix, stable tail
latency, long qualification or self-hosting milestones. No server implementation
has begun. Existing complete/freshness requirements remain intact.
