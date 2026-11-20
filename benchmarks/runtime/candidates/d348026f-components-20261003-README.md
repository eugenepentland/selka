These five versioned component diagnostics use exact compiler/runtime source
`d348026f52eb02792e8c0c1d07dae7f6c8e26bd7`, its Debug host compiler receipt,
and ReleaseFast guests. Thirty probes across MyLang LLVM/QBE, Rust, Go and Zig
Safe/Fast pair with ordinary or dispatch-removed controls. Every source copy,
dependency, diff, command, clock object and executable is hash-bound before
and after capture; immutable original ports are unchanged.

Both sizes use all 12 control/probe guests, 15 randomized rounds and three
warmups. The evidence contains 1,800 samples, 360 warmups, 180 diagnostic edge
qualifications and 120 memory probes. Independent replay passed all 120 sample
groups and 60 ratios/intervals. CPU2 averaged99.11% busy, sibling CPU3 averaged
0.57%, powersave was active, and no frequency warnings were recorded.

Large-size probe/control ratios are shown below. Exact paired exploratory 95%
bootstrap intervals, samples, order and calibrations are in the JSON. Intervals
have no multiple-comparison or repeated-tuning correction.

| Probe | MyLang LLVM | MyLang QBE | Rust | Go | Zig Safe | Zig Fast |
|---|---:|---:|---:|---:|---:|---:|
| dispatch_outside | 0.786 | 0.575 | 0.871 | 0.692 | 0.865 | 0.858 |
| arithmetic_only | 0.898 | 0.695 | 0.724 | 0.961 | 0.981 | 0.565 |
| collection_only | 0.208 | 0.751 | 0.111 | 0.336 | 0.214 | 0.275 |
| text_without_score | 0.329 | 0.310 | 0.788 | 0.849 | 0.955 | 0.948 |
| escaped_allocation | 0.559 | 0.583 | 15.871 | 9.333 | 3.695 | 4446.594 |

All large MyLang intervals are below one. Removing dispatch changes the
optimized control flow; scalar-input arithmetic also changes the values and
uses dispatch_outside as its control. Collection-only removes phase/modulo
arithmetic. Text-without-score consumes ASCII integer output length, removing
the whole byte fold and MyLang encode. These changes are diagnostics, not
additive or isolated cost measurements of the original workload.

Escaped-allocation returns nested owned lists across a helper boundary and
retains them until consumption. It is faster on these MyLang guests and much
slower on several references. That contrast demonstrates sensitivity to
optimization, live-object shape and storage policy; it does not prove the
original or probe physically allocates a specific number of objects. Compiler
inlining/elimination is still possible. Physical allocation and RC event claims
require separately identified executable/counter evidence, with any counting
policy differences stated. The original alloc_short acceptance row stays open
and is not replaced by this workload.

The source archive retains generated ports, dependencies, reviewable diffs,
source receipt and complete build manifest/log. The gzip preserves exact JSON
bytes. These timings concern a historical candidate, before scalar-policy/P2/P7
followups; no final-candidate acceptance or CPU-coverage claim is made.
