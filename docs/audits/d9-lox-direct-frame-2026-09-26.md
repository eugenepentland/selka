# D9 direct Lox frame reads, 2026-09-26

The optimized external-port patch now constructs `ExecFrame` directly from
the closure and function variants in the runtime heap. The prior version
returned complete closure and function records through two accessors before
copying only their constants, bytecode and upvalue lists into the frame.
The new nested matches keep those payloads read-only and preserve the same
type assertions and saved-frame roots.

## Matched source comparison

Both source arms use the frozen Debug compiler at `9f42e5a9`, including the
closed-region ownership proof. Guests use ReleaseFast on both backends;
LLVM uses optimization level 3 and full LTO. The mandated `pc.py` harness
checks exact output and takes median-three instruction counts on CPU 2 at
its calibrated sizes. Ratios compare the new source against `143a3e2b`.

| VM case | QBE | LLVM |
| --- | ---: | ---: |
| binary_trees | 0.9764× | 0.9838× |
| closures | 0.9428× | 0.9562× |
| fib | 0.9352× | 0.9394× |
| trees | 0.9597× | 0.9686× |

[Raw measurements](evidence/d9-lox-direct-frame-perf.json) retain every
sample and compiler, source and binary hashes. These are isolated source
improvements; the full stage 3 baseline gate remains unmet.

## Validation and replay

All 63 port tests pass in each semantics mode with the existing
10-million-step allowance. All 13 VM smoke scripts pass on both backends
in each mode (52 runs). The 23 error cases, with and without Lox GC stress,
match the exact `60b668cf` baseline on both backends and in each mode, with
native GC stress enabled throughout:
[184 trace comparisons](evidence/d9-lox-direct-frame-traces.json.gz).

Value-mode builds use the frozen compiler above. Compatibility builds use
the isolated default candidate at `b937d4fc` with `--legacy-sharing`, which
supports the migrated port's scalar-record mutation in compatibility mode.
`d9-stage3d-migrations/apply-lox.sh WORK --optimized` reproduces every tested
`.my` module byte for byte. Only the external-port patch and audit evidence
change; the joined compiler/source still needs its full integration gate.
