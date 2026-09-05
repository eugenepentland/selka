# Implementation progress

The complete scalar MVP in plan sections 4–13 is implemented and audited.
Post-MVP A1, A2, B, and exact duplicate discovery are also implemented. Remaining
tracks in sections 15 and 18 are still pending. Earlier entries below describe
their historical milestone checkpoints.

## 2026-09-05: M0 and M1

Implemented the initial vertical slice in the separate `mylang` repository.
At the user's request, pinned Guardian's exact installed Zig snapshot:
`0.17.0-dev.1683+5ceec001b`. Updated both the working plan and original attached
plan to record that toolchain decision.

Evidence:

- `zig build test --summary all`: 13/13 tests pass (9 core, 4 CLI).
- `zig build test -Doptimize=ReleaseFast --summary all`: the same 13/13 pass.
- `zig build fmt-check --summary all`: passes.
- `zig build run -- run examples/arithmetic.my`: prints `7`.
- CLI tests spawn the compiler built in the selected host optimization mode.
- Allocation-failure testing exercises request creation, compilation, execution,
  and disassembly with the testing allocator. Core malformed-source and runtime
  trap cases also release request and VM storage.

The tests exposed an allocating-writer error that needed conversion back to
`OutOfMemory`, and a test runner path that needed resolution before changing the
child working directory. Both were fixed and the suites rerun.

CI is configured for the same Debug/ReleaseFast commands and exact manifest
toolchain. No remote repository or hosted CI run has been created. Guardian's
repository and gates were not modified or exercised by these builds.

## 2026-09-05: M2

Implemented booleans, initialized locals, optional annotations, assignment,
nested scopes, unary negation/not, comparisons, and advisory binding warnings.
The frontend now has separate expression and statement tables. Semantic
checking resolves each binding to a unique local slot, and the VM stores typed
local values. Source lifetime and explicit allocation ownership are unchanged.

Verified the minimum-integer literal exception (including parentheses),
negation overflow, active-shadowing rejection, sibling-scope name reuse,
immutability, unknown names, type mismatches, warning ordering, and initializer
traps despite unused-binding warnings. A 4,096-term expression exercises the
iterative semantic/lowering walks. Updated the return instruction's source
mapping to the actual return statement.

Evidence:

- Debug: `zig build test --summary all` passes 20/20 tests (15 core, 5 CLI).
- ReleaseFast: the same 20/20 tests pass.
- Formatting check passes.
- `zig build run -- run examples/locals.my` prints `21`.
- The testing allocator covers allocation failures through scope checking,
  warning rendering, and local-value execution, as well as the original pipeline.

## 2026-09-05: M3

Implemented branches, loops, compound assignment, signed division/remainder,
explicit discard, short-circuit logical operators, conservative return analysis,
and configurable instruction budgets. Lowering patches symbolic jump labels;
emission validation checks jump bounds and consistent operand-stack heights.
The VM counts instructions before dispatch and reports budget exhaustion at the
next instruction's source span. The CLI rejects malformed, duplicate, zero,
overflowing, and non-run budget options.

Evidence:

- Debug: 23 core tests and 7 CLI tests pass (30 total; unchanged core tests
  were cached on the final invocation).
- ReleaseFast: all 30 tests pass in a fresh mode build.
- Formatting check passes on Guardian's `0.17.0-dev.1683+5ceec001b` snapshot.
- Inline sum and GCD examples print `4950` and `6` respectively.
- Tests cover logical truth tables, skipped traps, discarded traps, signed
  arithmetic boundaries, condition types, conservative returns, unreachable
  code, warning use counts, and allocation failures through jump lowering.
- Guardian gates were not exercised.

## 2026-09-05: M4

Implemented signature collection, typed parameters/results, direct calls,
forward references, mutual recursion, per-function binding diagnostics, and
explicit iterative VM frames. Calls preserve unfinished caller expressions and
return exactly one value. Both runtime budgets are CLI-configurable. Guest
traps include up to 16 source-level frames and count omitted older frames.

Evidence:

- Debug: 29 core and 9 CLI tests pass (38 total; unchanged core tests were
  cached on the final invocation).
- ReleaseFast: all 38 tests pass in a fresh mode build.
- Formatting check passes on the exact Guardian Zig snapshot.
- The plan's exact sum and GCD examples print `4950` and `6`; their copies are
  exercised by actual CLI tests. Recursive factorial returns `3628800` and
  nested calls preserve surrounding arithmetic operands.
- Mutual recursion, boolean parameters/results, 5,000 discarded helper calls,
  immutable parameters, uncalled invalid helpers, duplicate declarations,
  argument ordering, warning identity, and readable guest traces are covered.
- A 20,000-frame recursion test reaches the guest frame limit without host
  recursion. Allocation-failure tests cover signature collection, growing VM
  buffers, trap rendering, and disassembly.
- Guardian gates were not exercised.

## 2026-09-05: M5 and completion audit

Completed the CLI fixture matrix, related declaration diagnostics, malformed
source and parser-limit checks, invalid-bytecode boundary checks, and bounded
runtime-storage verification. Source errors, guest traps, and host failures
remain distinct. Added editable factorial, nested-call, and Collatz examples.

Evidence:

- 47/47 tests pass in Debug and ReleaseFast (35 core, 12 actual CLI).
- Fresh detached checkout of implementation commit `fb3458a` builds, passes the
  same 47 tests in both modes, and passes formatting on Guardian's exact Zig.
- A 100,000-iteration calling program fits a 16 KiB runtime allocator; repeated
  executions and allocation-failure sweeps release their storage.
- All three commands preserve warning order, status, and their exact stdout;
  source errors and runtime traps assert relevant locations. Oversized input
  produces a host-resource failure with no result output.
- New examples return 120 (factorial), 6 (nested calls), and 111 (Collatz).
- [mvp-audit.md](mvp-audit.md) maps the complete MVP contract to code and tests.

No MVP work remains. Hosted CI has not run and no remote was created. Guardian
was not exercised. Later experiments remain deferred as the plan specifies.


## 2026-09-05: first post-MVP experiment — exact duplicate discovery

Added a separate advisory command over the checked function representation.
It normalizes bound spelling and direct self-recursion, retains other resolved
calls and scalar structure, and uses canonical-byte hash indexing with equality
verification. Reports group members once, retain all source locations, and
permit intentional independent implementations. No source code is merged.

54 tests pass in Debug and ReleaseFast. New tests cover binding identity,
changed constants/operators/types/callees, recursion, declaration reorder,
thresholds, deterministic reports, CLI separation, and allocation-failure cleanup.
The reviewed sum corpus finds the legacy copy and keeps the inclusive variant
separate. A generated scaling benchmark records frontend and discovery time
independently, with machine/toolchain/mode/input metadata.

See [the experiment record](experiments/duplicate-discovery.md) and
[the remaining post-MVP tracks](experiments/roadmap.md). This milestone does not
claim that the aggregate, borrowing, ownership, effect, module, or native
experiments are implemented. Guardian gates were not exercised.


## 2026-09-05: full-roadmap goal — A1 storage foundation

The user activated the goal to complete all pending roadmap items. The full
scope is retained. A1 now has nominal runtime type IDs and immutable aggregate
values with explicit VM ownership. Creation and field-projection instructions
are internal backend operations while record frontend work remains pending.

Value copies survive overwrites and function boundaries. Destruction is iterative
and does not allocate. Tests cover nested sharing, deep chains, wrong-type and
out-of-bounds internal operations, instruction-budget traps, all allocation
failures, and 10,000 VM loop constructions under a 4 KiB live-byte cap.

Debug and ReleaseFast each pass 62/62 tests (49 core, 13 CLI); formatting passes.

See [the A1 record](experiments/aggregates.md). This is a storage checkpoint;
A1 and the other pending roadmap tracks are not complete. Guardian gates were
not exercised.


## 2026-09-05: A1 record frontend and declarative conversions

Implemented nominal record schemas, forward type references with cycle rejection,
explicit complete construction, named field access, immutable preserving updates,
and restricted declarative `conversion fn` bodies. Constructor/replacement
expressions evaluate in source order before values are arranged in schema order.
Complete conversions require a named use/discard decision for every source field;
passing the whole source to an ordinary helper does not satisfy accounting.

The conversion form permits direct source-field discards and an explicit complete
destination construction. It intentionally does not claim arbitrary control/data
flow proves completeness. Ordinary geometry/query functions remain unrestricted
by conversion accounting. Type mismatch and missing-field diagnostics identify
actual types/fields and retain declaration locations.

Exact discovery is now `exact-v2`, preserving nominal record names, resolved field
identities, initializer order, construction/update, and conversion contracts.
VM validation checks record schemas and construction/update field types and
indices. The lifetime foundation continues to own/release all values.

Evidence:

- Debug and ReleaseFast both pass 70/70 tests (56 core, 14 actual CLI).
- Formatting and whitespace checks pass on the pinned Guardian Zig snapshot.
- Editable records and conversions examples print 12 and 11 respectively.
- Added-field construction/conversion failures, preserving updates, nested values,
  nominal mismatches, helper-accounting limits, source evaluation order, and
  duplicate identity are covered by semantic and actual-CLI fixtures.
- Allocation-failure sweeps cover schema collection, construction/update, nested
  projection, conversion checking, disassembly, and discovery. The ReleaseFast
  sweep exposed heap-dependent resize success varying allocation counts; the
  failure-injection fixture now forces allocation fallback for stable fail indices.
  Ordinary success tests still exercise the normal allocator behavior.

Arrays, checked indexing, and additional integer widths remain within A1. The
full pending-roadmap goal remains active. Guardian gates were not exercised.


## 2026-09-05: A1 checked integer widths and casts

Implemented signed and unsigned 8/16/32/64-bit types, suffixed literals,
per-width signed-minimum handling, and explicit range-checked casts. Operations
retain width and reject mixed types. The original unsuffixed `i64` and main
entry rules are unchanged. The VM handles full-range unsigned values and detects
intermediate overflow explicitly in both host modes.

Aggregate type IDs now start after the built-in types and use a named boundary;
record/field identities and conversion checking remain intact. Exact discovery
is `exact-v3`, preserving widths and cast targets. Examples and semantics are
in [the integer experiment record](experiments/integers.md).

Evidence: 79/79 tests pass in Debug and ReleaseFast (64 core, 15 actual CLI),
including all width limits, exhaustive byte addition/multiplication pairs,
unsigned 64-bit arithmetic, casts, nominal records, complete conversions, and
allocation-failure cleanup. Fixed arrays/indexing remain within A1. All other
pending roadmap tracks remain in scope. Guardian gates were not exercised.


## 2026-09-05: A1 complete — fixed arrays and checked indexing

Implemented structural `[N]T` types, explicit complete array construction,
checked indexing for all integer widths, immutable single-element replacement,
and evaluated `len` returning u64. Arrays compose with records and complete
record conversions. Type interning preserves nominal element identities without
expanding array metadata. The acyclic schema check includes array edges.

All 90 tests pass in Debug and ReleaseFast (74 core, 16 actual CLI). Tests cover
empty/nested arrays, bounds and source spans, full-range unsigned indices,
evaluation order, rejected schemas, parser limits, allocation failures, and
invalid internal bytecode. A source loop performs 10,000 replacements within
4 KiB live runtime storage and releases all allocations, including on traps.
Formatting and whitespace checks pass. The arrays example prints 44.

Exact duplicate discovery is now `exact-v4`, retaining array structure and
operations. [Array semantics](experiments/arrays.md) documents syntax, copy
costs, and acceptance evidence. A1 is complete; the full roadmap goal remains
active. A2 domain identity and exhaustive mappings are next. Guardian gates
were not exercised; hosted CI has not run.


## 2026-09-05: A2 nominal domains and private construction

Implemented nominal integer/bool domains, qualified factories/accessors, private
functions inside domains, and owner-restricted wrapping/unwrapping. The source
checker rejects unit substitution, representation access by outside or other-domain
code, and attempted factory bypass via casts, fields, construction, or updates.
Privileges are lexical and do not propagate to free helpers called by a factory.

Bytecode retains domain ownership and private visibility, validates privileged
operations/calls, and separates domain wrapping from ordinary record creation.
Exact duplicate discovery is `exact-v5`, preserving these contracts and qualified
callees. Dumps and runtime call traces show domain-qualified function names.

All 100 tests pass in Debug and ReleaseFast (83 core, 17 actual CLI), with
allocation-failure sweeps and a 10,000-construction loop under 4 KiB live runtime
storage. Budget and checked-cast traps release all storage. Formatting and
whitespace checks pass. The domains example prints 1003.

