# Joined receiver-storage and scalar-update checkpoint

Frozen source `7d68202d59cf834bf9649fd77df2000f548ffec9` passes all four
required gates and both uncached RC sweeps. It joins `29294450` (certified unused
receiver buffers), `8a875c49` (plain scalar field replacement), and the
diagnostic-only Lox clone evidence `61374874` with the previously green source.

| Check | Result |
| --- | --- |
| Debug compiler build | 19/19 steps |
| Main gate | 94/94 steps; 2,285 executed tests |
| QBE gate | 51/51 steps; 439/439 tests |
| Native build gate | 29/29 steps |
| Formatting | 2/2 steps |
| Uncached counted RC, each actual backend | 875/875 assertions across 150 programs |

Both RC sweeps have zero failures, skips, cached results, dropped files or
unloaded files. LLVM uses O3/full LTO. The main runner's 23,278 skipped entries
are exclusions from its shard partition. Source stayed frozen throughout;
the shared gate lock, build slots, on-disk scratch and a worktree-local cache
were used. Current `main` (`b292660a`) is already an ancestor.

The immutable Debug compiler SHA-256 is
`7decd168a86694b21d9c69eda88f7097a351e161b033c18c8270225129460b48`.
[Raw receipts](../../experiments/d9-rc-scope-scalar-gate-20260927/README.md)
record every gate and complete sweep output. This checkpoint establishes
correctness evidence; isolated speedup ratios are not multiplied or treated as
full-corpus acceptance.

The required 43-program-per-backend instruction/RSS gate remains open. A separate
30-program parity/schematic diagnostic uses this frozen compiler to prioritize
remaining work; it excludes Lox and cannot satisfy acceptance. Empty-frame,
closed-field ownership and fresh-constructor candidates remain isolated.

After performance acceptance, Stage 4 still requires making RC the ordinary
value-runtime default, updating the runtime documentation/contracts, and
validating the final combined state. GC remains the default at this checkpoint;
arenas and the explicit legacy-sharing compatibility behavior remain supported.
No Stage 5 implementation or main/remote changes are included.
