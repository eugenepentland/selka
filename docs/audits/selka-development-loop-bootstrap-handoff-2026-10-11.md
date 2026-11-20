# Development loop / bootstrap integration contract

Read-only branch refresh on 11 October 2026: confirmed local
`codex/selka-bootstrap-20261011` remains
`8aae33ef38207492c80fbf36c96908afdfa65907`. No bootstrap checkout was changed
and no external agent was contacted. Comparison uses development-loop baseline
`fab77294a` and branch merge-base `1d202d41bfff888ee91354f706cb74e860dc4b94`;
these are branch-side changes since the common ancestor, not an integration verdict
or a claim that all differences are new since the roadmap was written.

| Shared file | Bootstrap change relevant to first pass | Integration obligation |
| --- | --- | --- |
| `build.zig` | Adds qualification actions, component manifest inputs, SHA object wiring and measured RSS reservations | Merge new reporting/helper/Juice registrations around those actions; preserve complete gate coverage, fresh qualifiers and resource limits |
| `build_test_inputs.zig` | Adds pilot, frontend, declaration, type-interface and body qualification recipes | Preserve source/package/fixture closure and membership; add first-pass recipes without replacing bootstrap lists |
| `build_verification.zig` | `requiresQualifiedSeed` keeps ten pilot/qualification cohorts fresh | Retain external seed authentication before receipt reuse; first-pass Juice purity grants no exemption to seed checks |
| `scripts/verify_cache.py` | Introduces seven-name `COMPONENTS` inventory used by artifact paths/providers | Preserve complete manifest plus executable content binding while merging report/process refactors |
| `scripts/verify_cache_test.py` | Fake preparation includes all seven components; tests cover changed/missing frontend artifacts | Preserve these negative tests with first-pass telemetry/cancellation tests |
| `src/core/test_runner.zig` | Captures frontend identity and configures component frontend sessions | First pass does not own semantic execution changes; preserve host failure propagation and captured identity |
| `src/core/test_runner_directory.zig` | Verifies producer before/after directory execution; configures discovery/shared loads | Preserve component mutation rejection and discovery/negative lookup closure |
| `src/core/test_runner_receipt.zig` | Settings include frontend identity; hit/replay/publication reverify it | Preserve receipt safety described below; merge only with semantic/cache owner review |

No branch-side change was found in `build_identity.zig` or the new first-pass
`scripts/verification_report.py` / `scripts/verification_process.py` paths.
The latter are new modules to be carried into the eventual integration.

The bootstrap coordinator's component set is `test-index`, `cache-plan`,
`lexer-pilot`, `parser-pilot`, `declaration-index`, `type-interface`, `body-check`.
Prepared provider identity must cover authenticated manifests and the referenced
executable bytes. Missing artifacts require preparation; a valid replacement
producer still changes identity. Source equivalence or an unchanged wire schema
alone cannot make a replacement implementation interchangeable.

Preserve the following cache/provenance requirements:

- Verify external qualified seed receipts even when repository input manifests
  are unchanged. Ten qualified-seed cohorts remain explicitly fresh in the
  bootstrap registry; build actions also set side effects for qualification.
- Bind selected producer mode, verified frontend implementation and cache-plan
  identity before test success/replay lookup. Reverify at lookup and publication,
  reject an identity changed during execution, and retain conservative eligibility
  for shadow mode, fact verification, forced execution, host effects and toolchains.
- Preserve imported/embedded/generated source closure, directory membership,
  negative dependencies and exact test/operation accounting. Added gate actions
  must appear in the exported inventory; no reporting or budget feature may turn
  an incomplete run into a reusable success.
- Preserve the pinned seed/build recipe/toolchain/runtime/ABI/protocol provenance,
  authentic hostile replies, full checked graph parity and prohibition on hidden
  per-body native fallback. The install graph remains Python-free.
- Carry release fact/leak qualification and the existing performance policy:
  every required workload's median and p95 must each be at most 1.5 times the
  frozen Zig reference. Component coverage and development-loop cache gains do
  not establish full self-hosting or performance acceptance.

The first development-loop pass owns reporting, cancellation/budget plumbing and
one synthetic Juice freshness boundary. It does not narrow whole-compiler identity,
qualify a semantic producer identity, change frontend selection, port language
algorithms or waive self-hosting requirements. Broad compiler/test-binary and common
inventory/configuration/tool invalidation remain until separate qualified changes.
Future producer narrowing needs a complete source/import/generated/seed/build/runtime
closure agreed with the bootstrap owner, plus transitive failure, replacement,
mutation, schema and cross-worktree qualification.

This is a static handoff against the named local commit. Refresh the branch again
before integration; no new gate or timing qualification was run for this document.
