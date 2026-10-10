# Wave 6: shared storage, retention and warm validation

Baseline: `b2de7b2f0` (Wave 5), branch `codex/selka-cache-wave6`.
Local main remains `1d202d41b`, already an ancestor of this branch; this clone
has no configured remote. The dirty primary checkout is outside this work.

Add an explicit, versioned local shared evidence store to the developer
verification, fuzz and Juice coordinators. Share immutable blobs and exact
action receipts. Keep workspace inventories, snapshots, runs and fuzz corpus
catalogs private. Preserve every existing path and execution dependency in
action keys. Existing native unit/runtime objects already share their separate
content-addressed store; packed frontend indexes remain private.

Protect store operations and complete coordinator use with process leases.
Garbage collection takes an exclusive nonblocking lease, skips active stores,
honors persistent retention pins and deterministic-conflict evidence, and
reports when protected data prevents satisfying a disk budget. Keep the global
lease inode permanent; reclaim per-key locks only with proven exclusive ownership.
Publish atomically; reject foreign formats explicitly. Preserve
the first valid physical observation, while contradictory deterministic
outputs invalidate the action and raise an investigable error.

Reduce warm validation work without metadata-only trust. A bounded in-process
digest session can reuse reads from overlapping snapshots while their original
watches remain active and clean. A tiny optimized native SHA-256 module removes
Debug's unoptimized hashing overhead while still streaming every input byte.
One-shot commands remain correct without a daemon. This wave does not introduce
remote trust or application journal durability.

Qualify multiprocess publication, concurrent GC, process death, retained roots,
conflict poisoning, corruption, eviction, version mismatch, revert and exact
receipt sharing. Exercise timestamp-restored edits, event loss and closed
watchers for the digest session. Record actual hash work and end-to-end no-op
cost, including memory; run timing on reserved CPUs without concurrent gates.
Run the complete verification inventory and format checks before committing.
