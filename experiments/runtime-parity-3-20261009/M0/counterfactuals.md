# M0 counterfactual bounds

Diagnostic probes only. The production compiler retains every required check and count. The inherited norc probe removes inline count branches; C runtime count operations remain. Both EDA norc variants abort and provide no valid bound; they are not timed again on CPU 10. The valid EDA reference_at-inlining probe and all six Lox exit probes are confirmed. CPU 8 uses five interleaved perf rounds. CPU 10 uses nine interleaved wall-time rounds after two warmups, holding the timing lock and all build/gate slots. Every CPU-10 sample checks stdout, exit status, and EDA generated-file hashes.

Ratios below use the unedited LLVM rebuild (`base`); the `real` arm is the direct compiler output and reveals rebuild/layout variation. Absolute timing is milliseconds. Both forms are retained in the raw receipts.

| cell | variant | CPU-8 instructions ÷ base | CPU-8 cycles ÷ base | CPU-10 ms | CPU-10 ÷ base | CPU-10 ÷ real | output |
|---|---|---:|---:|---:|---:|---:|---|
| lox:vm/invocation | real | 1.000 | 1.054 | 2735.228 | 1.000 | 1.000 | match |
| lox:vm/invocation | base | 1.000 | 1.000 | 2736.243 | 1.000 | 1.000 | match |
| lox:vm/invocation | norc | 0.662 | 0.643 | 1838.042 | 0.672 | 0.672 | match |
| lox:vm/invocation | checks+norc | 0.569 | 0.482 | 1584.828 | 0.579 | 0.579 | match |
| lox:vm/fib | real | 1.000 | 0.981 | 1459.965 | 1.001 | 1.000 | match |
| lox:vm/fib | base | 1.000 | 1.000 | 1458.814 | 1.000 | 0.999 | match |
| lox:vm/fib | norc | 0.747 | 0.785 | 1128.639 | 0.774 | 0.773 | match |
| lox:vm/fib | checks+norc | 0.659 | 0.709 | 1032.295 | 0.708 | 0.707 | match |
| lox:vm/method_call | real | 1.000 | 1.359 | 2292.583 | 1.000 | 1.000 | match |
| lox:vm/method_call | base | 1.000 | 1.000 | 2292.103 | 1.000 | 1.000 | match |
| lox:vm/method_call | norc | 0.688 | 0.798 | 1591.042 | 0.694 | 0.694 | match |
| lox:vm/method_call | checks+norc | 0.583 | 0.615 | 1402.333 | 0.612 | 0.612 | match |
| lox:vm/string_equality | real | 1.000 | 0.634 | 1215.483 | 1.006 | 1.000 | match |
| lox:vm/string_equality | base | 1.000 | 1.000 | 1207.868 | 1.000 | 0.994 | match |
| lox:vm/string_equality | norc | 0.993 | 0.625 | 1190.551 | 0.986 | 0.979 | match |
| lox:vm/string_equality | checks+norc | 0.811 | 0.527 | 1011.896 | 0.838 | 0.833 | match |
| lox:tree/equality | real | 1.000 | 0.994 | 308.297 | 0.991 | 1.000 | match |
| lox:tree/equality | base | 1.000 | 1.000 | 311.082 | 1.000 | 1.009 | match |
| lox:tree/equality | norc | 0.573 | 0.595 | 185.970 | 0.598 | 0.603 | match |
| lox:tree/equality | checks+norc | 0.510 | 0.612 | 187.398 | 0.602 | 0.608 | match |
| lox:tree/string_equality | real | 1.000 | 0.997 | 436.291 | 0.997 | 1.000 | match |
| lox:tree/string_equality | base | 1.000 | 1.000 | 437.509 | 1.000 | 1.003 | match |
| lox:tree/string_equality | norc | 0.499 | 0.479 | 215.863 | 0.493 | 0.495 | match |
| lox:tree/string_equality | checks+norc | 0.453 | 0.520 | 225.756 | 0.516 | 0.517 | match |
| eda-rds3+flat:rds3+flat | real | 1.000 | 0.988 | 80.783 | 0.991 | 1.000 | match |
| eda-rds3+flat:rds3+flat | base | 1.000 | 1.000 | 81.543 | 1.000 | 1.009 | match |
| eda-rds3+flat:rds3+flat | reference-inline | 0.966 | 0.969 | 79.085 | 0.970 | 0.979 | match |
| eda-rds3+flat:rds3+flat | norc | invalid | invalid | — | — | — | CPU-8 exit -6; no bound |
| eda-rds3+flat:rds3+flat | checks+norc | invalid | invalid | — | — | — | CPU-8 exit -6; no bound |
| eda-labstation:labstation | real | 1.000 | 0.975 | 51.466 | 1.000 | 1.000 | match |
| eda-labstation:labstation | base | 1.000 | 1.000 | 51.490 | 1.000 | 1.000 | match |
| eda-labstation:labstation | reference-inline | 0.956 | 0.920 | 49.924 | 0.970 | 0.970 | match |
| eda-labstation:labstation | norc | invalid | invalid | — | — | — | CPU-8 exit -6; no bound |
| eda-labstation:labstation | checks+norc | invalid | invalid | — | — | — | CPU-8 exit -6; no bound |

## U2 cell exits

For each required cell, closing 60% of the gap means final/base ≤ 1 − 0.60 × (1 − norc/real). The direct compiler output is the production base for this calculation; both direct and rebuilt controls are reported above.

| cell | norc ÷ direct base | U2 final ÷ base ceiling |
|---|---:|---:|
| lox:vm/invocation | 0.672 | 0.803 |
| lox:vm/fib | 0.773 | 0.864 |
| lox:vm/method_call | 0.694 | 0.816 |
| lox:tree/equality | 0.603 | 0.762 |

Generated per-layout release was not probed: cf.py has no such stub. The requested reference_at inlining probe is included for both EDA designs. U2 implements generated release with its own correctness gates.

The first no-op norc attempt is invalid and excluded (`counterfactual-v1-invalid.json`). The current matcher changes reachable P1 count branches; its faster implementation exactly matches the completed Lox probe LLVM. See DECISIONS.md for both corrections.
