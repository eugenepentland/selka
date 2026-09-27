# Combined dictionary, native type facts and variant-read diagnostic

The combined source `e5d47d20f7978e788e9e4a7ad158c80d703db041` finishes all five unchanged target/control programs on both actual backends with correct output. Every measured row still exceeds the 1.3 instruction cap. This is an instruction-only diagnostic, not whole-corpus Stage 4 acceptance; no peak-RSS claim follows from it.

| Program | QBE instructions / GC | LLVM instructions / GC |
| --- | ---: | ---: |
| parity/micro/dict_count | 6.598428 | 7.383473 |
| schematic/fixture | 17.576954 | 26.355741 |
| schematic/changed-net | 17.534070 | 26.226652 |
| schematic/changed-value | 17.510567 | 26.764758 |
| lox/vm/binary_trees | 27.911220 | 44.806239 |

This source combines dictionary tail `3c4251e8`, native type facts `c71d4046` plus report correction `242439ec`, and adjacent variant-read `4f60ff94`. It includes no later dictionary-key or scalar-readiness prototype. Initial main-gate validation exposed one missing test-input declaration; the other three gates and both forced RC sweeps passed. The only correction in `c90c84be` adds that declaration, and its fresh Debug compiler is byte-identical to this measured compiler. The separate gate report records the final rerun verdict.

There are six production guest builds, four counted builds, ten comparison rows and 60 instruction observations, all reporting 100% running. GC and RC alternate within three repetitions; exact output is checked separately. Workload sizes, input hashes and the accepted GC baseline are unchanged. In Lox binary trees N10, RC median instructions are 202,167,264,650 QBE and 153,826,821,464 LLVM. The corresponding median wall durations of the entire measurement wrapper are 18.813 and 13.583 seconds. These durations include taskset/perf startup and depend on CPU2 and concurrent host load; they are not isolated guest timings and should not be directly compared to another core’s component measurements.

Both backends produce identical balanced counted results. Dictionary: O acquisitions 2,002,001, H acquisitions 4,002,001, heap allocations/retirements 2,029, uniqueness checks 2,001,000, clones zero. Lox: O acquisitions 81,463,495, H acquisitions 264,505,085, heap allocations/retirements 4,350,608, uniqueness checks 20,836,904 and clones 1,095,889. For each, H releases equal acquisitions and O releases equal O acquisitions plus heap allocations; arena allocations, limit trips and saturation are zero.

The immutable Debug compiler SHA256 is `1f3bca2c62180a58fcc54782f9414a2b272e8447f996096a6883dc330774e3c7`. The accepted GC compiler remains `8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`. Guest builds use ReleaseFast; archived manifests verify actual QBE/LLVM selection and LLVM O3/full LTO. Measurements use reserved CPU2.

The archive preserves exact compressed result and baseline bytes, raw measurement output, build manifests with guest hashes, the unchanged driver, and an independent verifier. Archive construction rechecked every used compiler and guest binary hash against the run records. The verifier reparses raw counters, recomputes medians, checks the selected corpus and validates build manifests. Only explicit MYLANG environment overrides are retained. No guest or baseline was changed to obtain a pass.

Run `python3 experiments/d9-rc-ownership-joined-20260927/verify.py` from the repository root.
