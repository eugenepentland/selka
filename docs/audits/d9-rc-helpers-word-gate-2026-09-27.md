# Joined managed helpers and dictionary overwrite checkpoint

Frozen source `c07016f308422b76cfe55607b26243efe0b4257e` passes the complete
four-command gate: main 94/94 steps with 2,368 executed tests, QBE 51/51 with
451 tests, native builds 29/29 and formatting 2/2. The Debug install passes
19/19 steps and the separate whole-tree Guardian run passes all 88 checks.
Compiler SHA256:
`db9d8791fb56a9c07e5db529b5abe54b2689966364095de89e2abcaca4409b2b`.

Both forced counted-RC backend sweeps pass **1,019 assertions across 173
programs**, with zero failures, skips, cached verdicts, dropped or unloaded
files. LLVM uses `--release`, including O3/full LTO. Source and HEAD stayed
frozen through the serialized build, gate and sweeps. The
[archive](../../experiments/d9-rc-helpers-word-gate-20260927/README.md) binds the
exact compiler, command summaries, terminal statuses and raw receipts.

The source adds managed readonly helper composition `b6ff7788` and registered
plain dictionary word overwrites `0efd82ad` to the preceding `49c6ca07` loop
checkpoint through real two-parent merges. The only merge conflict retained
the independent append-loop and readonly fields and their initializers.
Both component archives passed independent live verification before integration.
The managed-helper report retains its separate pre-existing LLVM combined-wrapper
build failure; it was not counted as a passing component control.

This establishes combined correctness, not performance acceptance. Stage 4
still requires the unchanged 43 programs per backend to satisfy instruction
geomean at most 1.0, every row at most 1.3 and lower median peak RSS against
accepted GC. The focused joined comparison measures only dictionary counting
and three schematic workloads. GC remains the default, and main is unchanged.
