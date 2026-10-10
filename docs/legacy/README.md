# Removed features

These pages describe language and tooling surfaces that no longer exist. They are
kept so that older sources, audits and evidence files remain readable, not as a
description of the current language. Every page carries a removal banner.

The broad removals recorded here:

- **Explicit storage tier** (removed 2026-09-13). `buffer`/`pool`/legacy `list`
  declarations, the `allocator` capability and entry parameter, `&T`/`&mut T`
  references and `&[]T`/`&mut []T` slices, lexical `borrow` scopes, `from`
  return-provenance, legacy `arena parent as name { }` scopes and `reset_arena`,
  and every standard module built on them. Garbage-collected managed collections
  (`list`, `str`, `dict`, `bytes`) and `with arena()` regions replace them; see
  [../managed-memory.md](../managed-memory.md) (arenas are [retired](../managed-memory.md#retired-arenas) too).
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
- **Bytecode interpreter** (removed 2026-09-14). The interpreter and its
  project-evaluation commands were removed. QBE native code is the only runtime:
  `mylang run`, `run-project` and `test` build a program and execute it in a child
  process. Bytecode remains the compiler's internal IR and `dump-bytecode` still
  prints it; see [../current-language.md](../current-language.md).
- **Opt-in mutation markers** (removed 2026-09-21). The `mutates(a, b)` clause,
  the `&argument` call-site marker, the `--mutation-markers` flag and the
  advisory `W_MUTATES_MISSING` warning. A parameter a function writes through is
  now declared `name: mut T` and every argument bound to one is written `mut
  argument`, with the rule always on; writing `mutates(...)` or `&x` reports
  `E_REMOVED_SPELLING` naming the replacement, and `--mutation-markers` is
  rejected on every command. See [../effects.md](../effects.md).

- **The old back end** (removed 2026-10, new-core stage S5). QBE and its IL
  emission, the bytecode IR, the QBE-to-LLVM translator, the tracing collector,
  two-count reference counting, runtime selection (`--gc-runtime`, `--gc-stress`,
  `--rc-runtime`), legacy sharing (`class`, `Cell`, `--legacy-sharing`), arena
  regions (`with arena()` is rejected with `E_ARENA_REMOVED`),
  host functions (`host def`, `mylang invoke`, `--library`, `--provider`,
  `--link-library`, `--library-path`), the host applications `board-trial`,
  `schematic-svg` and `mylang-io`, per-module `compile-module`/`link-modules`
  builds, and the test runner's `--bench*`, `--pure-skip`, `--diagnostics` and
  `--max-calls`. The new core (Core IR to LLVM through `zig cc`) builds, runs and
  tests every program; see [../tooling/native-build.md](../tooling/native-build.md).
  The pages for the retired host tooling moved here: [invoke](invoke.md),
  [invocation](invocation.md), [packed host calls](packed-host-calls.md), [the byte
  runner](byte-runner.md) and [bulk byte I/O](byte-io-bulk.md).

`src/features.json` records every removal under its `removed` key with its date
and the narrower spellings it took with it; that list is the authority.
