# Wave 10 — Shared native cache retention

Branch `codex/selka-cache-wave10`, based on Wave 9 commit `19b920524`.

## Result

Shared compiler artifacts and ordinary native test successes now have configurable
native retention. `compiler-artifacts-v2` and `native-tests-v2` isolate the new
lease protocol from legacy v1 producers. Existing shared-root environment variables
and flags continue to select the root; old v1 namespaces are left untouched.

Default policies retain up to 10 GiB of compiler records or 256 MiB of test records,
with 100,000 entries per namespace, least-recently-used eviction, no age expiry,
and an hourly automatic collection interval. Collection is opportunistic on open,
so the budgets are soft between successful scans. Verified accesses refresh
recency without changing content admission. Persistent policy is per namespace.

The installed Python-free commands are:

```bash
mylang cache gc --shared-cache-dir DIR --kind compiler
mylang cache gc --shared-cache-dir DIR --kind compiler --apply
mylang cache configure --shared-cache-dir DIR --kind compiler --max-bytes 21474836480
```

Use `--kind tests` for native test receipts. `gc` previews by default; one-time
GC overrides do not change policy. `configure` intentionally persists it. JSON
reports expose known inventory, proposed/actual removals, retained entries/bytes,
active-store skips, incomplete inventory and unmet budgets.

## Concurrency and compatibility

Storage operations own shared leases through reads, staging, hashing and waiting
for per-key publication locks. Collection takes a nonblocking exclusive lease
and skips active operations. Builds and tests hold no exclusive retention lock,
and collection requests no server build/gate slot. Process termination releases
leases automatically. The collector preserves permanent namespace locks while
reclaiming abandoned partials and per-key locks under exclusive ownership.

Inventories stop at one million visited entries, including unknown names.
Incomplete inventories perform no deletion. Unknown entries and symlinks remain
protected and cause an unmet-budget report. Counts cover recognized files rather
than filesystem allocation overhead; permanent format/policy/lock overhead is
excluded. Native retention has no pin protocol. The separate developer evidence
collector and its pins are unchanged. Legacy pruning preserves scratch directories
that contain native retention locks.

Evicted/corrupt records miss and refill. Private materialized executables do not
depend on the continued presence of shared blobs. Old v1 stores require manual
idle-only cleanup; neither the new native collector nor the Python collector
adopts them. No application-journal or power-loss durability claim follows.

## Qualification

The acceptance matrix is in `PLAN.md`. `qualification-summary.json` records
focused checks and their revision limits. Focused native retention, compiler
store, receipt-store and CLI tests passed, including empty PATH, actual compiler
eviction/refill, automatic throttling, busy leases, child termination, corruption,
legacy-format refusal and policy persistence. The four developer retention CLI
checks also passed, including preservation by the legacy pruner.

The combined installed compiler passed all 88 Guardian checks and all 14 install
steps. `source-hashes.json` records its exact input files and executable digest.
Final full-inventory verification passed all **42 selected groups** and
**126/126 build steps**, with `inputs_stable: true`. The Zig runner reported
**2,743 executed tests passed**; its larger denominator includes 24,772 shard
filter skips, not omitted verification groups. The complete gate also covers
language tests, documentation examples and the developer script suites.
`verification-final.json` and `verification.log` retain the final evidence.

The verified installed compiler SHA-256 is
`6c99fae295f2a3464100c084837ef9dc365ddd4870004835feccf7b3919d4bb2`.
No extra warm gate or isolated timing experiment was run.

## Next wave

The prior warm-validation and duplicate-work coordination proposal is now Wave 11.
No isolated performance measurement or new latency claim was made in this wave.
