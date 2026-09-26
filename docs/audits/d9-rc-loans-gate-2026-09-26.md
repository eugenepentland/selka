# Joined RC borrowing and constructor checkpoint — 2026-09-26

Frozen source `3f300771` passes the full required gate and both uncached RC
language sweeps. Its Debug compiler SHA-256 is
`339b1ffe5799a10e09377e7042eafabc3a9b9f955d7645f7631da021075d4f23`.

| Validation | Result |
|---|---|
| Main gate | 94/94 steps; 2,215 executed tests |
| QBE gate | 51/51 steps; 437/437 tests |
| Native-build gate | 29/29 steps |
| Formatting | 2/2 steps |
| Actual RC QBE language sweep | 731/731 tests, 127 programs, zero cached/dropped/unloaded |
| Actual RC LLVM language sweep | 731/731 tests, 127 programs, zero cached/dropped/unloaded |

The 22,508 main-gate exclusions are shard exclusions. LLVM uses `--release`
(O3/full LTO); neither sweep supplies an overriding `--qbe` option. Full logs,
verdicts and command identities are retained as `evidence/d9-rc-loans-*`.
The latest main remains `b292660a` and was already an ancestor before the gate.

This checkpoint combines pointer-transfer runtime fast paths, whole-body loans
for proven read-only scalar-result functions, stable collection receiver loans
for scalar reads, and guarded takes of consumed constructor fields. Their
isolated evidence is in the corresponding pointer-fastpath, readonly-bodies,
scalar-read-loans and constructor-takes audit reports. Recursive constructors
retain ownership; callbacks and mutable or escaping inputs retain the general
paths. Arenas and trap cleanup remain covered by actual RC execution.

Performance acceptance is still open. Early exact-workload results on the
superseded `39f75f3f` source fail the criterion substantially; private probes
show progress but do not establish the complete corpus instruction or RSS
criterion. GC remains the default. Small flat runtime transfers, inert receiver
scopes, further physical loop hoists and the GC/RC callback receiver discrepancy
are subsequent work. WP-5 remains dependent on completed WP-4.
