# Joined flat-loan and borrowed-loop correctness checkpoint

Frozen source `636524b81562e30285b15e297078fac24ffccb58` passes the full
four-command gate and both counted-RC language sweeps. It adds two independently
reviewed and measured optimizations to the green `a9eae92e` checkpoint through
real two-parent merges:

- `c0a5904a`: use registered bounded physical layouts for lifetime loans and
  releases, preserving dynamic finalizer refusals, sequential prefix acquisition,
  rollback, queued callback ordering and metadata reentry.
- `3b867d50`: prove borrowed returns through bounded read-only loops using a
  converged anchor analysis and deterministic certificate dependencies.

The composed plain-retain/fresh-loop performance evidence `5ba0d76e` also joins.
It records its own compiler identity and does not establish this checkpoint's
complete performance acceptance.

| Command | Result |
| --- | --- |
| Debug compiler install | 19/19 steps |
| `zig build test --summary all` | 94/94 steps; 2,305 executed tests pass |
| `zig build test-qbe --summary all` | 51/51 steps; 440/440 tests |
| `zig build test-qbe-build --summary all` | 29/29 steps |
| `zig build fmt-check --summary all` | 2/2 steps |
| Counted RC QBE language sweep | 916/916 assertions; 157 programs |
| Counted RC LLVM language sweep | 916/916 assertions; 157 programs |

The main gate's 25,803 selections include 23,498 shard exclusions: 2,305 tests
actually execute. Both language sweeps have zero failures, skips, cached verdicts,
dropped files and unloaded files. LLVM uses its actual `--release` backend.
Whole-tree Guardian passes without a baseline waiver.

The immutable Debug compiler at
`d9-rc-integration/.tmp-rc/install-flat-borrow-loops/bin/mylang` has SHA256
`32e272cf75968d2fe913f636739d4b11d83701448e515f057dfa87f1ed8cba46`.
The source and tracked tree remained frozen throughout the gate and sweeps.
The [archive](../../experiments/d9-rc-flat-borrow-loops-gate-20260927/README.md)
contains raw logs, scripts, hashes and exact sweep counts.

Stage 4 is still incomplete. The complete instruction/RSS requirements remain
open, followed by the ordinary RC default transition, documentation and final
combined validation. Newer matched samples still show substantial overhead in
schematic and Lox VM workloads. GC remains the default and arenas stay available.
The original dirty checkout, language `main` at `b292660a`, and pending devspeed
merge remain untouched.
