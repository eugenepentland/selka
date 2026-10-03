# AST/constant source factorial

This experiment freezes the accepted 84-test source (`44cd4307`) and two
independent source changes. The AST candidate matches call/class nodes inside
their handlers, eliminating two owning getter returns. The VM candidate splits
the constant operand read from its readonly pool read and adds an operand-255
regression. Their composition has 85 public tests and changes exactly
`interpreter.my`, `vm.my`, `driver_tests.my` and `driver_cases.json`.

The canonical migration remains the accepted 84-test version. Full repeated
wall-time and counter measurements are pending. The complete one-round
instruction screen gives the following reductions, using the geometric mean of
13 paired workload ratios per engine:

| Source change | LLVM VM | QBE VM | LLVM tree | QBE tree |
| --- | ---: | ---: | ---: | ---: |
| AST | 0.0000% | approximately 0% | 1.7871% | 2.0784% |
| Constant | 1.0547% | 0.0473% | approximately 0% | approximately 0% |
| Combined | 1.0547% | 0.0473% | 1.7871% | 2.0784% |

`source-screen-instructions.json.gz` contains all 208 diagnostic cells, with
all 832 PMU running percentages equal to 100. `source-smoke.json.gz` contains
208 successful output/collector checks. Native qualification of the composed
85-test source is recorded separately in `../lox-composed-20261003`.
Component source reviews are in `../lox-ast-carrier-independent-review-20261003`
and `../lox-vm-constant-review-20261003`. Complete native streams are preserved
in those qualification experiments; the measurement runner compares full
stdout before recording its hash and records decoded stderr up to 1,500 chars.

`binaries.json` freezes ten original measurement arms: the four source variants
under checked LLVM O3/full LTO and checked QBE, plus the original Rust/Go ELFs.
Compiler `d14a7040…` and adjacent QBE `99ad919d…` are unchanged. The baseline
sidecars are inherited from the accepted binaries and retain their original
binary paths; identity is established by the recorded byte hashes. All four
37-file source maps are in `sources.json`.

Reproduce the exact source factorial in a new workspace with an explicitly
selected compiler:

```bash
LOX_WORK=/absolute/path/to/new-workspace
LOX_COMPILER=/absolute/path/to/qualified-releasefast/bin/mylang
python3 experiments/lox-ast-constant-20261003/prepare.py \
  --work "$LOX_WORK" --compiler "$LOX_COMPILER"
```

The helper validates a deterministic archive of the accepted 37-file source,
applies the two independently reviewed patches without fuzz, composes them,
checks all four source maps and builds eight mylang guests. It builds references
from `4e48a09220c2e018eba8c4b1eb3fe1137a3dae73` and records private build commands,
toolchains, runtime objects and helper identities. It refuses an existing
workspace. No current canonical migration is required to reconstruct source84.

The tested helper run is `.tmp-lox-round3/fresh-rebuild`, manifest
`00ec53962dc576e3567a0f83f4df6711c3e428d22d16c82ca4d64a24501d36aa`.
All eight mylang guests and Rust match the measured ELFs byte for byte. Fresh
Go has a distinct identity and different embedded source paths; it remains a
behavior-only reproduction arm. The helper passes `-buildvcs=false`.
`fresh-rebuild-smoke.json.gz` records 260 successful checks with exact output
hashes and equal Lox collector work across all ten fresh arms.

Run one performance command at a time. These commands use the full factorial
so each component and its composition share the same matched controls:

```bash
LOX_ARMS=baseline-llvm,baseline-qbe,ast-llvm,ast-qbe,constant-llvm,constant-qbe,combined-llvm,combined-qbe,rust,go
python3 experiments/lox-parity-20261003/run.py time --work "$LOX_WORK" \
  --out "$LOX_WORK/wall.json" --arms "$LOX_ARMS" --tier timed --rounds 3 --cpu 2
python3 experiments/lox-ast-constant-20261003/analyze.py "$LOX_WORK/wall.json" \
  --metric wall_s --out "$LOX_WORK/wall-analysis.json"
python3 experiments/lox-parity-20261003/run.py counters --work "$LOX_WORK" \
  --out "$LOX_WORK/counters.json" --arms "$LOX_ARMS" --tier tree --rounds 3 --cpu 10
python3 experiments/lox-ast-constant-20261003/analyze.py "$LOX_WORK/counters.json" \
  --metric instructions --out "$LOX_WORK/counter-analysis.json"
```

The full analyzer requires all 780 unique cells and three rounds, checks output
identities and diagnostics, and checks all four PMU running rates for counters.
It reports medians of within-case paired ratios and then their geometric mean.
The `--screen` mode requires the eight source arms and labels its result as a
diagnostic. CPU 2/sibling 3 and CPU 10/sibling 11 are reserved; build-slot admission
excludes all four. The tested fresh smoke uses CPU 0 and provides behavior
evidence during the original wall run. Partial wall rows are outside this
completed diagnostic checkpoint.
