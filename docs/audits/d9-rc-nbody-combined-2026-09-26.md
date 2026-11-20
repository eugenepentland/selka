# Combined nbody refinements on the unchanged workload

The immutable Debug compiler from `685e2631` combines direct plain-record updates,
plain terminal read borrowing, inert plain-record receiver scopes and native
plain replacement with the previously gated constructor/runtime changes.
All runs of the original **5,000,000-step nbody** produce the exact expected output.
Three interleaved instruction samples per backend on CPU 11 still fail the
required 1.3× per-program ceiling:

| Backend | Accepted GC median | Combined RC median | RC / GC |
|---|---:|---:|---:|
| QBE | 32,990,208,051 | 76,685,260,994 | 2.324486 |
| LLVM O3/full LTO | 3,595,206,336 | 26,335,251,081 | 7.325101 |

The candidate compiler SHA-256 is
`ed3dc4a72024b855272981ada0c4ff46e36bc7a6d3e58fd784a9835dfb5326fd`.
The unchanged accepted-GC compiler, native binary hashes and exact source content
are checked by the measurement driver. Each perf counter reports 100% enabled
time. This measured combined result supersedes estimates made by combining
individual reduced-workload ratios; the native replacement and direct compiler
store improvements overlap.

Both counted RC backends allocate and retire two heap objects, acquire one O token
and release three, acquire/release 10,000,005 H tokens, and execute 10,000,007
uniqueness checks. There are no clones, saturated counters or count-limit refusals.
This confirms balanced normal execution for this program, not general acceptance.

The [receipts](../../experiments/d9-rc-nbody-combined-20260926/README.md) retain
all samples, output, counts, backend manifests, source/compiler/native hashes and
commands. Both instruction profiles point predominantly into generated guest
code; frame initialization/cleanup and the remaining per-call scopes warrant
further investigation. The sampled percentages are qualitative: the machine
limits sampling to 1,000 samples/second and emits throttle records. Initial and
coarser repeated profiles are preserved, with raw data and throttle counts;
the perf-stat medians above are separate and unthrottled counter measurements.

The concurrent full gate at this source is **not green**: its ordinary guest
runner and both RC sweeps drop `rc_plain_replacements.my` because module name
resolution rejects the declared callable `replace`. Both RC sweeps pass their
865 executed assertions but drop that file. The module resolver correction is
being validated independently. A separate Lox argv shutdown imbalance is also
under investigation. GC remains the default and WP-4 remains incomplete.
