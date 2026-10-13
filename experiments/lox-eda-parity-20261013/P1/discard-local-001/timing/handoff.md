Authorized discarded-local diagnostics completed on the original controlled common001 compiler (955f311e), using frozen C1, identical runtime001 inputs/output pins and uninstrumented checked release binaries. No source adoption occurred. Three arms (Zig, C1, discarded-local only), CPU8, two initial warmups, nine alternating measured rounds per case across three resumable leases each. Fresh five-sample Zig calibration with two calibration warmups established the 3× guest cutoff (120-second absolute ceiling). All 81 measured invocations passed expected outputs; zero censors. Admission logs, commands, resume specs, raw receipts and progress records are preserved.

| Case | paired candidate/C1 median | paired range | wins | quotient of medians candidate/C1 | candidate/Zig median quotient | C1/Zig median quotient |
|---|---:|---:|---:|---:|---:|---:|
| fib | 0.993446 | 0.981322–0.999135 | 9/9 | 0.989085 | 1.184790 | 1.197865 |
| invocation | 0.997018 | 0.987918–1.005165 | 6/9 | 1.001344 | 1.069474 | 1.068038 |
| string_equality | 0.852259 | 0.830579–0.878809 | 9/9 | 0.852063 | 1.637403 | 1.921692 |

String equality improves 14.77% by paired median, winning all nine rounds; even its slowest paired ratio remains 0.87881. Fib has a small 0.66% paired benefit; invocation is noisy and effectively unchanged (paired median suggests 0.30% benefit while the quotient of medians suggests 0.13% regression). These two controls do not contain the repeated bare-local-expression workload, so their small changes may reflect native layout differences. The native code-size cost is execute +263 bytes (5606→5869) and evaluate +32 bytes (7906→7938).

This is a bounded source-only result, separate from getter/fresh-call-env benefits. Combining them requires application/GC/error qualification on source002 and the new final compiler; their effects cannot be multiplied into an unmeasured result. No all60-case parity claim is made. Prior standalone qualification remains 97 passing tests plus nine exact-execute baseline-matched invalid/negative-index controls.
