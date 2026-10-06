# S2 Wave B exit report

Date: 2026-10-06. Branch: `codex/new-core-s2-integration`.
Accepted starting head: `72eaae74`. Final repaired compiler: merge `996d9baa`.
Wave B combined compiler: `b70a6a3f`; pre-repair S2-X evidence: `090dabd5`.
All named S2 exit gates qualify. S3 has not started; the stage stops here
for the user's go/stop decision.

One explicit planned optimization is unimplemented: the fused split cursor
of design §3.5. Split materializes owned pieces and a list. The measured
split rows pass the named exit gates; that does not waive the planned fusion.
This is an as-built deviation for the user's S3 go/stop decision. The separate
conditional parameter-view ABI evaluation was not triggered.

## Package commits and merge checks

Each package began in its own locked worktree. D, T1 and F ran in parallel with
the coordinator's I worktree; T2 started from the first I merge. At most four
build-heavy agents and two strict fuzz jobs run concurrently. No `main` merge
or push was made; the original dirty checkout and runtime reference worktree
remain intact.

| Package | Source | Qualified evidence | Integration merge | Held unit gate on resolved integration tree | Full corpus, each mode |
|---|---|---|---|---|---|
| S2-I | b68232d3 | 1b3de437 | 0563edd6 | 189/189, 169.53 s | 795 match / 0 mismatch / 745 refused |
| S2-T1 | ec44e2b6 | 4b12d578 | dd1ea75a | 191/191, 166.05 s | 897 / 0 / 643 |
| S2-F | 3465f423 | e8424a59 | 746d3b8b | 193/193, 215.87 s | 1061 / 0 / 479 |
| S2-D | 89f65316 | 62656609 | 6a918a94 | 197/197, 232.75 s | 1224 / 0 / 316 |
| S2-T2 | e5139598 | 995823e6 | b70a6a3f | 198/198, 238.76 s | 1224 / 0 / 316 |
| S2-X fact repair | 0c6029d7 | 41deb663 | 996d9baa | 200/200, 242.43 s | 1224 / 0 / 316 |

The checks ran on each fully resolved staged merge tree before its merge commit;
logs identify that Git tree and package, then the table associates the actual
merge commit. Later experiment/document commits do not change compiler inputs.
Package READMEs record exact commands, results and source commits. Per package:
held test-core, full debug/release comparison, own-file leak/fact sweeps, strict
50-case feature fuzz, S0/S1 identity or explicit parser nonregression proof,
own rows and coverage. Full old gates, 200-case matrix and all 35 were reserved
for S2-X.

## Final S2-X gate and conformance

The combined old-core gate is qualified in `integration/full-old-gate/combined-summary.json`. The final repaired full leak/fact sweep and the complete strict matrix also pass.

The full old `test` run initially had 111/115 successful steps; both failed
incremental drivers filtered out their copied fixtures because the private
TMPDIR contained `.mylang-cache`. Their 5/4 candidates became 0/0. The corrected
private `.zig-cache` scratch replay passes `test-incremental` 24/24, with both
120-step and 60-step drivers at zero mismatches (64.46 s). The original
passing old tests are not repeated. QBE passes 519/519 (75.41 s); QBE build
passes 29/29 steps (3.01 s); formatting passes 2/2 (0.22 s). All reported
test-shard RSS stays within the ceiling; no overrun diagnostics. Final held formatting after the dictionary-fact edit passes 2/2 (0.24 s,
MaxRSS 47,936 KiB). The old unit/QBE roots exclude the core facts and core
tests; their accepted proof is unaffected by the repair, as independently
checked against the build graph.

