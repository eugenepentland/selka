# Frozen primer and corrected unit telemetry audit

Read-only reviewed old frozen candidate9d1b51f310477e4ceccffd8ad41ecf6fc2156e13.
Complete forced primer passed with stable inputs:46groups,106required/registered
members,106explicit test telemetry slots and zero outstanding action groups.
Supported46members comprise30native plus16Python members;60are unknown,
including59unsupported/absent contracts and the documented corrupted unit/member0.

Known3121executed cases are all timed:2752native(2747named/5unnamed) and369Python.
Every observed record is complete and nontruncated. Native core1026,cli270,
golden4,memory7,tooling28,scalar9,componentsupport10 inventories execute each ID
exactly once. Unit has11valid shard records and1398unique observed executions;
compiled inventory1532 leaves134timing gaps(128named/6unnamed), matching lost
member0. The gate log independently reports member0 PASS134; no failure result
was converted to success, and the malformed sidecar became explicitly unknown.
Selected dispatch counts include cross-shard skips and must never be added as
unique tests or summed as wall time. Frozen-primer-telemetry-audit.json contains
exact per-group/unknown-member accounting and final report SHA.

The retained gate stdout/stderr file captures are available, complete and not
truncated. Eight live tee backlog drops affected display, with files retained.
This is distinct from missing or malformed supported test telemetry.

Root adopted fixture isolation at final1eea987411a1ac5b42941b2ad26a25052a002460
and regenerated the actual unit root under its existing admission. S01 launched
no build/gate. Exactly12sidecars match unit/member0..11, all supported, complete
and nontruncated. Executed/timed union1532 =1532unique, with1526named and6unnamed,
all passed. Member0 now134timed; member1=128, other members127. The full executed
records, sidecar/log/binary hashes and raw build log are committed in
regenerated-unit-telemetry-audit.json and regenerated-unit-build.log. Skipped
rows are intentionally omitted from this archive to avoid duplicating18384
protocol dispatch rows; source sidecar hashes and per-member counts preserve
provenance. Original compiler/test binary remains unchanged; standalone test
seed differs and is recorded in the raw command log. No wall comparison made.

This restores missing unit timings through an independently executed diagnostic
run. It does not rewrite old primer observations or label the final reused unit
step fresh. Native clocks remain runner-protocol intervals including reporting
and transport; pure body duration remains unknown. Guest timing and unsupported
standalone drivers remain unknown. Current candidate complete selective
requalification belongs to root/S10 and must retain explicit unknown reuse
telemetry. These observations do not qualify per-test memory, headroom, latency
p95, bootstrap parity, or self-host ratios.
