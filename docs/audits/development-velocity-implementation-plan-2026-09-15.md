# Development velocity: implementation plan

Status: **proposed implementation plan; no fixes implemented by this document**.
Prepared 2026-09-15 for subsequent implementation by AI agents.

Source: [comparison audit](development-velocity-proposals-2026-09-15.md) and its
[42 recorded observations](development-velocity-proposals-2026-09-15-probes.json).
The [agent handoff](development-velocity-agent-handoff-2026-09-15.md) gives launch
order, a task prompt, and the required completion report.

## 1. Outcome and scope

The first release from this plan should make ordinary changes safer and the
edit/check/test loop faster:

1. A checked function contract describes its externally observable mutation and
   effects. Shared mutable aliases cannot bypass that contract.
2. Public contracts remain stable when implementations change within their bounds.
3. Formatting produces one canonical layout; native failures explain the operation
   that failed with useful values.
4. Ordinary commands reuse checked functions across processes and support useful
   reuse in projects containing generics.
5. Consumer tests can select a fake while the production implementation is unfinished.
6. Projects can require architectural policy through their ordinary commands.
7. Measurements demonstrate which work was skipped and how quickly useful feedback
   reached the developer.

This is **not a requirement to implement every aspirational feature in the two
proposals in one pass**. Section 11 assigns the remaining gaps to later milestones.
The core release is complete only when every core acceptance criterion below has
evidence; completion of an individual work package does not establish completion
of the release.

### Recommended design defaults

These are planning recommendations, not claims that the user already selected a
new language specification. An explicit subsequent user decision overrides them.

| Decision | Default for this plan |
| --- | --- |
| Memory | Keep tracing GC, current list/dictionary sharing, shallow value-record copying, explicit `Cell`, and managed arenas. |
| Mutation | Add compiler-checked effect and input-mutation contracts; do not silently change assignment into copying. |
| Public effects | Require explicit ceilings at exported function boundaries; private helpers retain inference. |
| Substitution | Keep parameter/result type identities invariant initially; allow a callable implementation to use fewer effects and mutate fewer inputs than its contract permits. |
| Compiler architecture | Extend the current compiler, stable identities and caches. Do not introduce a second frontend, runtime or independent semantic graph. |
| Execution | QBE native only; bytecode remains internal IR and its validator remains relevant. |
| Cache behavior | A cache is an optimization. Missing, incompatible, damaged or unresolved entries cause fresh work. |
| Compatibility | Migrate repository-owned code with each enforcement change. Keep old caches isolated by versioned contracts. |

Keeping sharing does **not** deliver Proposal B's full immutable-value/COW model.
It addresses the audit's mutation-contract problem while retaining today's
application model. If the user selects value semantics instead, replace M1–M3
with a separate graph-copy/COW design before executing those packages; the
formatter, diagnostic and observability packages can still proceed.

## 2. Execution rules and baseline

### W0 — Establish the baseline and freeze shared contracts

**Owner:** integration agent. **Size:** small planning/integration task.

1. Select and record a commit containing the changes that should precede this
   plan. The audit used HEAD `a9e29d4` plus an already dirty working tree; do not
   treat that commit as including the uncommitted named-constraint fixes.
2. Inspect current implementation and rerun the relevant audit probes using a
   pinned compiler built from the selected baseline. Mark already-fixed findings
   as verified; do not reimplement them from an old audit.
3. Record exact Zig version, compiler build identity, executable hash, QBE identity,
   operating system, and baseline gate results. Use the repository's pinned Zig
   `0.17.0-dev.1683+5ceec001b`; retain the pin unless the user changes it.
4. Create an execution ledger under `docs/audits/velocity-implementation/`, with one
   row per package: owner, branch/worktree, base SHA, status, dependencies, evidence,
   and integration SHA. The directory is a future deliverable, not created here.
5. Freeze the exact public encodings for mutation contracts, effect assignability,
   runtime diagnostic details, reuse counters, and semantic cache entries before
   dependent agents edit shared representations. Section 3 supplies the required
   semantics; spelling/layout decisions must be written once in the ledger.
6. Reconcile the current incremental contract document with the verified baseline.
   Some existing text describes desired query behavior as though every path already
   executes it. Preserve historical measurements and label their scope.

**Done when:** all packages have a known base and owner; focused baseline behavior
and full baseline acceptance are recorded; shared contracts have no competing
definitions. W0 may resolve routine implementation details autonomously within
this plan; it is not an additional user-approval ceremony.

### Collaboration and ownership

- Use a distinct worktree and `codex/velocity-<package>` branch per active writer.
  Never share a mutable checkout, installed binary or build-output directory.
