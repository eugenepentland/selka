# Native sort run rotation: source 804 screening archive

Candidate production `8043c4d9e0ad907c8a1b9e8416a1e58815eef0df` was adopted unchanged by the coordinator as `63df6b6c481b12fd711755ec40cdcb5d1c984ccc`. The explicit LLVM tradeoff accepts a repeated 17.6% small integer sort improvement with an 11.0% QBE large nested-mutation slowdown. The candidate initially remained unintegrated while the regression was investigated. Original raw report statuses and observations are preserved; this evidence-only commit does not modify production.

No new goal cell passes. LLVM small integer sorting remains 1.36× the current fastest arm. QBE is informational under the goal policy. Layout/cache interaction is a hypothesis for its regression, not a demonstrated cause.

All measurements use Debug compiler hosts and ordinary ReleaseFast guests. The exact before artifacts belong to source `5a60ef1039aca32657ef5877a464eb8a81d6c115`; their complete production input map is byte-identical to accepted join source `957f97c6d9906ef11cf344ce055dada8be8446ea`. The control compiler was reused. Frozen sources, guest policy and reference artifacts were retained.

The CPU 2 six-arm screen used the ordinary timing lock, five measured rounds and one warmup, from 03:22:09 to 03:23:21 UTC, with 240 measured samples and 720 successful qualifications. Session `118e5b2a-23a0-4b29-a630-9906fbbe59af` is a subset screen. The initial paired screen used the same eight plans and 5/1 rounds from 03:23:37 to 03:23:57 UTC, with 160 measured samples plus 32 warmups. The independent repeat retained the six sorting/nested plans and used 15/3 rounds from 03:25:44 to 03:26:19 UTC, with 360 measured samples plus 72 warmups and session `5aea9874-b35d-4099-b5b7-fa640e5ccb98`. No builds or other agent processing overlapped the timing intervals. Guest timing ended before each paired bootstrap/replay.

The original five-round helper remains byte-identical: SHA256 `2f0bdf77d4ca75ed2dde83393936bb83f09af717562c0899c4494445482988fb`. The repeat has a separate helper and UUID-seeded randomized arm order, with unchanged input sizes, iterations, seeds and artifact checks. These Debug-host diagnostics are not ordinary ReleaseFast-host six-arm confirmations.

## Results

After/before ratios below 1 indicate improvement. Intervals use same-round paired deterministic percentile bootstrap, without multiple-comparison correction.

| Case / size | Initial LLVM ratio [95% CI] | Repeat LLVM ratio [95% CI] | Initial QBE ratio [95% CI] | Repeat QBE ratio [95% CI] |
| --- | ---: | ---: | ---: | ---: |
| sort_records / small | 1.02547 [1.02129,1.02713] | 1.01978 [0.99694,1.03050] | 1.01316 [1.00943,1.02365] | 1.00971 [1.00720,1.01210] |
| sort_records / large | 1.01012 [0.99110,1.03018] | 1.01194 [0.97084,1.07364] | 1.00031 [0.99826,1.00893] | 0.99973 [0.99320,1.00314] |
| sort_int / small | 0.82234 [0.82234,0.82700] | 0.82396 [0.81992,0.82759] | 0.87480 [0.86878,0.88365] | 0.87446 [0.87200,0.87833] |
| sort_int / large | 1.00152 [0.99736,1.00705] | 1.00468 [1.00092,1.01022] | 0.99385 [0.98875,1.00058] | 0.99594 [0.99435,0.99860] |
| mutate_nested / small | 0.98910 [0.97605,0.99282] | 0.98644 [0.98048,0.98977] | 1.00264 [0.98720,1.02633] | 0.99866 [0.99528,1.00093] |
| mutate_nested / large | 0.99960 [0.99099,1.03150] | 1.00122 [0.99678,1.01450] | 1.10596 [1.07961,1.11767] | 1.10972 [1.09834,1.11763] |
| list_append / small | 1.01118 [0.93715,1.02216] | — | 0.99856 [0.99360,1.01250] | — |
| list_append / large | 0.99518 [0.99136,0.99897] | — | 0.99905 [0.99465,1.00046] | — |

Repeat absolute LLVM small-sort medians are 268.657→221.364 ns/op; QBE nested-large medians are 7880.641→8745.309 ns/op. LLVM record-small medians 1181.065→1204.426 ns/op yield ratio 1.01978 with interval [0.99694,1.03050]; no record-sort benefit is established. Six-arm LLVM/current-fastest levels are:

