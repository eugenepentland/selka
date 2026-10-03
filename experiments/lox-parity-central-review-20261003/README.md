Independent review of root Lox measurement/provenance, 2026-10-03.

The completed receipts pass exact coverage, identity, output and pairing
checks. This review performed no benchmark runs or root writes. The final
wall checkpoint was incomplete at the first inspection; the single natural
end-of-review check found a completed receipt and outer source/log checks,
so only that completed version is accepted below.

| Receipt | Cases × arms × rounds | Observations |
| --- | ---: | ---: |
| Baseline smoke | 26 × 4 × 1 | 104 |
| Baseline counters | 26 × 4 × 3 | 312 |
| Baseline wall | 26 × 4 × 3 | 312 |
| Initial source smoke | 26 × 14 × 1 | 364 |
| Initial source counters | 5 × 7 × 2 | 70 |
| Tree wall screening | 13 × 6 × 2 | 156 |
| Direct tree wall screening | 13 × 4 × 2 | 104 |
| Positive compiler smoke | 26 × 8 × 1 | 208 |
| Positive compiler counters | 26 × 8 × 1 | 208 |
| Carrier baseline counters | 13 × 4 × 1 | 52 |
| Sweep smoke | 26 × 4 × 1 | 104 |
| Sweep counters | 26 × 4 × 2 | 208 |
| Final matched wall checkpoint | 26 × 6 × 3 | 468 |
| Final matched counter checkpoint | 26 × 6 × 3 | 468 |

The first twelve receipts contain 2,202 observations. Every declared
case/arm/round tuple exists exactly once. All stdout hashes equal the pinned
expected outputs; exits and diagnostics are correct, and smoke collector
statistics match across arms. Executable, generated input and current source
hashes match their saved manifests. The complete review includes 3,138 observations. All 1,318 completed counter
observations contain four metrics; all 5,272 recorded PMU running percentages
equal 100.0. Both final checkpoints pass the outer run.py source/log checks.

All 127 reference source/input/expected-output hashes match both the manifest
and the Git tree at `4e48a09220c2e018eba8c4b1eb3fe1137a3dae73`. The reference
directory is extracted source, so `git rev-parse` from it would refer to the
surrounding integration checkout; the review instead compared Git object
contents directly. The canonical overlay hash remains
`233332c7b4fd1325f3ec1251406b0b433e87520f5abc4db9cfcc70e79813445b`;
all 37 final files equal the canonical replay. Joined-flat and final-sweep
LLVM/QBE guests are byte-identical under the positive-only and combined
compiler builds represented by their saved build receipts.

All 38 saved comparison reports independently recompute from same-case,
same-round ratios, per-case medians, then an engine geometric mean. All 1,829 raw
arm/case summary medians, spreads, counts and IPC also recompute correctly.

| Completed wall ratio | VM | Tree |
| --- | ---: | ---: |
| Baseline LLVM / Rust | 2.973742 | 8.233485 |
| Baseline LLVM / Go | 3.020034 | 8.156662 |
| Final LLVM / preceding LLVM | 0.942336 | 0.517605 |
| Final LLVM / Rust | 2.779057 | 4.237094 |
| Final LLVM / Go | 2.811139 | 4.131576 |
| Final QBE / preceding QBE | 0.927490 | 0.604278 |

| Completed instruction ratio | VM | Tree |
| --- | ---: | ---: |
| Final LLVM / preceding LLVM | 0.965176 | 0.643184 |
| Final QBE / preceding QBE | 0.930205 | 0.606887 |

These support the preceding roughly 3× VM / 8× tree LLVM baseline and a
measured checkpoint improvement; they do not support Rust/Go parity.

`run.py` refuses output overwrite, strips runtime-option/preload environment,
and verifies `.my` source hashes and manifest identity before/after the run.
The audit runner interleaves shuffled arms, pins the designated CPU, checks
expected outputs and verifies binary/input hashes at completion. Quiet checks
cover the CPU and its sibling before each group. Their saved waits satisfy
the stated less-than-25% busy admission rule.

The generic paired helper alone can silently replace duplicate tuples and
cannot notice whole missing rounds. The checkpoint analyzer separately
rejects incomplete/duplicate coverage and requires all cases/arms and at
least three rounds. This independent review applies those full checks to
every receipt. The checkpoint analyzer checks instruction PMU percentages;
the independent review checks all four percentages on every completed
counter observation.

Initial baseline/source-screen receipts lack uniform `run.py` source
before/after records. Their audit-runner identity checks and present source
hashes pass. `run.py` checks `.my` files rather than all metadata; final
37-file identity is independently verified here. One/two-round and five-case
screens are diagnostic and do not replace the matched reference checkpoint.

Root has separately identified a `try_result` interior-edge omission in the
positive-index certificate and is fixing/rebuilding it. This artifact
reviews the immutable measured guests and their existing provenance; it
does not approve broad compiler integration or assume the future rebuilt
compiler has identical output.

Full final hashes, coverage details and independent ratios are in
`review.json`; the final checker and output are `review.py` and
`review.log`. The initial `initial-review.json` receipt is preserved unchanged
and linked by its SHA in the final receipt. The corrected attribution in
this note supersedes the initial receipt’s transfer-proof attribution.

Reproduce this read-only check against the saved root receipts with
`taskset -c 14 python3 experiments/lox-parity-central-review-20261003/review.py`.
It performs no builds, tests, benchmark runs or root writes. Guardian was
not exercised by this review.
