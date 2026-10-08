# S3-A: qualified standard library and applications

The combined application package qualifies on frozen source
`203c0ca6100344304cbd9fd20d22cc7f9448a145`. All 40 rows pass both new/old and new/Zig ReleaseSafe
limits at 4096 and 64, with zero misses. Standard-library imports, literal split
fidelity, strict native semantics, Core, conformance and the full old-core gate
also pass. This is the A handoff; the coordinator still owns final integrated
S3-X qualification and the section 7/S4 decision.

`qualification-final-01.json` checks the receipts and records SHA-256 provenance
for the source inputs, fresh compiler, corrected oracle/QBE, reference workload
sources/binaries, all 80 measured old/new binaries and all 40 fresh LLVM modules.
The installed new compiler SHA-256 is `c3aaee87434f185a21970f76e94b655503c1e69561884a15098787ee46cca1bc`. It was built from this
worktree's source; guests link their independent Core runtime and the benchmark
clock port. No copied new compiler or old-runtime object link is used.

| Final combined check | Result | Evidence |
|---|---|---|
| Exclusive own-source install | 2.33 s actual command; all three build slots held; no other-build wait | `logs/core-trace-combined-11.*` |
| Core64 | 276/276; exactly 64 verdicts; 125.95 s; maximum shard 52.87 s; maximum test RSS 249 MiB; no overrun | `trace-combined-core64-review-04.json`, `logs/trace-combined-test-core64-06.*` |
| Full strict conformance | 1518 matching in each debug/release mode; zero mismatch/refusal; leak/fact verification; 52.00 s | `logs/trace-combined-full-conformance-06.*` |
| All40 performance | 80 size cells pass both ratios; strict four-program checks; 283.10 s after admission | `all40-combined-final-03.json`, `logs/all40-combined-final-03.*` |
| Imports/original/split native | 137 exact native executions; old/debug/release/verify; zero leaks, nonzero statuses or unexpected output; 54.58 s | `qualification-combined-final-02/summary.json` and per-build/native records |
| Pinned managed split | Seven exact lines in all four modes; zero exit and empty leak stderr; 15.26 s | `split-qualification-combined-final-03/summary.json` |
| Split-key transformation sweep | Fresh cursor source: 50 sources, 750 exact comparisons, zero mismatches; 145.83 s | `fuzz-split-cursor-50-02/summary.json`, `cursor-qualification-01.json` |
| Original35 instructions | All 343 actual definitions; exactly six approved scalar stores plus two trace calls; all remaining instructions/operands/CFG/phis/traps and site metadata match; full module remainder exact after trace declaration replacement | `combined35-final-04/summary.json`, all complete before/after LLVM and raw diffs |
| Fixture fidelity/tool checks | All five literal extractions unchanged; parser/registry smoke passes; Python syntax and diff checks pass | `split_apps.py --check`, `logs/final-tool-smoke-02.txt`, `logs/llvm-parser-smoke-01.txt` |

The combined old gate is required by the character package's SPEC update. The
final four-step run held both gate/build slots for each step on this frozen source:

| Old gate | Actual command time | Result |
|---|---:|---|
| `test` | 808.42 s | Pass; exit 0, successful summary, RSS inspection |
| `test-qbe` | 75.43 s | Pass; exit 0, successful summary, RSS inspection |
| `test-qbe-build` | 3.01 s | Pass; exit 0, successful summary, RSS inspection |
| `fmt-check` | 0.24 s | Pass; exit 0, successful summary, RSS inspection |

`old-gate-combined-final-03/summary.json` retains each exact command, source,
exit status, wall/admission time, successful summary, shard RSS and overrun
inspection. Its old-unit/QBE times are separate from the Core compiler/test
limits. Default Core sharding remains eight; explicit 64-shard qualification
keeps the native fixture work below the 90-second shard limit. The trace
package's functional-but-over-time Core32 receipt is retained alongside its
qualified Core64 replacement.

The first combined old run failed NATIVE-ZIG-CACHE-4 because the inherited gate
tool placed TMPDIR inside the project's .zig-cache; the unit assertion requires
private scratch outside it. That 945.07-second failed run is retained as
`old-gate-combined-final-01`. A second tool-only correction put scratch under
.mylang-cache, which made two incremental-test harnesses exclude every copied
source by an absolute-path cache filter; that 820.59-second failed run02 is also
retained, with all 3002 unit tests passed. The final tool uses unique private
/var/tmp scratch, avoiding both cache ancestors; both exact failed incremental
commands pass their focused scratch preflight. Fresh four-step
run03 above qualifies. No compiler/runtime/test changes were made for these
scratch corrections.
The original combined35 checker also miskeyed dotted LLVM helper names by
searching the whole function body. Its incomplete run03 is retained; the corrected
header-anchored parser accepts full LLVM symbols, rejects duplicate headers,
and proves all 343 definitions in run04. Neither tool correction changed
the compiler/runtime or required a repeat of already valid performance samples.

