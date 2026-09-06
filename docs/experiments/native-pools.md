# Native pools

The C backend now supports pool acquisition, queries, insertion, snapshot reads,
replacement, removal, clear, and nominal handle equality. Handles contain pool
identity, slot, and generation in immutable storage; they do not retain graph
owners. Removing or clearing nodes invalidates their old handles. Exhausted slot
generations retire their slots, and pool identities never wrap.

Pools share the VM default quotas: 64 live owners, 4096 slots per pool, and 16384
reserved slots in total. Zero-capacity pools consume owner quota. Clear retains
reserved storage; owner destruction returns quota. Root and arena allocators own
registry backing while immutable node snapshots use independent storage. Arena
reset remains blocked while a pool owns its backing, including an empty pool.

The existing pool and combined arena/pool examples produce their expected native
results (52 and 50). Debug and ReleaseFast pass all 28 build steps and 591 Zig tests
(531 core, 60 CLI). Native acceptance covers 2,616 comparisons across 83 single-file
and 15 module fixtures. The added module case was also rerun separately in both
compiler modes, checking exported pool/handle bundles, partial field transfer, and
arena ownership across imports.

Sanitizer memory acceptance passes 468 injected allocation failures. A
20,000-iteration pool lifecycle loop keeps live heap bounded. Quota tests cover
owner, per-pool, and total-slot limits; handle tests cover equality, foreign pools,
stale generations, removal, and clear. Formatting and all 88 Guardian checks pass
without frozen violations. A shared typed-result emission helper now serves pool
operations, buffer mutations, and arena reset.

[Native clock/random providers](native-providers.md) now use explicit C adapters.
Environment and external-resource native operations remain pending, alongside the
wider roadmap.
