# Final C4 evidence synthesis

**Parity remains unmet:** 59/60 runtime pairs completed; only `tree-invocation` passes (1/60). VM string equality exceeded the calibrated deadline; no ratio or RSS is inferred for that case. All60case rows/statuses remain in extracted-004/cases.csv and synthesis.json.

| Group | Completed/total | Runtime / previous | Runtime / ZigFast | RSS / previous | RSS / ZigFast |
|---|---:|---:|---:|---:|---:|
| EDA | 34/34 |0.808276|1.336319|0.995558|0.444286|
| Tree |13/13|0.732932|1.174890|0.929186|2.225083|
| VM |12/13|0.762021|1.806440|0.978746|3.025351|

Ratios are geometric means of completed matched per-arm medians. Application-source/runtime compiler factors remain separately available: EDA0.830085/0.973727, tree0.767237/0.955287, VM0.754712/1.009684. Managed allocation/cumulative-byte/peak-live ratios versus previous are EDA0.567272/0.691548/0.982099; tree0.407403/0.332157/0.919277; VM0.370522/0.374869/0.975551. RSS is process maximum, distinct from managed peak. Traffic, zeros, unmatched cases and allocator movement remain explicit in the JSON.

118completed counted invocations independently checked: runtime/shared/compiler RC, unique-tests, sharemarks and exit-live allzero; direct destruction remains distinct. P1 review retains all531matched candidate/previous pairs (all favor candidate). Five conservative whole-chunk overlap caveats remain: eda-rf-switch-8way, eda-rf-switch-eval, eda-stm32n6, vm-binary_trees and vm-closures. No samples dropped/rerun; CPU affinity does not exclude shared-cache/memory/I/O effects. Exact measurement context and P1screen snapshot are preserved.

Six compilation receipts cover three alternating pairs per application, with cold and warm observations for three arms in each pair (36 observations total). Cold median seconds before/same-compiler-old-source/after: Lox2.880/2.887/2.953; EDA12.218/12.225/12.131. Paired after/before ratios1.023810/0.994906; after/same-compiler-old-source1.021570/0.991652. Cold GNU RSS KiB117232/120036/120168(Lox),498740/500272/497088(EDA). Warm replay is roughly10–22ms and noisy; allraw observations retained. Guest caches were fresh then replayed; OS/shared-tool caches were not flushed. GNU maximum RSS covers command/waited children, **not summed concurrent process-tree or cgroup peak**. Compile observations are separate from application runtime.

Exact reportSHA256`5f069e3f1532fc6151df0ccc565555b05a128ee1f0011279e3d0f396c4fbedf6` checked before/end. Extraction used shared build2 ticket3262; RC/compile/P1 derivation used build1 ticket3265. Existing pinned root summarize.render and C1 managed-summary methodology reused. Allrequested source/common/native/ABI/gate/freeze/validation/publication/context manifests plus six compilation receipts pinned and exact snapshots preserved. Report publication was byte-identical; prior failed summary-path attempt remains in coordinator evidence. No root writes, native guests or new timing by this synthesis.

Coordinator archive verification metadata preserved:4,002files, SHA256`37880c8af762b3470f810cdd927bc1ebe37567d1fdc80c0a531d33251b624ce6`. Archive not rehashed/recompressed here. Separate finalmicro report/20MiB rawarchive is in ../P7-micro-final-004; its own samples finished before the documented unadmitted CPU0analysis/compression, which may overlap the five application cells above.

Detailed artifacts: extracted-004/{synthesis.json,derived-summary.json,cases.csv,receipt.json,initial-manifest-snapshots.json,regression-screen-snapshot.json,archive-verification-snapshot.json}. Exact extraction argv/admission in extraction-admission.json. Final evidence committed via normal shared gate/Guardian, no feedback/push. No further performance work planned.