The generic repairs are whitespace cursor fusion with borrowed lookup and owned
insertion keys, exact small-dictionary span probing and scalar value stores,
trusted byte-index normalization, complete scalar-use fusion with checked text
diagnostics/direct short append/guarded ASCII decoding, bounded trusted cursor
emission, and compiler-owned preserving error-trace twins. Reference algorithms,
input distributions, timed work and checksums remain unchanged. The frozen IR,
ownership implementation and tests/lang are unchanged from the qualified base;
module-interface-v5, check-summaries-v6, mutation-v2 and first-64 aggregate masks
remain intact. The sibling reports under `s3-packet`, `s3-char` and
`s3-packet-trace` retain their focused authority, diagnostics, ownership and
native sweeps. These packages were qualified before their A merges; combined
Core/conformance and fresh all40/native receipts establish the final composition.

Every performance pair below is 4096/64, in cycles per unit. Units and iteration
counts are the inherited S1/S2 registry; application units are dataset elements.
Timing uses CPU10 only, seven shuffled interleaved rounds, and subtraction of
three one-iteration startup medians. Every sample requires zero exit, exactly
two integer stdout fields, matching four-program checksums and one positive
finite cycle counter. Both CPU locks are acquired external EDA first, S2 second.
Neither size nor either ratio is averaged away.

