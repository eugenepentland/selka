# Shared runtime diagnostic results

All20 chunks exited0;198 raw guest invocations. Each arm completed9 alternating wall rounds and3 separate RSS samples per case; no censors or output errors. CPU8, fresh5-sample Zig calibration,2 warmups and3×Zig cutoff capped120s. Exact prior receipt hashes, pinned inputs and raw progression are retained.

|Case|Arm|Median wall ms|Wall/baseline|Paired median/baseline|Median RSS KiB|Max RSS KiB|
|---|---|---:|---:|---:|---:|---:|
|eda-adf5901|zig-fast|12.325|0.7763|0.7901|20768|20768|
|eda-adf5901|baseline-relinked|15.877|1.0000|1.0000|10268|10268|
|eda-adf5901|scalar|15.240|0.9599|0.9577|10264|10268|
|eda-adf5901|pointer|15.374|0.9683|0.9735|10204|10204|
|eda-adf5901|bulk|15.496|0.9760|0.9785|10264|10268|
|eda-adf5901|all|15.548|0.9793|0.9799|10268|10268|
|eda-Cyclops-Flex|zig-fast|11.290|0.8724|0.8743|19008|19008|
|eda-Cyclops-Flex|baseline-relinked|12.941|1.0000|1.0000|9588|9588|
|eda-Cyclops-Flex|scalar|12.630|0.9759|0.9722|9580|9584|
|eda-Cyclops-Flex|pointer|12.853|0.9932|0.9920|9580|9580|
|eda-Cyclops-Flex|bulk|12.998|1.0044|1.0148|9584|9588|
|eda-Cyclops-Flex|all|12.731|0.9837|0.9943|9580|9584|

Recommendation: advance scalar-only ee0509f45 to a fresh compiler installation and full qualification. Scalar was faster than baseline in8/9 adf5901 pairs and7/9 Cyclops pairs, with median wall improvements4.0% and2.4%. Hold pointer: its Cyclops gain is small/mixed5/9 faster pairs. Reject bulk/all for current adoption: bulk is slower on Cyclops (only3/9 faster pairs); combined all is slower than scalar-only on both cases. All receipts remain preserved for future investigation.

These12–16ms guests and two cases give limited evidence, not full-corpus parity. Scalar remains1.237×Zig on adf5901 and1.119×Zig on Cyclops; neither meets per-case parity. RSS differences are small (≤64KiB against baseline) and no material RSS improvement is claimed. Work counts, exit-live checks and RC controls come from separate untimed probes, not wall/RSS runs. Runtime conclusions compare the identical-LLVM relinked baseline and relinked candidates; installed C1 is a qualification control.
