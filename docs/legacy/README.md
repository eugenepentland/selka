# Removed features

These pages describe language and tooling surfaces that no longer exist. They are
kept so that older sources, audits and evidence files remain readable, not as a
description of the current language. Every page carries a removal banner.

Two removals are recorded here:

- **Explicit storage tier** (removed 2026-09-13). `buffer`/`pool`/legacy `list`
  declarations, the `allocator` capability and entry parameter, `&T`/`&mut T`
  references and `&[]T`/`&mut []T` slices, lexical `borrow` scopes, `from`
  return-provenance, legacy `arena parent as name { }` scopes and `reset_arena`,
  and every standard module built on them. Garbage-collected managed collections
  (`list`, `str`, `dict`, `bytes`) and `with arena()` regions replace them; see
  [../managed-memory.md](../managed-memory.md) and [../arenas.md](../arenas.md).
- **C backend** (removed 2026-09-13). `emit-c`, `emit-project-c`, `src/native.zig`
  and the C-only runtime units. QBE is the only native backend; see
  [../experiments/incremental-qbe.md](../experiments/incremental-qbe.md) and
  `zig build test-qbe`.

`src/features.json` records both under its `removed` key with the same date.
