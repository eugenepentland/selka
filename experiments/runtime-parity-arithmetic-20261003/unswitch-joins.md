# Joined comparison producer diagnostic

`unswitch-joins.my` is a standalone dynamic-argument program for short-circuit
and conditional-expression joins. The runner derives eight ordinary `main`
functions by replacing only the marked condition. Each keeps one separate
`kind == 2` branch so the loop remains eligible while its joined comparison
must retain the actual incoming boolean or integer value. Two separate prefix
literals can exceed the existing copy-growth budget; this diagnostic changes
neither that budget nor any acceptance port.

The forms cover OR, AND, mixed dynamic conditions, conditional booleans,
short-circuit division and a conditional integer operand. The last case enters
the literal-push instruction with `seed`, bypassing the adjacent `kind` load;
the boolean cases enter a final branch with another producer's boolean.

Run through the repository build wrapper with private disk temporary directories
and Zig caches:

```sh
scripts/build-slot.sh build python3 \
  experiments/runtime-parity-arithmetic-20261003/unswitch-joins.py \
  --compiler ABS/zig-out/bin/mylang --qbe ABS/zig-out/bin/qbe \
  --compiler-revision REV --host-mode Debug --output PRIVATE/joins
```

Every form must contain an actual emitted unswitch marker. The native matrix
builds ReleaseFast guests with accounted QBE, unaccounted QBE and LLVM
`--release` (O3/full LTO). It asserts the effective manifest backend and LLVM
optimization/LTO fields, then independently probes step accounting through
`MYLANG_OPTIONS`. The release switch already sets mode/backend/optimization/LTO
and cannot be combined with those explicit controls or a QBE-path switch.

For each form, all combinations of `kind` 2/3/99, `count` 0/3 and `seed` 0/1/2
must match in process status, stdout and complete stderr across the three lanes:
144 distinct outcomes, 432 guest executions. A separate Python oracle checks
the returned integer, printed sequence, skipped division and division-by-zero
output prefix/code. This is an untimed correctness matrix.

`unswitch-joins.json` preserves generated source, compiler, tool, executable and
manifest hashes, full commands and build/emission logs, accounting probes and
all outcomes. The source compiler revision is supplied explicitly by the caller;
the executable hash records the compiler actually used. No pre-build compiler
source attestation is inferred from the revision argument.

The initial verified run used the parent's stable Debug compiler from source
revision `730a86e62b47c922dc1411d24b5868c3bd2132f3`. All eight forms were admitted,
all 24 accounting probes passed, and all 144 three-lane outcomes plus the
independent oracle matched. Its receipt is retained at
`/home/epentland/.cache/mylang/runtime-parity-text-20261003/unswitch-joins-730a86e6/unswitch-joins.json`.