- Assign one writer per shared file per wave. Likely conflicts include `ast.zig`,
  `typed.zig`, `parser.zig`, `sema.zig`, `generic_bodies.zig`, `interfaces.zig`,
  `main.zig`, schema files and cache-key files.
- The integration agent owns `build.zig`, `src/root_test.zig`, `SPEC.md`,
  `src/features.json`, shared golden updates, and the execution ledger at integration.
  Feature agents provide the required patches/tests; they must run their tests in
  their own worktrees before handing them over. Ownership is not an excuse to leave
  a test unregistered or unexecuted.
- Land shared representation changes before consumer changes. Separate formatter
  implementation from repository-wide reformatting, which otherwise conflicts with
  every semantic migration.
- Preserve unrelated edits. Resolve conflicts by checking the combined semantics,
  not by choosing one branch's version wholesale.
- A task that exercises Guardian must append and commit its concrete feedback in
  `~/ai/canopy/guardian-zig/FEEDBACK.md`, following that file and the user's global
  instructions. Serialize writers to that shared feedback file; do not amend or
  delete previous entries.

## 3. Mutation and effect contracts

This section is intentionally more specific than “add a mutation effect.” A label
without alias enforcement would leave the audit's main finding unresolved.

### Proposed source contract

Recommended spelling, to be finalized once in W0; **not current language syntax**:

```text
def replace_first(values: list[int], replacement: int) -> None
    effects(mutation) mutates(values):
    values[0] = replacement

def total(values: list[int]) -> int effects():
    ...
```

The line break above is presentation only; use the parser's ordinary single
signature line unless a separate continuation syntax already permits it.

`effects(mutation)` permits externally observable managed-state writes.
`mutates(values)` identifies which input graph may be written. Names normalize to
parameter positions in checked metadata. Empty mutation permission is the default
at a declared contract. Private helper effects and write footprints may be inferred.

Mutating callable types also need an input footprint. Prefer named binders inside
those callable signatures so the source can say `mutates(values)`; their binder
names do not change callable type identity or introduce callback keyword arguments.
W0 must freeze this small grammar extension together with operation constraints.
Do not invent a separate mutation system for callbacks.

### Required semantic rules

1. **Scope of the promise.** An unlisted input's reachable mutable objects cannot
   be changed during the call by that call or its callees. This is a checked
   call-duration guarantee, not permanent freezing of the object after return.
   A function with no mutation effect cannot modify caller-owned managed state.
2. **Deep inputs.** Include lists, dictionaries and `Cell` through records,
   arrays, options, unions, other collections and recursive graphs. A value-record
   copy does not sever the origin of its managed descendants. Immutable strings
   and bytes require no write permission; value-only scalar/record reassignment
   remains local.
3. **All write forms.** Cover slot writes, augmented assignments, append/extend,
   insert/remove/pop/clear/reverse/sort, dictionary updates and deletions, and
   `Cell.value`. Use the resolved operation's actual behavior, not its spelling.
   Read-only operations and constructors' private initialization stay distinct.
4. **Local construction.** Definitely fresh storage may be built and mutated
   locally without an externally observable mutation effect. Allocation retains
   its existing effect. Fresh outer storage can contain borrowed input descendants:
   changing the outer storage and changing those descendants are different actions.
5. **Aliases.** Assignments, field extraction, matches, loop bindings, helper
   results and container round trips propagate origin information. Returning an
   input or storing it in a fresh wrapper must not launder it into fresh data.
   A shallow `.copy()` severs the outer container only.
6. **Overlapping arguments.** If a writable input graph overlaps an input promised
   read-only, reject the call. This includes the same value passed twice and nested
   aliases. Unknown possible overlap is not evidence of independence: conservatively
   reject unless it can be proved disjoint. Diagnostic repairs may include declaring
   both inputs mutable when intended or explicitly building an independent snapshot.
   Do not insert hidden copies or introduce general lifetime syntax to conceal this
   rule. Passing two writable aliases is permitted; ordinary sequential ordering
   applies. Runtime callbacks must obey the same rule.
7. **Return origins.** Publish a sound return-alias bound with callable contracts.
   A conservative exported default can say “may contain aliases of any compatible
   input,” without examining its implementation. Private summaries can be more
   precise. Freshness claims require proof and participate in interface/cache keys.
   Unknown is a separate state, never a synonym for fresh.
8. **Calls and recursion.** Substitute callee input footprints into actual argument
   origins and propagate to a fixed point through recursive calls. Handle unused
   generic bodies, specializations and indirect calls too. Reach analysis budgets
   by issuing a located limitation diagnostic or conservatively widening; never
   accept a write because analysis stopped.
9. **Foreign boundary.** Keep current unsupported managed FFI/host boundaries
   unsupported. Host contracts remain trusted boundaries with explicit `host`
   effects. Do not assert source-level purity for arbitrary foreign behavior.
