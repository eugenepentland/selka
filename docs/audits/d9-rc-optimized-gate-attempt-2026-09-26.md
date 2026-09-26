# RC optimization integration attempt — 2026-09-26

Frozen source `743fea73` and Debug compiler SHA-256 `e2673d24ef533a98eedce0243e38fc0126ea0555c99ad80ae8e475689da05625` pass **762/762 actual RC language assertions per backend**, across 133 programs with zero cached, skipped, dropped or unloaded. LLVM uses `--release` (O3/full LTO).

The required integration gate remains **failed**:

| Command | Result |
|---|---|
| `zig build test --summary all` | 91/94 steps, 2,225 passing executed tests, two failures |
| `zig build test-qbe --summary all` | 48/51 steps, 436/437 tests |
| `zig build test-qbe-build --summary all` | 29/29 steps |
| `zig build fmt-check --summary all` | 2/2 steps |

The 22,640 main-gate skipped tests are shard exclusions. The main failures are existing dictionary and set iteration-mutation trap tests (`python_values_test` and `sets_test`). QBE golden replay finds the same contract violation in `qbe_managed/9a7979d53a36d7a8114b24b6e6a2767c`: expected `R_LIST_ITERATION_MUTATION`, but execution returns normally. The other 230 replayed golden cases match. Subsequent focused reproduction confirms the dictionary/set loops also miss their required trap in RC mode. Passing positive language assertions therefore does not establish trap parity.

Earlier unit-mock and mutable-parameter rebinding failures are fixed on this source. Iteration owner identity requires a separate correction; expected traps are retained. The last complete green checkpoint remains `3f300771`. All four command logs, both RC sweeps and identities are preserved under `evidence/d9-rc-optimized-attempt-*`.
