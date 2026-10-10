# Wave 5: incremental performance evidence

Baseline: `bb2007483` (Wave 4B), branch `codex/selka-cache-wave5`.

Implement a developer coordinator over native Juice. Native `juice plan` exports
the authoritative manifest, expanded inputs, tool configuration and measurement
context without building or running a workload. The coordinator watches complete
per-workload dependency scopes, looks up retained evidence before server admission,
and admits only missing captures. Installed commands remain native and Python-free.

An explicit suite maps workload IDs to existing Juice manifests and closed external
dependency contracts. Separate harnesses and binaries provide locality: private
edits invalidate their consumers; shared helpers invalidate every declaring consumer.
A shared executable remains one physical dependency, including its link layout.
Source globs conservatively watch their complete directory scopes, including hidden
files. Undeclared external reads cannot become qualified evidence by observation.

Reuse policies distinguish deterministic software counts from historical physical
samples. Both require a complete declared execution/provider contract. Fresh is the
default; explicit fresh requests always capture again. Historical reuse never claims
a new observation or an elapsed-time guarantee. Thresholds belong to comparison,
which revalidates retained records and invokes native Juice without capture admission.

Retain original native records, raw collector/oracle files, semantic counters and
exact plain/counted binaries with bounded checksummed storage. Incomplete records,
missing/corrupt evidence, changing inputs, unsupported injection and uncovered runtime
libraries cannot publish receipts. Watches span planning, queueing, execution and
publication. Force/failure cannot resurrect a prior success through repaired blobs.

Also cache native static cost queries at final Core function granularity, including
optimization events, reachability, verification mode and allocation dependencies.
Reuse existing frontend/optimization queries and cache successful LLVM remark queries
by their exact instrumented unit/tool contract; unknown analyses remain unknown.

Qualification: focused native/Python regressions; real cold/warm/edited/shared-helper
captures, fresh requests, threshold-only comparison, corruption and cancellation;
static query cold/warm/edit/fresh parity; full repository gate and format checks.
Retain raw evidence and report actual work/admissions. Physical counts are evidence
under recorded context, not evidence of elapsed-time improvement.
