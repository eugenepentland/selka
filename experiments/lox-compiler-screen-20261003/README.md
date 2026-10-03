# Compiler-only Lox performance screens

These helpers compare a separately qualified compiler candidate against the
selected `3b33df52` compiler and selected AST source. The candidate's complete
37-file Lox input must match the selected source map. Qualification of the
compiler's ownership and ABI behavior remains a separate review requirement.

`prepare.py` hashes the qualified executables, sidecars, runtime archives,
compiler, pinned QBE, source maps, qualification receipt, controls and helpers
before rebuilding. It records the rebuild and requires matching AMD64 ELF
entry/program layout and every allocated section. Differences in nonallocated
debug or symbol metadata are permitted by a narrow allowlist. This comparison
is reproduction evidence for these inputs; it is not a general ELF equivalence
proof. The measured candidate is a byte-exact copy of the original qualified
ELF, rather than the rebuilt ELF. Copied sidecars and original files are checked
against their initial hashes, then guarded throughout measurement.

`build.py` supplies the explicit pinned QBE only for QBE builds. Supplying
`--qbe` to a command requesting LLVM changes the driver's backend, so LLVM
builds deliberately omit it and use LLVM O3 with LTO. Both arms use checked RC.
The existing measurement runner verifies outputs, manifests and source hashes
after each phase. Smoke checks compare collector statistics as well as output.

`analyze.py` verifies the full case/arm/round matrix, successful status, empty
diagnostics, exact expected output, unchanged guards, and 100% running time for
all four PMU events. Its one-round screen requires 104 cells; a full comparison
requires 468 cells across six arms and three rounds. It reports the geometric
mean over 13 workloads per interpreter of the median paired ratios within
rounds. Cycle screens are diagnostic; repeated wall timings determine whether
a candidate improves runtime.

The frozen four helper files were independently reviewed in
`../lox-compiler-screen-helper-review-20261003`. That review caught a missing
initial sidecar/runtime hash binding before the measured version was frozen.
Earlier preparations and smoke checks remain in private scratch evidence and
are excluded from the current performance results.