| Case / size | LLVM/current fastest |
| --- | ---: |
| sort_records / small | 2.24661 |
| sort_records / large | 1.21569 |
| sort_int / small | 1.36067 |
| sort_int / large | 1.00000 |
| mutate_nested / small | 1.00000 |
| mutate_nested / large | 1.00000 |
| list_append / small | 2.67897 |
| list_append / large | 2.38748 |

## Source and actual binary scope

`static-source.py` removes only the inserted 19-line block and recovers the complete baseline `native_collections.c` byte for byte. This is the only changed production file. Allocation order/sizes, refusal-before-mutation, fallback merge, key evaluation, accounting, COW and keyed sorted-copy paths are retained. Upper trimming leaves a left value strictly greater than right[0]; because left[last] is at least that large, lower trimming retains right[0]. Both trimmed runs are nonempty. Strict max(right)<min(left) permits rotation without disturbing stability; holding the shorter run fits the existing floor(count/2) scratch.

`static-binary.py` pins both LLVM and QBE guests. Actual LLVM integer sorting contains guarded memcpy/memmove/memcpy transfers. LLVM `myl_native_list_sort` grows 5398→5868 bytes; `.text` grows 292002→292594 bytes (+0.203%). QBE `.text` grows 418166→419462 bytes (+0.310%).

All 402 named QBE code bodies are compared, retaining mnemonics, registers, operand order, scalar constants, stack offsets and local branch offsets. Only annotated symbol addresses and known non-TLS address immediates are normalized. Exactly six native sort functions change; 396 bodies remain equivalent. Complete `batch_result` stays at `0x1016ab0`, size 132860. Its kind 10 nested arm remains `0x101caa5..0x101ffc4`, with 2649 equivalent instructions and 70 direct calls. All 96 functions in its direct-call/tail-call closure are equivalent; no changed sorting routine is in that closure. Complete before/after disassembly and per-function raw/normalized hashes are archived.

Unresolved indirect-call/jump-table sites are listed explicitly. Every named callback body is included in the whole-guest comparison; anonymous data, indirect target resolution and shared-library bodies remain outside the proof. Code after the sorting block shifts by `0x510` bytes, and generated data by `0x1510` bytes; both shifts alter 64-byte alignment by 16 bytes. These movements support a layout/cache hypothesis but do not establish causality or exclude residual measurement effects.

## Correctness and provenance

All 24 official guests built; 720 fresh frozen checksum qualifications and 516 holdouts passed with elapsed values discarded. All 32 native UBSan suites and two focused optimized ASan/UBSan suites passed on final source. The rotation suite checks 78 stable run cases and seven scratch refusals. Linker-wrapped memmove proves actual specialization, preventing accidental fallback from satisfying movement assertions. Coverage includes signed/unsigned widths, both shorter-run directions, odd/unequal/random/interleaved/ascending/descending runs, equal boundaries, distinct NaN payloads, infinities, signed zero, rooted text pointer identity and allocation failure before mutation. The first optimized UBSan run preceded a comment-only refinement; runtime code/tests were identical. Input manifest self-test passed.

The production commit gate passed 88 whole-tree Guardian checks. The host build passed 88 diff-scoped checks (65 files; 38 checks still read the whole tree), explicitly recorded as such. Native log outcomes are reviewed attestations backed by preserved bytes, not proof of execution merely because hashes match. Coordinator feedback `75c89ee` already records native/production gates; the evidence commit outcome is reported separately for consolidation.

`validation-receipt.json` binds production source fingerprints, both host receipts/manifests, backend manifests, checks and raw/gzip hashes. `timing-evidence.json` binds all three reports/logs, their preserved history, coordinator integration decision and the validation receipt. All 49 archived artifacts round-trip byte for byte. Original raw files remain in the private cache. The coordinator independently replayed 516 holdouts, 624 paired outcomes, live binary hashes and the 402-function/96-target comparison before adoption.

## Replay

From this worktree:

```bash
python3 experiments/runtime-goal110-sort-rotation-20261004/verify-archive.py
python3 experiments/runtime-goal110-sort-rotation-20261004/static-source.py
python3 experiments/runtime-goal110-sort-rotation-20261004/static-binary.py
python3 benchmarks/runtime/expanded/verify.py --focused --check-artifacts experiments/runtime-goal110-sort-rotation-20261004/six-arm-screen.json.gz
```

Binary/live-artifact checks require the recorded ELF/tool paths. Archive verification and checksum/paired replay read saved files. New measurements require coordinator START and the ordinary timing lock. No aggregate pools workloads, and final goal acceptance requires the normal ReleaseFast host policy and independent complete six-arm confirmations.
