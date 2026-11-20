# D9 Lox class method reads, 2026-09-26

The optimized VM now calls `heap.class_method` for constructor, invocation
and bound-method lookup. The helper reads one value inside a direct class
match, keeping the method table read-only instead of returning a complete
`ClassObj` snapshot. Constructor handling no longer carries that snapshot
across instance allocation. Allocation, stack updates, arity checks and
undefined-property errors retain their ordering.

The experiment starts at merge `b5d738eb`, which combines scalar instance
reads (`d8b741a6`) with the receiver/RHS migration fix (`4a926ec7`). It changes
only `heap.my` and `vm.my` in the optimized migration patch. The corrected
base migration remains the source of the two receiver regression tests.

## Matched measurement

Both sources use the frozen Debug compiler `5bdd99ea`, SHA
`ceb38b6e1fb1a23f20d92580b3cd7f07f635f5752311f27d477f9792e388b7d5`.
Guests use ReleaseFast, with LLVM optimization level 3 and full LTO. The
mandated `pc.py` harness checks output and records median-three instruction
samples on CPU 3 at its calibrated Lox sizes, using the VM engine.

| VM case | Candidate / before QBE | Candidate / before LLVM |
| --- | ---: | ---: |
| binary_trees | 0.9985× | 0.9998× |
| closures | 0.9961× | 0.9990× |
| fib | 0.9956× | 0.9985× |
| method_call | 0.9903× | 0.9937× |
| trees | 0.9934× | 0.9962× |

The improvement is small. Removing the constructor's aggregate temporary
also changes `call_value` scratch setup on other call paths. These results
do not establish the full D9 performance gate. On VM binary_trees N10,
sharing marks fall from 5,055,149 to 4,789,583; copies remain 1,063,200 and
273,336,509 bytes, with zero pins.

[Raw measurements](evidence/d9-lox-class-method-perf.json) preserve every
sample, source/compiler/binary/script identity and counter output.

## Validation and reproduction

All 65 port tests pass in each semantics mode. All 13 smoke scripts match
expected output on both engines, backends and modes (104 runs). All 23 VM
error cases match the historical baseline, with and without Lox GC stress,
on both backends and modes; native GC stress is enabled throughout those
184 comparisons. [Validation evidence](evidence/d9-lox-class-method-runs.json.gz)
includes exact outputs and compiler identities. Patch replay reconstructs
all measured `.my` and `.json` files byte for byte. The joined compiler/source
full gate remains the integration task.

The `d9-lox-class-method/.tmp-method/` scratch directory retains `before/`,
`port/`, `build.py`, `measure.py`, `validate.py`, `check-runs.py` and their
logs. Builds and tests use `scripts/build-slot.sh build env
TMPDIR="$PWD/.tmp-method" python3 .tmp-method/build.py` (or `validate.py`).
`python3 .tmp-method/measure.py` measures CPU 3 through `pc.py`;
`python3 .tmp-method/check-runs.py` performs smoke and trace comparisons.
Counting guest builds set `MYLANG_COW_COUNTING=1` only during compilation.
Compatibility builds use the prepared default compiler with the explicit
`--legacy-sharing` flag; its hash is included in the evidence.
