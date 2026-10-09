# Joined plain-value, loan and loop correctness checkpoint

Frozen source `a9eae92edb41f845a1caa9e8562cddd364117897` passes the complete
four-command gate and both uncached counted-RC language sweeps. It joins three
independently validated performance changes through real two-parent merges:

- `5237aebc`: retain registered plain bytes without generic ownership traversal,
  preserving region refusal, overlap fallback and queued finalizer behavior.
- `6ce92814`: borrow adjacent inline record fields only until their immediate
  scalar projection; admit scalar list-length readers to the existing proof.
- `4f7eeea9`: hoist uniqueness only after proving a fresh plain-list root's real
  physical ownership and its exact temporary releases, including external entries.

The root compatibility fix `1110e8c9` also joins: historical native manifests
without a runtime tag always decode as GC, independently of a future process
default. Explicit RC and counted RC replay still refuse those historical artifacts.

| Command | Result |
| --- | --- |
| Debug compiler install | 19/19 steps |
| `zig build test --summary all` | 94/94 steps; 2,300 executed tests pass |
| `zig build test-qbe --summary all` | 51/51 steps; 440/440 tests |
| `zig build test-qbe-build --summary all` | 29/29 steps |
| `zig build fmt-check --summary all` | 2/2 steps |
| Counted RC QBE language sweep | 911/911 assertions; 156 programs |
| Counted RC LLVM language sweep | 911/911 assertions; 156 programs |

The main gate reports 25,743 total selections with 23,443 shard exclusions;
2,300 actually execute. Both language sweeps have zero failures, skips, cached
verdicts, dropped files and unloaded files. LLVM uses the actual `--release`
backend. The imported loop and projection evidence verifiers also pass from
the integration checkout.

The compiler is a Debug build. The immutable copy at
`d9-rc-integration/.tmp-rc/install-plain-loan-hoist/bin/mylang` has SHA256
`5fb1935f74b11dd59bb6f21dbbe1f98f2637bd3a80c7504aaab933bcaddedb46`.
Both scripts check exact HEAD and a clean tracked tree before and after their
runs. All builds use the shared build-slot wrapper, a private cache and on-disk
temporary storage. The full gate holds `../.d9-closeout-gate.lock`.

Component evidence shows lower instruction counts on unchanged full workloads:
about 41% for allocation churn from plain retain, 29–31% for schematic from
plain field borrowing, and 88.5% QBE / 95.9% LLVM for fannkuch from loop checks.
Those comparisons have different isolated candidate compilers; their reductions
must not be multiplied or treated as this checkpoint's full performance result.
The separate complete corpus sweep continues against frozen predecessor `e926d1e1`.
Its measured rows still exceed the acceptance limits, including Lox binary trees.

Stage 4 remains incomplete. Complete instruction/RSS acceptance, the ordinary RC
default transition, documentation and final validation remain required. GC remains
the default, arenas stay available, and the original dirty checkout, language
`main` at `b292660a`, and the pending devspeed merge remain untouched.

Evidence: [gate archive](../../experiments/d9-rc-plain-loan-hoist-gate-20260927/README.md),
[plain retain](d9-rc-plain-retain-2026-09-27.md),
[plain projections](d9-rc-plain-fields-2026-09-27.md),
[fresh loop roots](d9-rc-fresh-owned-loops-2026-09-27.md).