The initial full strict sweep has debug 1224/0/316 and release 1223/1/316:
`dictionary_hashing::test_text_keys_count_the_same_through_one_key_object_or_many`
traps `R_CORE_FACT` only with release verification. The cause is explained: dictionary updates inherit unsettled unknown call
facts, so a loop phi permanently skips that populated back edge and asserts
length zero against actual length 27. The dictionary analogue of the existing
`pendingList` rule repairs it in `0c6029d7`; evidence `41deb663`. Six native
regressions plus an explicit IR-copy regression exercise the missing case.
The repaired package passes 200/200 held tests in 293.07 s, full conformance
1224/0/316 in both modes, its leak/fact sweep 264/0/84 in both, and strict
50-case dictionary fuzz (750 comparisons, zero failures). Its integration
checks pass: rebuild 2.16 s, held unit gate 200/200 in 242.43 s
(runner 205M / compiler 328M), and full ordinary conformance in 44.01 s.
The final full leak/fact replay on `996d9baa` passes 1224/0/316 in both modes
(exit zero, 49.99 s, MaxRSS 325,508 KiB). Separately, the wrapper incorrectly rejected documented
empty-selection status 3. It now admits only an exact empty native report with
zero counters; 16 synthetic process/report checks retain signal, blank-output
and inconsistent-status rejection. This harness repair does not qualify the
dictionary fact failure.

The full-corpus comparison uses the inherited `--set all` selection, without
`--include-arena`: it omits `arena_managed`, `arena_scopes`,
`arena_class_escape`, `arena_regions`, `rc_arena_values`, and test names
matching `*arena*`. This is the unchanged S1/Wave A comparison scope.

The final ordinary conformance run has 1540 selected test functions: each of debug and
release has 1224 matching, zero mismatching and 316 precisely unsupported.
Wave A's accepted 769 matching / zero mismatch grows by 455 matching functions.
The protected oracle is `.mylang-cache/wave-b/baseline/mylang`, copied with
adjacent QBE from the accepted 72 compiler before the old gate could reinstall
`zig-out/bin/mylang`. The pre-language Wave A baseline executable was not used
to grade these packages. Native status/stdout/stderr and outer compiler signals
are checked; stderr-only acceptance is forbidden.

The final strict matrix qualifies all nine kinds: 1,800 accepted cases,
25,800 comparisons and 35,600 successful native executions, at most two jobs.
Every case is admitted by the oracle and compiles in debug, release and
verification modes; zero rejects, refusals, build failures, mismatches,
crashes, leaks or fact failures. RC runs its oracle once per mode/argument
pair, hence 3,600 executions rather than 2,400.

Eight kinds run on the repaired final compiler `996d9baa`. The previously
passing 200-case rebinding run on `090dabd5` is reused: all 200 complete IR/fact
dumps agree byte for byte, none contains dictionary operations, and only
`facts.zig` changed in the compiler. `integration/rebinding-reuse.json`
records that checked proof. The matrix includes the original qualification
source and proof link; its 4,000 executions are included in the total above,
with 31,600 fresh executions on the repaired compiler. The earlier dictionary
run is superseded by the final repaired-source run. Paused dispatch and the
explained repairs are retained, and no incomplete run is qualified.

`integration/fuzz-final-200/matrix.json` is complete and qualified; each kind
has its full command, source, process result, harness transcript and summary.
Elapsed seconds below are execution after build-slot admission.

| Kind | Accepted cases | Comparisons | Native executions | Seconds | Qualification source |
|---|---:|---:|---:|---:|---|
| s0 | 200 | 3000 | 4000 | 449.32 | `996d9baa` |
| s1 | 200 | 3000 | 4000 | 616.20 | `996d9baa` |
| rc | 200 | 1800 | 3600 | 393.92 | `996d9baa` |
| rebinding | 200 | 3000 | 4000 | 1351.51 | `090dabd5`, justified reuse |
| iteration | 200 | 3000 | 4000 | 874.58 | `996d9baa` |
| dict | 200 | 3000 | 4000 | 1177.99 | `996d9baa` |
| text | 200 | 3000 | 4000 | 433.00 | `996d9baa` |
| number | 200 | 3000 | 4000 | 479.25 | `996d9baa` |
| functions | 200 | 3000 | 4000 | 531.17 | `996d9baa` |

Exact commands, process results and compiler commits are retained in the
following evidence. Private cache environment and slot-admission wait are
included in the logs; quoted times describe execution after admission.

Raw evidence is retained verbatim. The archived `integration/full-old-gate/test.log`
and `integration/rebinding-reuse-facts.diff` contain their original whitespace;
`git diff --check 996d9baa` passes with only those two transcripts excluded.
Authored documentation, tools and compiler inputs have no whitespace errors.

