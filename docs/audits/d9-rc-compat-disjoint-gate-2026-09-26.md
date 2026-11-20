# RC compatibility and transfer checkpoint — 2026-09-26

Frozen source `17750e3615feb57d6fbb8c5eefaa5615a92dc025` passes every required
gate command after narrowing the live-view classifier to preserve existing
legacy class borrow explanations. The same source includes the arena-region and
file-error cleanup corrections, small-allocation fast path and proven-disjoint
transfer optimization.

| Check | Result |
|---|---|
| Debug install | 19/19 steps, Guardian88 |
| Main gate | 94/94 steps, 2,239 executed tests passed |
| QBE gate | 51/51 steps, 437/437 tests passed |
| Native-build gate | 29/29 steps |
| Formatting | 2/2 steps |

The main suite's 22,772 reported skips are shard exclusions. Compiler SHA-256:
`c2c1b171a2248fcb8b942b623388da61424bb8add2b78125c595c17fa74cd084`.
[Commands and complete logs](../../experiments/d9-rc-compat-disjoint-gate-20260926/identity.json)
are retained with this exact source identity.

The [preceding attempt](d9-rc-correctness-gate-2026-09-26.md) at `dab80d84`
preserves the failed class explanation expectation and both successful 792-test
uncached RC sweeps. Those sweeps belong to that earlier source. The disjoint
transfer slice separately passed 131 actual assertions per backend, and the
compatibility correction passed 180 assertions across GC stress/RC and both
backends. No new complete RC sweep is attributed to this checkpoint.

This gate does not close WP-4. Semantic copy history still diverges from GC on
live-view identity cases, and measured instructions remain far above acceptance.
The ABI3 loan/history implementation is private work; compact journals and
null-leaf return optimization are separate pending slices. GC stays the default.