10. **What is not promised.** Read-only/effect-free does not mean total, trap-free,
    allocation-free at the process level, or safe for new shared-memory concurrency.

The overlap rule is deliberately conservative and may reject code that is safe at
runtime. Before shipping, measure that cost in real scanner/parser and schematic
functions. If it creates pervasive cloning or annotations, revise the documented
design with concrete examples; do not silently weaken the read-only guarantee.

### M1 — Complete mutation classification and metadata

**Depends on:** W0. **Size/risk:** large, semantic correctness.

**Implementation entry points:** `effect_set.zig`, `effects.zig`,
`buffer_operations.zig`, `typed.zig`, internal bytecode models/validation,
`generic_bodies.zig`, `sema.zig`, and schema rendering. New analysis modules should
contain the cohesive new logic rather than extending large switches everywhere.

- Inventory every managed operation and add the mutation category to one shared
  classification used by concrete checking, abstract generic checking and IR validation.
- Expand the eight-value effect enum deliberately: its current `enum(u3)` cannot
  hold a ninth value. Check masks, arrays, serialized data and every `all` constant.
- Introduce typed write/return-origin summaries and witnesses; add parser/AST
  support for the frozen contract. Preserve them through copying, relocation,
  generic substitution, interface schemas and callable metadata.
- Start conservatively by recording writes before proving local freshness. Do not
  publish a read-only feature or migrate pure annotations while enforcement is incomplete.
- Version effect/cache contracts and validator expectations together. The current
  native object cache has a mirrored cache-contract representation; update and
  test both encodings rather than changing only one.

**Acceptance:** every write form contributes the right facts, including an unused
generic and a callback; reads do not. Forged/missing IR summaries reject. The enum
extension neither loses existing effects nor admits old cache entries. M1 can land
as internal infrastructure; it does not claim the user-facing guarantee by itself.

### M2 — Enforce origins, aliases and call permissions

**Depends on:** M1 and E1. **Size/risk:** large; split into direct origins, call/return
summaries, and recursive/generic enforcement changes with independent evidence.

- Implement the rules above, with bounded analysis and located witnesses.
- Distinguish fresh object identity from managed descendants originating in inputs.
- Diagnose the write, its input origin and the missing permission. For overlapping
  call arguments, show both argument sites and the alias witness when available.
- Use contract bounds at exported call sites; never make a consumer read the callee
  body merely to determine its permitted writes.
- Ensure callbacks/operation contracts accept an implementation whose write
  footprint is a subset of the contract. Preserve shape identity separately.

**Required tests:** direct list/dict/Cell writes; nested record and collection
aliases; shallow-copy descendants; identity-returning helpers; return wrappers;
insertion into and retrieval from fresh containers; branches/loops; cycles;
generic helpers; indirect callbacks; repeated writable/read-only arguments;
unknown overlap; fresh local builders; read-only queries; and effect expansion
after a cached caller has been checked. Include native positive controls, not only
checker rejections. The audit's `effects()` list and nested-record mutations must
now reject; explicitly permitted counterparts must run correctly.

### M3 — Migrate and activate the contracts

**Depends on:** M2 and E2. **Size/risk:** medium to large, corpus compatibility.

- Migrate standard modules, self-host prototype, maintained examples, schematic,
  board code, docs and fixtures. Add narrow permissions reflecting intended writes.
- Keep intentional negative fixtures negative with updated expected diagnostics.
- Expose the contract in navigation and public schemas. Document sharing, overlap,
  return-alias behavior and fresh local mutation with runnable examples.
- Remove temporary compatibility modes before declaring completion. Do not “fix”
  the corpus by granting every function every effect/input mutation permission.
- Run representative mutation-heavy application tasks and report annotation count,
  rejected safe idioms, explicit-copy additions and performance changes.

**Done when:** no hidden input-mutation path in the required matrix remains; migrated
applications pass; the user can learn the new contract from current docs; overhead
and conservative limitations are visible in the completion report.

## 4. Public effects and callable substitution

### E1 — Directional callable assignability

**Depends on:** W0. **Size/risk:** medium, type compatibility.

**Entry points:** `callables.zig`, callable checks in `sema.zig`/generic resolution,
`structural_constraints.zig`, callable runtime/IR validation and type diagnostics.

- Keep exact equality for interning/schema identity. Add a separate directional
  assignability check; an implementation's allowed effects must be a subset of the
  destination callable contract's effects.
- Initially retain invariant parameter and result types. Do not implement broad
  function-type covariance/contravariance by replacing all equality checks.
- A call through a stored callable uses the destination contract's ceiling, even
  when today's concrete target happens to use fewer effects.
