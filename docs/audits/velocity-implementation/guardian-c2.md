# Guardian C2 feedback

Task: C2 durable checked-body reuse across processes
Branch: `codex/velocity-c2`
Base: `86ffbb7c`

## What Guardian exercised

`zig build` runs the repository Guardian gate on every install. C2 changes were
exercised repeatedly while adding `src/semantic_store.zig` and the cache wiring.
The first runs reported:

- `type-size` growth for `semantic_cache.Cache`, `semantic_entry.Entry`,
  `semantic_store.Store`, `Statistics`, `StoredBody` and `StoredDiagnostic`;
- a divergent `default_max_bytes` constant against `frontend_cache.zig`;
- a repeated `diagnostic.zig` import string;
- cognitive complexity over the limit in `semantic_cache.remember`;
- `change-classification` and `error-path-test` because the new persistence
  behavior initially landed without a named regression.

Those were fixed before commit by grouping public fields into small nested
records, importing the diagnostic module once, extracting `persistFresh`, adding
the real C2 process/damage/eviction regressions, and using explicit
`UNTESTED-ERROR` waivers only for OOM cleanup branches already covered by the
existing cache-wide `FailingAllocator` scenario. Final `zig build` and all
focused gates pass Guardian with no waivers beyond those named branches.

## Feedback for later C-series work

1. The type-size ratchet made it cheaper to keep the public shapes small. C2 now
   nests `SourceRef` in `Entry`, `Root`/`Context`/`Limits` in `Store`, and
   `Retained` in `Statistics`; C3 should extend those nested records rather than
   adding another top-level field.
2. The `change-classification` check is useful: it forced the C2 process and
   failure-mode tests to land with the implementation instead of only in manual
   acceptance notes.
3. The `error-path-test` checker accepts named `UNTESTED-ERROR` waivers only when
   they explain the exact allocation-failure cleanup branch. That is the right
   level for cache internals; do not waive a decoded-entry validation failure.
4. Guardian correctly blocked the temporary `std.debug.print` probes used while
   diagnosing the initial entry-validation bug. Keep future persistence debugging
   in a separate `zig test`-only file or use the named miss counters.

## Exact integration/spec patch requested

C2 is implemented and verified but its public behavior is not registered in
`SPEC.md` or `src/features.json`, both outside this task's write ownership. The
integrator should add a behavior in the `SEMANTIC-CACHE` group, after
`SEMANTIC-CACHE-7`:

```text
- [SEMANTIC-CACHE-8] Ordinary checked bodies persist across compiler processes as versioned `semantic-cache-v1` entries. The durable header/checksum and payload carry only stable declaration identities, dependency contexts, source-region/body bytes and owned remappable checked trees; every decoded reference/range/tag is validated and remapped through C1R or treated as a miss. Only successful checks publish atomically, incompatible compiler/effects/runtime-ABI/flags/mutation-contract versions are isolated, damaged/truncated/oversized entries fall back fresh, and `--no-cache` performs no semantic reads or writes while preserving acceptance and diagnostics.
```

The current docs updated by C2 are `docs/tooling/caches.md`,
`docs/tooling/work-report.md` and `docs/experiments/incremental-contract.md`.