| Exit check | Compiler source | Command/tool and retained evidence |
|---|---|---|
| Final rebuild and held core unit gate | `996d9baa` resolved merge tree | `scripts/build-slot.sh build -- zig build core`; held gate plus build slot for `zig build test-core --summary all`; `integration/merge-s2-x-fact-{build,test-core}.txt` and `merge-s2-x-fact.md` |
| Full old gate and affected setup replay | `090dabd5`, unaffected by the facts-only repair | `full_old_gate.py`: `test`, `test-incremental`, `test-qbe`, `test-qbe-build`, `fmt-check`; `integration/full-old-gate/combined-summary.json` and all step logs |
| Final ordinary and leak/fact conformance | `996d9baa` | `conformance_checked.py --set all --jobs 4 --why`, also `--leakcheck --verify`; `integration/merge-s2-x-fact-conformance.txt`, `s2-x-leak-verify-after-fact.txt` |
| Full strict matrix | `996d9baa`, rebinding reuse qualified by unchanged IR/facts | `fuzz_matrix.py --kinds dict,s1,iteration,functions,text,number,s0,rc --evidence …/fuzz-final-200 --reuse-rebinding …/fuzz-200/rebinding/summary.json`; per-kind commands/logs and final `matrix.json` |
| All35 seven-round measurement and count audit | Measured `090dabd5`; all 35 complete modules identical on `996d9baa` | `measure_all35.py --build --rounds 7 --cpu 10` under the CPU lock; `audit_all35.py`; `integration/all35.{json,txt}`, `count-audit.{json,txt}`, `count-notes.md`, `rows-after-fact.{json,txt}` |
| S0/S1 timed-kernel nonregression | `090dabd5`, extended to final by complete-module identity | `wave-a/compare_code.py` and `s2-t2/inspect_definitions.py`; `integration/code-{identity,nonregression}.txt` |
| Standard coverage and complete before/after loop attribution | Before `72eaae74`, final `996d9baa` | `wave-a/qualify_coverage.py`; `integration/coverage_loops.py`; `s2-x-coverage-standard-after-fact.txt`, `coverage-standard-after-fact/admission-proof.json`, `coverage-loops.{json,txt}` |
| Final formatting | `996d9baa` | Held gate plus build slot for `zig build fmt-check --summary all`; `integration/fmt-after-fact.txt` |

## All35 rows and count updates

All 35 rows build in both compilers; all 70 row/size pairs pass, with 2,800
successful samples and matching checksums. The final fact-repair source proves all 35 complete LLVM modules byte-identical
to the measured `090dabd5` modules; runtime, emitters, driver, native clock
and row sources are unchanged. `integration/rows-after-fact.json` records
35 successful final native builds and the qualified reuse; no measurement
or count-audit replay is needed. The complete
measured row table follows; static count-site explanations are retained in
`integration/count-notes.md`.
Seven interleaved rounds use CPU 10 under the shared timing lock, compare every
old/new/Rust/Zig ReleaseSafe checksum, and subtract startup user-cycle samples.
Both sizes 4096/64 are reported. S0 kernel identity is a permitted nonregression
proof; identical binary_search IR permits its documented layout noise. Every
other row must be at most 1.10× Zig at both sizes.

Every numeric row cell is `4096 / 64`, in CPU-10 user cycles per the listed
unit. `I/P/N` means static tagged count-store sites in timed innermost loops /
parent-exclusive loops / timed nonloop cleanup. These include initialization
and conditional release arms, and exclude opaque runtime bodies.

The count audit distinguishes timed innermost stores, parent-exclusive stores,
initialization, conditional decrement arms, saturated-header reads and opaque
callee/runtime scope. Static sites are not presented as dynamic event counts.