| Row | Old | New | Rust | Zig ReleaseSafe | New/old | New/Zig | Both gates |
|---|---:|---:|---:|---:|---:|---:|---|
| record_reads | 25.434 / 24.476 | 17.960 / 17.363 | 17.683 / 17.248 | 24.221 / 23.910 | 0.706 / 0.709 | 0.741 / 0.726 | Pass |
| tagged_stack | 63.279 / 63.263 | 33.304 / 33.300 | 25.922 / 25.892 | 47.856 / 47.759 | 0.526 / 0.526 | 0.696 / 0.697 | Pass |
| mutate_unique | 17.360 / 17.086 | 14.559 / 14.557 | 13.195 / 13.155 | 16.949 / 16.963 | 0.839 / 0.852 | 0.859 / 0.858 | Pass |
| mutate_shared | 0.963 / 6.994 | 0.633 / 0.640 | 0.625 / 0.641 | 0.977 / 1.002 | 0.657 / 0.092 | 0.648 / 0.639 | Pass |
| record_construct | 11.599 / 11.754 | 2.301 / 2.398 | 6.896 / 7.329 | 10.494 / 11.034 | 0.198 / 0.204 | 0.219 / 0.217 | Pass |
| record_update | 11.703 / 11.777 | 6.176 / 6.284 | 6.892 / 7.328 | 11.155 / 11.635 | 0.528 / 0.534 | 0.554 / 0.540 | Pass |
| option_handle | 4.065 / 4.033 | 2.007 / 2.490 | 2.412 / 3.155 | 6.553 / 7.383 | 0.494 / 0.617 | 0.306 / 0.337 | Pass |
| result_propagate | 6.117 / 5.589 | 3.625 / 3.497 | 3.509 / 4.120 | 7.225 / 7.283 | 0.593 / 0.626 | 0.502 / 0.480 | Pass |
| list_scan | 3.845 / 3.984 | 3.973 / 4.043 | 2.698 / 2.792 | 4.564 / 4.657 | 1.033 / 1.015 | 0.870 / 0.868 | Pass |
| list_append | 7.195 / 14.201 | 7.044 / 9.554 | 6.192 / 10.260 | 12.283 / 16.785 | 0.979 / 0.673 | 0.573 / 0.569 | Pass |
| list_filter | 9.298 / 17.741 | 8.215 / 10.484 | 5.735 / 9.998 | 10.592 / 13.847 | 0.884 / 0.591 | 0.776 / 0.757 | Pass |
| alloc_short | 242.390 / 245.913 | 4.811 / 5.097 | 5.017 / 5.499 | 21.805 / 22.233 | 0.020 / 0.021 | 0.221 / 0.229 | Pass |
| alloc_retained | 144.168 / 157.264 | 38.169 / 38.965 | 80.241 / 82.265 | 80.894 / 78.585 | 0.265 / 0.248 | 0.472 / 0.496 | Pass |
| mutate_nested | 28.911 / 45.751 | 12.987 / 14.411 | 81.511 / 72.422 | 76.247 / 74.107 | 0.449 / 0.315 | 0.170 / 0.194 | Pass |
| bytes_scan | 0.086 / 0.245 | 0.052 / 0.244 | 1.135 / 1.193 | 1.381 / 1.761 | 0.598 / 0.995 | 0.037 / 0.138 | Pass |
| string_equal | 53.644 / 16.670 | 50.503 / 15.273 | 134.764 / 12.722 | 277.495 / 16.887 | 0.941 / 0.916 | 0.182 / 0.904 | Pass |
| string_search | 423.613 / 79.956 | 433.713 / 68.420 | 5584.951 / 181.374 | 12922.396 / 385.098 | 1.024 / 0.856 | 0.034 / 0.178 | Pass |
| string_split | 201.731 / 210.625 | 61.004 / 64.419 | 27.865 / 35.716 | 65.658 / 68.997 | 0.302 / 0.306 | 0.929 / 0.934 | Pass |
| string_join | 6.178 / 10.138 | 4.593 / 6.159 | 13.836 / 14.516 | 17.995 / 20.374 | 0.743 / 0.608 | 0.255 / 0.302 | Pass |
| dict_lookup | 31.004 / 16.967 | 15.456 / 15.237 | 41.987 / 40.796 | 52.151 / 31.017 | 0.499 / 0.898 | 0.296 / 0.491 | Pass |
| dict_lookup_str | 61.643 / 28.608 | 23.956 / 19.783 | 61.178 / 57.247 | 62.468 / 31.890 | 0.389 / 0.692 | 0.383 / 0.620 | Pass |
| dict_update | 827.559 / 731.664 | 191.017 / 182.219 | 415.905 / 408.703 | 549.574 / 308.612 | 0.231 / 0.249 | 0.348 / 0.590 | Pass |
| dict_update_str | 1026.782 / 882.992 | 273.475 / 250.873 | 920.092 / 871.296 | 730.235 / 404.666 | 0.266 / 0.284 | 0.375 / 0.620 | Pass |
| set_dedup | 175.472 / 168.279 | 24.733 / 28.699 | 62.497 / 62.562 | 81.143 / 37.637 | 0.141 / 0.171 | 0.305 / 0.763 | Pass |
| int_parse | 46.392 / 41.419 | 28.927 / 26.517 | 24.661 / 19.219 | 30.798 / 24.324 | 0.624 / 0.640 | 0.939 / 1.090 | Pass |
| int_format | 213.023 / 209.331 | 68.450 / 62.736 | 63.449 / 60.691 | 214.227 / 198.020 | 0.321 / 0.300 | 0.320 / 0.317 | Pass |
| call_indirect | 5.016 / 5.081 | 0.302 / 0.314 | 7.203 / 7.691 | 9.008 / 9.502 | 0.060 / 0.062 | 0.034 / 0.033 | Pass |
| sort_int | 45.513 / 11.747 | 46.779 / 9.401 | 69.983 / 15.403 | 67.401 / 17.703 | 1.028 / 0.800 | 0.694 / 0.531 | Pass |
| sort_records | 54.517 / 66.317 | 38.750 / 40.106 | 41.709 / 44.826 | 117.300 / 50.655 | 0.711 / 0.605 | 0.330 / 0.792 | Pass |
| int_math | 8.687 / 9.065 | 0.355 / 0.495 | 5.695 / 6.178 | 7.801 / 8.312 | 0.041 / 0.055 | 0.046 / 0.060 | Pass |
| float_math | 8.288 / 8.427 | 1.568 / 1.705 | 6.965 / 7.322 | 6.512 / 7.027 | 0.189 / 0.202 | 0.241 / 0.243 | Pass |
| call_direct | 3.037 / 3.150 | 0.301 / 0.321 | 2.015 / 2.933 | 3.017 / 4.113 | 0.099 / 0.102 | 0.100 / 0.078 | Pass |
| branch_predictable | 4.026 / 4.150 | 0.396 / 0.498 | 3.195 / 3.252 | 7.723 / 7.929 | 0.098 / 0.120 | 0.051 / 0.063 | Pass |
| branch_mixed | 4.124 / 4.130 | 0.396 / 0.497 | 4.868 / 4.517 | 9.257 / 8.985 | 0.096 / 0.120 | 0.043 / 0.055 | Pass |
| binary_search | 143.824 / 33.045 | 33.186 / 17.869 | 36.634 / 19.494 | 136.943 / 27.894 | 0.231 / 0.541 | 0.242 / 0.641 | Pass |
| word_count | 291.178 / 376.324 | 35.469 / 49.768 | 59.163 / 66.211 | 47.230 / 50.783 | 0.122 / 0.132 | 0.751 / 0.980 | Pass |
| csv_aggregate | 4887.611 / 4155.417 | 1120.384 / 1051.270 | 1168.258 / 1063.193 | 1042.986 / 986.319 | 0.229 / 0.253 | 1.074 / 1.066 | Pass |
| json_transform | 13686.549 / 13992.007 | 2848.031 / 2959.839 | 1787.953 / 1967.209 | 2827.447 / 2853.505 | 0.208 / 0.212 | 1.007 / 1.037 | Pass |
| packet_decode | 15.623 / 15.083 | 15.922 / 15.942 | 10.345 / 10.737 | 18.968 / 19.671 | 1.019 / 1.057 | 0.839 / 0.810 | Pass |
| lox_eval | 629.831 / 659.055 | 206.007 / 214.136 | 165.422 / 171.686 | 503.969 / 521.546 | 0.327 / 0.325 | 0.409 / 0.411 | Pass |


