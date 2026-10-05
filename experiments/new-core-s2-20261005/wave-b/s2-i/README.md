# S2-I qualification

Base: `72eaae74`. Implementation commit: `b68232d3` (all checks below exercise this source).
The old-core oracle is the accepted integration head's `zig-out/bin/mylang`
(copied with its adjacent `qbe`); the pre-Wave-A cached binary is not the oracle.
All caches and TMPDIR belong to this locked worktree. Timing CPUs 2, 3, 10 and
11 are excluded from builds; no new timing row is needed because all 20 S0/S1
definitions are identical. Frozen `ir.zig` is unchanged.

| Check | Command | Result / evidence |
|---|---|---|
| Rebuild | `scripts/build-slot.sh build -- zig build core --summary all` | `rebuild.txt`; 2.66 s; compiler 1 s, MaxRSS 318 M |
| Core gate | `scripts/build-slot.sh gate -- bash -c '"$@"; result=$?; exit "$result"' -- scripts/build-slot.sh build -- zig build test-core --summary all` | `test-core.txt`; 189/189; 150.88 s; peak reported test RSS 127 M |
| Full comparison | `scripts/build-slot.sh build -- python3 experiments/new-core-s1-20261005/conformance.py --set all --jobs 4 --why --cache-dir .mylang-cache/wave-b/s2-i/conformance` | `conformance.txt`; 795 matching, 0 mismatches, 745 refusals / 1540 in each mode |
| Own leak + verify sweep | same runner with `live_place_iteration iteration_identity experiments/new-core-s2-20261005/wave-a/s2-lb/mut_callee_rebinding.my test/core/i_live_place.my --jobs 4 --leakcheck --verify --why` | `focused.txt`; 35 matching, 0 mismatches, 21 refusals / 56 in each mode; no leak/fact failures |
| Own fuzz | qualified wrapper `--kind iteration --cases 50 --seed 512 --mylang zig-out/bin/mylang --core zig-out/bin/mylang-core --evidence experiments/new-core-s2-20261005/wave-b/s2-i/fuzz --cache-root .mylang-cache/wave-b/s2-i/fuzz` through a build slot | `fuzz/summary.json`, `fuzz-replay.txt`; 50 accepted, 750/750 comparisons, 0 mismatches, leaks, fact failures or crashes; 291.72 s |
| S0/S1 code | `scripts/build-slot.sh build -- python3 experiments/new-core-s2-20261005/wave-a/compare_code.py --stage s2-i` | `code.txt`; 20 identical definitions |
| Coverage | `scripts/build-slot.sh build -- python3 experiments/new-core-s0-20261005/coverage.py` | `coverage.txt`; 2355/3627 functions accepted (65%); all refusal counts retained |
| Guardian | `guardian-check all . --gate` and normal commit hook | `guardian.txt`; 88 checks |

The first encode ownership fixture used an invalid hand-built print signature
(print operands must start with the capability, and byte values need conversion
to int). It failed IR verification before running; the fixture now uses
`Hand.printValues`. The retained fixture-failure log explains that repair.
An early fuzz generator emitted a discarded pop without the required `_ =`;
`fuzz-generator-failure.txt` explains the generator-only repair. Early oracle
setup was corrected to the accepted Wave-A binary before grading.

The gate wrapper keeps a waiting parent shell alive to hold the gate descriptor
while the inner wrapper takes the build descriptor. Admission waiting is outside
the recorded command time. No frontend, old-core source, language fixture or
external Lox checkout was edited. Final old-core gates, all-row measurements and
200-case fuzz are reserved for S2-X as the Wave B pace rules require.