| Row | Unit | Old | New | Zig ReleaseSafe | Rust | New/Zig | New/Rust | I/P/N |
|---|---|---:|---:|---:|---:|---:|---:|---|
| record_reads | iteration | 24.472 / 24.496 | 17.783 / 17.632 | 23.912 / 23.910 | 17.401 / 17.262 | 0.744 / 0.737 | 1.022 / 1.021 | 0/0/0 |
| tagged_stack | iteration | 63.284 / 63.270 | 33.330 / 33.309 | 47.931 / 47.856 | 25.940 / 25.905 | 0.695 / 0.696 | 1.285 / 1.286 | 0/0/0 |
| mutate_unique | iteration | 17.138 / 17.091 | 14.577 / 14.583 | 16.960 / 16.936 | 13.169 / 13.129 | 0.859 / 0.861 | 1.107 / 1.111 | 0/0/0 |
| mutate_shared | element | 0.955 / 7.123 | 0.637 / 0.637 | 1.121 / 0.999 | 0.627 / 0.642 | 0.568 / 0.637 | 1.015 / 0.992 | 0/0/0 |
| record_construct | element | 11.627 / 11.717 | 2.304 / 2.396 | 10.494 / 11.031 | 6.902 / 7.330 | 0.220 / 0.217 | 0.334 / 0.327 | 0/0/0 |
| record_update | element | 11.719 / 11.790 | 6.183 / 6.290 | 11.161 / 11.638 | 6.904 / 7.330 | 0.554 / 0.540 | 0.896 / 0.858 | 0/0/0 |
| option_handle | element | 4.036 / 4.055 | 1.954 / 2.496 | 6.506 / 7.411 | 2.415 / 3.156 | 0.300 / 0.337 | 0.809 / 0.791 | 0/0/0 |
| result_propagate | element | 6.201 / 5.605 | 4.043 / 3.970 | 7.095 / 7.456 | 3.513 / 4.118 | 0.570 / 0.532 | 1.151 / 0.964 | 0/0/0 |
| list_scan | element | 3.847 / 4.011 | 3.968 / 4.035 | 4.569 / 4.658 | 2.703 / 2.792 | 0.868 / 0.866 | 1.468 / 1.445 | 0/0/1 |
| list_append | element | 7.239 / 14.086 | 7.068 / 9.682 | 12.283 / 16.792 | 6.200 / 10.211 | 0.575 / 0.577 | 1.140 / 0.948 | 0/2/0 |
| list_filter | element | 9.262 / 17.611 | 7.900 / 10.621 | 10.592 / 13.847 | 5.737 / 10.052 | 0.746 / 0.767 | 1.377 / 1.057 | 0/3/0 |
| alloc_short | element | 244.897 / 249.942 | 4.722 / 5.075 | 21.812 / 22.193 | 5.013 / 5.329 | 0.216 / 0.229 | 0.942 / 0.952 | unknown (manual 0) |
| alloc_retained | element | 142.927 / 152.561 | 36.249 / 37.742 | 80.661 / 78.560 | 80.263 / 82.051 | 0.449 / 0.480 | 0.452 / 0.460 | 1/1/0 |
| mutate_nested | element | 29.188 / 46.418 | 12.283 / 14.675 | 75.435 / 73.896 | 81.281 / 72.220 | 0.163 / 0.199 | 0.151 / 0.203 | 2/0/0 |
| bytes_scan | element | 0.083 / 0.246 | 1.246 / 1.736 | 1.372 / 1.815 | 1.135 / 1.201 | 0.908 / 0.956 | 1.098 / 1.446 | 0/0/5 |
| string_equal | iteration | 53.707 / 16.679 | 134.607 / 15.260 | 277.655 / 16.809 | 135.459 / 12.711 | 0.485 / 0.908 | 0.994 / 1.201 | 0/0/5 |
| string_search | iteration | 420.276 / 79.811 | 1081.894 / 89.172 | 12923.277 / 387.888 | 5584.115 / 182.514 | 0.084 / 0.230 | 0.194 / 0.489 | 0/0/5 |
| string_split | element | 201.801 / 210.588 | 69.675 / 71.658 | 65.569 / 69.066 | 27.999 / 35.783 | 1.063 / 1.038 | 2.488 / 2.003 | 0/1/5 |
| string_join | element | 6.122 / 9.958 | 5.822 / 6.579 | 18.116 / 20.372 | 13.878 / 14.936 | 0.321 / 0.323 | 0.419 / 0.440 | 0/1/5 |
| dict_lookup | element | 31.080 / 16.984 | 15.668 / 15.124 | 52.235 / 30.957 | 41.943 / 41.013 | 0.300 / 0.489 | 0.374 / 0.369 | 0/0/4 |
| dict_lookup_str | element | 61.795 / 28.868 | 22.487 / 19.502 | 62.413 / 31.877 | 60.300 / 57.605 | 0.360 / 0.612 | 0.373 / 0.339 | 0/0/4 |
| dict_update | element | 828.676 / 733.364 | 196.748 / 200.324 | 550.219 / 309.074 | 414.143 / 400.552 | 0.358 / 0.648 | 0.475 / 0.500 | 0/1/4 |
| dict_update_str | element | 1016.314 / 852.210 | 282.968 / 265.426 | 729.773 / 404.923 | 919.045 / 860.744 | 0.388 / 0.655 | 0.308 / 0.308 | 0/2/4 |
| set_dedup | element | 175.418 / 168.280 | 24.547 / 29.841 | 81.057 / 37.629 | 62.648 / 62.484 | 0.303 / 0.793 | 0.392 / 0.478 | 0/1/4 |
| int_parse | iteration | 46.212 / 41.438 | 29.089 / 26.527 | 28.864 / 24.338 | 21.992 / 19.216 | 1.008 / 1.090 | 1.323 / 1.380 | 0/0/4 |
| int_format | iteration | 221.152 / 216.686 | 68.646 / 62.790 | 214.758 / 197.557 | 63.711 / 62.190 | 0.320 / 0.318 | 1.077 / 1.010 | 0/1/4 |
| call_indirect | element | 5.013 / 5.080 | 0.302 / 0.312 | 9.013 / 9.502 | 7.192 / 7.825 | 0.033 / 0.033 | 0.042 / 0.040 | 0/0/0 |
| sort_int | element | 45.474 / 11.705 | 46.678 / 9.691 | 67.428 / 17.721 | 70.051 / 15.486 | 0.692 / 0.547 | 0.666 / 0.626 | 0/1/0 |
| sort_records | element | 55.648 / 66.818 | 31.429 / 39.289 | 117.653 / 50.766 | 40.781 / 44.783 | 0.267 / 0.774 | 0.771 / 0.877 | 0/5/0 |
| int_math | element | 8.696 / 9.069 | 0.357 / 0.493 | 7.808 / 8.314 | 5.706 / 6.183 | 0.046 / 0.059 | 0.063 / 0.080 | 0/0/0 |
| float_math | element | 8.297 / 8.428 | 1.568 / 1.709 | 6.515 / 7.029 | 6.970 / 7.323 | 0.241 / 0.243 | 0.225 / 0.233 | 0/0/0 |
| call_direct | element | 3.039 / 3.147 | 0.300 / 0.321 | 3.020 / 4.115 | 2.017 / 2.934 | 0.099 / 0.078 | 0.149 / 0.109 | 0/0/0 |
| branch_predictable | element | 4.024 / 4.149 | 0.395 / 0.496 | 7.679 / 7.943 | 3.198 / 3.252 | 0.051 / 0.063 | 0.123 / 0.153 | 0/0/0 |
| branch_mixed | element | 4.119 / 4.128 | 0.398 / 0.498 | 9.244 / 9.062 | 4.870 / 4.518 | 0.043 / 0.055 | 0.082 / 0.110 | 0/0/0 |
| binary_search | element | 143.777 / 32.984 | 32.877 / 18.453 | 137.108 / 27.887 | 37.633 / 19.493 | 0.240 / 0.662 | 0.874 / 0.947 | 0/0/1 |

