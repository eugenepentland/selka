# S3-A packet trace ABI repair

This package starts at final application foundation `0a5dd8794faaf330ab411900d1eaf4e2a00ba0e8` and freezes compiler/runtime source at `2880b5001d843ce7b277ab3c13f1190efccb5d69`. Packet, JSON and the affected micro rows pass both gates at both sizes. Exact native trace checks, Core64, full strict conformance and the affected 50-program fuzz sweep pass. This is an isolated package for A to integrate; it claims no integration or S3-X completion.

All evidence is under `experiments/new-core-s3-20261006/wave-c/s3-packet-trace/` in this worktree. Command output files have unique run numbers. `qualification.json` records hashes and verdicts.

## Problem and implementation

The final A foundation persistently missed the packet/64 old-core gate at 1.101765 and 1.106961. A retained identical complete function definitions and optimized main instructions relative to the previous passing byte package; its zero-loss profile attributed 13.46% of samples to error recording. The packet source deliberately rejects three of every four frames, making trace origin recording a frequent operation.

The approved repair follows old-core ERROR-TRACE-6. The runtime's origin, count and last-32-entry ring algorithm is extracted unchanged into one static recording leaf. The original `myl_core_err_trace(site, mode)` ordinary-C export calls that leaf. Two `cold, noinline, preserve_most` wrappers call it with constant origin mode 0 or append mode 1. Only explicit Core IR `.err_trace` operations select these wrappers; ordinary foreign or unrelated calls keep their calling convention. LLVM declarations and calls use `preserve_mostcc`, matching the C definitions. Origins and runtime origins select the origin wrapper; propagation, conversion and returned sites select append. Site creation and `call-inline-cost=0` remain unchanged.

The first generic preserving wrapper, source `b0756eea14c747ec58cbaf88f6307c6d978ae5e9`, still missed packet/64 at 1.1087 (`apps-01.json`). Its assembly saved rax and rcx even on the origin path because its dynamic append branch needed them. Its meaningful profile retained 6,098 samples, zero loss, 89.52% main and 10.46% recorder (`profile-report-02.txt`). That unsuccessful prototype is preserved. The approved constant-mode refinement removes those unnecessary saves from the origin wrapper, while append retains its required saves (`packet-disassembly-02.txt`). It changes no trace event, allocation, ordering, ring capacity or printed report, and introduces no pure, read-only or speculative attribute.

## Exact semantics and authority

Both focused trace gates pass 8/8. The final `focused-trace-02.log` includes native debug, release and release-with-fact-verification runs of:

- an Err origin and propagated main error, exact stderr and exit 1, plus Ok(7) exiting 7;
- a returned site folding into its same-line origin, a named conversion and appended sites;
- 42 appends: exact complete report of the origin, ten dropped entries and the last 32 sites;
- an ordinary `.extern_c` call to the original `(i32, i32) -> void` trace export alongside an explicit trace operation and an unrelated internal call. The foreign declaration and call are ordinary C, the explicit operation is preserving, and all three modes return 7 with empty stdout/stderr.

The old unconditional ordinary trace declaration is replaced with the two compiler-owned declarations. When a module actually contains an ordinary extern trace call, the normal extern-declaration path emits its ordinary-C declaration on demand. This avoids duplicate declarations and adds no authority by spelling.

There are no IR, ownership, fact, source-language, persisted-format, `tests/lang`, benchmark or reference changes. Frozen IR diff against `dc1a5831` is empty (`frozen-ir-01.log`). The float-format runtime unit and its content/Zig-version cache inputs are unchanged; this package makes no new float cold-build claim.

## Performance

`apps-02.json` and `micro-01.json` retain seven shuffled interleaved rounds, three startup samples, native status/stdout/counters and all four configurations' matching checksums. Timing is on CPU10, holding both locks in order: `/home/epentland/.cache/mylang/s4-wave0-20261006/cpu10.lock`, then `/run/user/1000/mylang-s2-cpu10.lock`.

| Row | Size | New cycles/unit | New/old | New/Zig | Both gates |
|---|---:|---:|---:|---:|---|
| packet_decode | 4096 | 15.977 | 1.054 | 0.843 | Pass |
| packet_decode | 64 | 15.922 | 1.060 | 0.819 | Pass |
| json_transform | 4096 | 2839.926 | 0.207 | 1.001 | Pass |
| json_transform | 64 | 2964.085 | 0.212 | 1.041 | Pass |

