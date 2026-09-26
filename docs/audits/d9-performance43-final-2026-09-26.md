# D9 corrected default performance acceptance, 2026-09-26

The complete stage 3 instruction gate passes on both backends. All 86
baseline/candidate output comparisons pass, including schematic SVG checks.
This closes the performance criterion; the separate default migration gate
still needs its random-stream assertions corrected before WP-3f is complete.

| Backend | Programs | Instruction geomean | Largest ratio | Programs above 1.3× |
| --- | ---: | ---: | --- | --- |
| QBE | 43 | 1.021851044× | Lox VM instantiation, 1.242042590× | None |
| LLVM | 43 | 1.046853543× | Lox VM binary trees, 1.289478784× | None |

The limits remain geomean ≤1.05× and every program ≤1.3×. The exact set is
27 historical parity keys, three schematic inputs and 13 Lox VM scripts per
backend. The supplemental recursive-tree variant and tree interpreter are
excluded, as in the closeout plan. No baseline, workload size or threshold
was changed to obtain this result.

## Frozen inputs and method

- Compiler source: `178d43dc`, a Debug build with the real value-semantics
  default. SHA-256:
  `52ddd1337b4998b2a22184cac58af5ae4b0f4bc465dd449cfae3271c7451575d`.
  Candidate commands do not pass a value-semantics override; the environment
  is cleaned of `MYLANG_*`, and no ancestor project file overrides the mode.
- Guest source: `4798d47f`. Its compiler/build sources match `178d43dc`.
  It includes the indexed payload-return proof and Lox setter, late closure
  publication, scalar instance/class readers, global-table hash hoist, nested
  receiver scopes and the corrected `ref_local` liveness.
- Baseline: exact `60b668cf`, legacy sharing, compiler SHA-256
  `48427e9ac1c01b74e60d1b4c098c8fc149a6b5fef3c07e110c7fb4ba16cbb545`.
  All 58 executables were private copies whose hashes matched both the
  private and original historical manifests. This run needed no recovery or
  resume, and never measured the earlier accidentally modified artifact.
- Harness: historical `experiments/perf-gc-dict-20260925/scripts/pc.py`,
  byte-identical to `60b668cf`, driven by the retained
  [acceptance script](evidence/d9-performance43-final-harness.py). The driver
  uses its build commands, sizes, output checks and runtime specifications.
  Guests are ReleaseFast; LLVM uses O3 and full LTO. Compiler builds are Debug.
- Each ratio is median-three `instructions:u`, with CPU 2 affinity and
  alternating baseline/candidate order. There are 516 successful perf runs.
  Cycles are retained only as secondary data. Both sides pass their output
  check before measurement (172 successful side checks).
- Schematic declared provider functions are emitted independently for each
  side. Compiler, guest source, provider, executable and schematic IL hashes,
  exact commands and raw observations are retained in the
  [measurement data](evidence/d9-performance43-final.json) and
  [build manifest](evidence/d9-performance43-final-builds.json).

The final driver explicitly requires all 86 checked ratio rows, 43 per arm,
and both thresholds before printing `ACCEPTANCE PASS` and exiting zero.
An independent Astra review checked the workload set, flags, baseline hashes,
source/provider identity and sample arithmetic. The integrator recomputed
all 86 medians/ratios and verified all checks and 58 builds after completion.
The retained driver contains local paths and expects to live in the repository's
`.tmp-perf43-final/` directory; copy it there to reproduce this frozen setup.

## Relationship to earlier evidence

The [previous full sweep](d9-performance43-scoped-2026-09-26.md) preceded the
indexed setter and hash hoist. It passed QBE but failed LLVM at 1.07134×,
with three individual outliers. In this complete corrected run, LLVM Lox VM
binary trees is 1.28948×, closures 1.19052× and method calls 1.14562×.
The individual source optimizations' counter evidence remains in their
[indexed setter](d9-lox-indexed-setter-2026-09-26.md) and
[global hash](d9-lox-global-hash-2026-09-26.md) reports; this ordinary run does
not enable counting instrumentation. Rejected frame caches and scalar upvalue
accessors are absent from the measured source.

The compiler includes the [mut-reference root correction](d9-mut-reference-liveness-2026-09-26.md),
whose full gate, 260 uncached Lox native-GC-stress runs and 44 identical legacy
IL comparisons passed. The corrected default's new gate exposed two stale
random-stream sharing assertions. Their migration changes examples, tests,
specification and comments in `random.my`; it changes no generator algorithm,
layout, compiler lowering or runtime operation. That narrow follow-up has its
own gate and does not replace or weaken this frozen performance evidence.
