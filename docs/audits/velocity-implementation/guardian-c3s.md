# Guardian C3s feedback

Task: C3 concrete specialization body reuse
Branch: `codex/velocity-c3s`
Base: `121032ec` (C3 symbolic-template reuse and canonical specialization keys)

## What Guardian exercised

`zig build` gated every edit. The focused suites
(`-Dtest-filter=generic|symbolic|specialization|semantic|incremental|invalidation|cache`)
and the wider gates (`test-units`, `test-cli`, `test-native-tests`, `test-qbe`,
`test-doc-coverage`, `test-docs`, `fmt-check`) were run against the final tree.
The new `specialization-v1` durable kind, the `generic_specializations` session
and the `sema` replay path were exercised by fresh-process integration tests that
edit a body between processes and assert `work-report-v1` `checked_bodies`
performed/reused counts.

## Findings fixed in this package

1. **Ownership arena must outlive the request.** The first implementation built a
   specialization entry with the per-request compilation arena and then retained
   it in the `Cache`. `Cache.deinit` later reached freed arena nodes and crashed
   with a segmentation fault. Fix: `createSpecialization` is called with
   `reuse.allocator` (the cache's allocator) while the temporary reference tables
   stay request-owned. This mirrors `semantic_cache.remember` owning retained
   ordinary bodies through `cache.allocator`.
2. **function-size** for `sema.recordBodyRange` (7 runtime params); the recording
   inputs are now one `RangeRecord` value.
3. **cognitive-complexity** for `semantic_entry.validSpecialization` (26 over the
   limit 25); reference validation is extracted into
   `validSpecializationRefs`.
4. **twin-drift** between the two session `publish` methods; the specialization
   copy is annotated `// twin-drift-ok:` because only the typed store call
   differs by design.
5. **try-in-return** in `sema`; the tried values are bound to locals first.
6. **doc-comments** for the new public `SpecializationFunctionRef` and the
   session counters; all new public declarations carry real `///` docs.
7. **error-path-test**: a `// UNTESTED-ERROR:` waiver names the OOM release path
   that the cache-wide `FailingAllocator` scenario cannot reach, and a unit test
   names `createSpecialization`/`error.InternalError` for the range guard.
8. **repeated-string-literal** in the new in-process test; imports moved inside
   the test block.

Three sound design points worth carrying to C4:

- The specialization entry stores a checked tree, never an effect/mutation
  verdict. `effects.check` and `origins.check` rerun over the combined fresh and
  replayed trees, so Guardian C3 finding #4 is honored by construction.
- A nested specialization reference remaps only when the fresh run has already
  instantiated it. The worklist discovers nested instances while checking the
  outer body; a replay therefore conservatively misses the outer instance and
  lets the fresh check discover the nested one. Self-recursion remaps because the
  instance's own canonical key is already in the fresh map.
- Ordinary bodies that reference a specialization still take the existing
  `.generic_specialization` conservative miss in `semantic_cache.remember`.
  Callers are never replayed from a stale instance-key set.

## Requested patches outside this task's write ownership

### `SPEC.md` `[SEMANTIC-CACHE-12]` replacement

The deferred-list sentence is now stale. Replace the bullet with:

```text
- [SEMANTIC-CACHE-12] Concrete specialization keys are canonical over the template identity, ordered positional type/length descriptors, transitive name-ordered provider contracts, template constraint dependencies, declared effect/mutation/return-origin contracts and the build context, with every boundary length-prefixed. Checked concrete specializations persist under an explicit `specialization-v1` payload kind in the shared `semantic-cache-v1` store and are replayed only when the canonical key, defining declaration region/body, dependency context and build contract match and every stored typed `FunctionRef` and record reference remaps to exactly one fresh identity. Missing, ambiguous, interned-catalog and synthesized-lambda references, and nested specialization references whose instance the fresh run has not yet materialized, are conservative misses; a self-recursive specialization remaps to its own fresh instance. Whole-graph effect and mutation propagation always reruns from the combined fresh and replayed trees. `--no-cache` performs no specialization reads or writes.
```

### `src/features.json`

The `semantic_reuse` summary still says generic bodies check fresh. Update it to
name enabled concrete-specialization replay, for example:

```text
"semantic_reuse": "ordinary checked bodies and concrete specializations replay across processes; symbolic templates keep abstract checking; unresolved nested or interned-identity references stay conservative"
```

### `src/main.zig` counter patch (reporting only; no reuse semantics change)

`recordCheckWork` currently derives `instantiated_specializations` from
`checked.functions` and always passes `reused = 0`. To expose a dedicated
specialization replay count, add a `specializations` sub-object to the
`work-report-v1` shape (in `src/invalidation.zig`) and wire it from
`Cache.reuse.specializations.statistics` here:

```zig
if (functions) |f| {
    ...
    observation.work.specialization_checked +|= f.reuse.specializations.statistics.checked;
    observation.work.specialization_reused +|= f.reuse.specializations.statistics.reused;
}
```

Until that lands, concrete specialization reuse is still measured by the real
`checked_bodies.reused` counter (a replayed specialization increments it and does
not increment `checked_bodies.performed`), which is what the C3s regressions
assert.
