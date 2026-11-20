# Guardian C3 feedback

Task: C3 symbolic generic and concrete specialization reuse
Branch: `codex/velocity-c3`
Base: `8def75e8`
Commits: `d7a1cf00` (symbolic templates), `b0b156e8` (canonical
specialization key engine and conservative miss)

## What Guardian exercised

Guardian runs on every `zig build`/`install`, so the C3 changes were gated
repeatedly while adding `src/generic_cache.zig`, the `symbolic-template-v1`
store methods, the semantic entry kind and the report fields. The first runs
reported and the changes fixed:

- `change-classification` until the symbolic replay, selective-invalidation,
  unused-malformed-template and fresh-process regressions landed in the same
  change;
- `type-size` for `StoredSymbolic` (grouped into `SymbolicIdentity` /
  `SymbolicSource` / `SymbolicContract`) and for `Cache` (ordinary and symbolic
  retention grouped into one `Retention` record) and for `Work` (grouped
  `Results` and `Symbolic` records);
- `function-size` for `generic_cache.Session.init` and
  `generic_bodies.resolveTemplate` (bundled `Backend` / `TemplateCheck`);
- `cognitive-complexity` for `checkWithCatalogCached` and `sema.checkCached`
  (extracted `applyReplay`, `resolveTemplate`, `runFresh`,
  `openSymbolicSession`, `deinitSymbolic`);
- `repeated-string-literal` for repeated `semantic_cache.zig` /
  `generic_cache.zig` import strings (single module imports);
- `dead-pub` for `sym\x1fabstract-v1` helpers and the superseded
  `specialization_domain` constant;
- `error-path-test` for the new `Unrepresentable` error (named by the
  out-of-region capture regression);
- `spec`/`spec-link` because C3 has no `SEMANTIC-CACHE-9` bullet yet (the tests
  are tagged `// spec-case: SEMANTIC-CACHE-7`; the requested patch is below);
- `init-deinit-symmetry` for the allocator-owning symbolic `Table` (added
  `deinit`).

A temporary Guardian-runner stack-trace probe in the shared `guardian-zig`
checkout was used only to diagnose the arena copy-order leak; the file was
restored and Guardian rebuilt before the C3 commits.

## Findings worth carrying forward

1. Zig evaluates struct field initializers in source order. `generic_cache`
   originally copied an `ArenaAllocator` into a field before allocating the
   payload slices, so the arena never owned those nodes. Any future owned-arena
   entry should allocate every slice before the arena copy and say so.
2. Replacing an in-memory entry under the same stable declaration key must
   reuse the old slot (deinit the old arena, overwrite the slot, reinsert with
   the new key). Deiniting the old arena while leaving the old slot in the list
   makes `clear` double-free; leaving the old arena alive leaks until clear.
3. The `Work` struct is at the field cap. C4 should extend the grouped
   `Results`/`Symbolic` records rather than add top-level fields.
4. Whole-graph effect propagation is deliberately not cached. Any future
   concrete specialization reuse must still rerun `effects.checkAbstract` from
   fresh direct masks, or a changed provider/callee body can inherit a stale
   transitive verdict.

## Exact integration/spec patch requested

C3's behavior is not registered in `SPEC.md` or `src/features.json`, both
outside this task's write ownership. The integrator should add, after
`SEMANTIC-CACHE-8`:

```text
- [SEMANTIC-CACHE-9] Checked symbolic generic templates persist their direct abstract results (effect/mutation masks, body-local diagnostics and ordered abstract call edges) across compiler processes under an explicit `symbolic-template-v1` payload kind and a stable key namespaced away from ordinary checked bodies. Replay requires byte-identical declaration region/body, a matching dependency context, name-resolution mode and abstract-checker version; scoped-bound resolution and structural validation still run on every request, and the whole-graph effect propagation always reruns from the combined fresh and replayed masks. A changed template body invalidates its own entries while an unrelated ordinary body edit preserves template reuse; malformed unused templates are always rechecked; `work-report-v1` reports real `symbolic_templates` checked/reused counts.
- [SEMANTIC-CACHE-10] Concrete specialization keys are canonical over the template identity, ordered positional type/length descriptors, transitive name-ordered provider contracts, template constraint dependencies, declared effect/mutation/return-origin contracts and the build context, with every boundary length-prefixed. Concrete specialization body reuse is not yet enabled: a caller that references a specialization is rechecked fresh, so no unvalidated specialization is reused. Typed `FunctionRef` instantiation, fresh `instance_keys` remap, recursive/nested specialization remap and concrete durable payload publication remain the C3 specialization work.
```

The current docs to update are `docs/tooling/caches.md` (entry kinds and the
`symbolic-template-v1` namespace) and `docs/tooling/work-report.md` (the
additive `symbolic_templates` object and the `--no-cache` performed count).
