# D9 stage 3b performance evidence, 2026-09-26

**Status: performance acceptance is not met.** The COW implementation and
the private QBE transfer fix are correct under the branch's four-step gate,
but the LLVM Lox VM is above both stage 3 limits: 1.07199× instruction
geomean across the 43 acceptance programs and 1.63908× for the worst case.
The required limits are 1.05× geomean and no program above 1.30×, against
the `60b668cf` switch-off baseline. The QBE acceptance subset is 1.04411×
with a 1.25510× maximum. The extended suite, which also includes the Lox
tree engine, fails on both backends.

The [raw 116-key measurements](evidence/d9-stage3b-pc-efbc4285.json) contain
three `perf stat` samples for each side, on CPU 10. Each program's ratio uses
the median instruction count; geomeans are over those ratios. The exact
baseline compiler has SHA-256
`48427e9ac1c01b74e60d1b4c098c8fc149a6b5fef3c07e110c7fb4ba16cbb545`
and was built from `60b668cf`. The COW compiler was the Debug build at
`efbc4285`, with `--value-semantics` injected by the recorded wrapper. Guests
used ReleaseFast and the appropriate QBE or full-LTO LLVM backend. The run
used `pc.py measure --sides base,cow --phases perf --perf-reps 3 --rounds 0
--cpu 10`; the JSON records compiler paths and hashes. Instruction counts
are the gate metric; cycle samples had variable sibling-CPU load.

| Scope | QBE instruction geomean | QBE maximum | LLVM instruction geomean | LLVM maximum |
| --- | ---: | ---: | ---: | ---: |
| Acceptance subset: parity, schematic, Lox VM (43/backend) | 1.04411× | 1.25510× (`lox/vm/string_equality`) | 1.07199× | 1.63908× (`lox/vm/string_equality`) |
| Acceptance plus Result (45/backend) | 1.04217× | 1.25510× | 1.06873× | 1.63908× |
| Extended suite including Lox tree (58/backend) | 1.08482× | 1.40371× (`lox/tree/instantiation`) | 1.14477× | 1.66273× (`lox/tree/closures`) |

The QBE private-transfer change at `0e18d2bc` removed an artificial
scratch-pointer escape in `value_copy`. It restored QBE parity matmul and
byte scanning to approximately 1.0000× the baseline after earlier 2.91× and
2.08× regressions. All 27 parity keys on each backend now have geomeans of
1.0031× QBE and 1.0018× LLVM. The worst original-source regressions are
concentrated in Lox: Lox VM geomeans are 1.1937× QBE and 1.3488× LLVM. The
QBE source patch does not remove the LLVM performance blocker.

The final class-free Lox source at `ebe6b78f` was measured separately because
the historical 116-key baseline compiles the original class-based port. With
the same `efbc4285` compiler and exact `60b668cf` class baseline, the N=30,000
equality script produced `30000` on every run. CPU-10 median-of-three QBE
user instruction counts were 1,018,576,990 (class baseline) and 2,683,967,077
(class-free), a 2.635× ratio. This is an improvement over the prior 3.756×
class-free result, but is still far beyond the per-program limit. This is one
matched script, not a replacement for the 116-key suite.

The counted COW runtime on the previous class-free source recorded 26,226,706
mark-shared events, 8,491,274 uniqueness checks, and 60,581 COW copies for
N=30,000 equality. With the final small-frame source, mark-shared events fell
to 126,087 while uniqueness checks and COW copies remained at 8,491,274 and
60,581. This supports the source-level frame-change explanation for much of
the improvement, while the remaining checks and copies merit profiling.

The `efbc4285` branch passed `zig build test` (93/93 steps, 2,087 selected
tests), `test-qbe` (51/51 steps, 428 tests), `test-qbe-build` (29/29 steps),
and `fmt-check` (2/2 steps) under the shared full-gate lock. The new pinned
COW transfer regression also passed under `--gc-stress`. These correctness
results do not waive the stage 3 performance gate; default activation must
wait for it to pass.
