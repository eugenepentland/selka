# Managed iteration identity integration checkpoint — 2026-09-26

Frozen source `d57fef032dae830699e491621027aa418bd05057` passes the full
required gate and both uncached RC language sweeps. The Debug compiler SHA-256 is
`4e3cc120f065f63ecb3e8b75ce22c37582c1c4ba623a70853898d8063fd1aedb`.

| Validation | Result |
|---|---|
| Main gate | 94/94 steps; 2,232 executed tests |
| QBE gate | 51/51 steps; 437/437 tests |
| Native-build gate | 29/29 steps |
| Formatting | 2/2 steps |
| Actual counted RC QBE sweep | 774/774 tests, 136 programs |
| Actual counted RC LLVM sweep | 774/774 tests, 136 programs |

Both sweeps report zero cached, skipped, dropped or unloaded cases. The 22,695
main-gate exclusions are shard exclusions. LLVM uses `--release` (O3/full LTO)
without an overriding `--qbe` option. The exact commands are in
`.tmp-rc/gate-identity.sh` and `.tmp-rc/sweep-identity.sh`; all logs and verdicts
are archived by the [identity index](evidence/d9-rc-identity-identity.json).
The latest main remains `b292660a` and is already an ancestor of this source.

The [iteration correction](d9-iteration-identity-2026-09-26.md) fixes the two
unit and one native-golden failures recorded at `743fea73`. The required gate's
231 reproducible native goldens retain their recorded outcomes. This checkpoint
also incorporates the intervening invariant, scalar-store, inert-projection,
stable-journal and frame-region optimizations. Its existing language tests cover
the new iteration lifetimes and journal type reuse.

A supplemental counted-RC replay of all 231 native goldens on each actual
backend is separate work in progress. Its initial driver used build-only options
with `run` and received usage errors; those results are invalid evidence, not
compiler regressions. The corrected driver uses QBE by default and `--release`
for LLVM. It keeps five explicit legacy-sharing cases per backend on their
documented GC fallback, and does not change any recorded expected outcome.

WP-4 performance acceptance remains open. Private profiles still exceed the
per-program instruction limit substantially; the complete instruction and peak
RSS criteria have not passed. GC stays the default. Constructor publication,
loop versioning, tracing-root removal and frame-template experiments are later
slices. A separate newly observed direct view-mapping constructor snapshot
mismatch on GC is under investigation and is not covered by this green gate.
WP-5 has a proposed design and still depends on WP-4 acceptance.