[Domain semantics](experiments/domains.md) documents the implemented boundary and
its limitations. A2 remains in progress: closed enums/tagged unions, exhaustive
matching, and enum-indexed tables are next. The full roadmap goal remains active.
Guardian gates were not exercised; hosted CI has not run.


## 2026-09-05: A2 closed variants and exhaustive matching

Implemented closed enums, tagged unions with optional typed payloads, explicit
variant construction, same-enum equality, and exhaustive match statements. Every
variant requires one explicit arm; payloads require a scoped immutable binding
or explicit discard. Adding a variant breaks old matches, with diagnostics
naming the missing case and pointing to its declaration. Invalid nominal types,
payload shapes, duplicate arms, representation access, and by-value cycles fail.

The VM dispatches once on the evaluated scrutinee, retains selected payloads,
and preserves existing values across parent overwrite/calls. Emission validation
checks variant tags, arm tables, labels, stack joins, and payload destinations.
Exact duplicate discovery is now `exact-v6`, retaining variants, arm mappings,
and binding identities. Source-arm order remains part of exact identity.

All 112 tests pass in Debug and ReleaseFast (94 core, 18 actual CLI), including
allocation-failure sweeps and a 10,000-update state-machine loop under 4 KiB live
runtime storage. Traps at every boundary of a nested-payload execution release
all runtime storage. Formatting and whitespace checks pass. The variants example
prints 24. See [variant semantics](experiments/variants.md) for the full contract.

A2 remains in progress: complete enum-indexed tables are next. The full pending
roadmap goal remains active. Guardian gates were not exercised; hosted CI has
not run.


## 2026-09-05: A2 complete — enum-indexed tables

Implemented `[Enum]Value` tables with complete named construction, exact enum-key
lookup/replacement, immutable copies, and evaluated length queries. Table identity
includes the nominal key enum and value type; equal-length numeric arrays and
foreign enum tables remain distinct. Adding a case breaks incomplete constructors
with a diagnostic at the new enum declaration. Reordered enum declarations retain
the named mappings. Forward enums and nested aggregate/value types are supported.

Table construction reuses named initializer checking and aggregate lowering.
Validation checks key kind/cardinality, schema names/types, and constructor order;
the VM validates key identity before reading enum tags. Exact duplicate discovery
is `exact-v7`, retaining key types and named mappings. An explicit decoder fixture
preserves unknown numeric protocol codes in a separately handled union variant;
generated schemas/serialization remain future F work.

All 123 tests pass in Debug and ReleaseFast (104 core, 19 actual CLI), including
allocation failures, nested payload cleanup at every instruction trap boundary,
and a 10,000-replacement loop under 4 KiB live runtime storage. Formatting and
whitespace checks pass. The tables example prints 1407.

[Table semantics and A2 acceptance](experiments/tables.md) links domain, variant,
and mapping evidence. A2 is complete; borrowing/slices and guest memory identity
are next. The full roadmap goal remains active. Guardian gates were not exercised;
hosted CI has not run.


## 2026-09-05: B memory identity and dynamic borrow foundation

Implemented a guest-memory backend with store identities, generation-checked
allocation/lease registries, homogeneous owned buffers, bounded shared/exclusive
views, and nested reborrowing. Whole-allocation conflicts prevent alias writes;
exclusive parents suspend during child borrows, and parents cannot end before
children. Stale, foreign, out-of-bounds, and read-only accesses are rejected.
Generations and store identities never wrap into valid stale handles.

Successful reads retain immutable value snapshots. Destruction refuses active
borrows; final cleanup releases storage even with active leases. Failed registry
allocations leave locks and parent relationships unchanged. Recycled slots keep
10,000 allocation/reborrow cycles within a 4 KiB live-byte cap.

All 133 tests pass in Debug and ReleaseFast (114 core, 19 actual CLI). New backend
tests cover identity exhaustion, alias conflicts, child lifetimes, bounds, nested
values, allocation-failure cleanup, and rollback after failed borrow creation.
Formatting and whitespace checks pass. [The B record](experiments/borrowing.md)
distinguishes this implementation from the remaining language work.

B remains in progress: reference/slice syntax, static checks, VM integration, and
end-to-end borrow programs are pending. The full roadmap goal remains active.
Guardian gates were not exercised; hosted CI has not run.


## 2026-09-05: B scoped source references and VM integration

Implemented lexical `borrow` / `borrow mut` scopes, explicit `read_ref` and
`write_ref`, static owner/alias conflict checks, nested reborrowing, and diagnostics
for suspended, escaped, or read-only references. Reads retain value snapshots;
whole-local replacement preserves aggregate copies and nominal domain privacy.

The VM promotes borrowed locals into memory-registry cells, tracks leases per
frame, ends nested leases on normal exits and early returns, and releases storage
on guest traps or allocation failures. Repeated local and match payload bindings
update promoted cells correctly. Exact duplicate discovery is now `exact-v8`.

145/145 tests pass in Debug and ReleaseFast (125 core, 20 actual CLI), including
allocation failures, a 10,000-update loop within 8 KiB live runtime allocation,
every instruction-budget boundary of nested aggregate/call execution, and
malformed internal borrow ordering. The references example returns 23. A legacy
allocation-failure fixture now disables heap-dependent resize success so failure
indices stay deterministic, while ordinary tests retain the normal allocator.

B remains in progress: reference parameters/types, bounded slices, and their
lifetime acceptance tests remain pending. All other unfinished roadmap tracks
remain in scope. Guardian gates were not exercised; hosted CI has not run.


## 2026-09-05: B reference parameters and checked call reborrowing

Implemented `&T` and `&mut T` function parameters accepting active references.
Calls evaluate their value arguments in source order, then acquire temporary
parameter reborrows. Mixed parameter positions, shared fan-out, exclusive
mutation, multiple owners, recursive forwarding, and early returns are supported.
The checker rejects permission escalation, wrong underlying types, suspended
references, overlapping exclusive call arguments, and reference escape/copy.
Unused reference parameters retain binding warnings; forwarding counts as use.

The VM separates reference loans from value arguments, restores parent access
on return, and releases storage after partially failed call setup. Bytecode
validation checks parameter metadata and prevents reference parameters from being
loaded as value locals. Exact discovery is now `exact-v9` and preserves parameter
modes and ordered reference arguments. The parameter example returns 19.

155/155 tests pass in Debug and ReleaseFast (134 core, 21 actual CLI), including
allocation-failure sweeps, instruction and frame budget traps, malformed calls,
and 10,000 mutating helper calls within 16 KiB live runtime allocation. Existing
domain tests exposed a diagnostic-order regression during signature lookup; the
shared call resolver now preserves domain/privacy checks. Formatting and whitespace
checks pass on Guardian's exact pinned Zig snapshot.

B remains in progress: bounded slices and returned-reference lifetime contracts
are pending. The full roadmap remains in scope. Guardian gates were not exercised;
hosted CI has not run.


## 2026-09-05: B bounded slices and slice parameters

Implemented explicit half-open slice borrows, checked reads/writes/length,
shared/exclusive slice parameters, and narrowed reborrows. Helpers accept different
array lengths with the same element type. Ranges and indices accept integer widths
with negative, reversed, overflowing, and out-of-range checks before host casts.
Whole-array locks preserve the existing conservative alias rules. Slice writes
preserve array/element snapshots by replacing the whole immutable array value;
[slice semantics](experiments/slices.md) records the linear immediate-copy cost.

The VM carries private offset/length metadata alongside generation-checked leases.
Call forwarding, recursive narrowing, normal exits, and early returns retain
child-before-parent cleanup. Exact duplicate discovery is now `exact-v10`.

166/166 tests pass in Debug and ReleaseFast (144 core, 22 actual CLI), including
allocation failures, every instruction-budget trap boundary of nested aggregate
slice calls, malformed metadata, suspended runtime access, and 10,000 slice writes
through helpers under 16 KiB live runtime allocation. The slice example returns 13.
A malformed-bytecode test initially changed a Zig union tag while reading its old
payload; copying the payload before replacement fixed the test fixture.
Formatting and whitespace checks pass on the pinned Guardian Zig snapshot.

B remains in progress: returned-reference lifetime contracts and their acceptance
tests remain pending. Other unfinished roadmap tracks retain their full scope.
Guardian gates were not exercised; hosted CI has not run.


## 2026-09-05: B complete — returned-reference provenance and acceptance audit

Implemented reference/slice results with explicit `from parameter` contracts and
scoped receiving calls. Results must derive from that input with matching type,
shape, and permission. Returning borrowed local storage, a copied input, another
parameter, or an inactive reference is rejected. Branches, narrowed slices,
whole-array-to-slice results, mixed arguments, and recursive forwarding work.

The VM captures a valid result view, ends callee leases, releases locals, and
creates a result lease under the original caller input. Returned views preserve
bounds and aggregate snapshots and keep exclusive inputs suspended until the
receiving scope ends. Exact duplicate discovery is now `exact-v11`.

176/176 tests pass in Debug and ReleaseFast (153 core, 23 actual CLI), including
allocation failures, every instruction-budget boundary around capture/cleanup/
return, invalid provenance metadata, and 10,000 returned-loan cycles within 16 KiB
live runtime allocation. The returned-reference example prints 20. Formatting and
whitespace checks pass on the pinned Guardian Zig snapshot.

[B acceptance](experiments/b-audit.md) maps scoped references, common helpers,
bounded slices, lifetime identity, returned provenance, and cleanup to code/tests.
B is complete within its declared restricted-lifetime experiment. C/D ownership,
resources, recoverable errors, capabilities/effects, arenas/pools, and all other
unfinished roadmap tracks remain pending. The full roadmap goal remains active.
Guardian gates were not exercised; hosted CI has not run.


## 2026-09-05: C/D typed recoverable results and handling obligations

Implemented nominal result declarations with explicit success/error payloads,
exhaustive handling, and dedicated `acknowledge` statements. Result obligations
transfer through bindings, value parameters, returns, and wrapper types. Ordinary
discard, unused bindings, overwrites, repeated reads, partial projections that
would drop errors, and helpers that ignore result parameters are rejected.

The checker tracks continuing branch/match states, loop back edges, short-circuit
right operands, and every scope/return exit. Whole-value wrappers retain nested
obligations. Partial field moves and borrowing result-bearing values remain
restricted pending the ownership work. The VM reuses checked variants and adds an
explicit acknowledgement instruction that preserves evaluation and cleanup.
Exact duplicate discovery is now `exact-v12`.

187/187 tests pass in Debug and ReleaseFast (163 core, 24 actual CLI). Tests cover
recoverable errors through active borrow scopes, nested wrappers, path checks,
allocation failures, every instruction-budget boundary of nested aggregate/result
execution, and 10,000 acknowledged results under 16 KiB live runtime allocation.
The results example prints 7. Existing tests caught a common-name regression;
`result` is now contextual at declarations, preserving ordinary `result` bindings.
Formatting and whitespace checks pass on the pinned Guardian Zig snapshot.

This is a C/D foundation, not completion. Propagation syntax, resource ownership,
partial-construction cleanup, capabilities/effects, generics, typed handles, and
other unfinished roadmap tracks remain pending. The full goal remains active.
Guardian gates were not exercised; hosted CI has not run.


## 2026-09-05: C/D explicit propagation and early-return obligations

Implemented unary `try`: success yields its payload; failure propagates into the
enclosing function's declared result type with exactly matching error identity.
Named variant mappings permit different result types, success payloads, and case
orders. Error propagation cannot target ordinary unions or reference returns.

The checker requires all other active result obligations to be handled and tracks
unfinished expression operands so earlier result-bearing arguments or constructor
fields cannot disappear on failure. Lowering emits explicit failure cleanup and
return paths. The VM releases partial ordinary operands, retains the error payload,
ends active references child-first, and preserves caller operands and access.
Exact duplicate discovery is now `exact-v13`.

199/199 tests pass in Debug and ReleaseFast (174 core, 25 actual CLI), including
recursive/nested propagation, named error mappings, loop/short-circuit conditions,
returned-view cleanup, allocation failures, all instruction trap boundaries of a
nested aggregate propagation case, and 10,000 propagated failures within 16 KiB
live runtime allocation. The propagation example returns 20. Formatting and
whitespace checks pass on Guardian's exact pinned Zig snapshot.

The plan's fallible-result handling, propagation, and acknowledgement acceptance
cases now have implementation evidence. C/D remain incomplete: owned resources,
partial-construction cleanup, capabilities/effects, arenas/pools, generics, and
typed handles are still pending, along with the other unfinished roadmap tracks.
Guardian gates were not exercised; hosted CI has not run. The full goal remains active.


## 2026-09-05: C owned-buffer transfers and partial-acquisition cleanup backend

