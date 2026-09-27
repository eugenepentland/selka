# Joined argv, module and return correctness checkpoint

Frozen source `89e79524ef15e102c5f76e644e9bb97fbab0f3f8` passes the complete
four-command gate and both uncached experimental-RC guest sweeps. It combines
the module callable correction, native argv lifetime fix, empty-local journal
proof and fresh constructor return suffix with the earlier nbody refinements.

| Check | Result |
| --- | --- |
| Debug build | 19/19 steps |
| `zig build test --summary all` | 94/94 steps; 2,281 executed tests |
| `zig build test-qbe --summary all` | 51/51 steps; 439/439 tests |
| `zig build test-qbe-build --summary all` | 29/29 steps |
| `zig build fmt-check` | 2/2 steps |
| Uncached counted RC, QBE | 871/871 assertions; 149 programs |
| Uncached counted RC, LLVM O3/full LTO | 871/871 assertions; 149 programs |

Both sweeps report zero failures, skips, cached verdicts, dropped programs or
unloaded programs. The main summary's 23,234 skipped entries are shard exclusions,
not missing selected tests. The originally dropped plain-replacement file now
loads and executes. The old negative `685e2631` receipts remain unchanged.

The immutable Debug compiler SHA-256 is
`bcdf4c7dde9385a1d4b7306a35a5178fdbb04fecb55487a7759993b1574e1dae`.
The source stayed frozen through all checks, was already descended from current
`main` (`b292660a`), and used the shared gate lock, build slots and on-disk scratch.
The [receipts](../../experiments/d9-rc-argv-return-gate-20260927/README.md)
record scripts, full output, identities and raw sweep JSON.

The separate [historical golden replay](d9-rc-history-flat-goldens-2026-09-27.md)
also completes 462 selected outcomes on immutable `19e16e1d`; it does not claim
to test this newer compiler. The individual argv slice additionally proves exact
cleanup on normal returns, capability denial and traps, with sanitizer controls.

This is correctness evidence, not WP-4 acceptance. Full-corpus instruction and
peak-RSS requirements remain unmet/unmeasured. Further performance candidates
are isolated from this checkpoint. GC remains the default, WP-5 remains design
work only, and neither `main` nor the separate devspeed merge was changed.
