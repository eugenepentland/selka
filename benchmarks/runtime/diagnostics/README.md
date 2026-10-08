These diagnostics supplement the immutable 40-case acceptance suite. Their
changed workloads and source comparisons have separate schemas, exact source
and binary hashes, and no parity, CPU-coverage or additive-cost claims.

`pair_sources.py` reruns unchanged cases with current main, a candidate and
optional additional compiled sources, plus the exact original winner. Every
guest uses one global timing lock and CPU 2. Each source supplies a checked
compiler receipt and all 24 ordinary binaries; a focused input report may
supply an originally unmeasured case from those same binaries. The output
records which plans were previously measured. Additional manifests are
explicitly unmeasured and first receive all 240 MyLang edge probes. Both sizes
use 15 randomized rounds, three warmups, fresh qualification and memory probes.
Ratio-of-medians intervals resample the same round indexes, never old sessions.

```bash
python3 benchmarks/runtime/diagnostics/pair_sources.py \
  --main benchmarks/runtime/candidates/current-main-1fd1d566-20261003.json \
  --candidate benchmarks/runtime/candidates/milestone-d348026f-debug-20261003.json \
  --extra-manifest after=.mylang-cache/runtime-candidate-b3ff3bfb/runner/manifest.json \
  --cases call_direct option_handle result_propagate record_construct integer_math float_math \
  --output benchmarks/runtime/candidates/main-d348-b3ff-controlled-20261003.json
```

`prepare.py` transforms hash-checked copies of frozen ports across MyLang,
Rust, Go and Zig. Every generated source and dependency is hashed; reviewable
diffs accompany the four source languages. Original ports are never written.
The five probes use these controls:

| Probe | Control | Meaning and limitation |
|---|---|---|
| dispatch_outside | Original integer_math | Select its arithmetic operation before timing; remove inner dispatch |
| arithmetic_only | dispatch_outside | Replace collection values with scalar indices; the value distribution also changes |
| collection_only | Original list_scan | Sum collection values without phase/modulo arithmetic |
| text_without_score | Original int_format | Consume ASCII output length; remove the entire byte fold and MyLang encode |
| escaped_allocation | Original alloc_short | Return owned nested lists across construction helper, retain until consumption; physical allocation still needs assembly/counter evidence |

`run.py` builds 30 guests with recorded toolchains and private caches. It pairs
the six probe arms with six control arms, using unchanged common calibration,
15 randomized rounds and three warmups by default. All 180 diagnostic edge
probes check independently computed checksums. Source, dependency, compiler,
installed assets, controls and probe binary hashes are checked before and after.
Lower-round runs are explicitly diagnostic and do not qualify an acceptance
milestone. Timings do not decompose the original workload into additive parts:
optimization, values and live memory may change together.

```bash
python3 benchmarks/runtime/diagnostics/run.py \
  .mylang-cache/runtime-candidate-d348026f/runner/manifest.json \
  --work .mylang-cache/runtime-candidate-d348026f/components \
  --output benchmarks/runtime/candidates/d348026f-components-20261003.json
python3 benchmarks/runtime/diagnostics/verify.py \
  benchmarks/runtime/candidates/d348026f-components-20261003.json
python3 -m unittest discover -s benchmarks/runtime/diagnostics -p 'test_diagnostics.py'
```

`verify.py` independently replays coverage, checksums, medians and bootstrap
intervals without executing guests. It rejects missing or duplicated cells,
unknown arms, incorrect checksums and altered statistics. It does not attest
that receipts were produced by an independent authority or replace live hash
checks in the capture tools. Exact gzip evidence can be decompressed before
replay; raw perf archives preserve their original reports and source paths.

`holdouts.py` checks all six frozen arms on 86 additional input plans: two
unseen seeds and nearby non-power-of-two sizes for every case, plus four-times
larger scan, map and retained/nested allocation sets. All 516 checks retain
oracle results, commands and executable/source hashes. The ordinary clock
protocol is validated and every elapsed value discarded. These runs support
correctness and robustness only; they do not alter acceptance calibrations.
The fixed generators keep their original Unicode/error/alias topology. Empty
inputs and changed semantic shapes must cite separately identified tests in
the final evidence notes.

```bash
python3 benchmarks/runtime/diagnostics/holdouts.py \
  --manifest .mylang-cache/runtime-final/runner/manifest.json \
  --output benchmarks/runtime/candidates/final-holdouts-20261003.json
python3 benchmarks/runtime/diagnostics/holdouts.py \
  --verify benchmarks/runtime/candidates/final-holdouts-20261003.json
```

`eligible.py` isolates P7 using the exact d348 before compiler and an explicitly
pinned reviewed P7 descendant, with matching host compiler modes. It compiles
the committed Host-only entry and C shim once, then builds LLVM O3/LTO and QBE
with identical source/object/options. Environment integers are read before the
kernel timer; retained argv/list inputs are absent. The source hashes are fixed
to the actually built witness. Six iteration boundaries and three seeds give
72 oracle checks; four guests use 15 randomized rounds and three warmups at
one million iterations/seed17 by default. The closed-form oracle and paired
statistics have independent replay in `verify.py`. This eligibility measurement
does not replace original alloc_short or another acceptance row.

`backend_receipts.py` reads each emitted MyLang guest manifest and hashes its
native runtime archive. It rejects effective backend or LLVM O3/LTO mismatches.
This matters because this compiler's `--qbe` option sets QBE selection: it must
precede `--backend llvm`, or a later `--llvm-opt` is invalid. Successful P7 builds
and the final ordinary guest set retain explicit effective-backend receipts.