The first combined full sweep and its paired repeat remain failed evidence:
word64/Zig 1.103086/1.103926 and packet64/old 1.101765/1.106961. Profiles and exact
LLVM/assembly comparisons guided the cursor and trace repairs; neither failure
was waived or overwritten. The final independent full sweep above passes.

Normal commits use the whole-tree Guardian gate. Its source/evidence receipts
and local feedback candidate are retained; the coordinator owns the required
shared FEEDBACK.md append/commit. No pushes or integration/main merge are made
by this package owner. Final integrated operation-count auditing, coverage,
nine-kind 200-source matrix, separate split-key 200 sweep, full conformance,
all40 and old gates remain the coordinator's S3-X work.

## Retained qualification history

The following checkpoints preserve admission receipts, real failures, profiles,
approved repairs and their package-level qualifications. Pending statements
describe those earlier checkpoints; the combined qualification above is final.

## Application admission and measurement foundation

Source dependency: `f1319a774d638c664de9f02bb27098650a13249b` (qualified S3-C,
S3-T1 and S3-T2 integration). This checkpoint qualifies application admission,
literal split fidelity and strict native correctness. **It does not qualify
the application performance gate or S3 exit.** Profile-driven repairs follow.

`split_apps.py --check` verifies five saved fixtures against literal helper and
dispatch-body extraction from the unchanged expanded sources. Row selection and
unused setup/helpers are removed; timed algorithms, input distributions and
checksums remain the originals. Rust and Zig reference sources/binaries are
unchanged. `word_count` was built and measured first.

`measure_all40.py` retains the S2 API, registry and timing method, adds five
applications and records separate new/old and new/Zig ratios and misses. Every
native sample requires exit zero, exactly `checksum elapsed_ns\n`, one positive
finite user-cycle counter and consistent checksums across old/new/Rust/Zig.
Three one-iteration startup samples are subtracted from seven shuffled,
interleaved rounds. Both sizes are 4096/64 and each ratio limit is 1.10.
The original 35 row iteration counts, units and reference naming are unchanged.
Application counts for 4096/64 are word_count 400/25000, CSV 40/2500, JSON
20/1250, packet 400/25000 and Lox 40/2500, normalized per dataset element.

The protected old oracle and adjacent QBE were copied from the coordinator's
qualified corrected oracle, not the pre-D2 S2 baseline. Source commit
`65036fe792ef540392d0eb00c41c9ec71c7b2c82`; the corrected ENV-NAMES-GRANT-1 full
old gate qualified this pair. Compiler SHA-256
`d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79`; QBE
`b6139650a99b39131cd791fa1fdc84c09472dc303930bbadd3f8a5348487af4c`.
The new compiler was installed from this worktree's source. No copied new binary
or linked old runtime object is used.

All build-heavy runs hold the gate and build slots using the required preserving
shell wrapper. Timing/profile runs also hold
`/run/user/1000/mylang-s2-cpu10.lock`; native perf children use CPU 10 only.
Each command has a unique log. Runtime reference worktrees are preserved.