- Render canonical source types and named effects. Replace diagnostics such as
  `def@128:i64,i64` / `effects(0)` with the expected and provided source contracts.
- Extend this relation with M2's mutation footprints after those representations land.

**Acceptance:** pure callback into an output-permitting slot succeeds; the reverse
fails; stored/returned callbacks, generic constraints and unused declarations obey
the same relation. Native target validation agrees with the checker. Unrelated
parameter/result types remain rejected.

### E2 — Explicit exported ceilings and stable interfaces

**Depends on:** E1. **Size/risk:** medium, deliberate source compatibility change.

**Entry points:** `interfaces.zig`, generic/nominal exported signatures,
`schema.zig`, `generic_api.zig`, `incremental.zig`, `navigation.zig`, library sources.

- Require an explicit ceiling for exported functions, including unit procedures,
  exported generic functions, and public operations exposed through exported types.
  Existing explicit `noalloc`/`noio` ceilings remain accepted, with their exact meanings.
- Private helpers retain inference. A non-exported entry `main` retains its current
  entry behavior. Exported tests follow the same rule as other exports.
- Report a missing ceiling at the declaration. An optional suggested ceiling must
  be compiler-derived and described as a bound, not indiscriminately `effects(all)`.
- Fingerprint the declared public ceiling as API. Keep inferred implementation
  effects available for diagnostics and test cacheability, separately from the
  public API fingerprint. A body using a different subset of the same public
  ceiling should not invalidate callers' type checking merely for that reason.
- Preserve runtime-test invalidation when the body changes. Declared bounds do not
  imply unchanged behavior or deterministic tests.
- Migrate repository exports with this change; add M3 mutation footprints after
  mutation enforcement is complete.

**Acceptance:** unannotated private helper succeeds; unannotated export rejects;
body edits within a ceiling preserve the API fingerprint; exceeding it rejects
through direct, recursive, generic and callback calls. A changed declared ceiling
invalidates consumers. Defaults, keyword parameter names, nominal types and generic
requirements remain part of the public contract.

## 5. Everyday tools

### F1 — A real canonical formatter

**Depends on:** W0; teach it new syntax after M1's AST lands.
**Size/risk:** medium, comment and expression preservation.

**Entry points:** `formatter.zig`, `formatter_test.zig`, module formatting paths,
lexer/token trivia and CLI format checks. Avoid depending on semantic checking.

Fixed initial style: four-space suites; one space around binary/assignment
operators and after commas/annotation colons; no padding inside ordinary delimiters;
no trailing whitespace; one final newline for nonempty source; consistent top-level
declaration spacing (two blank lines between declarations, one after the header
directive group). Preserve comment attachment, literal values, directive order
and expression evaluation order. Establish explicit fixtures for comment-only and
empty files. Long-line wrapping can follow as one fixed policy; do not add settings.

- Use parser/token structure, preserving comments and string/bytes/f-string contents.
  Do not normalize source with regex replacements.
- `fmt` writes canonical source to stdout; `--check` is nonzero when bytes differ;
  `fmt-project --check` checks every reachable module. Preserve current non-writing
  CLI behavior unless a separate write command is deliberately added.
- Retain formatting of syntactically valid drafts with unresolved names/type errors.
- Replace tests that require every valid input to remain byte-identical with
  meaningful noncanonical-to-canonical fixtures, idempotence, structural equivalence
  and execution-preservation cases.
- Apply bulk corpus formatting only in a dedicated integration commit after
  semantic migrations have landed.

**Acceptance:** the audit's `value=  40+2` becomes `value = 40 + 2` and fails the
pre-format check. Format twice is stable; comments/literals, precedence, unary
operators, nested blocks, modules, generics and named constraints are preserved.

### D1 — Useful native trap details

**Depends on:** W0. **Size/risk:** medium, native ABI and diagnostics.

**Entry points:** `qbe_runtime.h/.c`, `qbe_managed.zig`, other relevant QBE emitters,
`native_collections.c`, `native_run.zig`, `native_execute.zig`, native test execution
and diagnostic output.

- Add bounded typed trap details to the existing sticky first-trap context. Record
  original index and length at bounds failure; handle negative indexes correctly.
  Add operation/operand details for division-by-zero and overflow where available.
- Capture values already evaluated by the operation. Never reevaluate a receiver,
  index or expression for the diagnostic, and never retain an unrooted guest pointer.
- Preserve trap codes, cleanup behavior, primary location, stack and omitted-frame
  count. Keep existing context-prefix ABI offsets or deliberately update every
  producer/consumer, static offset assertion and ABI/cache identity together.
- Text and JSON must derive from the same structured detail data. The current
  native JSON path reparses text: do not extend that approach with fragile numeric
  extraction. Define a bounded versioned diagnostic transport for native children,
  preserving ordinary stdout and public exit statuses across direct run and tests.