| Affected micro row | New/old 4096 / 64 | New/Zig 4096 / 64 | Both gates |
|---|---:|---:|---|
| bytes_scan | 0.603 / 0.972 | 0.037 / 0.141 | Pass |
| int_parse | 0.629 / 0.640 | 1.011 / 1.090 | Pass |
| int_format | 0.320 / 0.301 | 0.319 / 0.318 | Pass |
| result_propagate | 0.594 / 0.626 | 0.493 / 0.472 | Pass |

The final small-packet profile has 9,504 samples, zero lost samples, 94.42% main and 5.53% origin recording (`profile-report-03.txt`). Profiling percentages are sample attribution, not a replacement for the interleaved performance gates. The initial eight-sample profile is retained as exploratory evidence only.

## Code identity and qualification

`audit-01/` retains every complete before/after LLVM module and raw diff against A's frozen `all40-combined-final-01/llvm` foundation. Of the original 35 rows, 34 have identical function definitions. `result_propagate` changes precisely two trace calls. Of the five applications, word, CSV and Lox definitions are identical; JSON changes precisely 52 trace calls and packet five. Every site number, operation, argument, instruction ordering and inline-cost attribute is retained. `audit-full-module-02.json` proves every whole module is byte-identical after only replacing the fixed trace declaration and each exact constant-mode trace call with its corresponding preserving wrapper. No arbitrary instruction, global, metadata or call is removed. The first whole-module validator log retains its filename-registry mistake; the corrected run uses the existing row registry.

- Core64: **273 unique tests, 64 exact Guardian verdicts, zero failures**, suite **142.65 seconds**, longest shard **82.81 seconds**, peak RSS **245,092 KiB**; all below 300 seconds, 90 seconds and 2.5 GiB (`test-core64-01.log/.time`).
- Core32: all 273 pass, suite 164.45 seconds, but longest shard 104.32 seconds, so its timing is **unqualified**. The plan's prescribed shard increase produces the valid unchanged-source Core64 run. The slow shard contained a 62.91-second scalar fixture plus five other native fixtures; no individual test exceeded 90 seconds.
- Full strict conformance: **1,518 matching, zero mismatching, zero unsupported** independently in debug and release. Leak checks, verification, stdout and process status are checked (`conformance-01.log`).
- Affected S1 fuzz: **50 accepted programs, 750 comparisons, zero generator rejections, refusals, build failures, mismatches, facts, leaks, crashes or timeouts**, seed 737, 300.90 seconds (`fuzz-s1-01/summary.json`). This includes records, unions, Result propagation, mut and alias cases; exact printed trace structure is independently checked by the native tests above.
- Exclusive source rebuilds: 2.99 seconds at the generic prototype, **2.39 seconds** at frozen final source, all three build slots held with gate exclusion; final peak 337,188 KiB (`core-build-01/02.log/.time`). Waiting for admission is outside these timings.
- Source commits and build gates pass all **88 Guardian checks**. The first normal commit attempt requested hoisting assertion-free expected-output construction out of a test containing another top-level loop; its failed log remains, and the corrected normal commits pass.

The final own-source installed compiler SHA256 is `7377793a8e0dec21b0e42b0d1bec6b1552f640b527407328ce6966d3e748f205`. The unchanged qualified corrected old compiler is `d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79`, QBE `b6139650a99b39131cd791fa1fdc84c09472dc303930bbadd3f8a5348487af4c`.

Core gates retain the gate descriptor and a build slot; exclusive installs hold all build slots and exclude gate work. Ordinary guest builds, audits, fuzz and measurements use build slots under the inherited pace table. Source is unchanged through final qualification. No shared Guardian log, integration branch, main branch or external task is modified. The coordinator will serialize the Guardian feedback and A will run the required combined qualification/all40 before claiming the final application gate.

## Reproduction

From this worktree, the full Core timing is:

```sh
bash experiments/new-core-s3-20261006/wave-c/s3-packet-trace/slots.sh gate /usr/bin/time -v zig build test-core -Dcore-shards=64 --summary all
```

Strict conformance uses `wave-b/integration/conformance_checked.py --set all --modes debug,release --leakcheck --verify --jobs 3`, the frozen corrected oracle, this worktree's installed Core and a fresh private cache. Fuzz uses `wave-a/integration/fuzz_qualification.py --kind s1 --cases 50 --seed 737` with the same binaries and fresh evidence/cache paths. Both run under `scripts/build-slot.sh build`.

Performance uses `wave-c/s3-a/measure_all40.py --build --rows packet_decode,json_transform` or `--rows bytes_scan,int_parse,int_format,result_propagate`, fresh private output paths, both CPU locks above and a build slot. `audit_trace.py` records exact build commands and full LLVM; the named JSON/log artifacts retain every measured result.
