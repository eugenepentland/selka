# Next performance work — 2026-09-16

## Decision

Proceed with two bounded packages:

1. Reduce work inside dependency-key preparation, starting with repeated scans
   within a single request.
2. Reuse one checked compilation between native-test planning and selective
   lowering for the same provider graph.

Measure those changes before choosing retention/publication or nested
specialization reuse as the following optimization. Keep the current semantic
budget for the primary comparison. Self-hosting frontend work can continue on a
pinned compiler independently.

This decision reviews current source and recorded final-S1 evidence at
`e44046a3`. It does not represent another run of the full correctness gates or
an independent exhaustive audit of selective lowering.

## Evidence behind the order

- Final-S1 100k edit samples attribute roughly 519 ms ordinary / 496 ms managed
  to `semantic_key.prepare`, the largest individual measured phase.
- `src/semantic_key.zig:554` currently scans the complete defining module's
  source in `exportDigest` for each fingerprinted declaration. Declaration
  memoization avoids repeating a declaration within the request, but does not
  avoid scanning the same module for different declarations. Its contribution
  within the measured preparation phase still needs a timer or work counter.
- The ordinary-100k used-helper native probe records 24,655 fresh / 8,820 reused
  bodies in `native-test-graph`, followed by another 24,654 fresh / 8,821 reused
  in `emit-project-qbe`: **49,309 fresh checks across the two passes**. The final
  `test` report is their aggregate, not a third check.
- The managed rerun similarly records 24,200 + 24,136 fresh checks for a used
  helper edit. Selective lowering has reduced generated work; checking is still
  repeated before generating the selected closure.

Sources: `s1-final-report-2026-09-16.md`,
`s1-final-2026-09-16/matrix-100k.json`,
`s1-final-2026-09-16/native-probe.json`, and
`s1-final-2026-09-16/native-probe-managed-100k.json`.

Two baseline details matter for acceptance: matrix check states have 20 samples,
but forced-test states and mutating native probes have five. Managed-100k
used-helper edits have p50 4,925 ms / p95 5,554 ms in the quieter rerun; the
3,174 ms matrix p95 is for forced execution, not all affected edits.

## Package 1: cheaper dependency-key preparation

### First change: remove repeated work within each request

- Measure preparation substeps: declaration registration, module/export lookup,
  reference collection, declaration fingerprinting and context hashing. Count
  scanned bytes and reference visits, not just elapsed time.
- Build a module-level export lookup once, rather than scanning every line of
  a module for each declaration. Preserve the exact existing hash inputs,
  including ordering, whitespace/framing and duplicate-directive treatment.
- Reuse request-local stable identities and declaration facts where profiling
  shows repeated computation. Preserve lexical resolution and module-scoped
  negative lookups.
- Prefer this change before adding a new persistent preparation format. It can
  benefit cold checks, fresh-process checks and every native compiler child.

### Follow-up only if the measured preparation cost still warrants it

Retain preparation facts across session requests for unchanged declarations;
invalidate affected facts through resolved dependency edges. A body-only edit
should refresh its own reference facts without rebuilding unrelated facts.
Interface/type/constant/export/import/provider changes must reach every affected
dependent, including a formerly missing declaration becoming available.

Do not retain request-owned AST pointers, source offsets or catalog ordinals as
stable identities. Rebind positions to the current snapshot. Define ownership,
bounded retention, clear semantics and allocation-failure behavior explicitly.
Session reuse alone is not sufficient evidence of improved fresh-process CLI
or native-test latency; measure those paths separately before adding durable
preparation persistence.

### Acceptance

- Compare prepared stable keys and dependency contexts against the existing
  implementation byte for byte for the request-local optimization. Keep the old
  behavior as a test oracle, not a second production path.
- Exercise private-body edits; signatures/defaults; effects/mutation contracts;
  aliases/records/nominal types/constants; import/export changes; negative lookup
  changes; module/declaration insertion and reorder; generic/provider changes.
  Cached and fresh acceptance, diagnostics and results must agree.
- Show that export-source scanning scales with module bytes rather than
  declaration count multiplied by module bytes. Include both many small modules
  and fewer large modules to expose the scaling difference.
- Report preparation and end-to-end p50/p95, peak memory and work counts for
  ordinary/managed 10k and 100k. Keep compiler mode and other budgets fixed.
  Do not claim the overall <500 ms objective from a phase improvement alone.

Primary source area: `src/semantic_key.zig`; extend ownership into
`src/semantic_cache.zig` only if the measured follow-up needs session retention.

## Package 2: one checked compilation per native-test provider graph

### Implementation boundary

- Preserve the checked compilation used to produce test facts and use it to
  lower the selected uncached closure in the same invocation/provider graph.
  Choose an internal API/session boundary with clear ownership instead of
  immediately adding a durable whole-program IR format.
- Preserve declaration-first provider validation, receipt-first selection and
  distinct-provider isolation. Equivalent provider maps should share the same
  checked preparation.
- Revalidate source/provider/contract identity before reuse and publication.
  A changed snapshot must not consume a previous checked result.
- Continue checking required validity before returning cached successes. Keep
  effect/origin correctness passes and conservative indirect-call/codec handling.
- Preserve the C4 closure-only lower/emit/build path and the existing `--force`
  refresh versus `--no-cache` no-durable-I/O contracts.

### Acceptance

- A used-helper or forced run shows one complete semantic check per selected
  provider graph. Lowering consumes that result; instrumentation must expose
  any fallback recheck rather than hiding it.
- Fully cached unchanged and unaffected selections still perform zero
  lower/emit/link/execute work. Invalid projects still reject before green
  receipts. Fake-provider and malformed-cache regressions remain green.
- Compare native results with a fresh/no-cache control, including closure
  changes, provider changes, callbacks, codecs and nested specializations.
- Measure first build, warm cached, forced, used-helper, unused-helper and
  provider edits separately at 10k/100k. Use at least 20 successful acceptance
  samples for the edit/forced distributions; require successful warm-up for
  states labeled warm. Report aggregate and per-child checking work.

Primary source areas: `src/native_test_session.zig`, native test orchestration,
`src/project_compile.zig`, and the selective QBE/build boundary. Coordinate API
changes with package 1 if session-level preparation ownership is introduced.

## After these packages

1. Re-run the final-S1 matrix and direct native states on one pinned ReleaseFast
   compiler, with load records and isolated caches. Freeze the executable and
   supporting artifacts so another task's build cannot overwrite them.
2. Choose the next cost from the new profile. Current evidence includes fresh
   body checks, retention/publication, source/syntax work and missing nested
   specialization identities; their ranking may change after these fixes.
3. Preserve the original end-to-end <500 ms check and <1 s affected-test targets.
   The two packages are opportunities, not a guarantee that both targets land.
4. Finalize the productivity study separately: review the task packs, freeze
   cohort/model/tools/baseline and scoring, then enable the scored run. Its
   pending setup should not block the measured compiler work or self-hosting.