| Check | Command after slot wrappers | Result and retained evidence |
|---|---|---|
| Own-source installation | `python3 …/wave-a/exclusive_core.py -- /usr/bin/time -f '%e' -o …/logs/core-install-01.time zig build core --summary all` | 3/3 successful; 2.73 s uncontended command time, MaxRSS 374M; `logs/core-install-01.*` |
| Tool syntax and strict parser smoke | `python3 -m py_compile …/{split_apps,measure_all40,qualify_apps}.py`; `measure_all40.py --smoke-test`; `split_apps.py --check` | Registry40/S0 mapping/strict parser/signal-exit checks pass; all five fixtures match extraction |
| Original/split and import qualification | `qualify_apps.py --bin .mylang-cache/s3-a/qualification-01 --evidence …/qualification-01` | 137 native executions; five apps agree with unchanged original-old suites, split old, new debug/release/verify; strict leak/status/stdout checks pass. Unchanged full text entry also reaches strings.repeat and JSON in all three new modes. `qualification-01/summary.json`, per-build command/status logs, `logs/qualification-01.txt` |
| First word row | `flock -x …/mylang-s2-cpu10.lock python3 …/measure_all40.py --build --rows word_count --bin .mylang-cache/s3-a/word-count-01 --json …/word-count-01.json` | Valid and checksum matched, Zig miss at both sizes; `logs/word-count-01.txt` and `word-count-01.json` |
| Other four app rows | Same tool with `--rows csv_aggregate,json_transform,packet_decode,lox_eval --bin .mylang-cache/s3-a/apps-01 --json …/apps-01.json` | All builds/samples valid and checksum matched; Lox passes both gates; other three miss. `logs/apps-01.txt`, `apps-01.json` |
| Miss profiles | Locked CPU10 `perf record -F 997 -e cpu_core/cycles/u -g`; `perf report --stdio --no-children --call-graph none --sort symbol --percent-limit .5` | No lost samples. Compact hotspot reports and separate native record logs retained; binary perf data remains in private `.mylang-cache/s3-a` |

Qualification cases are `(size, iterations, seed)` = `(2,1,7)`, `(64,3,7)`,
`(65,1,17)`, `(4096,1,7)`, `(4100,3,17)`. Each new execution uses
`MYL_CORE_LEAKCHECK=1`. An abnormal status, unexpected stdout or any stderr fails
qualification. The full original text entry additionally runs string_equal and
json_transform at `(64,3,7)` in debug/release/verify mode. Programs use only the
benchmark's linked clock; no filesystem, entropy or network fixture is needed.

## Initial application table and required repairs

Every pair is 4096/64 in user cycles per dataset element.

| Row | Old | New | Rust | Zig ReleaseSafe | New/old | New/Zig | Both gates |
|---|---:|---:|---:|---:|---:|---:|---|
| word_count | 291.503 / 376.509 | 98.356 / 112.269 | 59.308 / 66.142 | 47.299 / 51.341 | .337 / .298 | 2.079 / 2.187 | miss |
| csv_aggregate | 4891.612 / 4151.454 | 2006.595 / 1806.958 | 1169.335 / 1058.373 | 1043.786 / 985.930 | .410 / .435 | 1.922 / 1.833 | miss |
| json_transform | 13655.770 / 14018.850 | 3160.786 / 3378.116 | 1780.526 / 1976.507 | 2817.246 / 2846.019 | .231 / .241 | 1.122 / 1.187 | miss |
| packet_decode | 15.529 / 15.074 | 48.339 / 48.973 | 10.277 / 10.667 | 18.937 / 19.452 | 3.113 / 3.249 | 2.553 / 2.518 | miss |
| lox_eval | 629.947 / 659.469 | 206.056 / 214.010 | 165.150 / 171.446 | 504.490 / 521.745 | .327 / .325 | .408 / .410 | pass |

Word profile (741 samples): whitespace split 18.65%, block allocation 17.39%,
string hashing 17.74%, block cleanup 8.96% plus block free 3.27%. Emitted IR has
one dictionary probe per input word; materializing every split piece dominates.
The coordinator authorized generic whitespace cursor fusion, with borrowed
spans for lookup and owned materialization plus same-key reprobe only at insert.
No view may escape or travel through a phi; nonqualifying consumers retain the
materialized implementation.

CSV profile (2K samples): equality 18.76%, append 17.74%, allocation 10.01%,
character creation 8.61%, width 7.00%. Character values have multiple comparison
and append consumers; the existing single-use append fusion cannot cover them.
JSON (1K samples): allocation 15.31%, buffer push 14.08%, read_value 7.81%, block
cleanup 7.61%, read_string 7.50%, byte index offset 6.02%. Packet (4K samples):
byte index offset 55.56%, main 40.59%, error traces 3.85%. Owning-package repairs
are routed through the coordinator. No shared compiler source changed at this
foundation checkpoint.

