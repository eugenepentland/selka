# Support7 applications

All four mandatory shapes pass five checked modes: 20 builds, 60 counted executions. Word count, nested JSON and resource-backed file processing run small/large deterministic inputs; parallel computation runs both sizes at 1/2/8 workers. Every run preserves its frozen expected output, records zero RC events and no managed exit leaks. Every binary passes emitted LLVM and linked-symbol checks.

Compiler/source/harness identities are in `summary.json`; source hashes and binary hashes are in `results.json.gz`. `raw.tar.gz` retains commands, stdout/stderr, per-run counters and emitted LLVM. Frozen source/data/checksum contracts and the original/migrated pairs are under `A06/`. The coordinator ran the unchanged A06 harness after that worker became unavailable.

This is intermediate Support7 evidence, not C1 or default/retirement qualification. Build durations include admission wait and are not compile-time measurements; managed counters are not process RSS. Later source/compiler changes require affected reruns.
