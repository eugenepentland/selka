# Skip empty RC slot cleanup calls — 2026-09-26

Generated slot releases now read their initialization guard before calling native
cleanup. A clear guard branches past the helper; initialized entries still use
the existing runtime function, which clears the guard before any callback and
preserves unique/count/abort ordering. Normal and trap frame cleanup are unchanged.

This matters after constructor takes: consumed operands frequently reach their
cleanup instruction with a clear guard. The generated branch also lets LLVM
propagate a known clear guard across the no-op release.

The focused test passes 12/12, and actual uncached RC aggregate, recursive-value
and capability tests pass 36/36 on each backend. Whole-tree Guardian88 passes.
Private n12 binary-trees probes preserve exact output and identical full counts
on QBE and LLVM: 19 owner acquires, 669,079 releases, 669,060 allocations and
retirements, zero holds/clones and 33 uniqueness checks. Three interleaved CPU2
instruction medians give after/before 0.983879 QBE and 0.983485 LLVM O3/full LTO.
This modest focused gain is not full-corpus performance acceptance.

All commands, compiler/binary hashes, raw samples, full source patch and 72 test
verdicts are in `experiments/d9-rc-drop-guard-20260926/`. Its original drivers use
`.tmp-schematic/drop-guard` and a frozen before compiler at
`.tmp-schematic/install-before-drop-guard/bin/mylang`.
