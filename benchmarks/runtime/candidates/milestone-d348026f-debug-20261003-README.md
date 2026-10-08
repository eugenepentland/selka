`milestone-d348026f-debug-20261003` measures compiler/runtime source
`d348026f52eb02792e8c0c1d07dae7f6c8e26bd7`. Its recorded compiler mode is Debug;
guests use ReleaseFast, with LLVM O3/LTO. Compiler-mode equivalence of guest
bytes has not been established. The receipt checks source bytes and installed
assets; later source revisions are separate candidates.

The focused run covered 13 cases at both original sizes, all six arms, 15
randomized rounds and three warmups. It retained 2,340 samples and all 720
40-case edge-qualification probes. Independent verification and comparison
passed with live artifact checks before later profiler changes. The raw SHA256
is `afea6d9173a33b57614811c3874b389e483e71924736f75e696d641719648432`.
The gzip files retain the exact JSON bytes; decompress before replaying the
expanded verifier with `--focused` or the candidate comparison tool.

Every measured MyLang row remains numerically above its frozen target and has
an exploratory same-session original-reference interval wholly above one.
The comparison preserves all 80 frozen targets, including unmeasured rows.
Sibling CPU 3 averaged 4.93% busy; the host governor was powersave and load
rose substantially. Cross-session raw changes are therefore unsuitable for
causal acceptance decisions.

The following source mechanisms and executable tests are present in this exact
revision. Source tests identify implemented contracts; this document does not
claim a passing full semantic gate for this revision. The owner reported
focused semantic checks, while the broader campaign gate still required cache,
call-count and module-provenance fixes in later revisions. The fresh benchmark
qualification above is directly tied to this source and its executable hashes.

| Package | Source mechanism in d348026f | Relevant checked-in tests | Remaining scope |
|---|---|---|---|
| P1 | Exact multiply-high recipes for literal integer divisors, retaining exceptional semantics | qbe_constant_divisor_test.zig; constant_divisors.my | Residual checked-product cost and dynamic hot-loop evidence |
| P2 | Bounded loop-write/domain propagation; exact integer-to-binary64 lowering and LLVM numeric-conversion fix | qbe_loop_bounded_write_test.zig; qbe_scalar_conversion_test.zig; bounded_loop_ranges.my; integer_float_rounding.my | Further iterator/storage proofs and controlled LLVM arithmetic checks |
| P3 | Entry leaf inlining with logical depth, admitted plain aggregates and preserved Result error traces | bytecode_inline_test.zig; qbe_build_llvm_test.zig | Indirect ABI; QBE regression investigation; broader frame/trace gate |
| P4 | Admitted plain list append/pop with original fallback paths | qbe_rc_append_test.zig; native_rc_collections_test.zig; rc_plain_appends.my | Nested COW/RC costs, retained-memory and holdout evidence |
| P6 | Direct immutable text/byte equality, stack integer formatting and single-pass integer parsing | qbe_text_test.zig; immutable_equal.my; integer_text.my | Nonescaping encode consumer and text component attribution |
| P8 | Buffered JSON spans and serializer construction | stdlib_json_test.zig; standard_json.my | Parse/transform/serialize isolation; sort, retained allocation and nested mutation residuals |

P5 transactions, P7 escape analysis and P9 byte bulk work are outside this source
milestone. No complete-package or all-target-parity claim is made.

Dividing each session's candidate/reference ratio by the fresh-main/reference
ratio gives the following large-size observations. This normalization helps
triage host drift, but it is still a ratio of separate sessions, with no paired
candidate/main interval:

| Case | LLVM normalized ratio | QBE normalized ratio |
|---|---:|---:|
| integer_math | 1.213 | 0.624 |
| float_math | 1.120 | 0.468 |
| call_direct | 0.551 | 1.958 |
| record_construct | 0.928 | 1.656 |
| option_handle | 0.515 | 1.423 |
| result_propagate | 0.739 | 1.954 |
| int_parse | 1.106 | 1.033 |
| int_format | 0.868 | 0.949 |
| json_transform | 0.277 | 0.368 |
| lox_eval | 0.572 | 0.553 |

A separate controlled session then reran unchanged `call_direct` with original
Rust, current-main LLVM/QBE, and d348026f LLVM/QBE together, at both sizes with
15 rounds and three warmups. Sibling activity averaged 1.28%. Candidate/main
LLVM ratios were 0.570 [0.566, 0.587] small and 0.602 [0.530, 0.639] large;
QBE ratios were 1.917 [1.901, 1.960] small and 1.876 [1.816, 1.967] large.
This directly supports investigating the QBE regression on this host. LLVM
still exceeded original Rust in that session, at 1.727 small and 2.320 large.
The source comparison has its own schema and five guests; it cannot masquerade
as a complete six-arm acceptance report.

Actual micro diagnostics of fresh main cover numbers, list scan, string
equality, text dictionary lookup, direct calls, Result propagation, short
allocation and binary search, both sizes/backends. All 32 captures completed.
Observed sample counts ranged from 27 to 620; six captures had fewer than 200
samples, nine hit the iteration cap, and all contained raw throttle records.
A separate candidate call capture had 487 samples. Retrying it at 19 Hz for a
six-second target still recorded throttling (113 samples). These captures are
hotspot hints; neither symbol fractions nor these eight selected families
measure common-code CPU coverage.

Raw hybrid hardware captures contain active `cpu_core/...` counts and inactive
`cpu_atom/...` rows. The original parser retained raw TSV but omitted the hybrid
rows from structured counts. `hybrid-reprocessed.json` preserves a separate
reprocessing result, with the CPU-to-PMU map read after capture; original
reports are unchanged. For QBE direct-call large, whole-process instructions
per inner element were about 270 for main and 469 for d348026f. Setup, launcher
and teardown are included. Sampled IPs point to stack traffic and expanded
checked arithmetic, but this does not isolate the exact causal contribution.

The archives preserve static assembly/IL and raw perf/counter captures for
review. Whole-function static instruction and divide sites are not executed
costs. The QBE compute frame grew from 3,048 to 4,248 bytes while total static
stack references fell slightly; a whole-function count alone cannot explain
the regression.

Versioned five-component diagnostics have 30 successfully built guests, with
hash-checked source copies and reviewable diffs across all four languages.
Their paired timings and allocation/RC counters remain pending. Additional
holdouts are also pending: high-cardinality words, mixed Unicode/escape JSON
shapes, varied sorting distributions, retained allocation and nested aliases.
The 720 original probes do not substitute for these holdouts. Final candidate
profiling must also include sort_int, sort_records, alloc_retained and
mutate_nested before their package residuals can be judged.
