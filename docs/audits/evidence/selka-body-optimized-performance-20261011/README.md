# Optimized B7 performance: failed budget, shared-machine contention

The matched run completes 20 samples for each of 36 workflows on both sides.
Its strict median/p95 verdict fails 34 rows and passes two; the process exits 1.
This is not performance acceptance. Other projects used the shared machine
during the run, so these results are diagnostic data and cannot establish the
size of any improvement over earlier B6 or B7 measurements.

Both sides use the same frozen ReleaseFast host and seven-package installation
from `61327e5be5ad8f4bce7b007a05772a5102ad41f9`. The candidate selects only the
Selka body checker. Host SHA256 is
`d438a9e1ee8df96d8280403be5c013ec9db08c0609893c0a99edbdcfb6a5f509`;
body SHA256 is
`a5bc6f28df1381cbcfbbb739f450d65605ca8c101c319e99230ce2f79163cb3b`.
`summary.json` retains complete authenticated package identities. These differ
from the later formatted-source Debug gate, whose evidence is archived
[separately](../selka-body-entry-optimized-timeout-20261011/README.md).

The observed candidate/native median ranges across six fixture groups are:

| Workflow | Observed ratio |
| --- | --- |
| Compile with fresh application cache | 1.87–3.70× |
| Check | 3.62–7.64× |
| Warm compile | 2.73–4.97× |
| Cold tests | 3.05–5.36× |
| Warm tests | 6.68–14.68× |
| Short generated runtime | 0.65–2.93× |

All compiler gate/build slots were held through FIFO admission, and the benchmark
was pinned to CPUs 2, 3, 10 and 11. Those reservations cover cooperating compiler
jobs; they do not reserve the entire machine. The read-only CPU observer recorded
external process activity with overlapping CPU affinity in all 25 sampled
intervals. It sampled process CPU deltas and excluded the reservation process's
descendants; it can miss short-lived tasks. The launcher's historical log line
`timing isolated` describes its compiler-slot reservation, not verified exclusive
machine isolation. A clean comparison must control this external contention.

Application caches are private; shared native units are prewarmed for both sides.
Twelve fixture/host behavior checks each run two tests with facts and leak checks
before timing. The exact frozen ReleaseFast installation also passes the retained
443-workflow/886-comparison qualification matrix. These remain intermediate
component measurements, without whole-compiler, cold-toolchain or full-language
acceptance. The native catalog, later semantic passes, backend and driver remain.

Raw timing samples, cache receipts, qualification reports, reservation logs and
CPU observations are retained as deterministic gzip files. The exact measurement
script, reservation wrapper and CPU observer accompany them. Run
`sha256sum -c SHA256SUMS` to verify the archive.
