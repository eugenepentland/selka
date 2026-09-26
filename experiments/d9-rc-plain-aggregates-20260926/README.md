# Plain aggregate code-generation diagnostic

See `docs/audits/d9-rc-plain-aggregate-codegen-2026-09-26.md` for the admission
proof, isolated results and limits. The control is source `7c78c511`; it already
includes the preceding fresh-constructor optimization. The runtime zero-edge
replacement and terminal read-loan optimizations are deliberately absent.

`measure.py` records the actual immutable Debug compiler pair, source and binary
hashes, native backend/LTO manifests, all median-three instruction samples and
ownership counters. `validate.py` runs standalone GC-stress/RC guest and trap
controls. `guests.py` runs existing aggregate/array/H fixtures on both backends.
Paths in those scripts identify the retained local immutable installations; the
compressed receipts preserve the exact commands independently of those paths.

`nbody_10000.my` is the benchmark source with just the step count reduced from
5,000,000 to 10,000. This is a diagnostic workload, not a replacement for the exact
acceptance corpus. `accepted-gc.json.gz` checks its output against the immutable
accepted f6 GC compiler and records a separate diagnostic GC reference.
