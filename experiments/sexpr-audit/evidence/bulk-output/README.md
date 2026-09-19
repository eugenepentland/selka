# Bulk text output: matched A/B evidence

Landing commit: `76c7e58f`. Audit: [runtime-to-2x-2026-09-19.md](../../../../docs/audits/runtime-to-2x-2026-09-19.md) §1.

`measure.py` builds no binaries: it takes two already-built executables and
compares them inside one batch. Both sides are the census port
(`experiments/sexpr-port/main.my`) compiled with the same driver; `A` is the
compiler before the landing and `B` after, so the only difference is the runtime
archive the linker selected.

```
python3 measure.py --a /tmp/rt2x/base --b /tmp/rt2x/new --rounds 9
```

| workload | instructions A → B | cycles A → B | wall median A → B |
|---|---:|---:|---:|
| census 927 KB | 119,482,620 → 119,479,709 (**−0.00%**) | 30,931,079 → 30,938,677 (+0.02%) | 25.06 → 25.47 ms (+1.63%) |
| render 927 KB | 195,859,883 → 179,802,692 (**−8.20%**) | 50,459,735 → 48,391,588 (**−4.10%**) | 32.63 → 31.76 ms (−2.68%) |
| census 7.42 MB | 1,022,523,707 → 1,022,528,516 (**+0.00%**) | 311,794,668 → 311,285,118 (−0.16%) | 113.03 → 112.39 ms (−0.56%) |
| render 7.42 MB | 1,633,901,919 → 1,546,564,432 (**−7.86%**) | 487,121,907 → 469,499,954 (**−3.62%**) | 174.93 → 168.54 ms (−3.65%) |

The census workloads are the control: the landing cannot change their byte
output (`summarise` prints one short line) and their instruction counts move by
0.00%, which is the resolution of this protocol. The wall column is noisier than
the counter columns — the machine had other active processes — so wall is
reported as a median of 9 interleaved samples and is only consistent with the
counters, not a separate claim. `result.json` holds both sides' medians, minima
and every sample, plus the sha256 of each binary, input and captured output.

Correctness checks run outside this script:

* stdout is compared byte for byte for every pair on every round (the script
  aborts otherwise); `result.json` records the output digest per workload.
* all 17 rendering goldens pass for both binaries
  (`experiments/sexpr-port/golden/manifest.tsv`).
* census and render output are byte-identical with and without `--gc-stress`.
* the landed change carries `QBE-BULK-TEXT-1` in `SPEC.md` and the native test
  `io_print_test.zig`, and the full gate (`zig build test`, `test-qbe`,
  `test-qbe-build`, `fmt-check`) passed 58/58, 36/36, 22/22 and clean before the
  commit.
