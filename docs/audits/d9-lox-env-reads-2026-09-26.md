# D9 Lox environment readers, 2026-09-26

The optimized external port now exposes `heap.env_enclosing` and
`heap.env_slot`. Environment walking, variable reads, `this`, `super` and
initializer returns request only the enclosing reference or one value they
need. They previously returned an entire `EnvObj`, including its mutable slots
list, just to read one field. Environment writes continue through
`set_env_slot` with its existing write-back behavior.

This extends the tree-dispatch helpers and direct VM frame reads at
`bb699470`. Only `heap.my` and six read expressions in `interpreter.my` change.
The optimized migration patch reconstructs the tested modules byte for byte.

## Matched measurement

Before and after sources use the same Debug compiler at `adcbb4ca`, SHA
`6961ce9e…`. Guests use QBE ReleaseFast or LLVM ReleaseFast, optimization
level 3 and full LTO. The table records median-three `instructions:u` samples
on CPU 3 for the tree engine's pinned `binary_trees` script. Every measured
output matches exactly. N10 is the harness's calibrated tree size; N4 is the
small diagnostic used in the preceding helper audit.

| Tree input | QBE reader / before | LLVM reader / before |
| --- | ---: | ---: |
| N4 | 0.9580× | 0.9525× |
| N10 | 0.9615× | 0.9586× |

[Raw counts and identities](evidence/d9-lox-env-reads-perf.json) preserve all
samples, compiler/source/binary hashes, build flags and script contents.
These are source comparisons against the already optimized port, not formal
D9 stage 3 acceptance measurements. A preceding QBE N10 profile attributed
3.5% of sampled cycles to `heap.env_obj`; the readers also reduce caller
snapshot storage.

## Validation

All 63 existing port tests pass in each semantics mode. All 13 smoke scripts
match expected output with both engines, both backends and both modes
(104 runs). The 23 tree error cases, with and without Lox GC stress, match
the exact historical observations on both backends and both modes, with
native GC stress enabled throughout (184 comparisons):
[validation evidence](evidence/d9-lox-env-reads-runs.json.gz).

Value-mode artifacts use the compiler above. Compatibility artifacts use the
prepared default compiler's explicit `--legacy-sharing`; its exact hash is
recorded in the evidence. Compiler hashes were checked again after the run.
No new language or compiler behavior is introduced. The joined candidate's
full gate remains the integration task.

Reproduction scripts and logs live under `.tmp-env/` in worktree
`d9-tree-env-reads`:

- `scripts/build-slot.sh build env TMPDIR="$PWD/.tmp-env" python3 .tmp-env/validate.py`
  runs tests, builds both modes/backends and the matched before binaries;
  `validate.log` and `tests-{value,legacy}.log` record results.
- `scripts/build-slot.sh build env TMPDIR="$PWD/.tmp-env" python3 .tmp-env/check-runs.py`
  runs smoke/trace comparisons and writes `check-runs.log`.
- `python3 .tmp-env/measure.py` uses
  `taskset -c 3 perf stat -x ';' -e instructions:u BINARY --engine=tree SCRIPT`
  with `MYLANG_MEMORY_LIMIT=8G`, writing `measure.log` and `perf.json`.
- `docs/audits/d9-stage3d-migrations/apply-lox.sh "$PWD/.tmp-env/replay-final" --optimized`
  reconstructs the exact tested source.