Extended the existing memory registry with initialized length/reserved capacity,
consuming owner-generation transfers, checked growth quotas, and allocation-free
reserved edits. Failed growth preserves the buffer; active loans block structural
changes. Added scopes that reserve cleanup bookkeeping before consuming owners,
transfer between scopes, and release acquired buffers in reverse order. Terminal
unwind invalidates nested views before releasing their owner.

211/211 tests pass in Debug and ReleaseFast (186 core, 25 actual CLI). New tests
cover generation exhaustion, stale/foreign owners, bounds/type/quota failures,
failed destination bookkeeping, retry after blocked rollback, aggregate snapshots,
all acquisition-path allocation failures, and 10,000 ownership cycles within
16 KiB live runtime allocation. Reserved edits, moves, destruction, and nonempty
rollback succeed with allocation disabled. Formatting and whitespace checks pass.

[The ownership record](experiments/ownership.md) states API contracts and costs.
This is a backend checkpoint: source ownership, resource VM integration, guest
acquisition results, capabilities/effects, arenas/pools, and the other unfinished
roadmap tracks remain pending. Exact discovery remains exact-v13 because no guest
syntax was added. Guardian gates were not exercised; hosted CI has not run.
The full roadmap goal remains active.


## 2026-09-05: C source buffer acquisition, moves, and cleanup integration

Implemented nominal buffer declarations and fallible `acquire_buffer<Result>(n)`.
Buffers and containing wrappers transfer through locals, calls, parameters, and
returns; reuse and inconsistent continuing-path availability are rejected. Owned
lexical bindings and match payloads release at scope exit. Result transfers now
consume VM local slots, and `try` releases acquired local/temporary resources on
failure while preserving caller operands.

226/226 tests pass in Debug and ReleaseFast (200 core, 26 actual CLI). Source
acceptance covers acquire A/fail B/release A once, successful wrapper transfer,
subsequent acquisition under the same quota, every host allocation failure,
instruction/frame traps, malformed bytecode, and 10,000 source ownership cycles
under a one-owner quota and 16 KiB live runtime allocation. The buffers example
returns 21. Formatting and whitespace checks pass. Discovery is exact-v14.

[Source ownership semantics](experiments/owned-buffers.md) documents restrictions:
acquisition currently creates empty buffers; buffer operations and borrowed views
are next. External resources, allocator/external capabilities, transitive effects,
arenas/pools, abstraction work, and every other unfinished track remain pending.
C is not complete. Guardian gates were not exercised; hosted CI has not run.
The full roadmap goal remains active.


## 2026-09-05: C buffer operations and borrowed-view integration

Implemented buffer length/capacity queries, retained reads, and typed status results
for append, resize, write, and reserve. Value arguments evaluate before checked
owner access. Mutations require a live mutable binding; recoverable failures retain
contents/capacity. Reserve may grow backing storage; other edits stay within it.

Buffers now support shared/exclusive slices, nested loans, common array/buffer
slice helpers, and returned-view provenance. The VM carries direct element-storage
metadata through calls and returned loans, including empty buffers. Buffer view
writes update one element while preserving retained snapshots. Moving an owner
with any active loan is rejected, including shared loans.

240/240 tests pass in Debug and ReleaseFast (213 core, 27 actual CLI). Acceptance
covers capacity/bounds errors, argument-consumption conflicts, immutable owners,
aggregate snapshots, escape/suspension checks, allocation-failure sweeps, every
instruction trap boundary of mutation/returned-view cases, and 10,000 returned-view
writes within 16 KiB live runtime storage and a one-owner quota. The buffer-view
example returns 19. Formatting and whitespace checks pass. Discovery is exact-v15.

[Buffer semantics and costs](experiments/buffer-operations.md) distinguishes backing
storage growth from result/VM allocation; no transitive effect guarantee is claimed.
External resources, explicit capabilities, effects including cleanup, arenas/pools,
abstractions, and every other unfinished roadmap track remain pending. C is not
complete. Guardian gates were not exercised; hosted CI has not run.
The full roadmap goal remains active.


## 2026-09-05: C transitive allocation-effect bounds

Implemented contextual function bounds (`noalloc`, `noio`, and explicit allowed
sets), iterative checked-body traversal, finite effect-set propagation over resolved
calls, and origin/call-path diagnostics. Owned acquisition and reserve contribute
allocation; reserved edits, moves, and current buffer cleanup do not. Bytecode
validation independently recomputes summaries and rejects forged bounds/summaries.
Dumps and exact-v16 discovery retain effect contracts.

251/251 tests pass in Debug and ReleaseFast (223 core, 28 actual CLI). Tests cover
recursive/declaration-reordered graphs, uncalled helpers, short-circuit/branch and
constructor operands, reference calls/results, cleanup under noalloc, malformed
annotations, emission metadata, all allocation failures, and a 512-function cycle.
The effects example returns 14. Formatting and whitespace checks pass.

[Effect semantics](experiments/effects.md) defines allocation as owned guest backing
storage, not physical host VM allocation. The vocabulary includes external effects,
but their source operations, explicit capability parameters, and external-resource
cleanup are pending. Current allocation still uses the implicit execution memory
store. This is a foundation, not completion of C or capability security. Arenas/pools,
abstraction work, and every other unfinished track retain their scope. Guardian
gates were not exercised; hosted CI has not run. The full roadmap goal remains active.


## 2026-09-05: C explicit allocator capability boundary

Added the opaque allocator capability type and an optional requesting entry
parameter. Helpers explicitly receive/forward authority; acquire and reserve reject
old implicit forms or wrong-typed operands. Runtime capabilities identify one live
execution store and share its quota ceilings. Copies and wrappers do not amplify
authority. The embedding runtime can deny the entry grant. Noalloc remains enforced
independently of capability possession.

Migrated the executable ownership/effect examples and fixtures to explicit authority.
260 tests pass in Debug and ReleaseFast (231 core, 29 actual CLI; unchanged core
results were cached in the final Debug check). New tests cover forwarding, quotas,
denied grants, fabrication, omitted parameters, stale/foreign identities, emission
and VM operand checks, and every allocation failure. Existing partial-acquisition,
trap, and bounded-storage tests pass with the new arguments. The allocator-capability
example returns 3. Formatting/whitespace checks pass; discovery is exact-v17.

[Allocator capability semantics](experiments/allocator-capabilities.md) defines the
trusted entry boundary and current single-store limit. External capabilities and
operations/resources, cleanup/completion effects, attenuation, arenas/pools, and all
other unfinished roadmap work remain pending. C is not complete. Guardian gates
were not exercised; hosted CI has not run. The full roadmap goal remains active.


## 2026-09-05: C injected clock and randomness capabilities

Implemented opaque clock/random entry grants, explicit forwarding through ordinary
values and wrappers, typed recoverable read results, and transitive external effect
inference. Synchronous host providers are injected per execution; absent grants
fail before guest code runs and never fall back to process-wide APIs. Capabilities
retain kind and execution identity, and invalid grants cannot invoke callbacks.

271 tests pass in Debug and ReleaseFast (241 core, 30 actual CLI). Acceptance covers
full-width samples, signed boundaries, denied/unused grants, authority fabrication,
effect bounds, malformed emission, short-circuit skipping, recoverable provider
errors and host OOM with owned cleanup, allocation-failure sweeps, and 10,000 reads
within 16 KiB live runtime storage. The CLI checks/dumps the external-capability
fixture and explicitly denies execution without providers. Formatting/whitespace
checks pass. Discovery is exact-v18.

[External capability semantics](experiments/external-capabilities.md) documents the
trusted host callback contract, error codes, wall-clock units, entropy quality,
and nontransactional observations. Noio/noalloc do not imply determinism. Filesystem,
network, environment, external resources and completion/cleanup, attenuation,
arenas/pools, and every other unfinished roadmap track remain pending. C is not
complete. Guardian gates were not exercised; hosted CI has not run. The full
roadmap goal remains active.


## 2026-09-05: C external resource completion and scoped cleanup backend

Implemented provider-backed filesystem/network resource stores with explicit grants,
non-reused identities, generation-checked moves, live-resource ceilings, and reserved
bookkeeping before host acquisition. Fallible completion retains ownership on error
and consumes it on success; fallback release never implies completion. Store teardown
uses reverse acquisition order even after slot reuse. Lexical scopes support adoption,
take, transfer, and reverse registration cleanup without losing owners on failed
bookkeeping allocation.

283 tests pass in Debug and ReleaseFast (253 core, 30 actual CLI). Acceptance covers
partial acquisition, all provider completion errors including host OOM, successful
retry, explicit fallback, stale/foreign/closed/wrong-kind tokens, quotas, slot reuse,
generation retirement, nested scope moves, and every registration/transfer allocation
failure. Registry moves/completion/release/unwind work with allocation disabled;
10,000 acquisition/move/release cycles fit under 4 KiB and reuse one slot. Formatting
and whitespace checks pass. Discovery remains exact-v18; guest semantics are unchanged.

[The external resource record](experiments/external-resources.md) defines trusted
callback contracts and cleanup order. This is backend evidence only: guest resource
declarations, capability entry grants, acquisition/completion, VM cleanup, and source
cleanup-effect inference are pending. Environment, attenuation, arenas/pools, and all
other unfinished tracks remain in scope. C is not complete. Guardian was not exercised;
hosted CI has not run. The full roadmap goal remains active.


## 2026-09-05: C source external resource lifecycle and cleanup effects

Implemented nominal filesystem/network resource types, explicit entry grants,
fixed-byte-array acquisition requests, and fallible completion that consumes its
input and returns the still-owned resource in a typed error on failure. Existing
moves, wrappers, results, and lexical/early-return cleanup now release provider
resources. Successful completion cannot be retried through an obsolete binding and
never triggers fallback release. Aggregate teardown is iterative, depth-first,
and reverse schema order, making observable external cleanup deterministic.

Owned signatures/locals conservatively contribute contained resource cleanup
effects; direct operations and callees add effects independently. Bytecode validation
recomputes both ownership and operation effects. Noio rejects implicit external
cleanup as well as explicit access; noalloc retains its guest-buffer-backing meaning.

297 tests pass in Debug and ReleaseFast (266 core, 31 actual CLI). Acceptance covers
owned completion retry/fallback, all completion errors and host OOM, partial
acquisition, quotas and restricted requests, independent entry grants, source move/
schema errors, wrapper cleanup, every instruction-budget boundary, recursive frame
traps, allocation-failure sweeps, malformed emission, and exact discovery identity.
10,000 acquisition/completion cycles fit in 16 KiB live VM allocation with one live
resource. The CLI checks/dumps the fixture and denies missing providers. Formatting
and whitespace checks pass. Discovery is exact-v19.

[Source resource semantics](experiments/source-resources.md) documents the trusted
provider contract and remaining restrictions. Requests are fixed arrays, there are
no actual file/socket data operations or OS adapters, and projecting an error code
still consumes its owned wrapper. Environment, owned-field inspection/partial moves,
attenuation, arenas/pools, and all other unfinished tracks remain in scope. C is
not complete. Guardian was not exercised; hosted CI has not run. The full roadmap
goal remains active.


## 2026-09-05: C non-consuming field inspection and code-dependent completion retry

Implemented `read_field(owner, field)` for live record bindings and copyable fields.
It preserves owner/result obligations, returns retained immutable snapshots, respects
borrow conflicts, and rejects resource/result duplication. Direct reads participate
in complete-conversion field accounting. Bytecode validates resolved owner/field/type
metadata; exact-v20 discovery retains these identities. Completion examples and
allocation-failure tests now choose retries by inspecting the code without losing
the error record's resource.

306 tests pass in Debug and ReleaseFast (274 core, 32 actual CLI). New tests cover
snapshot survival across owner updates/transfers, moved/owned/result-copy rejection,
unsatisfied handling obligations, shared/exclusive access, complete conversions,
malformed emission, discovery identity, and allocation failures. Existing resource
retry, trap, and bounded-memory tests pass with the non-consuming operation.
Formatting and whitespace checks pass.

[Field-read semantics](experiments/owned-field-reads.md) distinguishes inspection
from ordinary consuming projection. Partial field moves and owned-wrapper borrowing
remain pending, along with environment/data operations, attenuation, arenas/pools,
and all other unfinished roadmap tracks. Guardian was not exercised; hosted CI has
not run. The full roadmap goal remains active.


## 2026-09-05: C bounded environment capabilities and lookup

Implemented explicit environment entry grants, fixed-byte-array lookup names,
bounded typed results, and transitive environment effects. Injected providers return
absent or a complete byte length; missing/empty remain distinct and oversized values
produce recoverable NoCapacity. Returned tails and absent values are zeroed. Foreign/
closed grants fail before callbacks, and the CLI cannot read ambient process state.
Resource and environment operations now share checked byte-array conversion helpers.

