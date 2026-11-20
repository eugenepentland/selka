# Joined private-loan correction and constructor gate

Frozen integration `2b42a543c4245b3bfe5dff863ac69779f45dc2b9` passes all four
required gate commands and both uncached experimental RC sweeps. The Debug
compiler SHA-256 is
`0fcd8e4a799a76c9a7405812fa3db2db28c8e38cabd82a526656c54f4df53841`.

| Check | Result |
|---|---|
| `zig build test --summary all` | 94/94 steps; 2,266 executed tests |
| `zig build test-qbe --summary all` | 51/51 steps; 438/438 tests |
| `zig build test-qbe-build --summary all` | 29/29 steps |
| `zig build fmt-check` | 2/2 steps |
| Uncached RC QBE | 851/851 assertions across 146 programs |
| Uncached RC LLVM (`--release`) | 851/851 assertions across 146 programs |

Both RC sweeps have zero cached, failed, skipped, dropped or unloaded results.
The main runner's additional 23,069 exclusions are shard routing, not executed
tests. All gate commands used the tree's own cache and on-disk scratch under the
serialized D9 gate lock; the source commit was checked before and after execution.

This joins the [private-loan mutable-path correction](d9-rc-place-loans-2026-09-26.md),
[fresh-constructor proof](d9-rc-fresh-constructor-proof-2026-09-26.md),
[journal initialization improvement](d9-rc-journal-init-2026-09-26.md), descriptor
cache and ABI3 flat-destruction audit. The earlier augmented-field abort is fixed;
its original failed sweeps and the rejected whole-parent ownership candidate are
retained in their original evidence directories.

[Raw logs, JSON and exact scripts](../../experiments/d9-rc-place-constructor-gate-20260926/README.md)
identify this checkpoint independently of later changes. Supplemental golden
replay continues on immutable `19e16e1d`; new nbody refinements are being combined
separately. WP-4 performance acceptance is still open and GC remains the default.