Inherited compiler correctness at `f1319a77` is the coordinator's qualified
254/254 Core32 gate and full 1518/1518 debug/release strict conformance with zero
mismatch or unsupported test, including leak/fact verification. This checkpoint
adds no compiler or gate-list source, so does not rerun that unchanged proof.
The next compiler source change receives fresh required qualification. Frozen
`ir.zig`, record phi ownership, first-64 aggregate parameter masks and persisted
formats remain unchanged. No main merge or push occurred.

## Retained word fusion prototypes

Release-only private whitespace-split loops now use byte cursors and source-rooted
SSA views when every word use is a dictionary probe or insertion key. The
compiler's split declaration and new cursor helpers use authorized `runtime_c`
linkage, exact signatures, zero ownership/view argument masks. A source extern
lookalike cannot activate fusion. All loop-index/list/word uses are validated
before changing the IR; observable indices, escaped lists/words, ordinary calls
and word phis retain the materialized loop. Insertions explicitly materialize an
owned key and repeat `dict_find` against the same current dictionary/key before
`dict_insert`. No `own.zig` or frozen IR edit is needed.

A generated borrowed-key descriptor probe inlines the existing cached-hash
small-table scan only when the dictionary has no index or deletion bitmap.
Hashing calls the existing Core span hash and mixes its bits identically;
comparison checks byte length then `memcmp`. Indexed/deleted dictionaries retain
the existing runtime span probe and negative insertion-probe semantics. This
helper is emitted only for dictionary types with actual SSA-view probes.

| Prototype | New cycles 4096 / 64 | New/old | New/Zig | Status |
|---|---:|---:|---:|---|
| Cursor and owned-on-insert only | 64.785 / 76.779 | .222 / .203 | 1.368 / 1.512 | both Zig sizes miss |
| Cursor plus inline clean-small span probe | 53.051 / 66.381 | .182 / .176 | 1.118 / 1.302 | both Zig sizes miss |

Every timing uses seven interleaved rounds and three startup samples, strict
four-program output/status/checksum/cycle checks, CPU10 and its shared lock.
`word-count-prototype-01.json` and `word-count-span-03.json` retain raw samples.
The intermediate `word-count-span-02.json` is deliberately invalid: the LLVM
prototype used `%entry` both as a block label and value name. The build rejected
it before any measurement; it was corrected to `%number` and retained unchanged.

Own-source exclusive installation times were 2.86 s (cursor), 1.73 s (span), and
0.88 s (cached installation after the exact-signature authority hook); the latter
follows an actual source compilation performed by the preceding Core test build.
Each build and test has a unique log under `logs/`.

The semantic gate `split-tests-08.txt` passes 3/3 in 3.05 s test wall. Its native
fixture covers all six ASCII whitespace octets, UTF-8 and non-ASCII whitespace,
empty input, managed dictionary returns, an owned temporary input, source
rebinding, break/continue, captured dictionaries, growth beyond eight keys,
deletion fallback, and actual 32-bit hash collisions. The pair
`collision002553`/`collision005a0e` hashes to `ae700d18`; their counts stay distinct.
Five IR near misses and an identical-signature extern-authority near miss are
explicitly checked. `split-qualification-01/summary.json` additionally verifies
identical pinned output, zero exits and empty stderr against the corrected old
oracle and new debug/release/verify, with leakcheck in all new modes.

Failures are retained: the initial list-alias rewrite replaced a forwarding copy
among header phis with an `undef`, violating the phi prefix. The correction keeps
a copy of an out-of-block undef list constant, which stays dead and unowned.
`split-keys-failure-02.ir` preserves the rejected IR. Earlier syntax/prototype
logs remain evidence and are not counted as successful gates.

The post-span profiles retain 1247/1762 samples at sizes 4096/64, zero lost.
Remaining hotspots: scalar dictionary set 21.32%/19.38%, span hash 17.19%/13.64%,
end cursor 9.74%/7.55%, start cursor 6.02%/5.85%, main 28.21%/29.70%. The next
proposed owning-package repair is a typed store for scalar dictionary values;
managed-value release and copy behavior stays in the existing runtime path.
No next-step performance qualification is claimed here.

The generated split-key fuzz probe `fuzz-split-probe-02` passes three programs,
45 debug/release/verify comparisons and strict leak/status/stderr checks. The
first generated probe was rejected by the old checker because JSON's `\\f`
escape is outside mylang; the generator now emits the equivalent admitted
`\\x0c` octet, and retains that initial rejection without counting it as a
compiler mismatch. The required final 50-case run will use the final source.