319 tests pass in Debug and ReleaseFast (286 core, 33 actual CLI). Acceptance covers
explicit forwarding, denied/unused grants, raw bytes, all presence/capacity cases,
all provider errors, host OOM, invalid returned lengths, type/authority rejection,
transitive effects, malformed emission, and foreign/closed grants. Failure propagation
ends active buffer borrows and releases owners. Allocation-failure sweeps cover the
full lookup/reporting path. 10,000 lookups fit within 16 KiB live runtime allocation.
Actual CLI tests cover checks, dumps, denied execution, and effect rejection across
commands. Formatting and whitespace checks pass. Discovery is exact-v21.

[Environment semantics](experiments/environment.md) defines read-only, provider-scoped
byte lookup with no ambient fallback or mutation API. Resource data operations,
partial field moves, attenuation, arenas/pools, and all other unfinished tracks
remain in scope. C is not complete. Guardian was not exercised; hosted CI has not
run. The full roadmap goal remains active.


## 2026-09-05: C owned resource reads/writes and explicit partial progress

Implemented optional provider read/write callbacks and source operations on live
mutable resource bindings. Reads return bounded fixed-byte-array snapshots, actual
length, and explicit EOF with zeroed tails. Writes return actual accepted counts.
Neither operation consumes its owner, retries automatically, or implies completion.
Provider counts are bounds-checked; unsupported operations return Unavailable.
Source/bytecode validate mutability, lifetime, schemas, operands, and transitive
effects. Bounded read-result schemas share validation with environment results.

331 tests pass in Debug and ReleaseFast (297 core, 34 actual CLI). Acceptance covers
partial/zero progress, EOF, raw bytes/padding, invalid provider counts, unsupported
callbacks, stale owners, mutability/type errors, consuming write arguments, noio,
recoverable retries, host OOM, all allocation failures, and every instruction trap
boundary. 10,000 read/write cycles fit within 16 KiB live VM storage under one owner.
Actual CLI tests cover checking/dumps, missing-provider denial, and source rejection.
Formatting and whitespace checks pass. Discovery is exact-v22.

[Resource I/O semantics](experiments/resource-io.md) states single-callback progress,
trusted provider contracts, and nontransactional effects. Fixed arrays are supported;
slice/range I/O remains pending, along with partial field moves, attenuation,
arenas/pools, and all other unfinished roadmap tracks. C is not complete. Guardian
was not exercised; hosted CI has not run. The full roadmap goal remains active.


## 2026-09-05: C resource operation permission attenuation

Implemented `restrict_resource<permissions>(cap)` as monotone intersection of read,
write, and complete permissions. Original grants and existing owners remain intact;
copies and helper forwarding cannot restore removed rights or increase shared quotas.
Embedding options cap entry grants. Provider acquisition now receives permissions
and must honor them in open/request semantics; acquired owners retain restrictions
through moves. Denied read/write/completion returns before callbacks, preserves the
owner, and still permits fallback release. Restriction itself adds no effect.

339 tests pass in Debug and ReleaseFast (304 core, 35 actual CLI). Acceptance covers
wrapper/helper delegation, attempted re-expansion, provider-visible acquisition
restrictions, embedding ceilings, operation denial, completion failure cleanup,
parent authority, shared quotas, slot reuse, invalid/foreign/closed grants, malformed
source/bytecode permissions, normalized discovery, and all allocation failures. CLI
fixtures verify checking/dumps, absent-provider denial, and permission rejection.
Formatting and whitespace checks pass. Discovery is exact-v23.

[Attenuation semantics](experiments/attenuation.md) distinguishes resource operation
permissions from acquisition/release authority, provider scope, revocation, and
independent quotas. Slice I/O, partial field moves, arenas/pools, and every other
unfinished roadmap track remain in scope. C is not complete. Guardian was not
exercised; hosted CI has not run. The full roadmap goal remains active.


## 2026-09-05: C borrowed resource slice I/O

Implemented resource reads into exclusive u8 slices and writes from shared/exclusive
u8 slices, preserving resource ownership and existing lifetime/permission checks.
Reads report length/EOF and modify only their successful prefix; writes send exactly
the selected range. Fixed-array replacements are prepared before provider calls and
committed once, retaining immutable snapshots. Initialized owned buffers update in
place after staging. Provider errors discard scratch writes and leave destinations
unchanged; terminal failures after successful I/O do not promise rollback.

351 tests pass in Debug and ReleaseFast (315 core, 36 actual CLI). Acceptance covers
array snapshots, buffer views, untouched bytes, populated ranges, permissions/types,
suspended parents, returned narrowed views through parameters, empty ranges and EOF,
provider-error isolation, malformed emission, all allocation failures, and every
instruction-budget boundary for both storage routes. 10,000 slice read/write cycles
fit within 16 KiB live VM storage. CLI checks/dumps/denied execution and exclusive-destination
enforcement pass. Formatting and whitespace checks pass. Discovery is exact-v24.

[Resource slice semantics](experiments/resource-slices.md) documents staging/copy
costs and trusted callback boundaries. Partial field moves, arenas/pools, and all
other unfinished roadmap tracks remain in scope. C is not complete. Guardian was
not exercised; hosted CI has not run. The full roadmap goal remains active.


## 2026-09-05: C/D typed-handle pool backend

Implemented host nominal handle categories independent of node layout, globally
unique pool identities, reusable generational slots, retained snapshot reads,
replacement, removal, bulk clearing, and bounded issued-slot quotas. Cyclic graph
edges are inert IDs. Removed/cleared handles stay stale after reuse; exhausted
slots retire instead of wrapping. Registry allocation precedes input retention,
and replacement retains before releasing to preserve self-replacement safely.

361 tests pass in Debug and ReleaseFast (325 core, 36 actual CLI). Acceptance covers
cross-category/instance/layout identity, cyclic traversal and edge repair after
reuse, repeated bulk clearing, reserved operations without allocation, failed
registry growth, invalid mutations preserving payload ownership, immutable guest
snapshots, all allocation failures, identity/generation exhaustion, and 10,000
graph/reset cycles within 4 KiB live allocation. Formatting and whitespace checks
pass. Discovery stays exact-v24 because no guest syntax or semantics changed.

[Typed-pool semantics](experiments/typed-pools.md) records ownership hooks, storage
costs, cleanup order, and backend limits. Source pool/handle integration, arenas,
partial field moves, generics, and all other unfinished roadmap tracks remain in
scope. C/D are not complete. Guardian was not exercised; hosted CI has not run.
The full roadmap goal remains active.


## 2026-09-05: C arena backing and checked region reset

Separated memory Store buffer backing from runtime-owned payloads/registries and
added checked bulk reset with a full borrow preflight. Arena backend initialization
binds a Store to stable-address Zig arena backing. Normal reset preserves allocator
authority and registry capacity, invalidates removed owners through generations,
and preserves retained snapshots. Terminal cleanup also handles outstanding loans.
Backing retention is explicit and reports its outcome separately from reset success.

367 tests pass in Debug and ReleaseFast (331 core, 36 actual CLI). Acceptance covers
nested/suspended/empty loan rejection without partial cleanup, allocator authority
and quotas across cycles, stale owners/leases after reuse, independent arenas,
aggregate snapshots after reset/destruction, allocation-failure sweeps, preheated
cycles with host allocation disabled, and 10,000 create/grow/reset cycles within
16 KiB live allocation. Formatting and whitespace checks pass. Discovery remains
exact-v24 because the guest language has not changed.

[Arena semantics](experiments/arenas.md) records stable-address requirements, parent
snapshot ownership, retention costs, and physical-versus-logical memory limits.
Source arena scopes, escape checks, allocator forwarding, pool/handle integration,
partial field moves, and every other unfinished track remain in scope. C is not
complete. Guardian was not exercised; hosted CI has not run. The full roadmap goal
remains active.


## 2026-09-05: C execution-lifetime arena integration

Integrated the arena backend into VM execution with explicit embedding selection
and CLI `run --memory=general|arena`. General allocation remains the default.
Execution owns stable-address arena storage; buffers and reference cells use the
selected backing while snapshots, wrappers, registries, and VM metadata retain
parent allocation. All exit routes reclaim backing after owner cleanup.

374 tests pass in Debug and ReleaseFast (337 core, 37 actual CLI). Acceptance
compares allocator forwarding, growth, returned slices, limits, and missing grants
across backends. Arena execution covers every host allocation failure and every
instruction budget boundary, immutable snapshots, partial-construction propagation,
resource slice reads/writes and cleanup, and 1,000 separate executions within 32 KiB
live runtime storage with zero live bytes between runs. CLI selection, matching
output, traps, and invalid options pass. Formatting and whitespace checks pass.
Discovery remains exact-v24: this changes runtime backing, not source semantics.

[Execution arena semantics](experiments/arena-execution.md) documents one region per
execution and accumulation until execution end; logical quotas are not physical
arena byte bounds. Nested source arena scopes, escape checks, source reset, pool/
handle integration, partial field moves, and all other unfinished roadmap tracks
remain in scope. C is incomplete. Guardian was not exercised; hosted CI has not
run. The full roadmap goal remains active.


## 2026-09-05: T bounded approximate duplicate discovery

Added opt-in `discover-duplicates --approximate` with separately versioned near-v1
canonical-line edit distance. Exact-v24 groups remain unchanged. Matching headers
preserve signature/local/reference/effect/domain boundaries; body differences remain
visible as insertions, deletions, or substitutions. Reports show source locations,
exact-group representatives, edit counts, and bounded change excerpts. Work and
pair limits explicitly mark incomplete search. The command remains advisory.

382 tests pass in Debug and ReleaseFast (344 core, 38 actual CLI). Acceptance covers
literal/operator/callee changes, inserted statements, unrelated bodies, nominal and
effect boundaries, exact-copy grouping, deterministic output, default opt-out, work/
pair limits, invalid budgets, and every allocation failure through comparison and
rendering. CLI reporting, advisory exits, truncation, and invalid options pass.
Formatting and whitespace checks pass. The existing sum review corpus yields one
near pair with the intended lt/le difference, plus its unchanged exact-copy group.

[Approximate comparison semantics](experiments/approximate-discovery.md) documents
line-score limits, quadratic comparison bounded by explicit work, header exclusions,
and review outcomes. These fixtures do not establish production usefulness or
performance. Formatter, reference/complexity reports, verification tooling, and all
other unfinished roadmap tracks remain in scope. Guardian was not exercised; hosted
CI has not run. The full roadmap goal remains active.


## 2026-09-05: T resolved references and configurable structural reports

Implemented `report-quality` over checked function bodies. Reports use resolved
call identities and source locations, count incoming syntactic sites, compute
reachability from main iteratively, and list binding declaration/read/write facts.
Private unreachable functions are distinguished from other potential entry points.
Runtime execution, coverage, and assertion outcomes are explicitly unmeasured.
Structural node/line/parameter/nesting/decision counters have configurable advisory
thresholds; zero disables a signal without hiding its measured fact.

389 tests pass in Debug and ReleaseFast (350 core, 39 actual CLI). Acceptance covers
untaken call paths, cycles, unreachable callers, private/public notes, branch/loop/
short-circuit/match/try counters, physical lines, deterministic rendering, disabled
thresholds, every allocation failure, and a 2,001-function call chain without
lowering or execution. CLI advisory status, source errors, and malformed/duplicate/
wrong-command options pass. Formatting and whitespace checks pass. Manual inspection
of the duplicate corpus agrees with one loop decision per sum helper and three
resolved main calls. Exact/near discovery versions remain unchanged.

[Quality report semantics](experiments/quality-reports.md) documents every counter,
static-versus-runtime distinctions, threshold defaults, and reference coverage.
Formatter and verification-driver work remain pending; modules/schemas must extend
reference coverage and entry-root policy. All other unfinished roadmap tracks remain
in scope. Guardian was not exercised; hosted CI has not run. The full roadmap goal
remains active.


## 2026-09-05: T canonical syntax and comment-preserving formatting

Implemented `fmt` stdout output and `fmt --check` verification. The formatter reuses
cached parsing/tokens, preserves token spellings and comment gaps, and normalizes
spacing/indentation/line endings. Syntax-valid code can be formatted without finished
name/type/ownership checking. Files are not rewritten by the command. Formatting
checks remain distinct from semantic validity and advisory structural thresholds.

