# S2-La corpus dependency audit

Audit date: 2026-10-05. Compiler checker: `zig-out/focus/mylang` after the
receiver rule included the complete collection method vocabulary, including byte-buffer mutators. Read-only `fix --check`
diagnostics are recorded in `audit-examples-final.json`, `audit-bench-final.json`, and
`audit-benchmarks-final.json`; none contains `E_MUTATION_OVERLAP`. A source scan of
`examples/`, `bench/`, and `benchmarks/runtime/` found no assignments rebinding
whole list/dictionary/set parameters declared `mut`.

The canonical external Lox port is branch `bench/lox-mylang`, source directory
`/home/epentland/ai/canopy/mylang/.tmp/lox-bench/wt-mylang/benchmarks/lox/ports/mylang`.
It uses the earlier `class` spelling and does not check against this base, so
this portion is a source audit. No Lox source was changed. No whole mut
collection parameter assignment was found. Three receiver dependencies in
`resolver.my` require explicit call-before-update migration:

```python
# Original line 195
r.program.functions[index].slot_count = end_scope(mut r)
# Proposed migration
slot_count = end_scope(mut r)
r.program.functions[index].slot_count = slot_count

# Original line 251
r.program.stmts[id] = ast.Stmt.block(replace(node, slot_count=end_scope(mut r)))
# Proposed migration
slot_count = end_scope(mut r)
r.program.stmts[id] = ast.Stmt.block(replace(node, slot_count=slot_count))

# Original line 259
r.program.functions[index].slot = declare(mut r, name_ref, name.line, name.start, name.length)
# Proposed migration
slot = declare(mut r, name_ref, name.line, name.start, name.length)
r.program.functions[index].slot = slot
```

Each original receiver descends from `r`, while its evaluated call passes the
entire root `mut r`. These are exact prefix overlaps. The three findings were
reported to the coordinator, and dependent implementation/gates were paused
under the package's stop-and-report requirement. The snippets above are a
reviewable proposal only.

The user explicitly approved continuing Wave A with this documented external
Lox migration. Implementation resumed after that approval. The canonical Lox
checkout remains unchanged.

The discovery gate additionally exposed the same rule in the historical,
pre-marker Lox migration fixture (`test/fixtures/fix-migration/lox/heap.my:403`).
A read-only comparison confirms the canonical external source also has this
call at `heap.my:300`:

```python
blacken(mut rt, rt.marker.gray.pop())
# Proposed migration
gray = rt.marker.gray.pop()
blacken(mut rt, gray)
```

The pop receiver descends from `rt`; the evaluated `mut rt` argument overlaps
it by prefix. Only the internal historical fixture was migrated, preserving
its 91 mutation-marker edits. This fourth external occurrence was reported
and falls within the user-approved documented-migration disposition. The
canonical external checkout remains unchanged.

The exact-base compiler captured at
`codex-new-core-s2-integration/.mylang-cache/wave-a/baseline/mylang`
already aborts when a mutation or retained-value origin needs parameter position
16 (the seventeenth parameter). The three retained logs
`wide17-exact-base.log`, `wide17-readonly-exact-base.log`, and
`wide17-str-exact-base.log` show the same `origins.Origin.fromPosition` narrowing
panic for a mut list, a returned readonly list, and a returned readonly string.
Per implementation-plan §6 this pre-existing old-core bug is reported without
changing its mutation/origin contract in Wave A. The new backend ABI has a
conservative storage fallback beyond its mask, but that fallback does not widen
frontend support. A wide scalar-only readonly signature remains a guest
regression.