- Define supported fields and omission behavior for old/unavailable details;
  infrastructure failures remain distinguishable from guest traps.

**Acceptance:** the index-14/length-1 probe reports both values in text and JSON,
with its original call stack. Cover negative indices, read/write/pop, fixed arrays,
text/bytes indexing as applicable, budgets, first-trap preservation, Debug and
ReleaseFast, and both `run` and native test execution. No fabricated local variables
or complete-heap inspection is required.

### D2 — Reconcile current documentation and tools

**Depends on:** each relevant implementation; final pass after integration.
**Size/risk:** small to medium.

Update current guide pages, README, feature manifest, effect/callback docs,
formatter docs, cache docs and native diagnostic examples. Preserve dated audits
and evidence; label or redirect historical VM/watch/replay pages that current
navigation still presents as live tools. Verify negative claims as well as fenced
examples. A documented benchmark generator that still emits removed brace syntax
must be repaired before its numbers are used; `scripts/profile_large_project.py`
currently needs that reconciliation.

**Acceptance:** current examples execute/check through the documentation gate;
current feature claims match the built binary; proposed syntax stays in `text`
fences until implemented. Documentation does not claim purity, replay or compiler
reuse beyond the implemented contracts.

## 6. Incremental compiler work

### C0 — Report actual work independently of invalidation comparisons

**Depends on:** W0. **Size/risk:** medium, instrumentation/protocol compatibility.

**Entry points:** `invalidation.zig`, `frontend_cache.zig`, `semantic_cache.zig`,
`main.zig`, timing/reporting modules and native build/test receipts.

- Separate “fingerprint unchanged” from “result actually reused.” Keep explanations
  as comparisons; version or add explicit fields rather than silently redefining
  existing `hit` semantics.
- Report per invocation: parsed modules, checked bodies, instantiated
  specializations, lowered functions, emitted/compiled fragments, links, executed
  tests, reused results, bypasses and their reasons. A stage not run is `skipped`.
- Define cumulative versus per-request session counters and verify their deltas.
- Instrument the work execution sites. Deriving a reuse count from equal hashes
  after doing the work does not pass.

**Acceptance:** a forced fresh check with equal fingerprints reports work performed;
check-only commands do not report emission/link reuse; ordinary/session/native-test
reports reconcile with independently counted executions. Existing report consumers
receive a documented migration.

### C1 — Per-function dependencies and stable remapping

**Depends on:** C0, E2; mutation schema from M1 is frozen before integration.
**Size/risk:** large, cache soundness.

**Entry points:** `semantic_key.zig`, `semantic_cache.zig`, `semantic_entry.zig`,
`semantic_copy.zig`, `project_compile.zig`, stable identity and scope resolution code.

- Replace whole-program eligibility decisions with per-function eligibility.
  An unrelated generic, alias, constant or callback must not disable reuse of a
  supported ordinary function throughout the project.
- Track actual semantic dependencies: resolved declarations, referenced types and
  layouts, constant values, scope/import/visibility lookups, generic constraints,
  effects, mutation/return-alias contracts and relevant flags. Record negative
  lookups or otherwise invalidate when a newly introduced declaration changes name
  resolution. Continue global duplicate/export/import validation.
- Store stable declaration/type references and remap to the fresh compilation's
  catalog IDs. Existing numeric IDs and borrowed pointers are not persistent identities.
- Keep source-span relocation and warning provenance correct when code moves.
  Missing or ambiguous remapping is a miss, never a partially checked body.
- Recompute/invalidate effect and mutation summaries soundly after body changes;
  cached syntax/type checking must not reuse an obsolete global effect verdict.

**Acceptance:** in the audit's program containing an unused generic, changing one
ordinary body rechecks that body and reuses the other two. Insert/delete/reorder
unrelated declarations without corrupting type/function identities. Referenced
contract changes invalidate affected bodies; unrelated changes preserve reuse.

### C2 — Persist checked ordinary bodies across processes

**Depends on:** C1 and the final M2 metadata contract.
**Size/risk:** large, persistence and relocation.

- Serialize the owned, remappable checked-body representation, referenced
  contracts, diagnostics/warnings and versioned context. Do not dump in-memory
  Zig structs, pointers, allocator capacity or runtime catalog ordinals.
- Use the existing cache root and cache-key contract; no second user cache switch.
  Define checksums, lengths, bounds, atomic publication, eviction and concurrent
  writer behavior. Keep incompatible versions isolated.
- Validate every decoded reference/range/tag before integrating the body. Initially
  persist successful results only. Fresh errors must never inherit a previous pass.
- Connect the same query path to ordinary `check`, project checking, `build`, `run`
  and native-test preparation; resolve existing cache-directory and `--no-cache`
  semantics explicitly. Record remaining global work honestly.

