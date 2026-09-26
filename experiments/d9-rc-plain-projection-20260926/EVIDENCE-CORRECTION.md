# Plain-projection backend evidence correction


## LLVM evidence correction

The historical `llvm.json` build command placed `--qbe=...` after `--backend llvm`.
The later option selected QBE, so that file is retained as a second QBE run and
**does not establish LLVM validation**. Its raw command/result is unchanged.
The original claim that those three archived runs validated LLVM is withdrawn.

`actual-llvm-a49441c1.json` replaces that validation with an actual LLVM O3/full
LTO build from frozen integration `a49441c1`, Debug compiler SHA
`fc1f3fc16f5f3d1deecf3a7446ac1df27362e2d7dedf18e77a39ea9b7263361e`.
It passes all three exact required schematic SVG hashes, with balanced heap,
owner and hold counters. The command has no `--qbe` option. This newer checkpoint
contains additional fixes, so its counters do not isolate the plain-projection
change. The preserved QBE runs remain valid. The central RC LLVM language sweeps
use `--release` without `--qbe` and are unaffected by the runner mistake.
