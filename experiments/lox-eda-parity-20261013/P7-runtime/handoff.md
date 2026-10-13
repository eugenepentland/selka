# Isolated C1 runtime diagnostics

Baseline source: be33ce79b5b58c3e254e73709c9dd7eb97e5a849. No coordinator/C1 production mutations. No full compiler installation performed: these are controlled relinks of the same frozen C1 LLVM object, with identical native flags, providers and instrumentation across arms. Adoption requires a fresh full compiler install and qualification.

Independent source commits: scalar ee0509f45; pointer a84df0175; bulk e49e284bb. Normal Guardian88 passed each. Separate formatter-only commit37444d8c65a7929bfc8e7675be367d8cafae566e changes only blank lines in four exchange fixtures, with common955 fmt/check exit0.

Production changes preserve descriptor/tag/resource validation, allocation policy and production counters. Scalar aggregate work skips immediate primitive children only after aggregate memcpy. Pointer destruction requires zeroRC LIST, exact pointer stride, one reference, layout[2]==0, offset0, no guard and core_owned_child callback. Bulk copy requires immediate primitive LIST child and checked block_data_size; empty, zero-sized and boundary checks are covered. RC remains generic.

Untimed regression: probes-00140 commands/8 cells; probes-00284 commands/12 cells, both ABIs, all process statuses0. Tests cover exact scalar bits/independence, nested children/boxes, guarded/wide/offset fallback, alternate visitor, dictionaries,20k iterative recursive cleanup, static/null children, malformed tags/resources/descriptors, overflow and negative capacity. Every positive path live_count0.

|Variant|Aggregate queue work|4096 scalar-list queue work|zeroRC pointer reference reads|zeroRC recursive reference reads|
|---|---:|---:|---:|---:|
|baseline|400|4097|7|40000|
|scalar|10|4097|7|40000|
|pointer|400|4097|1|0|
|combined two|10|4097|1|0|
|bulk|400|1|7|40000|
|all|10|1|1|0|

These are instrumented work counts, not runtime performance claims. Copy allocation count remains4 in aggregate fixture. RC pointer counts remain baseline.

guest-builds-001/build-receipt.json retains exact build/link argv, every source/tool/provider/install/LLVM/input hash, output hashes and raw command status. Common LLVM compiled once with-O3; per-arm runtime-O2; links-O3, identical target/cpu flags. Baseline-relinked is the comparison control; frozen installed C1 is an additional output/symbol control. Installed C1 and all six relinks lack defined retain/release/share.

guest-qualification-002:34 EDA cases×7 arms=238 untimed commands, return0, golden tree and exact installed-C1 stdout/stderr equality, leakcheck enabled/no leak reports. All full input trees and binaries pinned before/after. First qualification attempt preserved: installed C1 legitimately emitted INFO stderr, so oracle was corrected from empty stderr to exact installed-C1 stderr; no output/status relaxation.

Combined diagnostic: timing-combined-001/comparison.json. Arms Zig-fast, baseline-relinked, scalar, pointer, bulk, all; CPU8, fresh5-sample Zig calibration,2 warmups,9 alternating rounds,3 separate RSS samples, checked3×Zig cutoff/max120s. run-timing.py takes one shared timing lease per single wall round or RSS chunk, no nested admission; retains execution.json and raw logs/receipts. Parent authorized timing after root gate admission; ticket1306 queued normally. Original four three-arm prepared plans remain historical unchanged.

Exact executable command from this worktree:

```sh
python3 experiments/lox-eda-parity-20261013/P7-runtime/run-timing.py
```

No speedup or adoption conclusion before valid timing receipts. Timings compare relinked baseline with relinked candidates; relinking differences cannot be attributed to runtime patches.

## Frozen guest hashes

- baseline: `b61d84235790ecff3044eba497aa0802d487ada43d9cdf871c49f33c078a27f2` at `/home/epentland/ai/canopy/mylang-lox-eda-runtime-prototypes-20261013/.tmp/lox-eda-parity/P7-runtime/guests/eda-baseline`
- scalar: `12fcec38a3ef1c47d502afd2d8e487eefc6874de6c844c78e9ac1f9fc8b6915d` at `/home/epentland/ai/canopy/mylang-lox-eda-runtime-prototypes-20261013/.tmp/lox-eda-parity/P7-runtime/guests/eda-scalar`
- pointer: `12be3c9de0416ee8a5906608668f3f6a8160f505f1d37f6571861dbc90a71efb` at `/home/epentland/ai/canopy/mylang-lox-eda-runtime-prototypes-20261013/.tmp/lox-eda-parity/P7-runtime/guests/eda-pointer`
- combined: `dad2e3aa43f374bada922a7fb97ed83f4011bf82349e9ccd96b988a4ae5e0954` at `/home/epentland/ai/canopy/mylang-lox-eda-runtime-prototypes-20261013/.tmp/lox-eda-parity/P7-runtime/guests/eda-combined`
- bulk: `37b8f630d38b2e9147fb8e7e5ca74eb0e2cc53b990890363714f75fb66a1fc68` at `/home/epentland/ai/canopy/mylang-lox-eda-runtime-prototypes-20261013/.tmp/lox-eda-parity/P7-runtime/guests/eda-bulk`
- all: `6b84b91e7568d1c394af394657400edc570572802eac019aaf5c915bab9a81de` at `/home/epentland/ai/canopy/mylang-lox-eda-runtime-prototypes-20261013/.tmp/lox-eda-parity/P7-runtime/guests/eda-all`

Current production module hashes:
- core_owned_copy.c: `26d8c9e775b64c8064d50fcf678fb89536ef1f40ca881bbda5943a4c17f30dc6`
- core_rt.c: `1da897c92854f2615dab2935a1f0c81f712cae15cbb5fe1c19e304a0f00a6ace`

Timing complete: see timing-combined-001/results.md and report.json. Scalar-only recommended for fresh-install/full qualification; pointer held, bulk/all rejected for current adoption. Neither selected case reaches Zig parity.

Permanent regression source/registration commit315e37c0766c3ea40789465088644932c1d7af6f adds owned_aggregate_copy_test.zig and runtime/owned_aggregate_copy_fixture.c, with one root_test import. The registered filtered test build and run both exited0/PASS1; both ABIs, NaN/scalar bits, primitive+managed arrays, primitive+managed union arms, nested owner independence, root/container initialization, zero-sized values, tag/resource/descriptor refusals. All subprocess counters and cwd are isolated in test tempdirs. Normal Guardian88 passed. Local registered runtime includes the three worker prototypes; permanent-regression-002 separately validates the exact selected scalar-only bundle. Coordinator full C2 gate remains required.

First direct Zig test lacked the core module imports; preserved regression-test.log.gz. First source commit Guardian rejected orphan/reachability/spec coverage until coordinator added registration, and one debug-print call was aliased per policy; preserved commit-permanent.log.gz. Final registered process statuses are0, without parsed-PASS-only inference.
