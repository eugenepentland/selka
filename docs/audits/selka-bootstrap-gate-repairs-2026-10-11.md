# Bootstrap integration gate repairs

The full gate on `8aae33ef38207492c80fbf36c96908afdfa65907` failed. These repairs
close its Core scheduling/test and stale scalar-byte expectation failures;
parser expectations and actual body-library admission remain separate work.
This is focused evidence, not a passing integrated gate, full bootstrap, or
performance acceptance.

The optimized Core test compilation used 5,222,174,720 bytes, exceeding its old
4.5 GiB scheduling estimate. `build.zig` now assigns 6 GiB to optimized Core test
compilation and enables Guardian test diagnostics on that root. Host, guest,
and process memory limits are unchanged.

The publication allocation-failure regression passed in Debug but failed as
`NondeterministicMemoryUsage` in ReleaseFast. In-place allocator growth depended
on backing bucket occupancy between trials. Its test helper now forces growth
through allocation, retaining failure injection and leak checking for every
allocation site. Production metadata publication is unchanged. All 15 graph
metadata tests passed in each build mode. Guardian initially rejected the helper
change for its missing changed spec/test annotation; the final spec annotation
and descriptive test-name change passed all 88 Guardian checks. Those annotation
changes leave the tested executable helper and assertions unchanged.

The sequence test now requires the already-supported canonical `u8[]` recipe and
reuse, while retaining refusal when the managed descriptor is absent. Its 16
tests passed normally and under release/fact/leak checks.

[The evidence receipt](evidence/selka-bootstrap-gate-repairs-20261011/receipt.json)
binds final source hashes and preserves the original full-gate and optimized
test failures, focused commands/results, the failed Guardian run, and the final
whole-tree Guardian result. Logs are deterministic gzip archives with hashes of
both archived and uncompressed bytes. Reproduction uses the pinned Zig through
`scripts/build-slot.sh build`, a private local cache, disk-backed `TMPDIR`, one
build job, and the shared heavy-build lock. The exact native commands appear in
the archived focused report and runner.