**Acceptance:** launch a new compiler process, edit one ordinary helper and observe
unrelated checked bodies reused. Test cold/warm/no-cache equivalence, warning
relocation, damaged/truncated/oversized entries, changed compiler/effects/runtime
ABI/flags, concurrent publication and eviction. Disabling the cache preserves
results and removes reuse, not correctness checks.

### C3 — Generic body and specialization reuse

**Depends on:** C2 plus current named-constraint fixes verified in W0.
**Size/risk:** large; deliver symbolic-template reuse and concrete-specialization
reuse as separate changes.

- Cache checked symbolic templates with resolved scoped constraints and their
  dependencies. Reuse unaffected ordinary bodies in the same project throughout.
- Implement the engine behind the existing specialization-key primitive. Keys
  include template implementation, canonical concrete arguments, resolved provider
  identities/contracts, constraints, effect/mutation contracts and build context.
- Never rewrite foreign concrete names by matching identifier spelling; retain
  defining-module scope and nominal identity through serialization/substitution.
- Template body changes invalidate specializations of that template; provider
  implementation changes must invalidate generated code/tests that depend on it.
  Unrelated templates/providers/specializations remain reusable.
- Keep abstract checking of unused malformed generics. Reuse cannot turn “unused”
  into “unchecked.”

**Acceptance:** a multi-module application using named constraints and at least
two concrete providers survives fresh-process body edits with expected selective
reuse. Invalid template, constraint, callback and provider changes reject exactly
as a cold check does. Include recursion, const lengths, nominal generics,
defaults and diagnostic source relocation.

### C4 — Integrate compilation and test selection without repeated lowering

**Depends on:** C3 and P1. **Size/risk:** medium to large.

Keep project validity checking before a green test result, but perform it through
the shared query cache. Separate the checked schema/dependency graph needed for
test discovery from full QBE emission. Look up valid deterministic result receipts
after that check, and lower/emit/build only the uncached tests' required functions.
Preserve provider selection, fixture/environment identity and forced-rerun eviction.

**Acceptance:** an unchanged deterministic test rerun reports zero test executions
and no unnecessary lowering/emission/linking. A helper edit reruns only dependent
tests; an invalid project still fails. Changed test expectations, arguments,
providers, environment, budgets and force mode invalidate the proper receipts.

## 7. Independent implementation and architecture

### P1 — Test selected providers against checked contracts

**Depends on:** E2, M3. **Size/risk:** medium to large, interface validation.

**Entry points:** `native_test_command.zig`, `native_test_session.zig`,
`native_test_snapshot.zig`, cases/options, declaration/interface checking and schemas.

- Resolve test configuration and replacement modules before checking production
  implementation bodies. Obtain required signatures from declaration/interface
  checking, using explicit public effects and mutation contracts.
- Materialize and fully check the selected provider graph. The unselected
  production module may contain a typed hole or a body type error while its public
  declarations are valid. Initially its syntax still needs to parse; accepting
  arbitrary malformed files is a separate concern.
- Validate replacements against all public contracts they replace, not just the
  selected test's result type: names/defaults, types and nominal identities, data
  shapes, generic requirements, effects, mutation and return-alias bounds. An
  implementation may use narrower permissions, but may not require stronger inputs.
- Preserve source isolation, unknown-path rejection and configuration validation.
  Selected implementation errors must fail; no fabricated valid declaration may
  hide a malformed selected body.
- Record the contract, selected-provider and source identities in test receipts.
  Keep the existing fake-only entry workflow working.

**Acceptance:** the same consumer test passes against a fake while production
returns `todo[T]()` or has a body type error. A production interface error or
incompatible fake rejects. Changing a fake value invalidates its receipt. A
full production build still rejects the unfinished production body.

### A1 — Required architectural policy in ordinary project workflows

**Depends on:** W0; merge CLI work separately from C2/C4.
**Size/risk:** medium, project configuration and cache correctness.

**Entry points:** `import_policy.zig`, project/CLI configuration, `main.zig`,
native build/test options, project receipts and existing package driver.

- Extend an existing authoritative project configuration if one exists on the
  implementation baseline; otherwise introduce one minimal versioned configuration
  with an explicit import-policy path. Freeze the filename/lookup rules in W0.
  Resolve relative paths from the config location and anchor discovery to the entry
  project root, not whatever directory happens to be the shell's cwd.
- Once configured, `check`, `check-project`, `build`, `run`, project variants and
  test preparation all apply the policy through one shared frontend step. Missing
  or malformed required policy fails clearly. No special `check-policy` invocation
  should be required to get enforcement; retain that command for inspection.
