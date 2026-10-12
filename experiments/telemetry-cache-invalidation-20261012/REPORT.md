# Telemetry placement invalidated unchanged guest tests

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
This is an owned developer transport change, without a compiler ownership transfer.

Coordinator and S01 (delegated configuration-review role for this three-agent
investigation) reviewed the prior 212-file configuration closure. Only the build
adapter's environment-name literal changed. All declarative input consumers,
registration, producer closures and install behavior remain unchanged. The exact
configuration is explicitly qualified in [configuration-review.json](configuration-review.json),
with the previous broad-invalidation fallback preserved for later unknown changes.

Focused validation: 89 coordinator tests passed, including inherited alias scrub,
semantic variable preservation, unique private directories, cleanup and unchanged
action reuse. All eight native collector and ten Python collector checks passed, including
legacy-path isolation. Eleven live compiler controls passed: new diagnostic
paths and absence preserve cache keys; unknown semantic `MYLANG_` settings still
change keys; force/fact/leak checks run fresh; an edited test fails while its
unchanged neighbor reuses; restoring the source reuses both prior successes.
See [controls-summary.json](controls-summary.json). Full-candidate verification
remains pending.

The real-suite experiment uses the unchanged frozen Debug compiler
`cc827c4e79243f299dc92327fa86049669307d1f0edfa816a5b641dc443176b0`,
private experiment caches and explicit `--jobs 4`. Preparation is outside timing.
The measured phase primes the new namespace inside timing admission because
admission kind is itself a keyed setting. The bounded experiment attempts three subsequent old/new pairs in alternating
order (AB, BA, AB). Both variants share each private per-mode cache, so switching
namespaces can replace the whole-file manifest and require individual receipt
lookup. These are namespace-transition observations, not homogeneous steady-state
samples. The ten-member sequential sum is not complete-gate wall time and this
small sample does not establish p95. The 360-second window expired during the third pair (exit 124); it is retained
as incomplete and excluded from performance qualification. The two completed
pairs each selected 5,412 tests per variant: old 5,412 fresh / zero cached; new
1,796 fresh / 3,616 cached; no failures, skips or unsupported tests. The fresh
subset is 1,790 release fact/leak checks plus six conservative metadata exclusions
(three tests in each ordinary mode). See [transition-summary.json](transition-summary.json).
Complete candidate verification and whole-loop measurements are pending. No source or compiler rebuild is hidden inside a claimed edit result.
