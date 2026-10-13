# P5 C2 gangable borrowed bindings result

Only production difference is compose.my: gangable now delegates its optional bindings dictionary to a private bool-only helper, retaining exact qualified-reference membership, original UTF-8 conversion and supply fallback. C2 source-002 was copied privately and never edited. Retained state/request/bank/document storage contracts remain unchanged.

Full matched C2 RDS3-flat output is exact: stdout, guest diagnostics/report ordering, and all 6 files. Actual savings are 37,926 allocations and 2,811,312 bytes, 126 dictionary copies/403,200 bytes, 25,200 buffer copies/264,348 bytes, 12,600 text copies/248,472 bytes. Baseline gangable owns all those copies; candidate gangable and helper allocate/copy zero. Peak is unchanged 56,973,832. Both variants have zero exit-live bytes and zero RC/shared-RC/unique-test operations. Calls increase by 126. No timing/RSS/parity claim.

Both variants passed 328 canonical application tests plus exactly 3 private-module contracts, all executed verify-facts with zero cached/failures. The canonical snapshots exclude the private fixture. Explicit fixtures append tests to exact production-prefix bytes without widening the public API. Baseline alone appends an owned-snapshot oracle adapter. Prefixes and appendices have independent hashes. qualification.json/full-v2-input-manifests.json/explicit-fixture-manifests.json pin the complete inputs, flags and inventory.

Preserved preparation evidence: a generic-str oracle was corrected to exact strs.text before native admission, cancelling only its own queued wrapper; a standalone private-helper import was rejected; initial full directory runs used default budgets and hit identical step/frame limits, and imported fixtures caused duplicate discovery. Final full suites use the same approved coordinator quotas: 4 jobs, 1B steps, 40k frames, 2G memory, 120s timeout. No resource/spec/native.py changes or hidden inventory exclusions.

Ranking remains allocation-based, not CPU attribution: gangable is first; split_runs and collect_field are next read-only snapshots; plan_cluster has mixed ownership and retained bank copies stay intact. Scalar pair arrays in rotate_lib/axis_span are smaller candidates for later geometry-oracle qualification. C1 CPU native call chains did not reconstruct, so those helper costs are not assigned to callers.

Uninstrumented C2 control/candidate use separate caches/output and compiler 9bed. Their emitted LLVM contains zero myl_count symbols. held-timing-plan.json prepares RDS3-flat plus hierarchical RDS3 with pinned Zig calibration 3× cutoff, 2 warmups and 9 alternating paired rounds, exact qualified output hashes and input manifests. Timing remains held for explicit coordinator release after the current sweep/report/pins; no timing admission requested.

Source and evidence commits are separate. Source003 integration is accepted by the coordinator for the demonstrated allocation improvement; final five-mode/compiler/corpus qualification remains pending.

Source-only commit: `6ebbe76e46dcd52bbcc88ff3e93489e368beed9b` (normal Guardian 88 checks). Evidence is committed separately.
