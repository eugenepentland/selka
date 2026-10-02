# Keep Lox activation data across child calls

`frames.patch` changes only `vm.run` in the unchanged October 2 optimized
external port. Each invocation dispatches one Lox activation. A pushed callee
runs recursively; returning resumes the caller's existing `ExecFrame` rather
than reconstructing its constants, code and upvalues. Native calls and empty
class construction do not add a frame, so they continue without loading the
same frame again. No compiler, runtime, canonical migration or expectation
changes are included.

This removes the return-side `load_frame` and its three list acquisitions and
releases. Callee activation still loads its frame normally. The caller's lists
stay alive across the child call, making the lifetime visible in ordinary
source instead of introducing an unchecked borrowed view.

## Semantics and limits

- `Runtime.frames` remains the authority for Lox roots, stack bases and error
  traces. A caller still publishes the post-operand IP before calling away;
  error-capable handlers publish the same pre-operand IP.
- Completed code/constants and closure upvalue *indices* do not change during
  execution. Updates to the referenced open/closed upvalue objects continue
  through `Runtime.objects` and remain visible to suspended callers. Each
  activation owns its snapshot of the three list descriptors until return.
- `OP_RETURN` performs the existing close-upvalues, frame-count and value-stack
  updates before returning to the parent dispatcher. A runtime error resets
  the Runtime and propagates through each dispatcher without resuming bytecode.
- The unchanged `heap.FRAMES_MAX == 64` check bounds native dispatcher recursion
  too. This adds native stack use proportional to Lox call depth; it does not
  raise the Lox limit or remove overflow/bounds/ownership checks. Deep successful
  calls, repeated frame-slot reuse and the exact overflow trace are checked.
- This lane edits only `vm.run`; property lookup helpers and stack operations
  can compose independently. The tree interpreter is unchanged.

## Preliminary performance

Frozen compiler source `6df58b02554401f9d37564cceffd14277a835ae1`, SHA-256
`45d05b554849bf3c12553549d9138556ba0204f9d59ba3aaa2ecb2327eb39ac4`.
Guests use explicit checked RC, the same project sources, and symbols.
LLVM uses O3 and full LTO; QBE uses the default ReleaseFast compiler settings.

One diagnostic instruction sample per arm/case at unchanged D9 `tree` sizes,
CPU 12, exact stdout checked. These are candidate/control ratios and **not**
official timing or full-suite acceptance:

| VM case | LLVM instructions | QBE instructions |
|---|---:|---:|
| fib | 0.9355 | 0.9098 |
| closures | 0.9373 | 0.9143 |
| properties | 0.9230 | 0.9020 |
| invocation | 0.9003 | 0.8755 |
| method_call | 0.9477 | 0.9329 |
| instantiation | 0.9481 | 0.9206 |

The parent integration lane owns repeated timing and counters on reserved
CPUs 2/10. It should qualify this patch across all 13 scripts before making an
acceptance claim.

## Correctness validation

- All 65 existing port tests execute and pass on QBE and LLVM, each with native
  GC stress and the unchanged 10-million-step test allowance. Nothing is cached
  or skipped.
- All 13 smoke scripts pass on both engines and both RC backends: 52 runs.
- All 23 VM error cases, each with Lox collection normal/stressed, match the
  unchanged baseline byte for byte on both RC backends: 92 comparisons. A
  separate pair of GC builds repeats all 92 comparisons with native GC stress
  enabled, including native and Lox stress together.
- `frames-probes.py` checks eight additional activation scenarios on both
  engines, with Lox stress normal/enabled, for reference and candidate. The RC
  pair and independently built GC pair total 256 successful runs across both
  backends. The GC pair enables native collector stress too. Probes cover
  no-frame native/class calls, distinct closures of the same function,
  escaping/closed and suspended/open upvalues, replacing the current closure's
  global root while a child allocates, bound/super method calls, 60-level calls
  followed by repeated frame-slot reuse, and receiver changes across calls.
- A clean reconstruction plus this overlay reproduces the candidate `vm.my`;
  all other 25 `.my` modules match the unchanged optimized port.

The initial attempt to apply native GC stress to RC binaries was rejected by
the runtime and is excluded from successful validation. GC binaries were built
separately for those checks. The first perf launcher was not pinned before
starting perf and crossed the machine's hybrid PMUs; its parser rejected the
two numeric event rows. Completed samples pin both perf and its child before
measurement. Both discarded attempts are recorded in the receipt.

## Reproduction and receipts

The standalone overlay expects the optimized port at audit commit `bbefb77f`.
Use that revision's migration script and this branch's overlay. The integrated
`apply-lox.sh --optimized` already includes this change and the other accepted
lanes; do not apply this overlay a second time there.

```bash
baseline=/absolute/path/to/baseline-worktree-at-bbefb77f
repo=/absolute/path/to/improvements-worktree
work=/absolute/path/to/fresh-private-work
"$baseline/docs/audits/d9-stage3d-migrations/apply-lox.sh" "$work" --optimized
patch -p1 -d "$work/lox/benchmarks/lox/ports/mylang" \
  < "$repo/experiments/lox-perf-improvements-20261002/frames.patch"
```

`frames-receipts.json` records exact compiler/build/test commands, all 26
source hashes for both arms, guest hashes, every preliminary perf command and
instruction value, successful verification counts, and raw-evidence hashes.
Build/test commands use `scripts/build-slot.sh build` with private cache,
output and `TMPDIR`. Raw JSON, logs, test reports and guest binaries remain in
`/home/epentland/ai/canopy/mylang-worktrees/codex-lox-perf-frames-20261002/.tmp-lox-frames`.

The candidate RC LLVM and QBE binaries are `bin/frames-llvm` and
`bin/frames-qbe` in that private directory. GC binaries are `bin/frames-gc-llvm`
and `bin/frames-gc-qbe`; they are validation controls. Probe replay:

```bash
python3 experiments/lox-perf-improvements-20261002/frames-probes.py \
  BASELINE_BINARY CANDIDATE_BINARY PRIVATE_PROBE_WORK
python3 experiments/lox-perf-improvements-20261002/frames-probes.py \
  BASELINE_GC_BINARY CANDIDATE_GC_BINARY PRIVATE_GC_PROBE_WORK --native-gc-stress
MYLANG_OPTIONS=--gc-stress \
  python3 docs/audits/d9-stage3d-migrations/verify-lox-traces.py \
  BASELINE_GC_BINARY CANDIDATE_GC_BINARY PRIVATE_TRACE_WORK
```
