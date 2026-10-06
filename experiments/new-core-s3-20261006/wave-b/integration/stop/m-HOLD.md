# S3-M unqualified checkpoint at the S3-C plan stop

Source HEAD is `681e84cf1` on `codex/new-core-s3-values`. Source-aware rendering fixes and expanded regressions are staged/unstaged working-tree changes, captured in `checkpoint-unqualified.patch`; they are not built, qualified or integrated. Further implementation/builds stopped after S3-C confirmed the old Environment callback-context implementation accident required review under plan §2.

## Evidence already obtained

- Numeric checkpoint `8535295d` and conversion-fact checkpoint `dcc3841c` passed Guardian 88. The former covers all seven float unary operations, shifts, saturating addition, checked float/unsigned conversion; the latter corrects intervals after unchecked signed/unsigned conversion.
- Aggregate/source checkpoint `c87e4fb0` passed Guardian 88. Its strict value/place comparison selected 111 existing tests and obtained 109 matching, zero mismatching, with property-runner and float-parse dependencies still refused. Separate mutation-place comparison passed all 41 selected existing tests in both modes.
- Unchanged S0/S1/functions fuzz each accepted 50 cases and performed 750 comparisons with no wrong answers, fact failures or leaks. Separate logs and summaries remain under this directory.
- All 35 benchmark definitions matched the pinned baseline on the aggregate checkpoint.
- Source `681e84cf1` merges qualified text/number source dependencies, adds list membership, and passed Guardian 88. Its uncontended installed core rebuild took 2.31 seconds. This remains a development checkpoint, not package exit qualification.

## Failures and pending source

The held `test-core` run02 was canceled by the coordinator for review-found corrections; no pass is claimed. Its new membership regression found an invalid cmp operand for a `None` needle. The pending source handles that needle and large unit-list literals explicitly.

Source-aware rendering now carries a separate seven-field descriptor graph through ephemeral IR strings. It preserves domains erased to wire types, explicit unit payloads, unit list/record/array placeholders, exact custom variant spelling, and dictionary-with-None versus set rendering. Equality/hash descriptors and the frozen IR are unchanged. Only zig fmt/static whitespace checks were run. A Guardian commit attempt failed boolean-operation and change-classification checks; source/regression changes remain uncommitted. Before qualifying, resolve marker authority: crafted literal/blob contents can collide with prefix-based metadata discovery.

The expanded regression fixture was first rejected by the old checker for aggregate str(...) and missing Some(None) type inference. Those prototype mistakes were corrected to f-strings and an explicit Option[None] annotation; every original log is retained.

A new captured-place probe is unresolved: after evaluating `mut cursor.rows[-1]`, a later `tick(mut cursor)` changes only the scalar ticks field. The old compiler leaves rows unchanged, while the installed `681e84cf1` core publishes the row mutation. The prototype predicate expected publication, so old reports False and new reports True. This demonstrates a new-case mismatch in unqualified M code, not an approved language change. Determine the old captured-location/ancestor semantics, add an expectation matching the old answer, repair lowering and requalify. No negative-index-only diagnosis is claimed.

## Resume requirements

Resolve and qualify source-aware rendering, marker authority, unit storage and captured-place behavior; make the regression test spec-tagged change concrete for Guardian. Then commit a source checkpoint, measure an uncontended core rebuild, install it explicitly, run 16-shard test-core, full debug/release conformance, strict own-file leak/verify comparison, all-35 definition identity and coverage. Preserve every run separately. Integrate only after package exit qualification; run core tests and full conformance after its integration merge. Final S3-X 200-case fuzz/performance/full-old gates remain owed.
