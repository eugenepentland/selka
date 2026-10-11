# Wave 11 — Retained validation and concurrent work coordination

Baseline: `5c4d4235f` (Wave 10). This is the final wave in the current cache
roadmap. Results and limits belong in `REPORT.md`.

Keep validated input inventories and content identities alive across sequential
developer requests in an explicit foreground session. Reuse requires live clean
watches and complete path-identity revalidation. Retain bounded process-local
state; eviction, watcher loss, reset and restart require fresh snapshots. An
active request stays attached to its original revision after an edit. The
session dispatches verification, fuzz and performance coordinators with their
existing action contracts and admission rules. JSON Lines carries requests and
completion status; tool output stays on stderr. It is developer tooling: source
builds and every installed compiler command remain Python-free.

Use exact-key process claims for native object compilation, linking and eligible
shared test executions. Acquire batches in sorted unique order, recheck receipts
after waiting, and publish only after input validation. Preserve parallel unit
compilation, cache bypasses, forced tests and verification semantics. Different
keys remain independent. Process exit releases claims; failures publish no
success. Shared retention leases protect claim owners and waiters; namespace
leases protect native objects until linking/output publication completes. The
legacy pruner must honor these leases, preserve permanent lease inodes and
reclaim idle per-key locks only under exclusive ownership.

Acceptance:

- A warm session reuses complete watched snapshots with zero repeated content
  hashing and directory enumeration for unchanged scopes; reports count actual
  new work. Metadata validation and provider resolution remain observable work.
- Source edits, membership changes, aliases, restored timestamps/bytes, watcher
  failure, process changes, reset and bounded eviction never admit stale state.
  Unaffected declared scopes remain reusable.
- Fully reusable verification requests need no server admission. Required fresh
  cohorts still execute. Edited cohorts and explicit fresh requests retain their
  existing qualification, including failures and edits while queued/running.
- Session protocol rejects malformed/oversized requests and internal worker
  entry points. Loaded implementation/runtime changes require a restart.
  Cancellation, command failure and end-of-input release watches and resources.
- Real concurrent native processes demonstrate one successful computation for
  the same missing key, independent different keys, ordered overlapping batches,
  receipt recheck after waiting, forced failures and owner termination recovery.
- Collection skips active native work and waiters. Legacy cleanup cannot delete
  active claim inodes or objects leased through linking; idle disposable data remains
  collectible.
- Qualification uses the pinned Zig, build-slot admission, a private Zig local
  cache and disk TMPDIR. Full inventory verification and Guardian cover the
  frozen combined implementation. Use work counters rather than timing claims;
  timing runs must not overlap a gate.

This wave does not promise zero validation, a persistent compiler AST daemon,
remote distributed execution or resuming arbitrary application stacks. Existing
native incremental sessions and application durable-step contracts retain their
separate ownership and correctness boundaries.