396 tests pass in Debug and ReleaseFast (355 core, 41 actual CLI). Acceptance covers
exact comment layout, token/comment round trips, idempotence, CRLF, arrays/generics/
operators, syntax-only behavior, empty/comment-only source, syntax rejection, and
every allocation failure. The failure sweep exposed WriteFailed escaping from the
allocating writer; it now consistently reports OutOfMemory. All 28 valid CLI fixtures
format, type-check again, and pass idempotence checks in both host modes. CLI stdout,
check differences, canonical success, and malformed options pass. Formatting and
whitespace checks pass; exact-v24, near-v1, and quality-v1 are unchanged.

[Formatter semantics](experiments/formatter.md) records the single style, unchanged
tokens/comment associations, syntax-only validation, and lack of automatic width
reflow. The project-verification driver and all other unfinished roadmap tracks
remain in scope. Guardian was not exercised; hosted CI has not run. The full roadmap
goal remains active.


## 2026-09-05: T separate manifest project-verification driver

Implemented a Python standard-library driver with ordered, validated command/spec
steps, explicit dependencies, step filters, and structured evidence. Reports retain
requested/selected/unselected scope, manifest digest, definitions/expectations,
executed commands, lossless output, exits, and monotonic durations. Dependency
failures block dependent steps without hiding independent outcomes. Selected success
is distinct from full-manifest success; runtime coverage remains unmeasured.

All 11 repository manifest steps pass: build, format/check, Debug/ReleaseFast tests,
expected runtime value, general/arena memory parity, immutable-assignment rejection,
specification marker, advisory report, and three timing observations. The 396 Zig/
CLI tests passed from cache in both modes; eight new driver tests executed in each
mode via zig build test. Driver acceptance covers filtered dependencies, failures,
parity including invalid UTF-8, mutation diagnostics, timeout/output/launch errors,
spec/benchmark separation, strict manifests, and actual CLI/report statuses. The
filtered parity run selects exactly build + memory-parity, with selected success true
and full-manifest success false. Formatting and whitespace checks pass.

[Verification-driver semantics](experiments/verification-driver.md) documents explicit
scope and limits: the mutation sentinel is not a mutation score, spec-marker presence
is not conformance, timings are not performance gates, and general/arena parity is
not native execution parity. The initial verification manifest does not cover future
language features. Modules, source pool/arena scopes, generics, partial field moves,
native execution, compile-time/schema/incremental work, and every other unfinished
roadmap requirement remain in scope. Guardian was not exercised; hosted CI has not
run. The full roadmap goal remains active.


## 2026-09-05: E scalar native execution and shared executable parity

Implemented C emission from checked/lowered scalar instructions and a builder that
verifies Guardian's exact Zig before invoking zig cc. Generated programs use direct
branches and explicit operand/call frames, checked width arithmetic, matching guest
step/frame accounting, and trap codes/source locations. Unsupported post-MVP
signatures and operations diagnose E_NATIVE_FEATURE without partial C output or a
VM fallback. Native diagnostics use concise location/trace formatting.

399 Zig/core-and-CLI tests pass in Debug and ReleaseFast (357 core, 42 actual CLI),
plus eight verification-driver tests. Each host mode also passes 23 scalar fixtures
and 182 executed VM/native comparisons across C -O0/-O2 with undefined-behavior
sanitization. Cases cover widths/casts/overflow/division/remainder, booleans, skipped
traps, branches/loops, caller operands, mutual recursion, 20,000 explicit frames,
and call-program budget boundaries. The actual native builder, wrong-toolchain
rejection, quoted paths, and malformed budgets pass. Generator determinism and all
allocation failures pass; formatting and whitespace checks pass. Final repeats used
cached Zig suites and executed the Python/native tests again.

[Native execution semantics](experiments/native-execution.md) records the hosted C
route, supported scalar subset, and limits. No speed claim, whole-language native
support, or native allocator-fault-injection coverage is asserted. This satisfies
the tracked scalar native acceptance experiment; native expansion requires its own
operations and corresponding parity cases. Source pool/arena scopes, partial field
moves, generics, modules/interfaces, compile-time/schema/incremental work, and all
other unfinished roadmap requirements remain in scope. Guardian was not exercised;
hosted CI has not run. The full roadmap goal remains active.


## 2026-09-05: C/D partial record field moves and remaining obligations

Implemented take_field across parsing, checking, lowering, VM, and tooling. Field
transfers immediately remove parent ownership while preserving access to untouched
fields. Immutable field-state snapshots participate in branch/loop/short-circuit
checks. Missing fields and whole-value use of partial records reject; complete binding
replacement restores availability. Remaining result-bearing fields stay obligations,
while transferred fields carry their own obligations to their new expression/binding.

Unique runtime aggregates allocate a moved-field bitmap before first transfer.
Cleanup skips transferred slots, preserving immediate resource release and remainder
order; shared aggregates reject destructive extraction. 413 Zig/core-and-CLI tests
pass in Debug and ReleaseFast (370 core, 43 CLI), plus eight driver tests and the
unchanged 23-fixture/182-comparison native suite per host mode. Acceptance covers
quota reuse, metadata, nested moves, result/overwrite obligations, equal/different
path states, recoverable propagation, every allocation failure, every instruction
boundary on both memory backends, malformed bytecode, and external release order
1,3,2. A 10,000-cycle fixture uses <=16 KiB live runtime allocation and releases all
20,000 buffers. Formatter coverage grows to 29 valid CLI fixtures. Formatting and
whitespace checks pass. Exact discovery advances to exact-v25 with read/take identity.

[Partial-field semantics](experiments/partial-fields.md) documents runtime uniqueness,
state-copy costs, result obligations, complete binding replacement, and native
unsupported-feature behavior. Source pool/arena integration, generics, modules,
compile-time/schema/incremental work, and every other unfinished roadmap requirement
remain in scope. C/D are not complete. Guardian was not exercised; hosted CI has not
run. The full roadmap goal remains active.


## 2026-09-05: C/D source pools and nominal graph handles

Implemented `pool Nodes(NodeId): Node;` declarations, allocator-authorized acquisition,
owned pool transfers/cleanup, length/capacity queries, insert/read/replace/remove/clear,
and nominal handle equality. Handle types break by-value graph cycles without owning
nodes; reads preserve independent snapshots. Pool/slot/generation identities reject
stale and foreign access through typed results. Acquisition reserves registry storage
and contributes allocation effects; reserved operations satisfy the existing noalloc
contract. Independent per-execution pool quotas are shared across allocator copies,
returned on owner destruction, and observable through embedding statistics.

426 Zig/core-and-CLI tests pass in Debug and ReleaseFast (382 core, 44 CLI), plus
eight verification-driver tests and the unchanged 23-fixture/182-comparison native
suite per host mode. New acceptance includes cyclic graphs, replacement snapshots,
slot reuse/clear, all host allocation failures, every instruction budget through
completion on both buffer memory backends, forged/wrong-category ID rejection,
quota sharing/recovery, owner-death and generation-aware equality, effect bounds,
partial construction/field moves, malformed bytecode, and duplicate discovery.
10,000 aggregate insert/read/remove cycles stay within 16 KiB live runtime storage
with zero bytes remaining afterward. Actual CLI graph execution returns 52 in both
memory modes. Formatter coverage grows to 30 valid fixtures; formatting and whitespace
checks pass. Exact discovery advances to exact-v26; near-v1 and quality-v1 remain.

[Source-pool semantics](experiments/source-pools.md) records syntax, error codes,
logical quotas, parent-allocator backing, snapshot/ID rules, and native limitations.
Pool registries currently use the VM parent allocator even with arena buffer backing.
Nested source arena scopes/escape checking and arena-backed pools, generics, modules,
compile-time/schema/incremental work, broader native support, and every other unfinished
roadmap requirement remain in scope. C/D and the full roadmap are not complete.
Guardian was not exercised; hosted CI has not run. The full roadmap goal remains active.


## 2026-09-05: C checked shared region backing and arena-backed source pools

Implemented a generational region manager with parent/child lifetime guards and
retained backing leases shared by buffers and pools. Allocator capabilities can carry
region identity; stale/foreign capabilities reject. Buffer cells retain their original
backing allocator across growth and cleanup. Pool registry allocation is now separate
from the allocator used to release retained node values. Source pool acquisition in
VM arena mode now uses arena registry backing while snapshots remain parent-owned.
Execution-arena reset preflights live root pool backing leases before changing buffers.

434 Zig/core-and-CLI tests pass in Debug and ReleaseFast (390 core, 44 CLI), plus
eight verification-driver tests and the unchanged 23-fixture/182-comparison native
suite per host mode. Region acceptance covers mixed buffer/pool snapshots surviving
region end, every allocation failure, nested/stale/foreign capability checks, slot
limits/reuse, live-borrow and live-owner closure rejection, transactional root reset,
parent-allocator node release during clear, and zero-capacity/failed-acquisition lease
accounting. 10,000 mixed region/pool/buffer lifecycles stay within 16 KiB live runtime
allocation and leave zero bytes. Formatting and whitespace checks pass. Exact-v26,
near-v1, and quality-v1 remain unchanged.

An existing reserve-failure test replaced Store.allocator after creating its buffers.
That no longer targets buffer backing once cells preserve their allocator. The test
now installs the failure allocator at Store creation and enables failure after setup,
retaining its failed-growth/failed-transfer/noalloc assertions without changing allocator
identity midway through live allocations.

[Checked region backing](experiments/region-backing.md) documents the embedding API,
quota/lease rules, independent arena chunks, reset preflight, and teardown ordering.
This completes a runtime prerequisite, not the source arena experiment: lexical arena
syntax, allocator/owner provenance, and static escape checking remain pending. Generics,
modules, compile-time/schema/incremental work, broader native support, and all other
unfinished roadmap requirements remain in scope. Guardian was not exercised; hosted
CI has not run. The full roadmap goal remains active.


## 2026-09-05: C lexical arena scopes and conservative escape checking

Implemented `arena heap as scratch { ... }` through parsing, checking, lowering, VM,
and tooling. Scoped allocator bindings create checked regions. A separate monotone
lifetime analysis propagates regional dependencies through assignments, wrappers,
fields, calls, references, container mutation, and recoverable-error payloads. Outward
regional escapes reject with E_ARENA_ESCAPE, while explicit heap owners, plain retained
snapshots, and inert IDs can leave scopes. Calls respect the callee's reference
mutability. Scope entry contributes allocation effects; exhausted region slots trap
with R_REGION_LIMIT. Normal exits release body ownership before region closure;
returns/propagation release frame ownership before closing that frame's regions.

448 Zig/core-and-CLI tests pass in Debug and ReleaseFast (403 core, 45 CLI), plus
eight verification-driver tests and the unchanged 23-fixture/182-comparison native
suite per host mode. Acceptance covers nested pool/buffer/helper/view execution,
every host allocation failure, every instruction budget to completion on both
execution backends, return/propagation quota reuse, escaped snapshots/IDs, authority
and effect checks, reference/helper/container escape rejection, legal arena-local
capability containers, malformed bytecode defenses, and duplicate discovery.
10,000 mixed source arena scopes fit within 16 KiB live runtime storage and leave
zero bytes in both modes. Actual CLI execution returns 50; formatter coverage reaches
31 valid fixtures. Formatting and whitespace checks pass. Exact discovery advances
to exact-v27; near-v1 and quality-v1 remain unchanged.

ReleaseFast exposed NondeterministicMemoryUsage in the existing call/frame/trace
allocation-failure sweep, reproduced in an isolated test run. The sweep now disables
in-place resize with the same failure-allocator pattern used by other exhaustive
sweeps. The resulting complete Debug and ReleaseFast runs pass with all failure
points exercised consistently.

[Source arena semantics](experiments/source-arenas.md) documents field-insensitive,
flow-insensitive, conservative call dependencies and their possible safe-program
rejections. It also records runtime closure guards, snapshots, diagnostics, and
teardown order. Functions without local arenas need no new relative-lifetime analysis.
Explicit source arena reset operations/results remain pending, alongside generics,
modules, compile-time/schema/incremental work, broader native support, and every other
unfinished roadmap requirement. No general borrow-checker soundness or full-language
native support is claimed. Guardian was not exercised; hosted CI has not run. The
full roadmap goal remains active.


## 2026-09-05: C explicit arena reset with recoverable results

Implemented reset_arena<Result>(allocator) across parsing, checking, lowering, VM,
and tooling. A bool/i64 result reports successful chunk reclamation or live backing,
active-child, and invalid/root-capability errors. Reset preserves the region's scope
and copied allocator authority. It preflights lifetime guards before changing storage,
performs no guest backing allocation, and is allowed in noalloc helpers. Pool clear
still pins registry backing until its owner releases; retained snapshots remain on
the execution allocator and survive successful reset.

