# D9 Q3: retain copied list-element write-back

Decision: drop the proposed in-place list-element write-back optimization from
the D9 close-out. Keep the existing `qbe_moves.zig` behavior for `xs[i].f = v`:
the record update uses a copy and writes the resulting value back to the list.
No compiler behavior changes for this decision.

The stage 2 evidence recorded beside `Update` in `src/qbe_moves.zig` reports
nbody instruction ratios of 0.68× on QBE, 1.06× on LLVM with full LTO, 1.00×
with thin LTO and 0.99× without LTO. These are prior measurements, not a new
benchmark run. The stage 2 implementation removed the optimization after the
full-LTO regression. Full LTO is the shipped optimized guest configuration;
the QBE result alone does not justify restoring it.

This optimization is optional for D9. Retaining the current behavior preserves
the measured stage 3 baseline and avoids adding an unresolved backend tradeoff
to the copy-on-write and reference-counting changes. This decision does not
disable ownership-proven local-slot updates, record copy elision, or required
copy-on-write uniqueness checks.

A later proposal may revisit the optimization with an isolated explanation of
LLVM alias analysis and matched QBE/full-LTO measurements across the parity
suite, schematic and Lox. It must establish both value independence and a
performance benefit before changing the current default.

Evidence: [close-out plan, Q3](d9-closeout-plan-2026-09-26.md),
[`Update` and its accompanying measurements](../../src/qbe_moves.zig).
