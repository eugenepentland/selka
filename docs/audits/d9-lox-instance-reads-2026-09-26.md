# D9 Lox VM instance reads, 2026-09-26

The VM's `instance_of` now returns an optional object reference. Invocation
and property handlers match that heap object directly instead of receiving a
snapshot of its entire `InstanceObj` and mutable fields table. Property
writes read the class id before extracting fields and store a fresh instance
record after the table update. Receiver checks, assigned values and runtime
error messages retain their ordering.

This changes only the optimized port's `vm.my`, from source `bb0fe9b4`.
The separate tree setter RHS migration bug is outside this VM experiment.

## Matched measurement

Both sources use the frozen Debug compiler at `f8dad8e8`, SHA `2e5e577f…`.
Guests use QBE ReleaseFast or LLVM ReleaseFast, optimization level 3 and full
LTO. The mandated `pc.py` harness checks exact output and takes median-three
instruction samples on CPU 3 at its calibrated Lox sizes, using the VM engine.

| VM case | Candidate / before QBE | Candidate / before LLVM |
| --- | ---: | ---: |
| binary_trees | 0.9664× | 0.9696× |
| closures | 1.0000× | 1.0079× |
| fib | 1.0000× | 1.0042× |
| trees | 0.9705× | 0.9688× |

[Raw measurements](evidence/d9-lox-instance-reads-perf.json) preserve all
samples, source/compiler/binary hashes and script hashes. The small LLVM
regressions on unchanged execution paths are retained in the result.
These isolated comparisons do not establish the full D9 acceptance gate.

On VM binary_trees N10, counted sharing marks fall from 8,239,219 to 5,055,149.
Copies remain 1,063,200 and 273,336,509 bytes, with zero pins: the setter's
field extraction still copies before its indexed union store-back. This
change removes redundant read snapshots without claiming that remaining
mutation copies have been eliminated.

## Validation

All 63 existing port tests pass in each semantics mode. All 13 smoke scripts
match expected output with both engines, both backends and both modes
(104 runs). All 23 VM error cases, with and without Lox GC stress, match the
historical baseline exactly on both backends and both modes, with native GC
stress throughout (184 comparisons):
[validation evidence](evidence/d9-lox-instance-reads-runs.json.gz).

The optimized migration patch reconstructs every measured module byte for
byte. Value builds use the frozen compiler above; compatibility builds use
the prepared default compiler's explicit `--legacy-sharing`, with its exact
hash recorded. The joined source/compiler gate remains the integration task.

Scratch scripts in `d9-lox-instance-reads/.tmp-instance/` retain reproduction:
`build.py`, `measure.py`, `validate.py` and `check-runs.py`. Builds and tests
run through `scripts/build-slot.sh build env TMPDIR="$PWD/.tmp-instance"`;
`python3 .tmp-instance/measure.py` invokes `pc.py` measurement functions on
CPU 3. The corresponding `.log` files record completed runs. Counting builds
set `MYLANG_COW_COUNTING=1` only for the compiler invocation.
