# Joined append, borrowed-helper and scalar-loop correctness checkpoint

Frozen source `468bd8e536b0e088ff71291cb9a3c92db8ebf448` passes the full
four-command gate and both uncached counted-RC language sweeps. Real two-parent
merges add three independently reviewed and measured changes to green `636524b8`:

- `3bc671b7`: append scalar elements directly when registered layout, available
  capacity, generation and callback conditions permit; retain the original
  growth and refusal path.
- `b2a251c3`: compose bounded borrowed-return certificates through independently
  proved callees and exact argument anchors, including cache dependencies.
- `280ef314` with evidence `209d4404`: admit the existing guarded numeric loop
  version when a bounded proof excludes every explicit or implicit ownership
  action, preserving original checked and step-accounted paths.

The joined diagnostic/profile archive `f89aec29` also lands as evidence only.

| Command | Result |
| --- | --- |
| Debug compiler install | 19/19 steps |
| `zig build test --summary all` | 94/94 steps; 2,315 executed tests pass |
| `zig build test-qbe --summary all` | 51/51 steps; 440/440 tests |
| `zig build test-qbe-build --summary all` | 29/29 steps |
| `zig build fmt-check --summary all` | 2/2 steps |
| Counted RC QBE language sweep | 931/931 assertions; 160 programs |
| Counted RC LLVM language sweep | 931/931 assertions; 160 programs |

The main gate's 25,923 selections include 23,608 shard exclusions. Both RC sweeps
have zero failures, skips, cached verdicts, dropped files and unloaded files.
LLVM uses the actual `--release` backend. Whole-tree Guardian passes all 88 checks
without a baseline waiver. Imported component evidence verifiers pass from the
integration tree.

The immutable Debug compiler is
`d9-rc-integration/.tmp-rc/install-append-compose-scalar/bin/mylang`, SHA256
`082edf36c3b1370debeccb4bdcbf3069fbf7829ad1852e8a7d0d5d7f2a34c67e`.
Source and tracked HEAD stayed frozen through the full gate and both sweeps.
The [archive](../../experiments/d9-rc-append-compose-scalar-gate-20260927/README.md)
preserves raw receipts, scripts and hashes.

This is correctness acceptance for the combined checkpoint. Complete Stage 4
performance acceptance is still open: exact predecessor measurements include
Lox VM instruction ratios of 117.54× QBE and 207.36× LLVM against accepted GC.
Individual component improvements cannot be multiplied into a combined verdict.
The next work addresses broad record publication, conservative hold propagation
and bounded runtime retain traversal. The ordinary RC default transition,
documentation close-out and final combined validation remain required. Arenas,
the GC default, language `main` at `b292660a`, and the pending devspeed merge stay
unchanged.
