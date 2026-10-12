# Concrete retirement order and dependencies

Status: implementation plan only. The CLI patches and documentation drafts here
are unapplied. Runtime owners' preview patches are also unapplied. C1 qualification
and actual C2 default qualification are prerequisites, not checklist substitutions.

1. Freeze C2 with ordinary command, public export, application, full fixture and
   registered gate evidence. Choose a real source-only component-compiler pin that
   already uses owned compilation by default. A08 qualifies both component protocols,
   counters, cleanup and LLVM/symbol ABI with that precise builder. Coordinator adds
   the real archive digest and new manifest only after those results exist.
2. Coordinator and A07 establish one current Core IR/runtime ABI. Migrate
   `build.Input`, `ir.Module`, direct source wrappers and test-support builders,
   then remove optional legacy ownership/emission branches. All source helpers
   must validate ownership; setting a mode bit on unchecked source is insufficient.
   `runOwned` currently means the ownership pass, not necessarily count-free IR.
   Coordinate IR-file reservations and shared declarations before editing.
3. In the same integration wave, runtime owners remove their counted alternatives:
   A02 header/count/COW/list and byte-buffer branches; A01 task environment/result
   retain/release branches; A04 text encode/append and rendering cleanup branches;
   A05 dictionary/sort/provider/durable branches; A07 owned-copy/LLVM/drop emission.
   Coordinator resolves common headers, helper declarations and linked unit imports.
   Preserve task synchronization atomics, direct child traversal/destruction,
   file/provider cleanup and storage growth. Obsolete helper deletion must follow
   removal of every caller; a surviving count-free name does not excuse a counted
   alternate implementation behind a compile-time selector.
4. A08 removes obsolete optional ABI identities or changes them to one mandatory
   owned ABI contract. Canonical IR, lowering/optimization/emission caches, runtime
   object identities, and test receipts must agree. Reusing C0 old RC receipts or
   artifacts must miss/refuse before source ownership validation is bypassed.
5. A10 applies selector retirement across both dispatchers, parsers, directory
   children, doctests and developer commands. Remove false/default alternatives
   from the new allocation analysis and portable receipt paths; remove the historical
   allocation-free RC text-encode exception. The prepared CLI patch alone does not
   perform those internal or runtime deletions. Exact refusals: status2, flag name,
   `was retired; checked ownership is the default; drop the flag`, including
   `=VALUE`; arguments after guest `--` remain data.
6. A10 retires the component builder's optional legacy route. Use only the actual
   qualified owned manifest (or an explicit independently qualified owned override),
   remove `Seed.owned`, legacy default/fallback selection, and experimental flag
   forwarding. The pinned builder must use owned ordinary commands, so final C3
   selectors are never needed. Update the fake-tool orchestration tests and native
   qualification driver, then requalify fresh component-only provision and complete
   installed layout. Coordinator updates root recipe/input registrations. Historical
   `component-seed.json` and Git seeds remain unchanged historical inputs.
7. Coordinator dispatches the enumerated internal call sites and inline source
   programs by current reservation. Replace implicit aliases with explicit copies
   preserving assertions. Replace current RC-only tests with supported ownership
   behavior or explicit unsupported-boundary diagnostics; retain frozen old artifacts
   solely for invalidation/refusal tests. Do not force active test contexts to RC.
   Direct-IR wrong-ABI tests may remain as negative inputs, never execution controls.
8. Freeze C3 and run the complete verification coordinator directly (it owns
   admission), registered format/tests, required Guardian checks, ordinary command
   matrices, public/library/application cases, original30 and expanded census,
   cold/warm/edit/cache invalidation and fresh affected A09 measurements. Audit
   emitted LLVM, preprocessed runtime layout, linked symbols and installed artifacts.
   Classify lexical `release`, `count` and `snapshot` matches: direct destruction,
   resource release and task work counts are not memory RC. Static cost-report
   cleanup labels are not runtime RC-event evidence.

Every remaining refusal keeps its source/hash, status and owner in the denominator.
A safety or supported-resource failure blocks its milestone; it cannot become a
performance tradeoff. Rollback is a previous qualified commit/release, never a
hidden source-ownership fallback.
