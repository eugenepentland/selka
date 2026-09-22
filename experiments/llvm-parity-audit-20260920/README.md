# LLVM/Zig parity audit evidence

Read the [audit](../../docs/audits/llvm-zig-parity-2026-09-20.md).
This directory contains diagnostic scripts and retained results; production code
was not changed. Probes inherit the chart's **unchecked, noncollecting,
header-retaining arena** contract. Never link the root-clean lowering to a
collecting runtime.

- `chart-recheck.json`: exact retained chart O3 and Zig binaries, fresh 21-round
  wall comparison and separate counter batches, both input sizes and modes.
- `build_probes.py`, `width_probe.c`, `probe-builds.json`: control rebuild,
  internal linkage, three width-helper substitutes, and their combination.
- `ablation.json`: matched 21-round comparison of those variants, original chart
  binary, and Zig. Raw samples preserve round order; confidence intervals
  resample matched rounds.
- `build_root_probe.py`, `root-probe-builds.json`: byte-identical regeneration
  of chart IR; remove proven private GC root-record stores; combine that with
  width helpers; separately annotate the pure heap getter's effects. This imports
  the current translator, proves regenerated IR matches the retained input, and
  leaves production code unchanged. `root-width-build.json` retains the first
  combined build receipt; the script now reproduces that variant itself.
- `root-ablation.json`, `summary.json`: final matched timing/counters and derived
  ratios to Zig. Do not combine absolute times from different batches.
- `qualification.json`, `root-qualification.json`, `heap-qualification.json`:
  73 valid inputs, both modes, across each group. The 17 retained render goldens
  are also checked. `extra-qualification.json` adds signed integer boundaries,
  empty text, and Unicode around width limits; inputs are embedded in that JSON.
- `view-noalloc.json`: expected `E_EFFECT_BOUND` from an installed-compiler probe
  of `.view(...).scalar_count()`, including source and compiler hash.
- `profile.py`, `*-profile.txt`: 40-process sampled self-cycle profiles, with
  guest hash symbols renamed from the frozen manifest. Raw perf files remain
  under `.tmp/llvm-parity-audit-20260920/`. Some samples are unattributed and
  Python/libc activity is included; profiles are hotspot evidence, not wall-time
  decompositions. A larger percentage after cleanup does not imply a regression.
- `*.asm`, `assembly-summary.json`, `root-code-size.json`: selected optimized
  machine code, static call sites, and the printer size/frame comparison.
- `provenance.json`: inspected source hashes, revision, tool/CPU identity and
  preexisting workspace changes. Runtime and guest inputs remain frozen from
  the chart; current source inspection is labeled separately in the report.

Run from the repository root, while the frozen `.tmp/bench/armsset` inputs and
formatter objects named in the original receipt remain available:

```sh
python3 experiments/llvm-parity-audit-20260920/build_probes.py \
  --builds .tmp/bench/armsset/maxperf/builds.json \
  --manifest .tmp/bench/armsset/manifest.json \
  --work .tmp/llvm-parity-audit-20260920/probes \
  --receipt experiments/llvm-parity-audit-20260920/probe-builds.json
python3 experiments/llvm-parity-audit-20260920/build_root_probe.py

python3 experiments/llvm-backend/measure.py \
  --work .tmp/llvm-parity-audit-20260920/root-measure \
  --input .tmp/runtime-audit-20260919 --rounds 21 --warmups 3 --cpu 6 --sink null \
  --arms regenerated,root-clean,root-width,heap-effects,zig \
  --binary regenerated=.tmp/llvm-parity-audit-20260920/probes/regenerated.bin \
  --binary root-clean=.tmp/llvm-parity-audit-20260920/probes/root-clean.bin \
  --binary root-width=.tmp/llvm-parity-audit-20260920/probes/root-width.bin \
  --binary heap-effects=.tmp/llvm-parity-audit-20260920/probes/heap-effects.bin \
  --binary zig=.tmp/llvm-streaming-20260919/before/zig \
  --reference regenerated \
  --json experiments/llvm-parity-audit-20260920/root-ablation.json

python3 experiments/llvm-backend/maxperf/qualify.py \
  --reference .tmp/bench/armsset/maxperf/whole-o3.bin \
  --binary root-clean=.tmp/llvm-parity-audit-20260920/probes/root-clean.bin \
  --binary root-width=.tmp/llvm-parity-audit-20260920/probes/root-width.bin \
  --input .tmp/runtime-audit-20260919 \
  --work .tmp/llvm-parity-audit-20260920/qualification \
  --json .tmp/llvm-parity-audit-20260920/requalification.json
```

These are local retained artifacts, not a portable clean-checkout build recipe.
Rebuilding the guest closure from newer compiler/source inputs is a new
experiment. The new scripts run direct native compilation, guest binaries, and
read-only compiler checks; no project `zig build` or Guardian gate ran.