## Qualified word package, before sibling application merges

The profile-driven scalar store is restricted to integer, bool, f64 and unit
dictionary values. Ownership still supplies the unique dictionary after COW;
the store uses the existing descriptor stride and value offset and returns the
same dictionary pointer. Managed values keep their runtime release/copy path.
`d_scalar_stores.my` verifies snapshots, indexed and tombstoned dictionaries,
bool/unit, narrow signed/unsigned values, NaN and signed zero in debug, release
and verify with leakcheck. Four focused Core tests pass in
`logs/split-store-tests-13.txt`. Earlier failures are retained.

`word-dict-store-04.json` qualifies the final word source and every affected
dictionary/set micro row at both sizes. Cycles below are per original row unit;
each cell is size 4096 / size 64. Every ratio is at most 1.10.

| Row | Old | New | Rust | Zig ReleaseSafe | New/old | New/Zig |
|---|---:|---:|---:|---:|---:|---:|
| word_count | 291.066 / 377.834 | 39.879 / 53.263 | 59.246 / 66.166 | 47.208 / 50.893 | .137 / .141 | .845 / 1.047 |
| dict_lookup | 30.941 / 16.939 | 15.371 / 15.258 | 42.207 / 41.651 | 52.337 / 31.121 | .497 / .901 | .294 / .490 |
| dict_lookup_str | 62.011 / 28.675 | 27.218 / 19.816 | 64.713 / 57.309 | 62.812 / 31.903 | .439 / .691 | .433 / .621 |
| dict_update | 827.239 / 731.503 | 191.838 / 182.705 | 415.239 / 398.886 | 549.963 / 309.679 | .232 / .250 | .349 / .590 |
| dict_update_str | 1025.832 / 882.514 | 276.833 / 250.257 | 920.686 / 861.430 | 731.204 / 404.517 | .270 / .284 | .379 / .619 |
| set_dedup | 175.502 / 168.279 | 24.643 / 28.799 | 62.455 / 62.519 | 81.055 / 37.572 | .140 / .171 | .304 / .767 |

The fresh 50-source split-key sweep, `fuzz-split-50-01/summary.json`, completes
750 exact old/new comparisons across debug/release/verify, five argument cases,
zero mismatches, zero nonempty stderr and zero leak reports in 149.99 s. Native
`split-qualification-02` also matches the corrected old oracle on seven pinned
output lines. It adds original-source lifetime coverage while heap list and
dictionary entries are overwritten inside the cursor loop. Each resulting
dictionary retains all original keys correctly.

Own-source Core32 passes 258/258 in 139.97 s, maximum shard 68.80 s. Full strict
conformance matches 1518/1518 in both debug and release, zero mismatches and zero
unsupported, with leakcheck and verify, in 184.60 s. See unique `word-test-core32`
and `word-full-conformance` logs. The final installed build took 0.64 s after the
focused Core test compiled the exact source; earlier fresh source installations
were 2.86 s and 1.73 s. No measured Core build or Core test exceeded its limit.

`word35-diffs-01` retains fresh full raw LLVM diffs and semantic-metadata/SSA
definition diffs for every original row against the accepted C baseline. Thirty-
one rows have identical normalized definitions. The four affected dictionary
functions contain exactly six approved scalar-set replacements, counts 1/1/2/2;
all other call counts are unchanged. `exact-store-review-02.json` establishes the
stronger instruction-by-instruction correspondence after expanding only those
six old i64 set calls into the exact stride-16, block-offset-40 typed store and
same-dictionary forwarding. It removes only the six proven-private spill slots,
then checks semantic metadata and bijective SSA/block names. Every remaining
instruction, operand, trap, branch and phi edge matches. Raw diffs remain intact.
The first review receipt is a retained tool failure from stale match offsets;
the corrected receipt qualifies, with no compiler change between them.

Frozen IR, ownership implementation, persisted formats, aggregate masks and all
reference workload algorithms remain unchanged. This is the word package proof;
the final all40 A gate awaits the qualified packet and character packages,
combined-source Core/conformance, and the final combined old gate required by
the sibling SPEC update. No full-A performance claim is made here.

The normal commit's whole-tree Guardian check found local test-tag and formatting
issues; `word-commit-02.txt` retains that rejection and `word-guardian-03.txt`
retains its follow-up. Supplemental tests now use `spec-case`, diagnostics use
the existing file-scope print alias, and boolean/line/literal formatting follows
the gate rules. These mechanical corrections leave the transformation and LLVM
store recipe unchanged. `word-guardian-04.txt` passes all 88 checks. The exact
corrected source is freshly installed in 1.78 s, then passes Core32 258/258 in
98.56 s, maximum shard 45.20 s, and full conformance 1518/1518 debug/release with
zero mismatch/unsupported and verify/leakcheck. The uniquely named
`word-style-test-core32-02` and `word-style-full-conformance-02` logs retain the
refresh. Final combined all40 timing will use a fresh compiler source build.


