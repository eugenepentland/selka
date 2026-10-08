# Certified presized scalar readiness: source 638

Candidate `63842d3c32ab3079d878cff89224478543f9b7f3` was adopted unchanged by the coordinator as `7e7773e43c934e67e32db3205a9f867049f9b46a`, following a repeated 2.1% LLVM small integer sort gain with a repeated 1.1% small nested-mutation cost. Nested mutation remains the fastest current arm. The complete production input trees match byte for byte. It is based on accepted rotation source `63df6b6c481b12fd711755ec40cdcb5d1c984ccc`. No new goal cell passes: small integer sorting remains 1.34× the fastest current arm.

Only the already-certified presized-loop guard's emitted callee changes from `myl_rc_list_plain_ready` to the existing identical `myl_rc_list_plain_ready_hot`. Every eligible guard uses the same policy; there is no case, PC or fixture selection. Certificates, work/refusal bounds, capacity and trip checks, generation<2^62, complete original fallback, per-append cache invalidation, accounting and collector emission are unchanged. `static-source.py` recovers the entire lowering module by removing the explanatory comment and reversing one callee substitution. Native runtime source remains byte-identical, and both entry points call the same admission body.

The measured frozen `list_append` starts with zero spare capacity. Positive trips refuse its whole-loop capacity guard before readiness, so its ordinary fallback remains a regression control. The reachable hypothesis concerns presized scalar comprehension setup such as `sort_int`.

Actual ReleaseFast LLVM O3/LTO collection ELF inspection finds ordinary readiness calls decrease 13→9 overall and 8→5 in `batch_result`. The `sort_int` presized admission block contains the original metadata, pending-finalizer and generation checks without a call; the ordinary per-append fallback remains at `0x1039edf`. The batch grows 51595→52108 bytes (+0.994%), and `.text` grows 292594→293522 bytes (+0.317%). The QBE batch retains the exact instruction/address stream except three ordinary→hot call targets. Both predicates are identical. LLVM register allocation/layout can still change, so call removal alone is not a performance conclusion.

Both compiler hosts are Debug and every guest retains the ordinary ReleaseFast backend policy. The baseline source/artifacts are rotation804, whose complete production input map matches accepted63df. Baseline and candidate each passed live all24-guest, clock, installed-asset and compiler-receipt checks. No accepted control path was written during compilation or inspection; the helper uses objdump/readelf/nm only and rechecks input ELF hashes afterward.

Fresh720 qualification and516 holdout outcomes pass independent oracle replay. The focused unit suite passes20 tests with actual command exit0, covering the hot guard, unchanged generation bound, complete ordinary fallback, counting, GC and parameter/checked-loop refusals. Existing `native_rc_collections` passes53 cases under optimized ASan/UBSan, including ordinary/hot predicate equality, widths1/2/4/8, cold metadata, queued finalizers, managed/refused values, alias/growth and generation/heap refusals. The native C implementation is unchanged. Input-manifest self-test passes. An initial test wrongly expected the default checked comprehension to receive a presized guard and failed18/19; that log remains archived, and the corrected test retains its existing refusal behavior. Zig still prints misleading failed-command text alongside final Guardian PASS even though the shell returns0.

The production commit gate passes 88 whole-tree Guardian checks; the Debug compiler build passes 88 diff-scoped checks across 67 files, with 38 whole-tree checks. These are separate scopes. Execution statuses are reviewed observations with preserved logs/source/artifact bindings, not proof merely from hashes. `validation-receipt.json` binds 43 artifacts and all helper bytes; gzip archives round-trip exactly. Guardian feedback is consolidated by the coordinator.

## Timing evidence

The CPU 2 six-arm screen ran 04:29:17–04:30:17 UTC, five measured rounds and one warmup, with 240 measured samples and 720 qualifications. Session `693cd1d6-6d63-44cb-bfa2-3b1984e73325` remains an explicitly labeled subset. The matched Debug-host 804→638 pair ran 04:30:45–04:31:05, with 160 measured outcomes plus 32 warmups. The independent targeted repeat ran 04:36:54–04:37:10, with 180 measured outcomes plus 36 warmups and session `33abd131-20be-4585-b69f-632e7aadc564`. It uses 15 rounds and three warmups for small integer sorting and nested mutation at both sizes, with unchanged plans/artifacts and UUID-seeded randomized arm order. No builds, commits or archive processing overlap guest timing; every invocation uses the normal timing lock.

After/before ratios below 1 indicate improvement. Intervals use same-round paired percentile bootstrap, without multiple-comparison correction.

| Case / size | Initial LLVM ratio [95% CI] | Repeat LLVM ratio [95% CI] | Initial QBE ratio | Repeat QBE ratio [95% CI] |
| --- | ---: | ---: | ---: | ---: |
| sort_int / small | 0.97997 [0.97086,0.98565] | 0.97896 [0.97644,0.98317] | 1.00081 | 1.00106 [0.99734,1.00822] |
| sort_int / large | 0.99381 [0.97273,0.99780] | — | 1.00457 | — |
| sort_records / small | 0.99306 [0.99003,0.99703] | — | 0.99976 | — |
| sort_records / large | 0.95377 [0.92914,0.99321] | — | 0.99817 | — |
| mutate_nested / small | 1.01162 [1.00086,1.02049] | 1.01061 [1.00732,1.01435] | 0.99760 | 0.99786 [0.99486,1.00097] |
| mutate_nested / large | 0.99572 [0.97316,1.00591] | 0.98074 [0.97022,0.98753] | 0.99597 | 1.00131 [0.99640,1.00734] |
| list_append / small | 0.99592 [0.99043,1.00791] | — | 0.99732 | — |
| list_append / large | 1.00111 [0.99621,1.00484] | — | 0.99787 | — |

Repeat absolute LLVM small-sort medians are 219.869→215.243 ns/op. Nested-small medians are 714.870→722.453 ns/op. Nested-large medians are 7077.966→6941.637 ns/op. Record/nested observations are preserved without attributing them to the presized setup mechanism. All intervals and absolute medians, including QBE, remain in the raw reports and `timing-evidence.json`.

The original five-round helper is byte-identical, SHA256 `5275342962f572987e3edf60d6cdd27df1feabe887aaa7fe84d4394d24c10e08`; the repeat has a separate helper. The validation snapshot precedes timing, and the timing receipt precedes integration approval. Their historical statuses and original raw subset/complete statuses remain unchanged. This README records the current coordinator decision. The coordinator independently replayed all 192 initial and 216 repeat outcomes, live bindings and the official six-arm verifier before adoption.

Replay without timing:

```bash
python3 experiments/runtime-goal110-presize-ready-20261004/verify-archive.py
python3 experiments/runtime-goal110-presize-ready-20261004/verify-archive.py --check-artifacts
python3 experiments/runtime-goal110-presize-ready-20261004/static-source.py
python3 experiments/runtime-goal110-presize-ready-20261004/static-binary.py
python3 experiments/runtime-goal110-presize-ready-20261004/verify-timing.py --check-artifacts
```

Live checks need the recorded paths; saved checksum/hash replay is standalone in this repository. Timing requires explicit coordinator START and the ordinary timing lock. A five-round subset screen and Debug-host pairs are diagnostics; normal goal acceptance still needs the ReleaseFast host policy, all six current arms, paired confidence bounds and independent normal sessions.
