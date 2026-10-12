# A01 complete tuple frontend checkpoint

Base: `2d471045543d74ea49014062c226b583d2963f5a`. Proposed commit: recorded by coordinator after commit.

Owned production: `sema_places.zig`, `origins.zig`, `effects.zig`, `value_semantics.zig`, `duplicates.zig`; unique frontend/Core tests and this evidence directory. Coordinator authored the two root-test imports. Shared `typed.Store` remains an unstaged validation prerequisite from A08 `3bbff3a61db91c4f8105749cefc1652159a2d162`; coordinator integrated it as `8f5206e4e`. The authorized `dictionary_views.zig` overlay and old guest migrations are excluded.

The producer stages every tuple field before target effects. Provenance consumers retain the whole RHS origin, and exact duplicate keys distinguish ignored field positions. Marker shape and consumer tests pass; this checkpoint is **not native feature qualification**.

Commands (shared admission, source dev-env first):

```sh
scripts/build-slot.sh build "$ZIG" build test-core -Dtest-filter='A01 complete tuple staging records exact' -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
scripts/build-slot.sh build "$ZIG" build test-units -Dtest-filter='A01 tuple staged' -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
```

Statuses: structural1/1; consumer10/10 (three named + seven always-run blocks); Guardian88. Raw logs are compressed under `raw/`; `manifest.json` records exact test binary and source identities. `origin-test-1` is a retained invalid build-step attempt; `origin-probe` is a retained CLI spelling failure. Corrected before/after class probe refuses E_VALUE_CLASS in both compilers and is not an admitted-source regression.

Outstanding owners: A07 Core/checker and typed dump, A08 cache qualification, coordinator integration. Full native five-mode/provider/Result/optional fixture and seven negative controls remain to run. The RC borrowed-input control is temporary evidence while both modes exist, not a permanent post-retirement RC contract. Final C1/C2/C3 qualification must rerun on exact integrated artifacts. No timing/RSS/performance saving claimed here.
