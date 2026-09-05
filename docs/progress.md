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
