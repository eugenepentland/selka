# Full source-counter closeout

The completed `combined-counters.json` passes the independent read-only
audit: all 13 scripts on both engines, six arms including Rust and Go, and
three original-size rounds give exactly 468 unique rows. All output hashes,
empty diagnostics, command/log hashes, source37/module26 identities, measured
guest identities and original build/runtime receipts match. All four PMU
running rates are 100 in every row, adding 1,872 rate checks. Per-case summary
values, paired round ratios, spreads and all six engine comparisons match
the recorded analysis independently.

`source-counter-closeout.json` preserves the primary 1,300-row review at
`2a3d750d` unchanged and adds these 468 rows, for 1,768 completed audited rows.
Source instruction reductions reproduce about 1.913% LLVM/1.855% QBE on VM
and 0.207%/0.422% on tree. The preceding wall-time findings and statistical
limits remain unchanged. This audit ran no guests, new tests or performance
commands and made no root changes.

Compiler-only `write-attribution-timing.json` was still active at this
observation: 44 retained rows out of a 312-row target. No complete pass or
wall-time result is claimed for that phase. Its four arms compare combined
source84 with control or write compiler; it excludes Rust/Go and will support
compiler attribution only. A later separate receipt must qualify completion.

To inspect later phases, choose a fresh destination:

```bash
python3 experiments/lox-next-measurement-independent-review-20261003/closeout.py \
  --root /home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003 \
  --out .tmp-lox-next-measurement-review-20261003/later-closeout.json
```

The verifier imports this review's independent checker. It confirms the
primary manifests/receipts/helpers remain unchanged, rechecks sources,
references, guests and native RC build identities, and certifies only later
phases that completed post-run validation. Primary stdout/stderr/CSV retention
limits still apply. Every completed new diagnostic is empty ASCII text and
every expected stdout hash matches; raw per-sample streams/CSV were not
independently archived.
