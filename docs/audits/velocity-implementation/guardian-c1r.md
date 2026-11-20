# Guardian feedback: package C1R (follow-up to C1)

Recorded 2026-09-16 while closing C1's invalidation gaps in the
`velocity-c1r` worktree (branch `codex/velocity-c1r`). Guardian ran
automatically on every `zig build` / `zig build test-*`; the final
diff-scoped run passed all 88 checks (89 source files in scope). The shared
`~/ai/canopy/guardian-zig/FEEDBACK.md` was not edited.

## Good findings

- **change-classification / spec** correctly demanded regressions in the same
  change as the behavioral edits. The new measured-reuse tests cover module
  insert/reorder with an unused generic, two modules with the same bare name,
  import-directive-only edits, declared-callback reuse versus interned
  function-value misses, generic-specialization and interned-record reasons,
  mutation/effects context changes, and return-origin recomputation. Tags reuse
  the existing `SEMANTIC-CACHE-7` bullet; no `SPEC.md` edit is required.
- **dead-pub** caught `semantic_cache.missReasonName` before the work-report
  wiring referenced it. It is now used by `recordSemanticBypass`.
- **function-size** caught `semantic_key.prepare` at seven runtime parameters;
  the unused `records` parameter was removed (the initial catalog is only needed
  by `Cache.begin` for the record remap), bringing it to six.
- **type-size** caught both `Cache` and `Session` at eight fields. The Wave-3
  contract and mutation-contract version now share `semantic_cache.Context`, and
  the three fresh-catalog remap tables share the private `Remap` struct, keeping
  both below the cap without accepting a ratchet.
- **formatting** caught three unformatted files after the refactor; `zig fmt`
  fixed them.
- The worktree owner did not edit `src/native_test_*.zig` or provider/interface
  test paths owned by P1.

## Friction and follow-ups for the integrator

- **`invalidation.zig::summarize` borrows a by-value parameter.** It returns
  `work.bypassed.slice()`, a slice into the function's by-value `work`
  parameter, which dangles once `summarize` returns. This is latent but real:
  adding a reason-tagged bypass to a `check-session` reply made the reply's JSON
  stringifier read a freed slice and segfault. C1R deliberately reports the
  per-reason miss counts through the `check-session` `.functions.misses` array
  instead of adding bypass entries, so it does not rely on the buggy path. The
  integrator should copy the bypass list into caller storage or return counts
  rather than a borrowed slice.
- **`incremental.zig`'s checked interface fingerprint** (`writeTypedFunction`)
  still omits the inferred `mutates`/`return_origin` fields even though
  `schema_graph.zig` and `navigation.zig` publish them. C1R carries the checked
  contract in `semantic_entry.Identity.checked_contract` and refreshes it for
  reused bodies, but the incremental API fingerprint needs a patch owned by the
  integration agent. C1R does not own `incremental.zig`.
- **Body-level reuse is invisible in a no-edit `check-session`.** The second
  identical `check` is answered by the `check_project` verdict cache
  (`reused_results`), so the semantic `.functions` counter does not move until an
  input actually changes. Tests must edit the source between checks (as the new
  regressions do).
