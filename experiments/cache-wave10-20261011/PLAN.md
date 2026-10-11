# Wave 10 — Native shared-cache retention

Baseline: `19b920524` (Wave 9). This wave adds retention to the shared compiler
artifact and native test-success stores. The former proposed Wave 10, retained
warm validation and duplicate-work coordination, becomes Wave 11. This document
is an acceptance plan; results belong in `REPORT.md`.

The implementation must remain native and Python-free. Independent v2 namespaces
prevent collection from racing old v1 binaries that do not acquire leases.
Ordinary reads and publications hold shared leases through staging and per-key
publication-lock waits. Collection takes a nonblocking exclusive lease and
skips busy stores, with no server admission. Permanent namespace/lease locks
survive collection; crashed staging files and per-key locks can be reclaimed
only under exclusive ownership.

Default retention is 10 GiB for compiler records, 256 MiB for test records,
100,000 retained entries per namespace, no age expiration, and an hourly
opportunistic collection interval. These are soft budgets between scans. Verified
hits update last-use ordering without changing validity. Configuration persists
per namespace. Explicit `mylang cache gc` previews by default; `--apply` deletes.
`mylang cache configure` intentionally writes policy. Neither command adopts
legacy/unknown formats or creates a missing namespace.

Acceptance matrix:

- Deterministic LRU byte/entry eviction preserves the newest retained records;
  optional age uses last verified access, and zero budgets permit full eviction.
- Preview preserves artifacts, control files and lock inodes. Applied collection
  reports actual removals, retained bytes/counts, busy skips and unmet budgets.
- Configured policies persist across command processes; malformed/unsupported
  values fail explicitly. Automatic collection respects the throttle, retries
  skipped busy stores and remains bounded even with unknown entries.
- A held shared lease protects active reads, staged publication, and publication
  lock holders/waiters from collection. Process exit releases protection.
- Missing/corrupt records safely miss and refill after eviction; verified hits
  renew recency and corrupt records do not. A materialized private artifact
  remains independent of shared storage.
- Abandoned partials and per-key locks are collectible. Permanent locks, foreign
  filenames and symlinks remain protected. Incomplete inventories never claim
  satisfied budgets or perform a partial unsafe sweep.
- Real native command tests cover preview/apply/configure, active leases,
  compatibility refusals and operation with an empty `PATH`.
- Existing cross-worktree compilation and test-success qualification runs
  against v2 namespaces; report schemas and exact dependency admission remain
  unchanged. Legacy pruning must preserve retention-managed scratch caches.

All builds/tests use the pinned Zig through build-slot admission and the
worktree-private Zig local cache. The final verification inventory and Guardian
gate cover the frozen combined implementation. No timing measurement or speedup
claim is required, and Guardian feedback logging is not required.
