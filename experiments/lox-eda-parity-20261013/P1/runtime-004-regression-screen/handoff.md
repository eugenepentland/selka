# Final runtime-004 regression and overlap screen

Validated report SHA256: `5f069e3f1532fc6151df0ccc565555b05a128ee1f0011279e3d0f396c4fbedf6`. Coordinator report-validation-004 validation/publication receipts establish artifact pin eligibility. This screen independently checks all 780 receipt-chain entries and preserves receipt hashes, all measured wall values and all final censor records in final-screen.json. Analysis ran under shared build admission ticket 3261; no benchmark, source change or root write.

No repeatable candidate regression above 5% against freshly measured mylang-before appears in the 59 complete cells. Every one of their 531 matched pairs favors the candidate. The largest paired median is tree-equality 0.930439, and the largest individual candidate/before ratio is also tree-equality 0.945728. Consequently no regression cause can be attributed from these observations. This comparison concerns the previous mylang binary, not Zig parity or isolated attribution to a particular source/compiler change.

VM string equality remains censored: before, candidate and before-same-compiler each exceeded the fresh Zig-derived 1.425576069-second warmup budget. These are three actual censored invocations inherited through later receipts, not repeated timeouts. No candidate/before equality ratio or exact median is available. Existing P1/vm-string-audit-002 identifies heavy opcode/stack/scalar-reader dispatch for this workload, rather than content hashing; that older native audit supports a plausible remaining workload cost, not a causal diagnosis of this final binary or an estimate past the censor.

Conservative possible wall-sample overlap (whole chunk intervals; individual launch timestamps unavailable):

| Cell | Paired median | Pair range | Overlapping chunks |
| --- | ---: | --- | --- |
| eda-rf-switch-8way | 0.802967 | 0.763136–0.818538 | 1–9, coordinator search |
| eda-rf-switch-eval | 0.792953 | 0.781428–0.898614 | 1–9, coordinator search |
| eda-stm32n6 | 0.818999 | 0.782275–0.891709 | 1, coordinator search |
| vm-binary_trees | 0.596037 | 0.593058–0.615587 | 1–9, archive verification |
| vm-closures | 0.868709 | 0.861719–0.873318 | 1–7, archive verification |

No measured wall chunk overlaps the recorded worker analysis or compression intervals. Broad search bounds are 09:35:01–09:36:06 UTC; archive verification bounds are conservative 09:44:45.036491–09:47:03.617796 UTC. CPU0 affinity for worker analysis does not prevent shared cache, memory or filesystem contention. Ordinary polling also occurred. Retain these limitations when quoting precise improvements, particularly rf-switch-eval and stm32n6 with wider ranges. No evidence establishes contention as the cause of those ranges: dual-flash and adf5901 also have wide non-overlapping ranges. All overlap-cell pairs remain below 1, but that does not make the host quiescent or remove uncertainty about the exact effect size. No samples were excluded or rerun.

Reproduce (ordinary shared admission; no timing): source the dev environment, then `scripts/build-slot.sh build python3 experiments/lox-eda-parity-20261013/P1/runtime-004-regression-screen/screen.py` from this P1 worktree. The provisional inventory is historical and explicitly withheld; final-screen.json is the validated analysis.