- Evaluate resolved imports, including unused direct imports, before returning a
  cached success. Policy/config identity participates in verification receipts and
  caches where it affects acceptance. A stricter policy must invalidate an earlier pass.
- Keep projects without configured policy working; do not invent package layers
  or a network registry as part of this package. Apply policy consistently to selected
  provider graphs and locked package snapshots.

**Acceptance:** a forbidden import fails every applicable normal command in both
cold and warm states; allowed imports pass; policy-only edits change acceptance;
changing cwd does not change which policy is selected. Import-cycle checking remains
independent and cannot be disabled by policy.

## 8. Scale and productivity evidence

### S1 — Representative workloads and consistent resource budgets

**Depends on:** C0 for initial baselines; C4/M3/A1 for final acceptance.
**Size/risk:** medium, measurement quality and loader limits.

- Repair/reuse the existing profile scripts rather than creating a competing
  benchmark stack. Validate generated source against the current language before
  timing it; pin generator and compiler identities.
- Use three workload families: ordinary call graphs; realistic managed data with
  generic/named-constraint providers; and maintained schematic/self-host workloads.
  Include body, signature, union, constant, effect, mutation and provider edits.
- Start at 10k and 100k lines, then 500k lines. Record actual bytes, modules, edges,
  functions, specializations, graph depth and peak memory. A rejected size is an
  unsupported workload, never a successful timing sample.
- Expose/document bounded project limits consistently through checking, builds,
  test snapshots, providers and package materialization; currently their limits
  differ. Raise limits only after acceptance and resource measurements, and include
  them in validation/receipt context. Changing only the loader's `256` constant is
  insufficient. Preserve bounded failure on excessive input.
- Record process-start-to-diagnostic/test-result wall time, not only native runtime
  time. Separate cold, unchanged, implementation edit, API edit, forced tests and
  no-cache states. Record real stage counts beside each sample.
- Use an idle named reference machine, at least 20 measured edit samples after
  warm-up, deterministic edits and an explicit percentile method. Preserve raw
  samples; report median/p95 and memory rather than only the best run.

**Performance objectives, to be assessed rather than presumed:** p95 under 500 ms
for check feedback and under 1 s through affected tests on the selected 100k-line
workload. The 500k-line workload is the next scaling milestone, with the same
targets as an aspiration and an explicit achieved/not-achieved result. API changes
that legitimately affect many functions are reported separately from private edits.
W0 records hardware and workload so these thresholds cannot be met by shrinking
the workload or excluding process startup.

**Productivity trial:** unfamiliar-code tasks that add a union variant, change an
exported contract, repair aliasing, swap a provider and diagnose a runtime failure.
Keep task requirements, model/tool access and verification workload comparable;
randomize order and repeat with fresh contexts. Measure time to correct accepted
delivery, source/functions examined, repair attempts and feedback latency. Report
confounders; do not claim language-wide superiority from tiny fixtures.

## 9. Work order and integration

Packages describe ownership units, not promises that all their internal changes
fit one short agent turn. Large packages must publish intermediate verified changes.
Keep the initial fan-out to three implementation agents plus an integrator.

| Wave | Tasks that can begin | Integration constraint |
| --- | --- | --- |
| 0 | W0 | Baseline and shared contracts first. |
| 1 | F1, D1, C0 | Separate formatter, native diagnostics and observability owners. E1 follows when a slot is free. |
| 2 | E1 then E2; M1 after effect representation ownership is available; S1 baseline collection | Serialize changes to effects/types/schema. Do not claim mutation enforcement from M1 alone. |
| 3 | M2; C1; A1 | Only separate owners if their exact file sets are disjoint; sequence shared `sema`/project/CLI edits. |
| 4 | M3; then P1; C2 after final mutation metadata is stable | Corpus migration precedes provider-contract acceptance. |
| 5 | C3 then C4 | One owner for the evolving generic/query representation; provider flow must already be integrated. |
| 6 | D2 final pass, S1 final evaluation, integration gate | Bulk format only after semantic corpus edits; final outcomes checked on one combined commit. |

Dependency summary:

```text
W0 -> F1, D1, C0, E1
E1 -> E2
W0 + serialized effect/type ownership -> M1
M1 + E1 -> M2
M2 + E2 -> M3 -> P1
C0 + E2 + M1 contract -> C1
C1 + M2 final metadata -> C2 -> C3
C3 + P1 -> C4
W0 -> A1
C4 + M3 + A1 + F1 + D1 -> D2 / S1 final / release gate
```

Parallelism is optional when conflict costs exceed its benefit. An agent may
prepare a design/test matrix while waiting for its source owner, but should not
fork an incompatible second implementation of the same compiler concept.

## 10. Validation and definition of done

### Each implementation package

