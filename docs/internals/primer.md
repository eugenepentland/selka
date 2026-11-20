# Primer: how it works

Implementation detail moved out of `docs/primer.md`. The guide keeps the user-visible rule.

## Commands

`run` and `build` make a lean debug build by default: one unit per module, Core's passes, then code generation at
`-O2` with LLVM's IR passes off (on for a unit of at most 50,000 bytes), so an edit recompiles only what changed. `test` builds the same way at LLVM `-O0`.
`--debug-o0` gives `run` and `build` the `-O0` build (the cheapest cold build), `--optimize-debug` LLVM `-O2` and
`--unoptimized` a build with no Core pass. `--release` optimizes the
whole program as one unit and recompiles all of it after any change. Both keep
every overflow, cast and bounds check.