## Combined-source gate failures and cursor follow-up

The first complete combination, `0a5dd8794faaf330ab411900d1eaf4e2a00ba0e8`,
passes own-source exclusive installation in 2.63 s, Core32 272/272 in 115.61 s
(maximum shard 75.71 s, exactly 32 verdicts, maximum test RSS 251 MiB), and full
1518/1518 strict conformance in both modes in 56.25 s with leak/fact checks.
`char-combined-core32-review-02.json` retains the complete RSS/verdict inspection.

Its fresh `all40-combined-final-01.json` is valid but **fails** two size-64 cells:
word_count new/Zig 1.103086 and packet_decode new/old 1.101765. A single authorized
paired seven-round repeat, `word-packet-combined-paired-02.json`, confirms the
misses at 1.103926 and 1.106961. Neither run is waived or overwritten. All other
cells of the first full run pass both gates, including CSV 1.070/1.081 and JSON
1.006/1.048 versus Zig. These receipts do not qualify the final all40 gate.

Zero-loss size-64 profiles retain word main 39.20%, span hash 18.11%, whitespace
end 11.37% and start 6.32%; packet main 86.54% and error-trace recording 13.46%.
Complete normalized LLVM function definitions match the previous qualified
word/packet versions. Optimized main bodies keep 742/955 instructions respectively;
full retained assembly diffs contain only two/three rodata RIP displacements.
The assembly already contains the guarded six-octet whitespace bitmask, so a
cosmetic predicate rewrite was discarded before any source edit.

The approved generic cursor follow-up is committed at
`8d1e135a885b6d19eb68a71313dc5a89dd35c557`. Exact compiler-runtime start/end calls
with `(str, i64) -> i64`, zero ownership/view masks and matching actual operands
emit bounded byte loops directly. Each byte access follows signed lower and
upper guards, and emission updates the current block label for surrounding phis.
Untrusted declarations retain their C call. Both private C helpers now safely
return negative offsets unchanged, matching their existing past-end behavior.
No IR or fact representation changes and no ownership edits are involved.

Three new Core tests compare the trusted-inline and extern-C paths in debug,
release and verify with empty/all-six-ASCII/UTF8/NBSP/negative/extreme/past-end
cases, 168 exact result integers and empty leak stderr. The existing three
managed split tests also pass, including source rebinding, temporary inputs,
container overwrites, break/continue, collisions, indexed/deleted dictionaries,
COW snapshots and all unfused boundary cases. Release LLVM explicitly has no
cursor calls. The initial test fixture selected a runtime declaration as its
entry; run14 retains UnsupportedEntry, run15 retains a mistaken test-option
correction, and run16 uses the proper module.entry and passes 3/3. Run17 passes
all three existing split tests. The compiler implementation was unchanged by
these fixture corrections.

`word-cursor-inline-06.json` then passes both gates with new cycles 32.998/47.089,
new/old .113/.125 and new/Zig .695/.924. The original and paired failed receipts
remain the qualification history; a fresh full sweep after the trace repair is
still required. All subsequent profiles/timings acquire the independent EDA
CPU10 lock first and the required S2 CPU10 lock second. The first cursor install
waited 310.274 s for external build-slot admission before its actual 2.18 s build;
the committed-source install took 2.92 s after separate gate/slot waits. These
admission waits do not count as Core compilation time.

The normal cursor commit hook initially found a 251-character tuple and a
repeated temporary-name literal. Mechanical formatting and a file-scope constant
made the normal whole-tree Guardian gate pass all 88 checks. Both hook receipts
are retained. Full committed-source Core/conformance, renewed split50/raw35 and
the final combined trace-package qualification are pending at this checkpoint.

The committed cursor follow-up now qualifies: Core275/275 in124.24s/max75.76s/exact32/RSS250MiB; full1518each0/0 with leak/fact checks in57.59s; fresh split50 completes750 exact comparisons/zero mismatches in145.83s. Fresh `word35-cursor-diffs-02` and `exact-store-review-03.json` prove31 unchanged rows and exactly six scalar-store replacements in four functions, with zero other changes. `cursor-qualification-01.json` records the proof; final A remains pending the qualified trace merge and final combined checks.