- State the source behavior before/after and the new guarantee, if any.
- Add meaningful regressions at the correct layer. Reuse the audit probes as
  fixtures where useful; do not register 42 shallow tests merely to mirror the log.
- Run focused suites first. For example, the repository provides
  `zig build test-units -Dtest-filter=...` and
  `zig build test-cli -Dtest-filter=...`; confirm nonempty selection.
- Follow the package with the relevant native, cache, CLI or documentation tests.
  Record commands, actual executed counts and outcomes. Do not repeat unchanged
  broad gates without a new change or concern that justifies them.
- Update the relevant SPEC requirement, current docs and feature manifest with the
  implementation. Proposed features must not be labeled implemented early.
- Report open limitations and concrete remaining work. A written cache key, planned
  API, test stub, or passing unrelated suite is not implementation completion.

### Integrated release gate

On the combined commit, run the documented full Debug and ReleaseFast acceptance,
Zig formatting, documentation coverage/examples, and affected native build/test
acceptance not already included in those gates. Current commands include:

```sh
zig build
zig build test --summary all
zig build test -Doptimize=ReleaseFast --summary all
zig build fmt-check
zig build test-doc-coverage
zig build test-docs
zig build test-qbe
zig build test-native-tests
```

The integrator checks the current build graph and records which steps are already
covered rather than running duplicates mechanically. `-Doptimize` selects the host
compiler mode; runtime/native mode coverage must also be verified where relevant.

**Release checklist:**

- [ ] Audit mutations reject under empty effects; declared writes succeed; deep
  aliases, callbacks and generic bodies cannot bypass the guarantee.
- [ ] Exported ceilings are explicit; effect/mutation subset substitution works.
- [ ] Formatter changes noncanonical source, preserves semantics and is idempotent.
- [ ] Bounds traps show index/length in native text and JSON with preserved stacks.
- [ ] Unrelated ordinary bodies reuse with generics present and across processes.
- [ ] Symbolic templates and concrete specializations have measured selective reuse.
- [ ] Warm/cold/no-cache status, diagnostic, interface and native results agree.
- [ ] A fake can replace an unfinished production body against a checked contract.
- [ ] Configured architecture policy cannot be skipped by ordinary commands or caches.
- [ ] Selective tests retain correctness and skip unnecessary compilation work.
- [ ] Representative scale limits, latency and memory are measured honestly.
- [ ] Current documentation and feature claims match the final executable.
- [ ] Relevant gates and required Guardian feedback are complete.

Semantic/cache correctness is mandatory. Missing performance targets leave the
performance milestone open with measured causes; do not relabel correctness tests
as evidence that the speed target was achieved.

## 11. Subsequent roadmap for the remaining proposal gaps

These are planned follow-ons, each requiring its own concrete implementation plan.
They are not silently counted as delivered by the core release.

| Milestone | Starting point | Required outcome before claiming it |
| --- | --- | --- |
| Editor integration | Existing navigation, diagnostics and shared compiler queries after C4 | One compiler-backed language server handles edited buffers and partial invalid projects. Start with diagnostics/navigation and checked rename; validate edits against a source snapshot and recheck before publication. Extract/move follow with explicit supported cases. |
| Package evolution | Existing locked local packages, schemas and required policy | Compare old/new APIs including names/defaults, constraints, nominal layouts, effects and mutation permissions; support a local compatibility gate first. Publishing-time semver enforcement and codemods require an actual publishing workflow. |
| Native provider replay | Structured diagnostics plus explicit effect/provider boundaries | Versioned bounded recordings capture supported inputs/outcomes and reject missing/reordered/mismatched calls; replay demonstrably avoids repeating external effects. Add state/scheduling capture before claiming time travel or production-wide replay. |
| Structured concurrency | Re-review [the scoped-task proposal](../concurrency-proposal.md) against the native runtime and new mutation rules | Bounded tasks, isolated mutable heaps, typed snapshots, cancellation, join/error obligations, and explicit capability delegation execute natively. No revived VM implementation. |
| Hot replacement | Native generation host and explicit state boundaries | Specify request-boundary replacement first, failed-generation retention, old-code lifetimes and state migration. Live-stack function patching is a distinct later promise. |
| Broader tool unification | Current package, law, navigation and profiling drivers | Move established workflows behind `mylang` incrementally while retaining one semantic graph. Add general property generators, benchmark/coverage commands when their runtime data is real. |
| Hermetic/reproducible builds | Existing source/tool hashes and package locks | Verify all external inputs and byte-identical artifacts across declared environments, with a documented supported scope. Cache presence alone is insufficient evidence. |

General algebraic effects, runtime interface values, COW graphs and unrestricted
metaprogramming are design choices rather than automatic audit fixes. Evaluate
them against applications after the core contracts and feedback loop work.