457 Zig/core-and-CLI tests pass in Debug and ReleaseFast (411 core, 46 CLI), plus
eight verification-driver tests and the unchanged 23-fixture/182-comparison native
suite per host mode. Acceptance covers copied capability reuse, live buffer/borrow
and child rejection, reset of an empty child while retaining its parent relationship,
root/foreign/closed rejection, pool pinning and snapshots, physical chunk reclamation,
every host allocation failure, every instruction budget on both memory backends,
result obligations, noalloc helpers, duplicate identity, and malformed bytecode.
10,000 resets and 20,000 buffer acquisitions within one source arena stay inside
16 KiB live runtime allocation; a control program with reset removed exhausts that
same bound. Both paths unwind to zero bytes. Actual CLI execution returns 3 and
formatter coverage grows to 32 valid fixtures. Formatting and whitespace checks
pass. Exact discovery advances to exact-v28; near-v1 and quality-v1 remain unchanged.

[Arena reset semantics](experiments/arena-reset.md) records error codes, capability
preservation, owner/child guards, snapshot behavior, and the distinction from the
embedding root-reset API. Generics, modules/interfaces, compile-time/schema/incremental
work, broader native support, and all other unfinished roadmap requirements remain
in scope. Guardian was not exercised; hosted CI has not run. The full roadmap goal
remains active.

## 2026-09-05: M deterministic module header discovery

Implemented the bounded project loader and `list-modules` CLI. Logical dotted
names map to relative `.my` paths; matching declarations, unique imports/aliases,
source/module/edge budgets, shared dependency reuse, and acyclic dependency order
are enforced. Iterative traversal avoids recursive import loading. Cycle diagnostics
show both importing and related declaration files. Reports include whole-source
SHA-256 fingerprints and explicitly state that bodies/exports/types are unchecked.
Failed and unfinished loads cannot render successful reports.

467 Zig tests pass in Debug and ReleaseFast (419 core, 48 CLI), plus eight
verification-driver tests and the unchanged 23-fixture/182-comparison native suite
per host mode. New acceptance covers real filesystem imports, cross-file cycles,
diamond reuse, deterministic reports, body-sensitive fingerprints, malformed and
missing modules, duplicate aliases/imports, all configured budgets, path traversal
rejection, a 600-module chain, and exhaustive allocation failures for loading and
cycle diagnostics. Formatting and whitespace checks pass. The documented example
executes with `shared.units` preceding `main`. An initial example used reserved
keyword `domain` as a module segment; the actual CLI check caught it, and the
example/documentation now use the valid identifier `units`.

[Module discovery](experiments/module-discovery.md) documents the provider API,
resolution root, limits, report semantics, and remaining integration. This is a
prerequisite for complete modules, not completion of track M: exports, private
boundaries, cross-file binding/type checking, and shared-domain execution remain
pending. Generics, compile-time/schema/incremental work, native expansion, and other
unfinished roadmap requirements remain in scope. Guardian was not exercised;
hosted CI has not run. The full roadmap goal remains active.

## 2026-09-05: M parsed interfaces, explicit exports, and visibility resolution

Implemented `export Name;` after import headers, module-mode parsing of qualified
`alias::Name` types/calls/constructors/patterns, and an interface index with distinct
module/symbol identities. The resolver enforces direct imports, declaration kinds,
module-private names, and domain-private methods. Exported domains expose ordinary
methods while retaining private methods. Exported signatures cannot expose private
types through records, variants, arrays/table keys, buffers, pools, domain backing,
or function parameters/results. Duplicate exports/declarations and alias conflicts
have source diagnostics. `list-interfaces` parses all bodies and reports exported
declarations, explicitly stating that bodies are not type checked.

473 Zig tests pass in Debug and ReleaseFast (424 core, 49 CLI), plus eight
verification-driver tests and the unchanged 23-fixture/182-comparison native suite
per host mode. Acceptance covers public/private domain identity lookup, hidden
implementation functions, missing/wrong-kind references, signature visibility,
qualified AST spans, malformed bodies, actual CLI cross-file diagnostics, and all
host allocation failures through successful loading/indexing/resolution/rendering.
The shared-domain example's interface command runs successfully and lists Distance,
Distance.make, Distance.number, and Measurement while hiding Distance.raw. Formatting
and whitespace checks pass. Existing exact-v28, near-v1, and quality-v1 identities
remain unchanged because those commands still operate on single-file programs.

[Module interfaces](experiments/module-interfaces.md) specifies the implemented
boundary. Index lookup and exported-signature visibility are validated; function
bodies are not yet resolved or type checked across files. The next integration must
connect these module identities to the type catalog/function checker and preserve
module locations into typed IR and execution diagnostics. Shared-domain execution,
optional dependency-direction policy, generics, compile-time/schema/incremental
work, native expansion, and other unfinished roadmap requirements remain pending.
Guardian was not exercised; hosted CI has not run. The full roadmap goal remains
active.

## 2026-09-05: M mapped sources and relocated module syntax

Implemented checked forward/reverse source-span mapping with distinct per-file EOF
locations, original path/line/column lookup, and separate combined-buffer line
indices. Module AST relocation now combines parsed tables while preserving source
spelling, expression/statement references, per-module ranges, and each function's
owning module. All nested AST fields are handled through the pinned Zig reflection
API; the original AST remains unchanged. The output remains a prerequisite for
module-aware semantic resolution, not a replacement for it.

Diagnostics preserve original file paths for errors, related notes, and VM traces.
Mapped bytecode dumps include paths; quality line metrics use combined indices
while displayed references use original locations; duplicate reports also resolve
paths. Native scalar emission now uses per-instruction paths for traps/call traces.

478 Zig tests pass in Debug and ReleaseFast (429 core, 49 CLI), plus eight
verification-driver tests and the unchanged 23-fixture/182-comparison native suite
per host mode. New acceptance covers empty files, EOF and reverse span boundaries,
CRLF/tabs, related declarations across files, parser/checker/VM source provenance,
unequal-file quality metrics, relocation of module functions/calls/fields, and all
host allocation failures through mapped compilation/native emission and module AST
relocation. A separately emitted scalar native probe was compiled with pinned Zig
at O2 and undefined-behavior sanitization; it trapped at lib/helper.my:2:11 and
reported the caller at entry.my:1:27. Formatting and whitespace checks pass.

The pinned snapshot's reflection API uses field_names/field_types rather than the
older fields interface. Compilation exposed that mismatch and the relocation code
now uses the bundled API. A new native-emission assertion initially expected literal
paths rather than the emitter's octal-escaped C strings; it was corrected, and the
executed native probe confirmed displayed source paths.

[Module source mapping](experiments/module-source-mapping.md) describes ownership,
source-map boundaries, relocation, and validation limits. The trace probe uses
fragments of one scalar program; full module body resolution/type checking and
shared-domain execution remain pending. Optional dependency-direction policy,
generics, compile-time/schema/incremental work, native expansion, and other unfinished
roadmap requirements remain in scope. Guardian was not exercised; hosted CI has not
run. The full roadmap goal remains active.

## 2026-09-05: M cross-file semantic checking and VM execution

Integrated interface identities and mapped source context into the type catalog
and function checker. Named declarations use logical-module-qualified identities;
references resolve through direct import aliases in the source span's original
module. Caller/callee types retain nominal identity, private module/domain access
is enforced in bodies, and shadowing sees local declarations/import aliases without
exposing hidden dependency names. All discovered bodies are checked. Execution
selects main only from the entry module. Existing ownership, borrowing, result,
finite-layout, arena-lifetime, and transitive-effect passes remain in the pipeline.

Added `check-project` and `run-project` with ordinary VM step/frame/memory options,
renderable mapped diagnostics on failed checking, and cross-file runtime traces.
The documented Distance/Measurement example checks and returns 12, including arena
execution. Header and interface listing commands retain their narrower contracts.

484 Zig tests pass in Debug and ReleaseFast (434 core, 50 CLI), plus eight
verification-driver tests and the unchanged 23-fixture/182-comparison native suite
per host mode. New acceptance includes imported domain factories through private
helpers, distinct same-named nominal types, hidden function/type rejection, missing
references, import-alias shadowing, dependency-main isolation, uncalled invalid
bodies, recursive layout rejection, cross-file noalloc/result obligations, and
returned slices preserving caller mutation and snapshots. Real CLI tests check/run
multiple files, reject private imports, preserve trap paths, and exercise step and
memory options. Exhaustive allocation failures cover module loading, indexing,
relocation, checking, lowering, and execution. Formatting and whitespace checks pass.

[Module execution](experiments/module-execution.md) records commands, namespace and
entry rules, ownership, validation, and remaining scope. Optional dependency-direction
policy and broader module acceptance remain pending, alongside module-aware tooling,
project native commands/parity, generics, compile-time/schema/incremental work, native
operation expansion, and all other unfinished roadmap requirements. Guardian was
not exercised; hosted CI has not run. The full roadmap goal remains active.

## 2026-09-05: M optional dependency-direction policy

Implemented `check-policy <entry.my> --policy=<rules.json>` with strict versioned
JSON, required defaults and rule reasons, ordered allow/deny rules, exact module
names and namespace patterns, and bounded configuration/rule sizes. Evaluation uses
resolved direct imports and reports deterministic edge decisions, selected rules,
unused-rule match counts, reachable-graph scope, analysis version, and configuration
SHA-256. It does not modify the graph or language diagnostics. Ordinary checking
and execution do not load policy.

The CLI checks language validity first. Exit 1 indicates an invalid program, exit 2
configuration/usage/host failure, and exit 3 a policy failure on valid code; success
is exit 0. The report makes that distinction explicit. The documented shared-domain
policy passes with one allowed main -> shared.units edge.

490 Zig tests pass in Debug and ReleaseFast (439 core, 51 CLI), plus eight
verification-driver tests and the unchanged 23-fixture/182-comparison native suite
per host mode. Acceptance covers directional/namespace matching, first-rule/default
semantics, zero-match reporting, deterministic decisions, strict duplicate/unknown
configuration rejection, byte/rule bounds, all host allocation failures through
parsing/evaluation/rendering, and actual CLI separation of all four exit outcomes.
A type-invalid dependency takes precedence over an invalid policy configuration;
ordinary project execution succeeds despite a separately failing policy. Formatting
and whitespace checks pass.

[Import policy](experiments/import-policy.md) records syntax, matching semantics,
limits, scope, and verdicts. Core module import/export/privacy, execution, and optional
policy behavior are implemented. Broader module corpus/scaling acceptance and
module-aware formatter/reference roots/duplicate identities, project native parity,
generics, compile-time/schema/incremental work, native operation expansion, and other
unfinished roadmap requirements remain pending. Guardian was not exercised; hosted
CI has not run. The full roadmap goal remains active.

## 2026-09-05: T duplicate discovery over checked module graphs

Added `discover-project-duplicates` with the existing exact/approximate thresholds,
population labels, bounded work, and timing options. It checks all reachable module
bodies before discovery and renders original source paths and qualified function
names. Reports explicitly distinguish structural candidates from export visibility
and dependency-policy review. Project timings include loading/semantic work and
report original source bytes without source-map separators.

492 Zig tests pass in Debug and ReleaseFast (440 core, 52 CLI), plus eight
verification-driver tests and the unchanged 23-fixture/182-comparison native suite
per host mode. Acceptance groups scalar functions across files and aliases of the
same shared nominal type/callee, while keeping distinct module-local nominal types
and callees separate. Allocation-failure sweeps cover project checking, exact/near
discovery, and report rendering. Actual CLI tests cover population/timings, work-limit
truncation, invalid flags, and invalid dependency rejection without partial output.
Formatting and whitespace checks pass.

The documented three-module example reports one exact price/quote group and one
approximate alternate candidate, showing the literal edit 3 -> 4 with no truncation.
Its initial tiny functions fell below the default eight-node discovery threshold;
explicit subtotal bindings now make the reviewable example nine nodes without
changing that threshold. No production code was refactored or merged. Existing
exact-v28 and near-v1 formats remain unchanged because module-qualified nominal and
callee names already feed the canonical serializer.

[Module discovery semantics](experiments/module-duplicates.md) documents scope,
visibility/policy limits, timing counts, and validation. Module-aware formatting and
reference/quality roots, broader candidate-index/corpus scaling, project native
parity, generics, compile-time/schema/incremental work, native expansion, and other
unfinished roadmap work remain pending. Guardian was not exercised; hosted CI has
not run. The full roadmap goal remains active.

## 2026-09-05: T module quality reports and exported interface roots

Added `report-project-quality` over checked module programs with separate main and
exported-interface reachability. Export roots come from resolved interface identities,
including ordinary methods of exported domains; private helpers inherit reachability
through calls without becoming roots. Isolated recursive groups remain unrooted.
Reports retain qualified call identities, original source locations, static binding
counts, and configurable advisory metrics. No-call-path review now accounts for both
root sets without claiming that exports have external callers or measured coverage.
Single-file quality-v1 remains unchanged; module semantics use quality-modules-v1.

