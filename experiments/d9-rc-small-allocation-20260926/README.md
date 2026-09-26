# Small native allocation experiment

`source-identity.json` and `candidate.patch` identify the matched source pair.
`results.json` preserves the final-source median-three measurement and exact RC
counters. `initial-results.json` preserves the initial exploratory run; it is not
substituted for the less favorable final QBE median. Both use the same depth-12
fixture, Debug compiler installations, actual QBE and LLVM O3/full-LTO guests,
CPU 2, and exact output checks.

`build.py` and `measure.py` preserve the private `.tmp-rc/profile` workflow. The
build helper belongs in that directory, beside `binary_trees_n12.my`, its saved
expected stdout and the compiler installations named in each recorded command.
Build commands run through `scripts/build-slot.sh build`; measurement itself
does not use a build slot. Before and final installations/binaries were retained
separately. Compressed build and focused-unit logs preserve their verdicts.

See [the audit](../../docs/audits/d9-rc-small-allocation-2026-09-26.md) for cache,
budget, layout, custom-hook and validation details. This experiment does not
establish WP-4 performance acceptance.
