# D9 Lox tree dispatch frames, 2026-09-26

The optimized external Lox port now gives substantial statement cases their
own helper functions. The tree interpreter's `execute` dispatch calls helpers
for expressions, declarations, conditionals, printing, returns and loops;
`evaluate` also delegates literals and `this`. Each helper keeps the original
case body and error propagation. This reduces aggregate temporaries and their
initialization on dispatch paths that never use them.

The source change extends `d9-stage3d-migrations/lox-source-perf.patch` from
`143a3e2b`. Applying the pinned migration with `--optimized` reproduces every
module of the tested source byte for byte. Only `interpreter.my` changes;
existing VM, compiler and heap patch sections are preserved.

## Matched instruction measurement

The Debug compiler at `adcbb4ca` (SHA `6961ce9e…`) already removes redundant
payload-transfer scratch and initialization of aliased locals. Comparing both
source revisions with that same compiler therefore measures the helper gain
remaining after those compiler improvements. Guests use QBE ReleaseFast or
LLVM ReleaseFast, optimization level 3 and full LTO. Three runs on CPU 2 count
`instructions:u`; outputs are checked exactly. The diagnostic is the pinned
`binary_trees` script at N4.

| Tree N4 | Before helpers | With helpers | Helper / before | Helper / historical baseline |
| --- | ---: | ---: | ---: | ---: |
| QBE | 121,350,186 | 104,954,440 | 0.8649× | 1.8013× |
| LLVM | 58,327,716 | 51,704,325 | 0.8864× | 2.4071× |

[Raw samples and identities](evidence/d9-lox-tree-frames-n4-perf.json) include
compiler, source, guest and script hashes plus exact script contents. The
historical binaries are measured again in the same batch (58,266,098 QBE and
21,479,725 LLVM instructions), rather than reusing a previous sample.
The remaining tree regression is real extra audit evidence. The formal D9
stage 3 performance gate includes the Lox VM, not the tree interpreter.

A separate calibrated 13-script tree audit using the mandated `pc.py` harness
and frozen compiler `9f42e5a9` is still running at this commit: four of 26
program/backend rows have completed. This partial run is not an acceptance
result. Its source remains frozen independently of later VM source changes.

## Validation and reproduction

All 63 port tests pass in each semantics mode using the existing ten-million
step allowance. All 13 scripts match expected output with both engines, both
backends and both modes (104 runs). All 23 tree error cases, with and without
Lox GC stress, match the exact historical observations on both backends and
both modes, with native GC stress throughout (184 comparisons):
[run evidence](evidence/d9-lox-tree-frames-runs.json.gz).

Value-mode tests and those four-mode checks use the frozen Debug compiler at
`9f42e5a9` (SHA `76a141ef…`) for value semantics and the prepared default
candidate's explicit `--legacy-sharing` for compatibility. The N4 measurement
above separately builds both source revisions with the newer `adcbb4ca`.

Scratch scripts and logs are retained under `.tmp-tree/` in worktree
`d9-tree-small-frames`:

- `scripts/build-slot.sh build env TMPDIR="$PWD/.tmp-tree" python3 .tmp-tree/build-and-test.py`
  builds four guests and runs both test modes; logs are `validation.log` and
  `tests-{value,legacy}.log`.
- `python3 .tmp-tree/check-runs.py` runs the 104 smoke and 184 trace comparisons;
  `check-runs-final.log` records completion.
- `scripts/build-slot.sh build env TMPDIR="$PWD/.tmp-tree" python3 .tmp-tree/build-adc.py`
  builds matched before/helper guests with `adcbb4ca`.
- `python3 .tmp-tree/measure-adc.py` runs the N4 samples as
  `taskset -c 2 perf stat -x ';' -e instructions:u BINARY --engine=tree SCRIPT`,
  with `MYLANG_MEMORY_LIMIT=8G`.
- `docs/audits/d9-stage3d-migrations/apply-lox.sh "$PWD/.tmp-tree/replay-final" --optimized`
  reconstructs the patch; every top-level module was compared byte for byte.

An initial attempt to run the entire smoke set under native GC stress reached
the 120-second timeout on the tree N6 allocation case. Normal-collector smoke
runs passed; native stress remains enabled for every trace case. No semantic
failure was observed. This patch changes external-port source and evidence;
the joined compiler/source candidate still requires the orchestrator's full
gate after integration.
