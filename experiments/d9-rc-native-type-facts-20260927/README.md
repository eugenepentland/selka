# Native type-fact cache: isolated evidence

See [the implementation report](../../docs/audits/d9-rc-native-type-facts-2026-09-27.md)
and [the reviewed design](../../docs/audits/d9-rc-native-type-facts-design-2026-09-27.md).
The complete unchanged N10 Lox workload improves 10.32% QBE / 12.01% LLVM against
the corrected joined control, with exact counts/output. It still costs
31.23× / 51.20× the archival accepted-GC instruction medians. This is not Stage 4
performance acceptance.

Run the self-contained archive checks:

```sh
python3 experiments/d9-rc-native-type-facts-20260927/verify.py
```

Add `--live` to verify surviving original compiler, guest, input and source
identities. `archive-sha256.json` covers every archived file except itself.
The verifier checks 84 matched raw observations, 28 counted runs, 42 archival GC
observations, actual LLVM O3/full-LTO manifests, identical generated code for the
non-target controls, and 264 uncached guest assertions. It does not use wall-time
or profiler percentages as the acceptance metric.

The evidence is divided as follows:

- `identity.json`, `source.patch`, `before-builds.json.gz`, `after-builds.json.gz`
  freeze exact Debug compilers and production source/binaries. The implementation
  remains a private-layout cache; public RC ABI3 is unchanged.
- `lox-results.json` contains alternating full N10 median-three production
  observations plus separate counted runs. `binary_trees.tree.lox` and
  `expected-n10.txt` preserve exact input/output.
- `controls.json.gz` contains sieve, allocation churn, scalar append and all
  three schematic inputs, including raw samples, manifests and counted output.
  `emissions/` preserves all before/after emitted guest code.
- `accepted-gc-*` records only selected archival baseline identity/observations
  from the original accepted compiler. These GC runs are not newly interleaved
  with this candidate. The original corpus JSON may continue to receive unrelated
  RC observations; its captured file hash describes the moment read, not a claim
  that the live aggregate file is frozen. Inherited environment fields are omitted;
  only explicit `MYLANG_*` runtime overrides are retained.
- `profile-before/` is the corrected joined5b876 profile. Its raw hardware branch
  records expose direct predicate callers; they are not a reconstructed stack.
  `profile-after/` and `qbe-after-profile.json` preserve the candidate profile.
  Sampling has throttle records, no lost samples, and is qualitative only.
- `historical-6a75/` preserves earlier scalar-record binaries' profiles separately.
  The `qbe-callers` DWARF attempt did not unwind guest/runtime frames and supplies
  no caller evidence; its failed receipts remain archived.
- `suites/`, `legacy/`, their logs and `legacy-query-adapter.c` record 150 C
  ASan/UBSan/counting scenarios per implementation. The legacy comparison replaces
  the three production C files with baseline5b876 implementations and uses an
  uncached adapter for the new private test query. The common internal header has
  the proven same sizes; this adaptation is for semantic test comparison only.
  The measured old guest binaries use the actual complete old source/header.
- `validation.json.gz`, `build.log`, `focused.log` preserve the paired actual
  backend assertions, Debug19 install/Guardian88 and focused12 checks.
  `layout.json` and `scripts/layout.c` preserve ordinary/counting layout probes.
- `scripts/` retains the original local-workspace reproduction drivers. They
  expect the recorded immutable paths and on-disk scratch; they are not a portable
  benchmark package. Run builds through `scripts/build-slot.sh`; parent owns the
  integration gate and Guardian feedback.

No binaries or build caches are checked in. Compressed raw profiles remain
readable by `perf` after decompression while their original symbolized binaries
are available at the recorded paths. The old introductory source comment calling
whole bindings immutable is intentionally unchanged in the frozen measurement;
the report clarifies that descriptor/structural fields are immutable while the
serial heap-local fact byte is lazily mutable.
