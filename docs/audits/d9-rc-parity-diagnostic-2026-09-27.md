# RC parity and schematic diagnostic at 7d68202d

The frozen, correctness-gated `7d68202d59cf834bf9649fd77df2000f548ffec9`
compiler produces the correct outputs on all 60 measured executions of the
27 historical parity programs and three schematic workloads, on both actual
backends. Its instruction overhead remains far outside the Stage 4 limits.
This diagnostic excludes all 13 Lox VM cases per backend and cannot establish
Stage 4 acceptance.

| Diagnostic subset | QBE | LLVM O3 / full LTO |
| --- | ---: | ---: |
| Programs per backend | 30 | 30 |
| RC / accepted-GC instruction geomean | 4.806047 | 6.291449 |
| Programs above 1.3 times GC instructions | 23 | 22 |
| GC median of per-program median peak RSS, KiB | 6,994 | 7,052 |
| RC median of per-program median peak RSS, KiB | 5,410 | 5,260 |

The lower median RSS applies only to this subset. Several individual programs,
including binary trees and schematic, have higher RC RSS. Every instruction
ratio and both sides' per-program RSS are recorded in the linked measurement
table. Ordinary compilation continues to default to GC.

## Inputs and method

The RC compiler is a Debug build with SHA256
`7decd168a86694b21d9c69eda88f7097a351e161b033c18c8270225129460b48`.
The accepted WP-4pre GC Debug compiler has SHA256
`8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`.
The benchmark worktree remains at `be57cffb`; the immutable compiler bundles
the current RC runtime. Workload sources, provider, fixture files and the
mandated `pc.py` commands retain their accepted hashes and sizes.

The driver builds 56 private RC binaries, validates the private accepted GC
binaries, checks exact output or schematic SVG hashes, and alternates three
instruction samples and three peak-RSS samples per side on CPU 11. QBE guests
use the default ReleaseFast mode; LLVM guests use O3 and full LTO. Both runtimes
use the same 8 GiB limit from the original harness. Final verification rechecks
every source/input, compiler and private binary hash.

This diagnostic uses the unchanged `pc.py` counter parser. Its observations
retain decoded instruction/cycle counts and statuses, but do not retain raw
`perf stat` output or per-event multiplexing percentages. Those omissions are
another reason to treat it as prioritization evidence, not an acceptance run.
Peak-RSS receipts retain commands, status and raw stderr.

## Main causes to investigate

| Program | QBE RC / GC instructions | LLVM RC / GC instructions |
| --- | ---: | ---: |
| schematic fixture | 73.211301 | 125.743231 |
| sieve | 30.659160 | 78.296366 |
| list append and sum | 30.023171 | 47.583868 |
| fannkuch redux | 15.132061 | 24.949639 |
| dictionary count | 17.334521 | 20.429299 |
| binary trees | 3.665245 | 3.788092 |
| nbody | 1.914667 | 4.611764 |

Separate counted builds and symbol-preserving profiles explain two priorities:

- **Fannkuch:** 354,444,268 uniqueness checks, only 11 allocations/retirements,
  O acquire/release 5/16, no holds and no clone shells. Runtime uniqueness and
  descriptor lookup dominate the sampled profile. The next compiler proof
  should eliminate repeated checks only where physical exclusivity is proven.
- **Schematic:** 156 allocations/retirements and only one clone shell, but
  604,122 balanced H acquire/release pairs and O acquire/release 169,777/169,933.
  The profile points at value walking, unique-resource metadata inspection and
  transfer traversal. The large regression is not explained by clone volume.

Both profiles use the exact unchanged workload. A read-only ELF section-table
comparison confirms each symbol-preserving production binary has the same
`.text` bytes as its measured diagnostic binary. The profiles are qualitative:
fannkuch has 1,580 samples and 1,580 throttle records; schematic has only 96
samples and 96 throttle records. Percentages cannot establish precise saved
instruction counts. The counted runs independently verify complete O/H and
allocation retirement balance, without saturation or count-limit events.

## Preserved harness failure and continuation

The initial driver completed and persisted all 54 parity rows, then failed
while serializing the first schematic receipt because its SVG path was a
`Path` object. The first schematic measurement was not persisted. The original
driver, terminal failure log and completed partial result are preserved.

The corrected driver converts receipt paths to strings and records only
explicit `MYLANG_*` overrides, omitting unrelated inherited host environment.
An explicit previous-driver hash authorizes the serialization-only resume.
Each row records its original driver hash; all 54 persisted rows remain
numerically identical, and the six schematic rows were measured by the fixed
driver. The verifier checks that continuation and both summaries. Environment
redaction is also applied to the archived initial partial receipt; no workload,
runtime flag or measurement was changed to make serialization succeed.

The remaining acceptance work is the complete 43-program corpus on each
backend, median-three instruction and RSS gates, and then the ordinary RC
default transition with documentation and a fresh final correctness gate.

Evidence: [diagnostic archive](../../experiments/d9-rc-parity-diagnostic-20260927/README.md),
[all measurements](../../experiments/d9-rc-parity-diagnostic-20260927/measurements.md).
