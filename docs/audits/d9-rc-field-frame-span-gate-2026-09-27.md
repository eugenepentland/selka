# Joined RC field, frame and constructor correctness checkpoint

Frozen source `e926d1e13bf61ae3125102b46309225ca963a38d` passes the entire
four-command gate and both uncached counted-RC language sweeps. It joins:

- `57a26e87`: omit linkage only for provably empty ownership frames, retaining
  physical/logical frame admission and caller pin scopes.
- `cdec9ff5`: preflight complete fresh constructors, retaining source guards
  through allocation and publishing the result in one infallible span.
- `d4bff2a1`: move a certified closed field owner through mutation and ordinary
  storeback, preserving real snapshots, pins, traps and arena semantics.

All joins are real two-parent merges. The only integration conflict was the
independent additions to `root_test.zig`; both test imports were retained.
The original dirty checkout, language `main` at `b292660a`, and the pending
devspeed merge remain untouched.

| Command | Result |
| --- | --- |
| Debug compiler install | 19/19 steps |
| `zig build test --summary all` | 94/94 steps; 2,295 executed tests pass |
| `zig build test-qbe --summary all` | 51/51 steps; 440/440 tests |
| `zig build test-qbe-build --summary all` | 29/29 steps |
| `zig build fmt-check --summary all` | 2/2 steps |
| Counted RC QBE language sweep | 892/892 assertions; 153 programs |
| Counted RC LLVM language sweep | 892/892 assertions; 153 programs |

The main gate reports 25,683 total test selections with 23,388 shard exclusions;
2,295 actually execute. These exclusions are distinct from the language sweeps:
each sweep has zero skipped tests, cached results, dropped files or unloaded
files, and zero failures. LLVM is invoked through the real `--release` backend.

The compiler is a Debug build. Its immutable copied binary at
`d9-rc-integration/.tmp-rc/install-field-frame-span/bin/mylang` has SHA256
`aee67f9abfe65b61a960eaf3390082d9c338553e5b086ad1cfc7723b933ab475`.
Both scripts check the exact source commit before and after execution. All
builds and guest builds use the shared build-slot wrapper, this worktree's
private cache and on-disk temporary storage. The four-command gate holds
`../.d9-closeout-gate.lock`; the separately counted sweeps use the frozen copy.

The field-transfer evidence additionally establishes that the unchanged Lox
N10 binary-tree case now completes correctly on both backends, with matching,
balanced ownership counters. Those single feasibility runs and the reduced
N4/N5 component measurements do not satisfy the full performance gate.

The complete 43-program-per-backend median-three instruction/RSS comparison
is running against this immutable compiler and the accepted GC baseline. The
preceding 30-program diagnostic showed substantial remaining overhead. Thus
Stage 4 is still incomplete: full performance acceptance, the ordinary RC
default transition, documentation and final validation remain required.

Evidence: [gate archive](../../experiments/d9-rc-field-frame-span-gate-20260927/README.md),
[field transfer](d9-rc-field-transfer-2026-09-27.md),
[empty frames](d9-rc-empty-frame-2026-09-27.md),
[fresh constructors](d9-rc-fresh-span-2026-09-27.md).