All 70 row/size pairs pass the 1.10 Zig gate. The tightest ratio is `int_parse/64` at 1.0899657224757722. No binary-search noise exception was needed for this measurement.

## Dictionary layout decision

The production hybrid stays selected: ordered dense entries, cached hashes,
half-full 16-byte control groups and u32 entry indices, scan at most 8 entries,
tombstones and scalar rebuild. Capacity hints and the cheap rebuild are present;
no fixture-specific hash tuning or CPython fallback was needed because all five
package rows passed. Real emitted probe controls have matching checksums.

At 4096 elements, old-shape/hybrid cycles per operation: dense lookup 9.57/13.18,
sparse 26.73/17.38, cached string 45.06/21.44, mixed string miss 57.84/36.46,
churn 70.91/81.22, tiny-word count 58.35/96.72. Dense update and tiny-table costs
are visible limits, not hidden by the language row results. Design §18 and
s2-d/layout-real.txt retain all workloads/sizes and the decision.

## Coverage and every remaining refusal

Before is the preserved 72 new core; after is the frozen combined core, on
exactly the same corpus. The report retains the legacy name-deduplicated
function metric and per-file function/typed-loop instances separately. Loops
inside a refused function are attributed to its first blocker; this does not
claim independent loop-fragment admission. Frontend rejection lists are retained.

