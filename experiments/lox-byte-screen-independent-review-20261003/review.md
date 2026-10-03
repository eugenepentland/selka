# Independent byte-source measurement review

The completed byte-storage screen reconciles without an actionable defect. All
eight published comparison families reproduce using independent arithmetic in
`review.py`; the root analyzer was neither imported nor executed. These results
support leaving the byte source and AST/byte composition unselected.

| Candidate relative to source84 | LLVM VM | QBE VM | LLVM tree | QBE tree |
| --- | ---: | ---: | ---: | ---: |
| Instructions, one round | +1.240189% | -0.257449% | +0.000003% | +0.039104% |
| Wall time, three paired rounds | +0.621119% | -0.234464% | -0.478848% | +0.577288% |
| Median paired wall spread | 1.402045% | 1.098347% | 1.401197% | 0.696924% |
| Cases with lower median wall time | 5/13 | 9/13 | 11/13 | 2/13 |

Positive changes mean more work or time. The wall ratios against Rust and Go
also reproduce: LLVM VM 2.716216/2.715715, LLVM tree 4.242938/4.105162;
QBE VM 5.354569/5.364924, QBE tree 7.714471/7.472258. Parity remains unmet.
Each case's three within-round ratios, median, spread and regression name are
retained in `review.json`. Engine ratios are the geometric means of the thirteen
case medians. Spreads are `(max - min) / median * 100`, descriptive variability
rather than confidence intervals. Tree binary-trees spreads reach 16.754% LLVM
and 23.580% QBE; the small engine movements establish no convincing benefit.

The original matrix contains exactly 728 unique phase/case/arm/round cells:
156 smoke (13 scripts × two engines × six arms), 104 diagnostic counters
(four mylang arms, one round), and 468 wall observations (six arms, three
rounds). Every status is zero and every recorded stdout hash matches its frozen
expected output. Counter/wall stderr is empty. All smoke stderr is parsed as
the exact engine/statistics line, matches its collector object, and matches
across all six arms per case. All 416 running percentages for instructions,
cycles, branches and branch misses are exactly 100. Counter workloads use
tree sizes for both engines; wall workloads use engine-specific sizes.

The reviewed manifest pins unchanged d14a7040/99ad919d, six actual ELFs, both
37-file source maps and the reference inputs/helpers. Both rebuilt candidate
ELFs are byte-identical to the qualified author v3 ELFs. All 152 guarded
paths match before and after this read-only review, along with every materialized
case input and every checkpoint payload. Both source maps contain the older
`60009d57` interpreter, so this measurement does not include the selected AST
handler or the independently qualified composition. Baseline manifests and
runtime archives retain their original absolute paths; baseline copied
`.qbe-receipt` files are absent. The four manifests, four runtime archives and
two candidate receipts are covered by the guard set.

The complete checkpoint, wall worker closeout and README agree on scope and
selection. The historical diagnostic checkpoint is byte-identical to commit
`12a401b1`; its old README hash resolves to that commit's README. It predates
wall completion and adds no observations. The separate author qualification
records 352 accounted public executions, 1396 native program pairs, eight RC
refusals and 80 omissions. Those are not extra measurement cells or a full
compiler performance gate.

This review checks recorded stdout hashes against expected bytes; the central
measurement archive does not store full stdout. Its recorded stderr/statistics
are complete. No guests, tests, compiler builds or performance workloads were
run. Source semantics and the distinct native/public qualification are covered
by their existing independent receipts, not repeated here. Guardian outcomes
for this documentation commit are recorded separately; root consolidates its
feedback entry.

Replay the independent read-only check from this worktree:

```bash
scripts/build-slot.sh build python3 \
  experiments/lox-byte-screen-independent-review-20261003/review.py \
  --root /home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003 \
  --author /home/epentland/ai/canopy/mylang-worktrees/codex-lox-vm-bytecode-20261003 \
  --out /absolute/private/review.json
```

Raw wall SHA256:
`b2f8ec5e44d819b074bd3019eed5d06e304f1eec861639c23a4072f29acdeadc`.
The independently verified checkpoint, manifest, raw receipts, published
analysis and artifact identities are retained in `review.json`.
