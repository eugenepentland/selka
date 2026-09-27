# Two-slice composition against accepted GC

See [the report](../../docs/audits/d9-rc-owned-loops-composed-2026-09-27.md).
`python3 experiments/d9-rc-owned-loops-composed-20260927/verify.py` checks archived
receipts. `measure.py` runs from the compiler worktree root, reads the accepted
performance tree's immutable compiler/corpus manifest, builds only private RC
artifacts, and uses CPU 10. It does not replace any acceptance manifest or binary.
All workloads retain mandated full sizes and actual LLVM O3/full LTO.