| Count definition | Before accepted | Final accepted | Total |
|---|---:|---:|---:|
| Qualified function names, deduplicated within each corpus | 2329 | 3185 | 3627 |
| Per-file function instances | 2756 | 3687 | 4250 |
| Checked loop instances in accepted functions | 607 | 1260 | 1539 |

The checked standard coverage run took 71.18 s; all four child statuses are
zero and stderr is empty. Final standard coverage on `996d9baa` took 2.64 s:
all four children exit zero with empty stderr, with the same 3185/3627,
4757 proven and 3764 exact checks across 3017 qualified names. The final
admission proof compares every one of 4253 ordered raw function occurrences,
all individual check metrics, all 11 frontend diagnostics and all input lists:
every result matches `090dabd5`. Only core facts and their tests changed;
the typed frontend and corpus are unchanged. This qualifies reuse of the
per-file function and loop table on the final source.
The before/after loop run took 312.48 s. Both compiler
versions reject the same seven example and four language files in the frontend.
Function/loop attribution and methodology are in
`integration/s2-x-coverage-summary.md`, with JSON and raw evidence alongside it.
The complete 71 remaining observed reasons follow (fixed-array live-view
storage has an additional precise boundary demonstrated outside this corpus).

| First refusal | Standard functions | Per-file functions | Checked loops |
|---|---:|---:|---:|
| capability type | 52 | 104 | 3 |
| byte_buffer type | 77 | 81 | 42 |
| aggregate storage of live dictionary views | 29 | 29 | 28 |
| shift_right | 12 | 26 | 46 |
| f64_sqrt | 10 | 22 | 25 |
| text of a non-integer value | 18 | 18 | 28 |
| count | 11 | 13 | 3 |
| operator on an aggregate value | 10 | 13 | 6 |
| equality of a recursive value | 11 | 11 | 2 |
| replace | 8 | 10 | 10 |
| shift_left | 3 | 10 | 9 |
| extend | 9 | 9 | 10 |
| find_any | 9 | 9 | 4 |
| view | 9 | 9 | 1 |
| decode | 7 | 8 | 1 |
| interior mut argument ancestor changed during later argument evaluation | 8 | 8 | 0 |
| resource type | 6 | 8 | 0 |
| strip | 7 | 8 | 0 |
| host function | 3 | 7 | 1 |
| live dictionary view of an interior place | 7 | 7 | 8 |
| ordinary dictionary snapshot combined with a live view | 7 | 7 | 6 |
| f64_cos | 3 | 6 | 0 |
| f64_sin | 3 | 6 | 0 |
| lower | 5 | 6 | 0 |
| number_format | 6 | 6 | 0 |
| parse_float | 5 | 6 | 2 |
| parse_int_range | 6 | 6 | 0 |
| extern | 3 | 5 | 0 |
| live dictionary view with unproved source identity | 5 | 5 | 8 |
| text_repr | 5 | 5 | 1 |
| upper | 4 | 5 | 2 |
| contains | 3 | 4 | 0 |
| escaping live dictionary view | 4 | 4 | 4 |
| is_alpha | 3 | 4 | 0 |
| is_digit | 3 | 4 | 0 |
| is_space | 3 | 4 | 0 |
| lstrip | 3 | 4 | 0 |
| reverse | 4 | 4 | 2 |
| rstrip | 3 | 4 | 0 |
| text_chr | 4 | 4 | 10 |
| array | 3 | 3 | 0 |
| f64_to_u64 | 3 | 3 | 0 |
| find_range | 3 | 3 | 1 |
| index_of | 3 | 3 | 0 |
| rfind_range | 3 | 3 | 0 |
| text_ord | 3 | 3 | 4 |
| aggregate or captured dictionary alias combined with a live view | 2 | 2 | 3 |
| dictionary key type | 2 | 2 | 0 |
| f64_floor | 2 | 2 | 0 |
| find_start | 2 | 2 | 0 |
| float_round | 2 | 2 | 0 |
| hex | 2 | 2 | 2 |
| keyword call with a mut argument that is not a local | 2 | 2 | 0 |
| list storage of live dictionary views | 2 | 2 | 4 |
| mut live dictionary view argument | 2 | 2 | 2 |
| rebinding a live dictionary view | 2 | 2 | 1 |
| strip_chars | 2 | 2 | 0 |
| f64_from_u64 | 1 | 1 | 0 |
| f64_trunc | 1 | 1 | 0 |
| file handle type | 1 | 1 | 0 |
| from_hex | 1 | 1 | 0 |
| parse_int receiver | 1 | 1 | 0 |
| pop_at | 1 | 1 | 0 |
| print options | 1 | 1 | 0 |
| record field type | 1 | 1 | 0 |
| rfind | 1 | 1 | 0 |
| saturating_add | 1 | 1 | 0 |
| scalar_count | 1 | 1 | 0 |
| slice_step | 1 | 1 | 0 |
| splitlines | 1 | 1 | 0 |
| text_format | 1 | 1 | 0 |

