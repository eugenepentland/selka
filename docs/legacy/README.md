# Removed features

These pages describe language and tooling surfaces that no longer exist. They are
kept so that older sources, audits and evidence files remain readable, not as a
description of the current language. Every page carries a removal banner.

Three removals are recorded here:

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
- **Brace syntax** (removed 2026-09-13). `fn`/`let`/`let mut`/`struct`/`new`,
  `T { field: value }` record literals, `alias::name` qualification, `f::<T>(x)`
  turbofish, `cast<T>(x)`, `//` and `/* */` comments, bare `{ }` scope blocks,
  match expressions, `true`/`false`/`unit`, `else if` and `a..b` ranges.
  Indentation, `def`/`class`, `T(field=value)`, `alias.name`, `f[T](x)`, `T(x)`,
  `#` comments, `match`/`case`, `True`/`False`/`None`, `elif` and `range(a, b)`
  are the surface; see [../python-syntax.md](../python-syntax.md). `mylang
  migrate`, which converted between the two, went with it.

`src/features.json` records all three under its `removed` key with the same date,
alongside the narrower spellings each removal took with it.