495 Zig tests pass in Debug and ReleaseFast (442 core, 53 CLI), plus eight
verification-driver tests and the unchanged 23-fixture/182-comparison native suite
per host mode. Acceptance covers main-only/export-only/shared paths, private helpers
and domain methods, isolated cycles, empty/duplicate/out-of-range roots, all allocation
failures through checking/root extraction/analysis/rendering, original file references,
CLI threshold advisories, and invalid dependency rejection without partial output.
The shared-domain example report identifies make/number as exports and raw as a
private helper reached by them. Formatting and whitespace checks pass.

[Module quality semantics](experiments/module-quality.md) documents root scope,
visibility flags, advisory interpretation, and unchanged runtime-coverage limits.
Module formatting, broader corpus/scaling review, project native parity, generics,
compile-time/schema/incremental work, wider native operations, and all other
unfinished roadmap requirements remain pending. Guardian was not exercised; hosted
CI has not run. The full roadmap goal remains active.

## 2026-09-05: T canonical module and project formatting checks

Added `fmt-module` stdout/check modes and `fmt-project --check`. The per-file mode
parses headers and bodies without import loading or semantic validation. The project
mode uses the reachable graph's loader rules, then formats every body without type
checking, reporting all differing paths only after syntax validation succeeds.
Neither command writes source files. The common formatter now handles qualifier
colons while preserving token spelling and comment gaps. Module formatting does not
populate the single-file parser cache or allow a later check to ignore imports.

498 Zig tests pass in Debug and ReleaseFast (444 core, 54 CLI), plus eight
verification-driver tests and the unchanged 23-fixture/182-comparison native suite
per host mode. Acceptance covers idempotence, token/gap-comment preservation, CRLF,
qualified arrays/types/calls, malformed headers/bodies, unresolved drafts, parser-cache
isolation, every host allocation failure, CLI stdout/check behavior, and reachable
multi-file checks. An allocation-failure assertion initially expected SourceError
at a point that could also allocate; it now propagates OutOfMemory to the exhaustive
sweep, which passes. Formatting and whitespace checks pass.

Both existing module example graphs were canonicalized using formatter stdout and
pass `fmt-project --check`; execution still returns 12 and 46. Formatting changed
only whitespace, including expanding inline records/branches and removing blank gaps.
[Module formatting](experiments/module-formatting.md) records syntax-vs-graph scope,
output behavior, and validation limits. Broader module/candidate corpus and scaling
review, project native parity, generics, compile-time/schema/incremental work, wider
native operations, and other unfinished roadmap requirements remain pending.
Guardian was not exercised; hosted CI has not run. The full roadmap goal remains
active.

## 2026-09-05: E scalar module native execution and executable parity

Added `emit-project-c` and `scripts/native.py --project`, retaining exact Zig
verification, module semantic/privacy checks, original source maps, and the existing
scalar native operation boundary. C emission rejects unsupported dependency signatures
or instructions before stdout. The project builder runs in Debug/ReleaseFast modes;
frontend rejection preserves an existing output artifact. The documented duplicate
module example builds natively and returns 46, matching the VM.

500 Zig tests pass in Debug and ReleaseFast (445 core, 55 CLI), plus eight
verification-driver tests. The native harness now runs five project fixtures with
68 executed VM/native comparisons in addition to the existing 23 scalar fixtures
and 182 comparisons per host build mode. Project comparisons include source paths,
line/column, trap codes, and normalized call-frame identities/paths at C O0/O2 with
undefined-behavior sanitization. Cases cover nested cross-file calls, overflow through
a facade, recursion, short-circuiting, width conversion, frame/step limits, and every
step budget through nested-call completion. Public project builders run in both
modes; unsupported uncalled dependencies and private-call rejection are checked.

Zig acceptance also covers deterministic repeated native module emission and every
host allocation failure through loading, indexing, checking, lowering, and emission.
Actual CLI rejections have no partial generated stdout. Formatting and whitespace
checks pass. [Module native semantics](experiments/module-native.md) records commands,
parity scope, and limitations. Aggregates, nominal-domain operations, borrowing,
capabilities/resources, pools, arenas, and other wider native operations remain
unsupported; this milestone does not claim full-language native execution.

Broader module/candidate corpus and scaling acceptance, generics, compile-time/schema/
incremental work, wider native operations, and other unfinished roadmap requirements
remain pending. Guardian was not exercised; hosted CI has not run. The full roadmap
goal remains active.

## 2026-09-05: E native nominal scalar domains

Extended native signatures, locals, parameters, and returns to nominal domains backed
by integers or bool. Wrap/unwrap preserve scalar backing directly without VM host
aggregate allocation, while retaining their instruction ticks. Frontend nominal
identity, private representation access, private methods, and backing-width checks
remain mandatory. Domain arithmetic/equality syntax was not added. The new module
domain example builds natively, passes formatting checks, and returns 12.

502 Zig tests pass in Debug and ReleaseFast (447 core, 55 CLI), plus eight
verification-driver tests. Native acceptance now includes 27 single-file fixtures
with 206 executed comparisons and six module fixtures with 114 comparisons per host
build mode (320 combined). New cases cover domain copies/mutation, boolean backing,
u64 cast rejection, u8 overflow after unwrapping, private factory helpers, nominal
parameter/return forwarding, and every instruction budget through completion of the
module domain case at C O0/O2 with undefined-behavior sanitization. Module results
also compare original file locations and call frames.

Zig tests retain private-constructor and nominal mismatch rejection and sweep every
host allocation failure through native domain emission and VM execution. Formatting
and whitespace checks pass. [Native domain semantics](experiments/native-domains.md)
describes representation, privacy, logical instruction counts, and host-allocation
limits. Records/arrays/variants, references, owned buffers/resources, pools, arenas,
and other wider native operations remain pending, alongside generics, compile-time/
schema/incremental work, remaining corpus/scaling acceptance, and every other
unfinished roadmap requirement. Guardian was not exercised; hosted CI has not run.
The full roadmap goal remains active.

## 2026-09-05: Native closed enums

Extended native scalar slots to carry closed enum tags through parameters, returns,
locals, copies, and mutation. Equality/inequality use checked nominal enum identity;
exhaustive matching emits direct C switch branches indexed by resolved variant tag.
Instruction ticks retain VM budget behavior. Tagged unions, including payloadless
unions, remain explicitly unsupported by native emission.

Debug and ReleaseFast validation pass: 504 Zig tests (449 core, 55 CLI; the Debug
Zig test steps reused successful cached results), eight verification-driver tests,
and 392 executed VM/native comparisons per host build mode. The native harness
includes 32 single-file fixtures/236 comparisons and seven module fixtures/156
comparisons, compiled at C O0/O2 with undefined-behavior sanitization. New evidence
covers weighted all-tag dispatch with reordered arms, equality/copies/mutation,
loop continuation, singleton enums, traps, cross-file enum calls, and every step
budget through completion of the module enum fixture. Allocation-failure sweeps
cover emission and VM execution; semantic rejection tests preserve exhaustiveness
and nominal identity checks.

The new examples/native-enums.my builds with the pinned Zig toolchain and prints 7.
Canonical Zig/source formatting and git diff whitespace checks pass. The roadmap
and plan now link the enum experiment, and stale module milestone descriptions
point to their completed follow-on implementations. Generics, compile-time/schema/
incremental work, wider native types/resources, and remaining corpus/scaling
acceptance are still pending. Guardian was not exercised and hosted CI has not run.
The full roadmap goal remains active.

## 2026-09-05: Bounded approximate header index

Approximate duplicate discovery now builds a stable merge-sorted header index and
visits only compatible function pairs, retaining first-declaration pair order and
the existing canonical-line distance/traceback. Header sorting and index movement
are charged to the work budget; an incomplete index reports truncation without
claiming exhaustive absence. Temporary index arrays are freed on success, budget
exhaustion, and allocation failure. Near-v2 records the changed budget accounting;
exact-v28 and similarity semantics are unchanged.

506 Zig tests pass in Debug and ReleaseFast (451 core, 55 CLI), including the existing
allocation-failure sweeps, interleaved header bucket ordering, output limits, and a
1,024-input distant-pair test within 250,000 work units. The actual CLI scaling driver
now runs as part of zig build test. Generated source corpora with 128/512/1,024
functions find their compatible first/last pair without truncation under four
million units and produce byte-identical repeat reports. Observed work counts are
150,889 / 621,084 / 1,361,230. These generated cases establish header-index scaling,
not ordinary-program usefulness or a guarantee for large compatible buckets.

Eight verification-driver tests and 392 VM/native comparisons per host build mode
also pass. Zig formatting and git diff whitespace checks pass. The plan and roadmap
record this progress; broader ordinary-program review, compatible-bucket scaling,
module corpus acceptance, generics, compile-time/schema/incremental work, and wider
native operations remain pending. Guardian was not exercised; hosted CI has not run.
The full roadmap goal remains active.

## 2026-09-05: Banded approximate edit-distance comparisons

Approximate discovery now stores and computes only the diagonal band that can
contain an accepted edit alignment. It preserves full-matrix deterministic edit
explanations and acceptance thresholds while charging the smaller matrix and
conservative compared-line byte bound. Near-v3 records this budget-accounting change;
exact-v28 and header eligibility remain unchanged. Compatible pair enumeration and
fixed-percentage edit bands still have quadratic worst cases.

508 Zig tests pass in Debug and ReleaseFast (453 core, 55 CLI). A full-matrix oracle
checks all 4,805 short binary sequence/threshold combinations for acceptance,
distance, and complete edit explanations. A 1,000-line canonical drift pair now
completes within the default one-million-unit budget. Existing deterministic,
nominal boundary, truncation, and allocation-failure tests pass.

The CLI scaling driver now checks longer compatible source functions with 50/100/200
repeated statements: one changed return literal remains a single explained edit,
using 287,261 / 1,060,407 / 4,070,527 work units under an explicit 4.1-million budget.
Header-index corpus work is now 139,187 / 609,382 / 1,349,511 for 128/512/1,024
functions. These are generated acceptance fixtures, not production-usefulness or
whole-compiler performance claims. All scaling cases pass in both host build modes.
Eight verification-driver tests and 392 native parity comparisons per host build
mode also pass, along with formatting and whitespace checks.

The roadmap and attached plan record banded comparison progress. Ordinary-program
review, wider module/corpus acceptance, generics, compile-time/schema/incremental
work, wider native operations, and other outstanding requirements remain pending.
Guardian was not exercised; hosted CI has not run. The full roadmap goal remains active.

## 2026-09-05: Integrated module graph boundary acceptance

Added an actual-CLI module scaling driver to zig build test. A 256-module call chain
passes checking, canonical formatting, execution at the exact frame boundary,
deterministic dependency ordering, and quality/duplicate reporting. It verifies all
256 functions' main reachability, 255 export roots, and 255 resolved calls. Deep leaf
value edits change execution and exactly one source digest; type errors reject
checking and advisory reports at the original file/line without partial stdout.
Cycle diagnostics preserve both leaf and entry sites. The 257th module rejects
with E_MODULE_LIMIT.

A shared 92-module DAG at exactly 4,096 imports is counted once per module, reports
deterministically, checks, and executes. The 4,097th import rejects with
E_IMPORT_LIMIT. These acceptance cases use the default CLI limits and real files;
they do not establish unbounded scaling, native support, or incremental caching.

Debug and ReleaseFast full builds pass all 11 steps. The unchanged 508 Zig tests
reuse successful cached results; the new module scaling driver, duplicate scaling
driver, eight verification-driver tests, and 392 VM/native comparisons per host
build mode execute successfully. Zig formatting and git diff whitespace checks
pass. The plan and roadmap link the new module acceptance record. Ordinary-program
review, generics, compile-time/schema/incremental work, wider native operations,
and other unfinished requirements remain pending. Guardian was not exercised and
hosted CI has not run. The full roadmap goal remains active.

## 2026-09-05: Restricted project evaluation foundation

Added eval-project and the evaluation embedding API as the first F implementation.
The command loads/checks the declared module graph, validates bytecode, requires a
parameter-free entry with no inferred transitive effects, and supplies no guest
allocator or external authority. It produces an i64 result under explicit instruction,
frame, and fixed-buffer VM allocation budgets. Effect-free aggregates and calls retain
VM semantics. Unused effectful helpers remain checked but need not be executed.

Defaults are one million steps, 256 frames, and 16 MiB VM allocator storage. Guest
quota exhaustion reports R_EVAL_MEMORY; host backing-buffer allocation failure remains
OutOfMemory. Frontend/lowering/report storage is outside the VM quota, and fixed-buffer
allocation order/fragmentation affects exhaustion. The experiment document records
these limits without claiming whole-compiler memory bounds or cross-target layout.