Persistent dictionary views are precise: fresh unshared local roots, direct
temporary views and explicit list snapshots are supported. Interior, shared
ordinary-snapshot, aggregate-stored, escaping, mut-argument, rebound or unproved
persistent identities are refused. F's fixed-array storage now has the same
explicit boundary. Character/text methods, richer number text, mutable byte
buffers, recursive equality, capabilities/resources and other unsupported
constructs are enumerated by the complete first-refusal table.

The proposed fused split cursor was not implemented; split materializes its
owned list/pieces. Its package row passes the existing ABI, so the conditional
view-parameter ABI evaluation was not triggered. No short-string representation
or float-text stretch was added. These limits are recorded in design §19–20.

## Dev loop, invariants and hand-off

Meaningful integration rebuilds: I 2.83 s, T1 2.55 s, F initial 3.43 s and helper
repair 1.31 s, D initial 1 s (subsequent cached check 0.01 s), T2 2.22 s, fact repair 2.16 s. Final held
unit gate 242.43 s; runner MaxRSS 205M, test compiler 328M. Each accepted unit gate
is under 300 s, including F's package maximum 294.04 s; rebuilds under 10 s and
RSS ceilings checked even when the runner reports a green step.

The F semantic merge exceeded Guardian's `cognitive-complexity` ceiling for `bufferOperation`
(26 versus 25) after its first passing merge checks. Moving the existing keyed
sort body to a typed private helper repaired the check; source changed, so core
build, held unit gate and full conformance were rerun. No baseline waiver.
D's aggregate-view identity wrong answer was explained and repaired with precise
refusals before merge, followed by its complete affected package qualification.
Other explained repairs remain in package READMEs; no unexplained mismatch is
accepted. Invalid unheld timings are not qualification evidence.

`ir.zig` stays byte-identical to 72. No record phi is emptied. Aggregate parameter
positions remain 64-bit; persisted formats stay module-interface-v5,
check-summaries-v6 and mutation-v2. No Wave B shared frontend/old core or
`tests/lang` edit was made. The external Lox migrations remain documented only.
Locked worktrees, private evidence caches and runtime references are preserved.
The required Guardian feedback is recorded separately in
`/home/epentland/ai/canopy/guardian-zig/FEEDBACK.md`; its commit follows this
exit-evidence commit.

Only user decision: go/stop on S3, with the split-fusion deviation above
explicitly recorded in the complete S2 exit evidence.
S3 has not started.
