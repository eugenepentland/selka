# D9 Lox active-frame cache, 2026-09-26

The optimized external-port patch stores only the active frame data the VM
reads: constants, bytecode, upvalues, instruction pointer and stack base.
Previously it also copied the entire function record and a redundant closure
id. The saved runtime frame continues to root the closure. Call arity checks
now use scalar accessors instead of constructing function and closure records
whose collection fields the check never reads. Error behavior and object
identity remain unchanged.

This extends `d9-stage3d-migrations/lox-source-perf.patch`; applying the pinned
port migration with `--optimized` reproduces the tested modules byte for byte.

## Isolated source comparison

Both source revisions use the same frozen Debug compiler (SHA `5139b78f…`,
including `8a31f237` and the cold-return emitter change `2b889ba5`). Guests use
QBE ReleaseFast or LLVM ReleaseFast, optimization level 3 and full LTO.
The mandated `pc.py` harness checks exact output and measures median-three
instructions on CPU 11 at its calibrated sizes. Ratios below compare this
source change with `b51cddc1`, not with the pre-D9 acceptance baseline.

| VM case | QBE | LLVM |
| --- | ---: | ---: |
| binary_trees | 0.9764× | 0.9812× |
| closures | 0.9399× | 0.9433× |
| fib | 0.9323× | 0.9231× |
| trees | 0.9758× | 0.9842× |

[Raw measurements](evidence/d9-lox-frame-cache-perf.json) preserve every sample
and source/compiler/binary hashes. The broad stage 3 baseline gate remains
unmet; this source change alone does not close it.

## Validation

All 63 port tests pass in each semantics mode with the existing 10-million-step
port-test allowance. All 13 VM smoke scripts match output on each backend in
each mode (52 runs). The 23 error paths in `verify-lox-traces.py`, each run with
and without Lox GC stress, match the exact `60b668cf` baseline on both backends
and in both modes, with additional native GC stress enabled throughout:
[184 trace comparisons](evidence/d9-lox-frame-cache-traces.json.gz).

Value-mode guest builds use the frozen compiler above. Compatibility builds
and tests use the integrated default candidate's explicit `--legacy-sharing`,
including its later scalar-record compatibility support. This patch changes
only the external port and its audit evidence. The joined compiler/source
candidate still requires its full gate after integration.