512 Zig tests pass in Debug and ReleaseFast (456 core, 56 CLI), including aggregate
value/trace parity at 39 instruction budgets, frame and VM-memory exhaustion,
recursive memory pressure, invalid budgets, unused capability rejection, transitive
untaken effects, uncalled effectful helpers, host allocation-failure cleanup, imported
evaluation, and CLI option rejection. A test initially compared uninitialized trace
capacity; it was corrected to compare populated trace entries and lengths.
Eight verification-driver tests, module/duplicate scaling drivers, and 392 VM/native
comparisons per host mode also pass. Formatting and whitespace checks pass.

The roadmap, README, and attached plan now describe this evaluator foundation.
Compile-time source expressions, declared external input manifests, target layouts,
schema derivation, generated bindings, dependency/cache identities, incremental
invalidation, generics, wider native support, and ordinary-program review remain
pending. Guardian was not exercised and hosted CI has not run. The full roadmap goal
remains active.

## 2026-09-05: Evaluation dependency receipts and request identity

Added eval-project --evaluation-report with versioned JSON request/result encoding.
Successful reports retain every loaded source's exact content hash/byte count,
relative module path, resolved imports/aliases, explicit budgets, and SHA-256 of the
running compiler executable plus host build metadata. The canonical request digest
excludes the result. Results use typed decimal strings to preserve all i64 values.
The CLI reads its executable handle directly, with no filename/version-only fallback.

The independent Python acceptance driver recomputes compiler/source/request hashes,
checks exact maximum-i64 output, repeatability, relocation, unrelated-file exclusion,
and budget/source/alias mutation identities. Source/runtime/quota failures emit no
partial JSON. Unit tests cover shared dependencies, minimum-i64 output, changed
implementation identity, invalid/incomplete inputs, and every allocation failure
through report creation/parsing. Option rejection remains covered by CLI tests.

514 Zig tests pass in Debug and ReleaseFast (458 core, 56 CLI). All 12 build steps
pass; the final Debug run reused successful Zig test results and reran the drivers.
The report driver passes in both modes, along with eight verification-driver tests,
module and duplicate scaling acceptance, and 392 VM/native comparisons per host
mode. Formatting and whitespace checks pass. The report contract and conservative
identity behavior are documented; the roadmap and attached plan are synchronized.

This establishes source dependency/request recording, not cached execution or
incremental rebuild savings. External input manifests, schemas/generated bindings,
invalidation/cache reuse, target layouts, generics, wider native support, ordinary
program review, and all other unfinished roadmap work remain pending. Guardian was
not exercised and hosted CI has not run. The full roadmap goal remains active.

## 2026-09-05: Evaluation request identity before execution

Added eval-project --evaluation-request and an embedding preflight API. The shared
preparation path validates bytecode within the evaluation allocation quota and checks
entry authority/effects, stopping before the VM runner. The output explicitly says
not-executed, omits a result, and shares the request encoding/digest with successful
evaluation receipts. Report/request flags are mutually exclusive in both orders.

516 Zig tests pass in Debug and ReleaseFast (459 core, 57 CLI). Tests prove that
trapping and recursive entries can produce eligible requests with one instruction
and one frame, without claiming execution success. Type/authority/effect/quota
rejections retain their diagnostics and empty stdout. Request/report identity parity,
absence of fabricated results, shared dependency encoding, and allocation-failure
cleanup pass. The independent Python receipt driver checks actual CLI parity and
request generation for a trapping imported function.

All 12 build steps pass in both modes, including eight verification-driver tests,
module/duplicate scaling, and 392 VM/native comparisons per host mode. Formatting
and whitespace checks pass. The report contract, README, roadmap, and attached plan
now describe request-only eligibility and its limits. This provides the lookup input
for cache reuse; persistent caching, invalidation/rebuild explanations, external
input manifests, schemas/generation, generics, wider native operations, and other
unfinished roadmap work remain pending. Guardian was not exercised; hosted CI has
not run. The full roadmap goal remains active.

## 2026-09-05: Persistent successful-evaluation caching

Added scripts/evaluate.py with an explicit cache directory and versioned run reporting.
Every lookup invokes the compiler's checked request-only mode. Matching, checksummed,
validated successful reports skip VM evaluation; misses execute the VM and compare
the resulting request with the lookup snapshot before writing. Source/compiler races
fail without caching mixed identities. Source/runtime failures never become entries.
Writes use a flushed same-directory temporary file and atomic replacement, with
cleanup and preservation of existing entries on replacement failure. Cache documents
are bounded and duplicate-key/malformed/wrong-request/invalid-result entries are
rejected and recomputed. The documented cache is trusted local build state, not an
authenticated remote artifact store.

The new actual-compiler acceptance driver verifies cold request+evaluation versus
warm request-only invocation counts, source/budget misses, corruption repair, invalid
decimal/request records, injected write failure, source/runtime rejection without
writes, and source mutation between lookup and execution. All 13 build steps pass
in Debug and ReleaseFast. The unchanged 516 Zig tests (459 core, 57 CLI) pass, with
successful cached test results reused where reported. Eight verification-driver
tests, evaluation receipt checks, module/duplicate scaling, and 392 native parity
comparisons per host mode also pass. The manual module example returns 12 on a cold
miss and a warm hit; the warm run explicitly reports vm=skipped. Formatting and
whitespace checks pass, and the plan/roadmap/attached plan are synchronized.

This completes persistent reuse of successful restricted VM results. Parsing, type
checking, lowering, eligibility, and implementation hashing still run on every lookup.
Dependency-granular frontend/native rebuilds, field-level invalidation explanations,
measured rebuild savings, external data manifests, schemas/generation, generics,
wider native operations, and all other unfinished roadmap work remain pending.
Guardian was not exercised; hosted CI has not run. The full roadmap goal remains active.

## 2026-09-05: Field-level evaluation request comparisons

Added --compare-to and --max-changes to the evaluation cache driver. A chosen request
document, evaluation report, or validated cache entry supplies the explicit baseline.
The output reports deterministic added/removed/changed request fields, before/after
values, both request identities, and explicit truncation. Sources are matched by
logical module name, with dependency order compared separately. Budget/compiler
metadata and ordered imports remain visible. JSON value types are preserved during
comparison, and an encoding-only digest change is distinguished from field changes.
Comparison does not alter lookup eligibility or claim that source changes altered
runtime behavior or saved compilation time.

Extended cache acceptance covers identical requests on real hits, budget and source
changes on actual misses, implementation changes, source addition/removal/reordering,
imports, typed JSON differences, deterministic output, and bounded/truncated reports.
All 13 build steps pass in Debug and ReleaseFast, retaining the successful 516 Zig
tests, eight verification-driver tests, receipt and cache drivers, module/duplicate
scaling, and 392 VM/native comparisons per host mode. The manual CLI comparison
reports exactly /budgets/max_steps changing from 1000000 to 1000001 while preserving
the module example result 12. Formatting and whitespace checks pass.

The cache contract, README, roadmap, and attached plan now document chosen-baseline
invalidation explanations. Automatic baseline selection, frontend/native cache reuse,
dependency-granular rebuilds, measured rebuild savings, external input manifests,
schemas/generation, generics, broader native operations, and other unfinished roadmap
requirements remain pending. Guardian was not exercised and hosted CI has not run.
The full roadmap goal remains active.

## 2026-09-05: Typed scalar input manifest validation and generation

Added the input-module CLI and owned Manifest embedding API. Strict versioned JSON
names a logical module and typed scalar inputs; duplicate names/keys, unknown fields,
reserved identifiers, invalid paths/types/values, noncanonical literals, out-of-range
integers, and explicit byte/count/name limits reject before source output. The lexer
now exposes its identifier classification so manifest names share language keyword
rules. All existing integer widths and bool are supported, with string-encoded values
preserving full i64/u64 precision and preventing source-token injection.

Generation emits ordinary exported parameter-free functions, width-correct literals,
canonical source, and a SHA-256 provenance comment for the complete manifest bytes.
The checked-in input-values example evaluates to 64 and passes project formatting.
Generation writes stdout only. Evaluation currently imports the generated file;
automatic JSON loading and regeneration/freshness checks remain pending.

518 Zig tests pass in Debug and ReleaseFast (461 core, 57 CLI). All 14 build steps
pass. Unit tests cover canonical generated formatting, allocation-failure cleanup,
names/types/values/ranges/duplicates and versions. The actual CLI driver verifies
manifest hashes, deterministic output, imported evaluation at every integer width's
minimum/maximum and both bool values, strict JSON/path/value rejection, and manifest
byte/input-count limits. Existing verification, receipt/cache, module/duplicate
scaling, and 392 native parity comparisons per host mode also pass. Formatting and
whitespace checks pass; roadmap, README, and attached plan are synchronized.

Automatic external-input integration, stale-generation protection, schema derivation,
general serialization/bindings, finer incremental compilation, generics, broader native
support, and other unfinished roadmap work remain pending. Guardian was not exercised;
hosted CI has not run. The full roadmap goal remains active.

## 2026-09-05: Fresh declared inputs in evaluation and cache lookup

Added eval-project --inputs=manifest.json, including request-only and successful
report modes. The compiler reads/validates the manifest, generates its declared
module in memory, and supplies it through the bounded module provider. The explicit
binding takes precedence over a disk file at that logical module path without
writing or modifying that file. Generated source is copied into the owned project
snapshot. Entry-module replacement, unused manifests, and duplicate/empty or
wrong-command bindings reject. Manifest diagnostic formatting is shared with the
input-module command.

The evaluation cache driver forwards --inputs to both lookup and execution. Current
manifest bytes are therefore reread and regenerated before every lookup; edits change
the generated source hash through both values and the exact manifest provenance hash.
Receipts retain generated-source identity, and existing request/report comparison
rejects differing snapshots on misses. Original JSON filesystem paths are not separate
request fields; identical content supplying the same logical module can share a key.

All 14 build steps pass in Debug and ReleaseFast. The unchanged 461 core Zig tests
reuse successful cached results and all 57 actual-CLI tests pass (518 total). Extended
input acceptance verifies stale invalid disk-file override without writes, missing
files/directories, manifest value edits, generated-source receipt hashes, duplicate
bindings, and unused/entry-module rejection. Cache acceptance verifies manifest-driven
misses, refreshed values, and a warm hit while preserving stale disk contents. The
manual cache-driver invocation with --inputs returns 64 for the example. Existing
verification, receipt/cache, module/duplicate scaling, and 392 native comparisons per
host mode also pass. Formatting and whitespace checks pass; documentation and both
plan copies are synchronized.

One manifest binding per evaluation is supported. Multiple simultaneous manifests,
derived schemas, general serialization/bindings, finer incremental compilation,
generics, wider native operations, ordinary-program review, and all other unfinished
roadmap work remain pending. Guardian was not exercised; hosted CI has not run. The
full roadmap goal remains active.

## 2026-09-05: Multiple bounded input manifests and inclusive file budgets

Extended repeated --inputs bindings to at most 16 distinct generated modules, with
1 MiB per manifest and 8 MiB combined. Duplicate literal paths reject as usage errors;
duplicate logical modules across different files reject with both manifest paths.
Every module must remain imported and cannot replace the entry. The bounded provider
resolves unique in-memory bindings without depending on flag order. The cache driver
forwards all bindings to both request and execution.

Exact-boundary acceptance exposed the pinned Zig file reader's exclusive limit:
files reaching the supplied limit are rejected. Manifest and ordinary module provider
reads now add one to implement the documented inclusive byte budgets. Tests accept
eight exact-1-MiB manifests and an exact-4-MiB ordinary module, reject the next byte or
ninth full manifest, execute all 16 bindings, reject a 17th, and reject duplicate module
names. Full request documents remain equal under reversed binding flags. Cache tests
change either of two manifests independently and verify new results, while reversed
unchanged bindings hit the same entry.

All 14 build steps pass in Debug and ReleaseFast. The 461 unchanged core Zig tests
reuse successful cached results and all 57 CLI tests pass (518 total), alongside
extended input/cache drivers, eight verification-driver tests, receipt checks,
module/duplicate scaling, and 392 native comparisons per host mode. Formatting and
whitespace checks pass. Documentation, README, roadmap, and attached plan record the
limits, identity rules, and boundary correction.

Broader input types, schema derivation, general serialization/bindings, finer
incremental compilation, generics, wider native operations, ordinary-program review,
and all other unfinished roadmap work remain pending. Guardian was not exercised;
hosted CI has not run. The full roadmap goal remains active.
