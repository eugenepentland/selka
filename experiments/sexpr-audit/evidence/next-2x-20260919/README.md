# Remaining runtime gap: 19 September 2026

Findings and priorities: [runtime-to-2x audit](../../../../docs/audits/runtime-to-2x-2026-09-19.md).

## Recorded evidence

* `measurement.json`: all 21 interleaved wall samples, output digests, input and
  frozen executable hashes. Compilation excluded; CPU 6; one warm-up. Captured
  stdout checked every time. Token counts normalize mylang's additional EOF.
* `counters.json`: seven interleaved user-mode counter samples per candidate,
  including semantic-breaking `no_text_upper_bound`, with medians.
* `census-profile.txt`, `render-profile.txt`: 150 invocations, `perf record
  -F 4000 -e cycles:u`, names mapped through the build manifest. Approximately
  6K/10K samples. About 5% of samples have unresolved `[k]` attribution; do not
  assign those to a runtime mechanism. Percentages are approximate self time.
* `bulk-print.json`: separate same-batch comparison of ordinary build, unmodified
  emitted-IR build, and bulk-output prototype; 21 wall/seven counter samples.
* `validation.json`: original/scalar-string golden counts, eight differential
  diagnostic/Unicode/escape cases, and single-observation census peak RSS.
* `reproduction/`: a successful complete rerun of the saved reproduction script,
  including all timing/counter samples and source hashes. It reproduced the
  instruction reductions, 3.8% bulk-output wall reduction, and 17/17 goldens
  for the baseline, scalar-string, and bulk-output variants. Absolute timings
  differed with machine conditions; both batches are retained.
* `provenance.json`: revision, CPU/toolchain, source hashes, caveats, and measured
  representation sizes. Dirty checkout and installed compiler are explicitly
  distinguished. The compiler includes fused slice/decode, verified in assembly.

Original scratch directory: `.tmp/runtime-audit-20260919`. Frozen compiler SHA256:
`2b69b90799103b2d482dd9c018a8965a9a56502f3674eb5e80701b47c422f2c2`.
The results belong to this binary, not an assumed clean reconstruction of HEAD.
Raw perf data, emitted manifests, frozen sources, and compiled probes remain in
that ignored scratch directory; portable summaries are retained alongside this
README.

`scalar_string.patch` is a source probe, not a compiler implementation.
`no_text.patch` **changes program meaning**: it discards atom/string contents.
Its census happens to match because census does not read those contents. It
cannot pass rendering goldens and must never be counted as an achieved speedup.
`bulk_print.c` is a bounded output prototype, linked by replacing the text
renderer reference in a copy of the emitted metadata. It is not installed into
the production runtime.

## Reproduce against a current compiler

Requires Linux `perf` access, CPU 6, Python, `patch`, the pinned Zig toolchain,
and the installed mylang/QBE binaries. The Zig reference must be built from
`experiments/sexpr-port/zig-bench` in ReleaseFast. Some golden inputs reside in
the sibling EDA checkout.

From the repository root, choose a scratch directory that does not exist:

```sh
python3 experiments/sexpr-audit/evidence/next-2x-20260919/reproduce.py \
  --input /tmp/sexpr-bench/input.sexp \
  --zig-reference /tmp/zb-ReleaseFast-out/bin/zig-bench \
  --work .tmp/runtime-to-2x-repro
```

This copies the compiler, QBE, reference, and guest sources before building;
applies prototypes only to the copies; checks output equality; and writes new
results in the chosen scratch directory. Existing evidence is not overwritten.
It does not rebuild the compiler or exercise Guardian. For the original binary,
pass `--compiler .tmp/runtime-audit-20260919/bin/mylang` and the matching `--qbe`.
New source/ABI changes may require adapting the patches or C prototype; recorded
source and binary hashes let you identify such changes.

To repeat only existing prepared binaries:

```sh
python3 experiments/sexpr-audit/evidence/next-2x-20260919/measure.py .tmp/runtime-audit-20260919
python3 experiments/sexpr-audit/evidence/next-2x-20260919/profile.py .tmp/runtime-audit-20260919
python3 experiments/sexpr-audit/evidence/next-2x-20260919/bulk_measure.py .tmp/runtime-audit-20260919
```

These commands update results only in that scratch directory. They intentionally
serialize benchmarks; do not run them concurrently. All changes are compared
within a batch because other machine activity and frequency affect absolute time.
