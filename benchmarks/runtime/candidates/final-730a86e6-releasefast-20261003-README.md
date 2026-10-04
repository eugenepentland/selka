The complete final acceptance capture uses immutable source
`730a86e62b47c922dc1411d24b5868c3bd2132f3`, a ReleaseFast host compiler,
and ReleaseFast guests. Compiler SHA256:
`579856466e5d30e77887c9435fd2eb07af82b84792905d78cd926a004cd6eaa3`.
All 40 cases, both frozen sizes and six arms (Rust, Go, Zig ReleaseSafe,
Zig ReleaseFast, MyLang LLVM O3/full LTO and MyLang QBE) are preserved.
Sixteen reference guests are hash/source/tool-verified reuses, honestly recorded;
eight MyLang guests were rebuilt. Effective backend/runtime archive receipts
match before and after. Frozen ports, checksums and all 80 original fastest
reference targets are unchanged.

The capture ran 2026-10-03 23:40:22 UTC to 2026-10-04 00:04:48 UTC,
including calibration; measurement started 23:43:01. Fifteen randomized rounds
and three warmups produced 7,200 samples, 1,440 warmups, 480 RSS probes and
720 full-inventory qualification checks. Seven targets whose original winner
was an older MyLang binary additionally retained 105 concurrent original-winner
samples and 21 warmups. CPU2/global-lock timing was used throughout; CPU2
averaged 98.99% busy, sibling CPU3 1.07%, powersave was active, no frequency
warning was recorded. Averages cannot exclude short host interference.

Independent report replay with artifact checks passed all 480 sample groups
and 160 comparisons. [All 160 statuses](final-730a86e6-releasefast-20261003-comparison.md)
retain frozen ratios and same-session original-reference ratios/paired intervals.
[All six arms](final-730a86e6-releasefast-20261003-six-arm.md) shows absolute
medians and frozen normalization for every row. The JSON dashboard also retains
the distinct current-fastest dashboard; a current winner does not change the
original 1.00 target. [Resources](final-730a86e6-releasefast-20261003-resources.md)
records all 24 guest file/.text sizes and 480 individual peak-RSS probes.
RSS is whole-process and singly probed; guest compile durations were not
measured. The compiler receipt records one build interval with cache/slot/load
state, not a comparative compiler-speed result. Calibration limits are retained.

Numerical frozen status: LLVM 4 at/below, 3 near (within 5%), 73 open;
QBE 3 at/below, 77 open. Therefore 7 of 160 rows are numerically at/below and
153 still exceed 1.00. Near is an unresolved target. Concurrent evidence in
this session: LLVM 5 faster, 74 slower, 1 inconclusive; QBE 3 faster, 77 slower.
The eight provisional faster rows require independent RF confirmation before
a demonstrated-faster claim. The nested-mutation small row is faster than its
concurrent original yet remains above the frozen target. QBE byte/search wins
compare to the original winner; they do not imply QBE beats current LLVM.

| Case / size | Backend | Frozen ratio | Concurrent original ratio, paired 95% interval | Numerical status |
|---|---|---:|---:|---|
| mutate_nested / small | my-llvm | 1.0081 | 0.9899 [0.9806,0.9960] | near_target |
| mutate_nested / large | my-llvm | 1.0296 | 1.0243 [1.0137,1.0337] | near_target |
| sort_int / large | my-llvm | 1.0005 | 0.9981 [0.9937,1.0024] | near_target |
| bytes_scan / small | my-llvm | 0.4152 | 0.4073 [0.4054,0.4114] | at_or_below |
| bytes_scan / small | my-qbe | 0.9729 | 0.9543 [0.9517,0.9611] | at_or_below |
| bytes_scan / large | my-llvm | 0.2148 | 0.2093 [0.2081,0.2117] | at_or_below |
| bytes_scan / large | my-qbe | 0.2273 | 0.2214 [0.2192,0.2227] | at_or_below |
| string_search / small | my-llvm | 0.9952 | 0.9948 [0.9901,0.9968] | at_or_below |
| string_search / large | my-llvm | 0.8967 | 0.8913 [0.8839,0.8983] | at_or_below |
| string_search / large | my-qbe | 0.9547 | 0.9489 [0.9378,0.9586] | at_or_below |

A separate fresh RF confirmation session covers every provisional-win family,
the six preselected regression families, and JSON/Lox at both sizes. Current-main
and final guests both use RF host builds; scalar-policy1ec guests are explicitly
Debug-host controls. That session's result is a separate artifact. Archived
current-main/final medians are not paired here; any arithmetic comparison of
archived sessions would be cross-session. No demonstrated-faster conclusion is
made by this full-session artifact alone. Bootstrap intervals are exploratory,
uncorrected for selection, repeated tuning or multiple comparisons.

The accompanying [holdouts](final-730a86e6-holdouts-20261003-README.md) passed
516 unseen-input cells across all six arms. The final broad semantic gate and
fresh LLVM corpus are recorded separately under validation/730a86e6-validation.json.
[Build/static evidence](730a86e6-releasefast-build-static-20261003-README.md)
binds actual code and no admitted P2 compute specialization; the old 12-copy
faulty-source evidence is superseded. Implementation/package scope and remaining
work are documented in the campaign README, owned by the integration agent.

The original all-arm flags have unequal ISA policies. Common-ISA timing has not
been established; explicit SSE2/portable correctness does not resolve that
measurement limitation. Static whole-function counts, diagnostic component
ratios, ownership-event counts and whole-process profiles are not kernel-only
costs or additive causal shares. The original alloc_short reference eliminates
its construction path; it measures optimizer behavior, not allocator throughput.

Raw report SHA256: `5120ad6c5f38f3c4cf8441fa832b8e85cb8550689a3aa6e068f2be2a9d4c55a9`.
Comparison JSON SHA256: `dbb1906bcac50cb015171cce52ff68a0297f728db81e9ec4927f4f158117d473`.
The raw gzip files retain exact report bytes; receipt archive includes the
report exporter, backend before/after receipts, confirmation-selection policy
and full capture log.
