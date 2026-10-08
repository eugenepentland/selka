# Implementation progress

> **Record.** Progress up to the new compiler core. Stage S5 (2026-10) replaced
> the QBE back end, the bytecode IR, the tracing collector, two-count reference
> counting, arenas and host functions; see [native builds](tooling/native-build.md)
> and [removed features](legacy/README.md).

> Removed on 2026-09-13: the explicit storage tier (buffers, pools, legacy `list`
> declarations, the `allocator` capability, references and slices, lexical borrows and
> legacy arena scopes), the C backend and the brace dialect these entries are written
> in — `fn`, `let`, `struct`, `new T { … }`, `::` qualification, `//` comments — are gone.
> Entries below that describe any of them are history; see [legacy/](legacy/) and [the current language reference](current-language.md).
>
> Removed on 2026-09-14: the bytecode interpreter that ran the programs these entries
> record. QBE native code is the only runtime — `mylang run` and `run-project` build the
> program and execute it in a child process, `mylang build` writes the executable, and
> `mylang test` runs each guest test as a fresh native process — and the `eval-project`,
> `check-value-project` and `invoke-project` commands went with the interpreter.
> Bytecode survives only as the compiler's internal IR that QBE consumes. Dated entries
> below that describe the interpreter, a VM, or two backends are history.

The scalar MVP and substantial post-MVP experiments are implemented, and all of them now
run as native code: the compiler checks a program, lowers it to its internal bytecode IR,
and QBE compiles that to an amd64 Linux executable. The
[revision 3 plan](plan.md) and [current development-velocity status](audits/velocity-implementation/final-status.md) define
active priorities; the dated entries below preserve milestone evidence, including the
entries written while a bytecode interpreter was the runtime. A dated entry's
"remains open" or "future work" sentence describes that checkpoint, not the current binary.

## 2026-09-06: Interpreter-first direction adopted

The custom Zig bytecode VM is the primary runtime while the design develops.
Further native compilation and native ABI expansion are deferred; completed C
emission, bindings, and parity evidence remain historical assets. No runtime or
build-target behavior changed in this documentation revision.

Next: a focused interpreter acceptance workflow, generic local view/region checks,
diagnostic provenance and repair fixtures, a typed registered host-call boundary,
and a board-validation or constraint-processing trial with independent tests.
Keep expensive geometry/routing in native host libraries. Measure errors caught,
next-attempt repair success, unrelated edits/workarounds, and behavioral correctness
before claiming improved agent reliability. General host registration and the
application trial are pending; existing provider callbacks and native guest-call
ABIs do not establish their completion. See [the trial design](experiments/interpreter-first.md).

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
Formatting and whitespace checks pass. [The B record](legacy/experiments/borrowing.md)
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
[slice semantics](legacy/experiments/slices.md) records the linear immediate-copy cost.

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

[B acceptance](legacy/experiments/b-audit.md) maps scoped references, common helpers,
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

[The ownership record](legacy/experiments/ownership.md) states API contracts and costs.
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

[Source ownership semantics](legacy/experiments/owned-buffers.md) documents restrictions:
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

[Buffer semantics and costs](legacy/experiments/buffer-operations.md) distinguishes backing
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

[Allocator capability semantics](legacy/experiments/allocator-capabilities.md) defines the
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

[Field-read semantics](legacy/experiments/owned-field-reads.md) distinguishes inspection
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

Implemented `restrict_resource[permissions](cap)` as monotone intersection of read,
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

[Resource slice semantics](legacy/experiments/resource-slices.md) documents staging/copy
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

[Typed-pool semantics](legacy/experiments/typed-pools.md) records ownership hooks, storage
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

[Arena semantics](legacy/experiments/arenas.md) records stable-address requirements, parent
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

[Execution arena semantics](legacy/experiments/arena-execution.md) documents one region per
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

[Native execution semantics](legacy/experiments/native-execution.md) records the hosted C
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

[Partial-field semantics](legacy/experiments/partial-fields.md) documents runtime uniqueness,
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

[Source-pool semantics](legacy/experiments/source-pools.md) records syntax, error codes,
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

[Checked region backing](legacy/experiments/region-backing.md) documents the embedding API,
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

[Source arena semantics](legacy/experiments/source-arenas.md) documents field-insensitive,
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

[Arena reset semantics](legacy/experiments/arena-reset.md) records error codes, capability
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
checks pass. [Module native semantics](legacy/experiments/module-native.md) records commands,
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
and whitespace checks pass. [Native domain semantics](legacy/experiments/native-domains.md)
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

## 2026-09-05: Checked public schema derivation

Added schema-project and the schema.render embedding API. Derivation checks the
complete reachable project before emitting a versioned JSON graph rooted in exported
nominal types and function signatures. Qualified names replace compiler-local type
IDs. Sorted definitions/functions/exports remain deterministic across import discovery
order, aliases, comments, and private implementation changes. Fields and variant cases
retain declaration order. Public shape changes alter the output.

Schemas describe integer widths and lossless decimal bounds, record fields, arrays,
enum-keyed tables, closed variants, result obligations, ownership flags, function
parameter reference/slice modes, returned-reference source contracts, and inferred
transitive effects. Domain backing/private factories remain excluded. Runtime owners,
handles, and capabilities are explicitly opaque for reconstruction while retaining
public element, authority, and pool/handle relationships. An iterative worklist handles
cyclic pool/handle graphs without duplicate definitions. Private implementation-only
types are not roots. Empty public interfaces yield empty graphs.

All 15 build steps pass in Debug and ReleaseFast: 519 Zig tests (462 core, 57 CLI),
eight verification-driver tests, the new actual-CLI schema acceptance driver, existing
receipt/cache/input/module/duplicate drivers, and 392 native comparisons per host mode.
The schema unit scenario checks all allocation failures with leak detection. Acceptance
covers nominal identity, privacy, integer bounds, aggregate/variant structure, cyclic
handle graphs, ownership/authority, borrowing/effects, determinism, public shape edits,
duplicate fields, invalid private bodies, private interface leaks, and irrelevant flags.
The checked-in message schema example passes project formatting and schema generation.
Zig formatting and whitespace checks pass; README, roadmap, and attached plan are synced.

The document is a language type graph, not a wire format, JSON Schema standard document,
foreign ABI, or codec. Explicit effect bounds are not separately emitted. Typed
serialization/deserialization, domain codec declarations, external key mappings,
generated bindings, generation receipt/budget integration, finer incremental
compilation, generics, wider native support, ordinary-program review, and all other
unfinished roadmap work remain pending. Guardian was not exercised; hosted CI has not
run. The full roadmap goal remains active.

## 2026-09-05: Bounded ordinary typed JSON serialization and validation

Added typed_json.Document.parse/decode and typed_json.encode for checked ordinary
values, plus check-value-project --value=path.json. The CLI checks every source body,
selects an explicitly exported nominal or built-in type, materializes independently
owned compiler values, and emits canonical typed-json-v1. Private/unknown root names
reject. Source/data failures exit 1 with empty stdout; usage and host failures exit 2.
No source execution, provider invocation, or filesystem output is implicit.

The wire format uses decimal strings for all integer widths, booleans, complete
record objects, fixed arrays, enum-keyed table objects, case-name enums, and explicit
case/value objects for unions/results. Decoded duplicate keys, unknown keys/cases,
missing fields, incorrect shapes/types/ranges, and unsupported versions reject.
Encoding preserves nominal identities and declaration order. Complete type-graph
preflight rejects opaque domain/authority/owner dependencies even in an unselected
union arm or zero-length array. Domain codecs remain explicit future work.

A preliminary JSON scan bounds syntax before DOM allocation; decode/encode bound
value count and depth. Defaults are 1 MiB inclusive bytes, 65,536 value nodes,
262,144 scanner tokens/fragments, and 64 typed value levels. Encoding counts output
bytes before allocating the final output string. Intermediate storage remains host
allocated, with all allocation failures propagated. Partial aggregate decode failures
release acquired values, and encoding borrows without consuming its input. Canonical
decimal validation is shared with scalar input manifests through Type.parseDecimal,
preserving their existing error categories.

All 16 build steps pass in Debug and ReleaseFast: 525 Zig tests (468 core, 57 CLI),
eight verification-driver tests, the new typed JSON CLI driver, existing schema/
input/receipt/cache/module/duplicate drivers, and 392 native comparisons per host
mode. Unit evidence includes independent compiler-value inspection/construction,
every allocation failure, retained ownership, malformed host values, custom budgets,
and partial semantic-failure cleanup. CLI evidence includes all integer ranges,
aggregate/variant/table round trips, privacy/opaque rejection, escaped duplicate keys,
schema changes, invalid private bodies, host/flag failures, and exact byte/value/depth
boundaries. The message-value example validates canonically; formatting and whitespace
checks pass. README, roadmap, and both plan copies are synchronized.

Ordinary typed serialization/deserialization is implemented. Explicit domain codecs,
generated bindings, source-level codec operations, richer declared-input integration,
generation budget/receipt/cache integration, finer incremental compilation, generics,
wider native support, ordinary-program review, and all other unfinished roadmap work
remain pending. Diagnostics currently identify the input file and error category,
without a nested JSON path. Guardian was not exercised; hosted CI has not run. The
full roadmap goal remains active.

## 2026-09-06: Generated standalone Python data bindings

Added scripts/bindings.py, an embedded standalone runtime template, and an executed
Python/ compiler acceptance driver. Every generation invokes schema-project to check
the complete current source graph. Output contains annotated nominal record dataclasses,
closed enums, distinct variant/result case dataclasses, and typed-json-v1 loads/dumps
using only the Python standard library. Arrays decode as tuples and tables as read-only
enum-keyed mappings. Exact native class/type checks preserve nominal identities and
reject Python bool in integer positions. Collision-free escaping preserves module and
field identities while handling Python keywords and special attribute names.

Complete type-graph analysis lists opaque types and all dependent types explicitly as
unsupported. No implicit constructor/codec is generated for domains, authority, runtime
owners/handles, or wrappers containing them. Source result identities remain visible,
but Python clients do not gain the language compiler's static handling obligations.
Generated data bindings do not claim callable function wrappers or a foreign ABI.

The runtime enforces typed JSON byte/value/token/depth limits, strict Unicode and
object keys, full integer ranges, complete aggregate/table shapes, and closed case
names. Typed errors include JSON-pointer paths where available. Generation embeds
schema and generator/runtime content hashes, reports output identity and unsupported
types, caps captured output and compiler elapsed time, checks generated Python syntax,
and installs output atomically. Failures preserve existing output, and timed-out or
oversized compiler children are terminated and reaped. Captured temporary files may
overshoot the size threshold between polls; these limits are not a total memory quota.

All 17 build steps pass in Debug and ReleaseFast: 525 Zig tests (468 core, 57 CLI),
eight verification-driver tests, 29 compiler/Python wire comparisons per compiler host
mode, existing codec/schema/input/receipt/cache/module/duplicate acceptance, and 392
VM/native comparisons per host mode. Python binding acceptance also covers independent
host construction, keyword/nominal collisions, immutable decoded containers, invalid
wire/native values, custom limits, isolated standalone imports, private-change stability,
public-change regeneration, exact output budgets, atomic write cleanup, and process
reaping under time/capture failures. The generated message example runs successfully.
Zig formatting, Python syntax, and whitespace checks pass. Documentation, roadmap,
README, and both plan copies are synchronized.

Standalone Python data bindings are implemented. Explicit domain codecs, callable
foreign wrappers, source-level codec operations, richer declared inputs, generation
receipt/cache integration, finer incremental compilation, generics, wider native
operations, ordinary-program review, and all other unfinished roadmap work remain
pending. Guardian was not exercised; hosted CI has not run. The full roadmap goal
remains active.

## 2026-09-06: Checked incremental binding artifact reuse

Added optional --cache-dir to the binding generator and a versioned generation
request covering the returned public schema, one captured generator/runtime snapshot,
selected compiler executable, Python implementation/version/cache tag/optimization,
and output byte limit. The compiler checks current source before every lookup; its
selected executable hash is compared before/after checking and a detected replacement
rejects generation. Returned schemas, rather than paths or timestamps, determine the
public-contract input. Compiler timeout/capture limits apply freshly before lookup.

Successful artifacts are stored in checksummed, bounded-read cache envelopes. Hits
verify the full request, source/report identities and size, metadata, and Python syntax
without executing the artifact. Corrupt/mismatched entries regenerate; other filesystem
failures remain host errors. The generated source uses the same captured runtime input
as the request. Cache and destination writes are atomic, and invalid source/generation
cannot supply new artifacts. Cache storage is trusted local build storage, not an
authenticated distribution channel.

Before either cached or generated output is installed, complete byte equality now
preserves an unchanged destination's inode and modification time. Stale/deleted output
can be restored from a verified cache hit. This avoids file rewrites even when caching
is disabled or a changed compiler/limit produces identical artifact bytes. The new
python-bindings-run-v1 report distinguishes fresh frontend checking, hit/miss/disabled
cache status, actual generation execution/skips, and replaced/unchanged installation.

All 18 build steps pass in Debug and ReleaseFast. The unchanged 525 Zig tests (468 core,
57 CLI) reuse their successful cached results. The new binding cache driver, existing
29 compiler/Python wire comparisons, eight verification-driver tests, all codec/schema/
input/receipt/cache/module/duplicate acceptance, and 392 VM/native comparisons per host
mode pass. Cache evidence includes actual checked cold/warm execution counts, inode/
mtime preservation, stale/deleted output restoration, corrupt JSON/checksum/report/
request/syntax repair, schema/runtime/compiler/limit invalidation, detected compiler
replacement during checking, rejection of invalid private bodies, disabled-cache no-op
installation, and cache write failure preservation/cleanup. The example produces a
cold miss then a warm generation skip and executes its generated bindings correctly.
Python syntax, Zig formatting, and whitespace checks pass; documentation and both
plan copies are synchronized.

This implements binding artifact reuse and avoids unchanged-output rewrite triggers.
It does not skip the compiler frontend, provide a full source-snapshot generation
receipt, or establish a measured end-to-end speedup. Full generation source receipts,
finer incremental compilation, domain codecs, callable foreign wrappers, source/input
integration, generics, wider native support, ordinary-program review, and all other
unfinished roadmap requirements remain pending. Guardian was not exercised; hosted CI
has not run. The full roadmap goal remains active.

## 2026-09-06: Checked schema and binding source receipts

Added schema-project --schema-report and the schema_report.render embedding API.
The versioned envelope includes the public schema and its digest alongside complete
loaded-source identity: logical entry, dependency-first unique module records, relative
paths, whole-file hashes/byte counts, resolved imports/aliases, and the running compiler
image hash with Zig/target/optimization metadata. Source records use the project-owned
buffers that were checked, without reopening source paths after checking.

Source traversal, implementation formatting, and compact JSON hashing are now shared
with evaluation receipts through source_receipt.zig, retaining the evaluation report/
request formats. Main's executable identity helper serves both receipt paths. Ordinary
schema-project output remains unchanged, and duplicate/misplaced report flags reject.

The binding generator now requests and verifies schema receipts before generation or
artifact lookup. Every run report includes fresh schema_source and its digest, including
on cache hits. Artifact reuse remains keyed to the public schema and generation inputs,
so private source edits can change provenance while retaining a hit and unchanged output.
The cache request also records the actual compiler image reported by the schema process,
separately from the selected launcher hash for wrapper support.

All 19 build steps pass in Debug and ReleaseFast: 526 Zig tests (469 core, 57 CLI),
eight verification-driver tests, independent schema receipt acceptance, 29 compiler/
Python wire comparisons, binding/evaluation cache acceptance, all existing codec/schema/
input/module/duplicate drivers, and 392 VM/native comparisons per host mode. Receipt
acceptance independently verifies source/compiler/schema hashes, byte counts, shared
dependencies, relocation, unrelated files, private/public/alias changes, rejection and
integrity/order checks, and fresh provenance on binding hits. A project unit scenario
removes provider files after loading and exercises all allocation failures, proving
owned-snapshot use and cleanup. Python syntax, Zig formatting, and whitespace checks
pass; documentation, roadmap, README, and both plan copies are synchronized.

Complete loaded-source receipts for schema/binding generation are implemented. They
identify the checked bytes rather than archive source text or claim a filesystem-wide
atomic snapshot. Frontend/declaration-granular incremental compilation, domain codecs,
callable foreign wrappers, source-level codec/input integration, generics, wider native
support, ordinary-program review, and all other unfinished roadmap work remain pending.
Guardian was not exercised; hosted CI has not run. The full roadmap goal remains active.

## 2026-09-06: Owned typed JSON failure locations

Added optional located parse/decode/encode APIs and CLI JSON-pointer diagnostics.
Checked failures now identify nested record fields, array indices, enum-table keys,
variant discriminators/payloads, declared types, and unsupported document versions.
Missing fields are identified in schema order before materialization; extra object
fields identify their containing object, and array arity errors identify the first
missing/excess index. Existing unlocated APIs retain their signatures.

One bounded traversal stack records the deepest failure into an owned 4-KiB Location
buffer without allocating. Locations survive document/catalog teardown, reset before
reuse, escape JSON-pointer separators, and retain valid UTF-8 when truncated. CLI
rendering quotes the pointer and explicitly marks a truncated prefix. Out-of-memory
failures remain host failures; located decoding rechecks mutable embedding limits.
Raw JSON syntax/duplicate-key errors may still have no known pointer and retain their
input filename/error category. Message rendering follows ordinary host allocation
policy; location capture itself allocates nothing.

All 19 build steps pass in Debug and ReleaseFast: 529 Zig tests (472 core, 57 CLI),
eight verification-driver tests, extended typed JSON acceptance, all schema/source/
input/cache/module/duplicate checks, 29 compiler/Python wire comparisons, and 392
VM/native comparisons per host mode. Unit evidence covers independent location
ownership, malformed nested native values without consuming input, reset after
success, escaping, ASCII/UTF-8 truncation, mutated limits, allocation failures, and
existing partial-decode cleanup. CLI evidence covers nested result/union/record/
array paths, missing payload/table keys, integer ranges, discriminator/type/version
selection, excess elements, and explicitly truncated long field names. Python syntax,
Zig formatting, and whitespace checks pass; roadmap, README, documentation, and both
plan copies are synchronized.

Typed value failure locations are implemented. Domain codecs, source-level codec/input
integration, callable foreign wrappers, generics, wider native operations, finer
incremental compilation, ordinary-program review, and all other unfinished roadmap
work remain pending. Guardian was not exercised; hosted CI has not run. The full
roadmap goal remains active.

## 2026-09-06: Native packed tagged unions and results

Extended C emission with checked packed layouts for scalar-payload unions/results,
including nested variants, nominal scalar domains, and enums. An iterative memoized
layout walk supports complete payload graphs up to 127 bits; unsupported records,
arrays, owners, and oversized layouts remain explicit E_NATIVE_FEATURE failures.
Unsigned packing and explicit signed extraction preserve integer extrema without
signed-shift overflow. This internal representation is not a public ABI or wire format.

Construction, exhaustive matching, copyable union assignment, result local moves,
acknowledgement, and try propagation now emit directly. Error propagation repacks
named error cases across result declarations while clearing only the callee's
unfinished operands. Caller operands, frontend handling obligations, and instruction
budget behavior remain intact. The native-results example builds and prints 20.

Validation: 532 Zig tests (475 core, 57 CLI) pass in Debug and ReleaseFast; 770
VM/native comparisons per compiler host mode cover 40 single-file and eight module
fixtures at -O0/-O2 with undefined-behavior sanitization. New cases cover nested
variants/results, signed minima, maximum u64, domain payloads, copy/assignment,
reversed result tags, skipped traps, caller operands, every instruction budget in
small cases, cross-module diagnostics, and a 127-bit value. Unit tests cover every
allocation failure, handling/exhaustiveness rejection, unsupported payloads, and
128-bit layout rejection. All existing schema/codec/input/cache/module/duplicate
acceptance drivers, eight verification tests, and 29 Python/compiler wire comparisons
also pass. Formatting, Python syntax, and whitespace checks pass.

ReleaseFast completed all 19 build steps. Debug's full run passed all Zig tests and
other acceptance drivers, but its native driver encountered a host linker abort.
An isolated retry and syscall trace identified SIGBUS while writing a mapped output
file on /tmp; the same C compiled on the project filesystem. The complete Debug
native driver then passed with TMPDIR set to a directory in .zig-cache, retaining
the exact pinned Zig and sanitizer flags. Failure assertions now include the fixture,
mode, and compiler exit code. No backend behavior was changed to bypass this failure.

README, roadmap, experiment documentation, and both plan copies are synchronized.
Native records/arrays/resources/borrowing and wider layouts remain pending, as do
generics, domain codecs, foreign callable wrappers, source/input integration, finer
incremental compilation, ordinary-program review, and other unfinished roadmap work.
Guardian was not exercised; hosted CI has not run. The full roadmap goal remains active.

## 2026-09-06: Native ordinary aggregates and allocation-failure cleanup

Extended native C values with reference-counted immutable field storage. Records,
fixed arrays, enum-indexed tables, complete conversions, field access, preserving
updates, checked indexing/replacement, length queries, and aggregate arguments/
returns now execute directly in single-file and module projects. Result-bearing
records support partial field transfers and non-consuming reads. Small variants
retain packed storage; aggregate payloads and widths beyond 127 bits use boxes.
Typed error propagation crosses packed/boxed result representations while preserving
named cases, caller operands, static handling obligations, and instruction budgets.

Copies retain storage and updates retain unchanged children. Assignment and scope
exit release old values promptly. Normal release walks an intrusive work list without
host recursion or cleanup allocation. A separate live-object registry supports direct
failure cleanup, including temporary/partial values during construction and stack/
frame allocation failures. Unsupported resource, buffer, pool, handle, capability,
and borrowing operations still reject explicitly. Layout checking traverses complete
type dependencies, including zero-length array element types. No public ABI or VM/
native physical-allocation equivalence is claimed.

All 20 build steps pass in Debug and ReleaseFast: 533 Zig tests (476 core, 57 CLI),
1,506 VM/native comparisons per compiler host mode across 51 single-file and 10 module
fixtures, eight verification tests, 29 Python/compiler wire comparisons, and all
existing schema/codec/input/cache/module/duplicate acceptance. Native execution uses
UBSan at -O0/-O2. The new native memory driver additionally uses AddressSanitizer and
injects 38 allocation failures across both native modes, checking zero outstanding
runtime bytes after host errors. Normal/trap/step/frame cleanup passes; a 20,000-update
loop preserves an earlier copy and keeps peak live storage below 64 KiB. Compiler
allocation-failure tests cover aggregates and boxed propagation. The array example
builds natively and prints 44. Formatting, Python syntax, and whitespace checks pass.

Validation used TMPDIR under .zig-cache/native-validation to avoid the previously
observed /tmp linker mapping fault, retaining the pinned Zig and sanitizer settings.
README, native experiment documents, roadmap, and both plan copies are synchronized.
Native borrowing/resources/capabilities/pools/arenas, generics, domain codecs, callable
foreign wrappers, source/input integration, finer incremental compilation, ordinary-
program review, and the other unfinished roadmap work remain pending. Guardian was
not exercised; hosted CI has not run. The full roadmap goal remains active.

## 2026-09-06: Native ordinary-value borrowing and returned views

Extended C emission with scoped shared/exclusive loans, reborrows, reference/slice
parameters, checked slice ranges/access/writes, and returned-reference contracts.
Stable per-frame owner and reference storage survives frame-vector growth. Root
loans lock the full owner; exclusive parents suspend while children are active,
shared parents remain readable, and child/owner access checks preserve the VM rules.
Writes replace values or create updated arrays, preserving existing value snapshots.

Calls place ordinary arguments in their source parameter slots and reborrow reference
arguments separately. Returned views capture the declared caller owner's range,
end callee loans, and create a fresh caller-side child loan. Normal frame exit checks
that references are inactive; terminal cleanup frees reference/local storage and
aggregate allocations without traversing stale parent pointers. Native reference
values remain inaccessible as ordinary guest values, and existing static lifetime,
provenance, type, and exclusivity checks run before emission. Buffer/resource/pool/
arena operations still require their remaining native implementation.

All 20 build steps pass in Debug and ReleaseFast: 535 Zig tests (478 core, 57 CLI),
2,434 VM/native comparisons per compiler host mode across 64 single-file and 12
module fixtures, eight verification tests, 29 Python/compiler wire comparisons,
and all existing schema/codec/input/cache/module/duplicate drivers. Executed cases
cover mixed value/reference arguments, shared aliases, recursive reborrows across
frame growth, empty and narrowed slices, bounds traps, whole-record reference
returns, nested returned slices, propagation cleanup, snapshot preservation, and
cross-module locations/call frames. Small cases compare every instruction budget
at native -O0/-O2 with UBSan. Compiler allocation-failure tests and static rejection
cases also pass. The native returned-references example prints 20.

The expanded native memory driver passes independently with both compiler host
modes after adding recursive frame-growth fault coverage. It now injects 236
allocation failures across native -O0/-O2, including active reborrows and returned
views, and verifies zero outstanding runtime allocation bytes under AddressSanitizer
and UBSan. Normal/trap/step/frame cleanup and the retained-snapshot 20,000-update
memory bound also pass. Tests use the project filesystem for temporary native
outputs via TMPDIR, retaining the exact pinned Zig and sanitizer settings.

Formatting, Python syntax, and whitespace checks pass. README, native experiment
documents, roadmap, and both plan copies are synchronized. Native resources and
capabilities, pools/arenas, generics, domain codecs, foreign callable wrappers,
source/input integration, finer incremental compilation, ordinary-program review,
and other unfinished roadmap work remain pending. Guardian was not exercised;
hosted CI has not run. The full roadmap goal remains active.

## 2026-09-06: Initial ordinary-application corpus and duplicate review

Added an invoice calculator and borrowed packet decoder under examples/corpus:
13 modules, 320 canonical source lines, explicit import policies, and a checked-in
review explaining the application contracts and quality/discovery decisions. The
invoice combines quantity/money domains, exhaustive catalog tables, typed results,
aggregate calculations, and complete conversion to a public Receipt. The decoder
combines borrowed byte slices, frame validation, checksum/unsigned decoding, typed
errors and variants, and exhaustive caller handling.

Exact/near discovery reports one 21-node exact pair for independent delivery and
packaging tariffs and one near pair showing the handling increment's 100-to-150
change. Both are deliberately retained as separate policies, with an executed
independent delivery edit showing that packaging remains unchanged. Invoice search
uses 25,142 work units without truncation; packet search uses 4,858 with no exact or
near candidates. Default quality reports show all 21 functions statically reachable
and correctly leave runtime coverage unmeasured. A cohesive 103-byte decoder
condition is retained after its default 100-byte review signal; no extraction or
threshold change is made solely to appease the metric.

Added tests/corpus_review.py to the build. Independent Python expectations cover
24 invoice and 24 packet inputs, including domain limits, rounding and fee/discount
boundaries, maximum unsigned readings, malformed frames, and seeded valid cases.
Every case executes with general/arena VM memory and native -O0/-O2 under UBSan:
192 oracle checks per compiler host build mode. The driver also checks canonical
module formatting, deterministic non-mutating discovery, quality/export roots,
explicit import policy and denied added edges, added-product table completeness,
added-source-field conversion accounting, added-message-variant match coverage,
typed JSON and generated Python binding round trips, and declared-input evaluation
without overwriting source inputs.

All 21 build steps pass in Debug and ReleaseFast. The unchanged 535 Zig tests reuse
successful cached results; all existing 2,434 VM/native comparisons, 236 native
allocation-failure cases, eight verification tests, 29 Python/compiler wire
comparisons, and schema/codec/input/cache/module/duplicate acceptance pass alongside
the new corpus checks. Python syntax, Zig formatting, and whitespace checks pass.
Native temporaries use the project filesystem through TMPDIR. Both entry examples
produce their documented results, 7019 and 30064771372.

This completes an initial authored ordinary-program review; it is not independent-
user or production-deployment evidence. The review found no new compiler defect.
It records continuing limitations around explicit domain codecs, callable foreign
wrappers, unbounded inputs/real transport, and broader production evidence. README,
roadmap, related module documents, and both plan copies are synchronized. Native
resources/capabilities/pools/arenas, generics, domain codecs, foreign callable wrappers,
source/input integration, finer incremental compilation, remaining discovery/tooling
work, and other unfinished roadmap requirements remain pending. Guardian was not
exercised; hosted CI has not run. The full roadmap goal remains active.

## 2026-09-06: Typed invocation foundation for explicit domain codecs

Added vm.invoke and project Compilation.invokePublic so embedding callers can run
checked effect-free factories with typed arguments and receive an owned typed value
or a source trap without changing the program's main entry. Project selection
requires an exported function or public method of an exported domain; private
construction, references at the call boundary, authority/resource graphs, and
transitive effects are rejected. Ordinary run/runWithOptions behavior is retained.

Arguments are structurally checked and independently copied into the invocation
allocator, with a shared value-count budget and bounded traversal depth. Partial
copies clean up on allocation failure. Returned values may outlive the argument
allocator, while nominal IDs and trap metadata retain their documented compilation
lifetime requirements. Exact instruction counts and step/frame limits are exposed.
Structural checks cannot establish invariants for host-fabricated domain values;
future untrusted decoding must invoke a declared checked factory on wire values.
Invocation does not itself impose a total-memory or output-expansion limit.

Six new tests cover successful and rejected Positive factory inputs, export/privacy,
unchanged integer entry execution, cross-allocator snapshots, malformed arguments,
shared argument budgets, exact step boundaries and frame traces, and every allocation
failure through compilation, invocation, and nested argument copying. Initial full
runs exposed an unnecessary allocation of all export roots during public selection;
direct lookup now shares the existing export predicate and the focused failure
injection tests pass. The complete ordinary-type graph checker is shared with JSON,
which retains its existing errors and continues to reject implicit domain codecs.

Debug and ReleaseFast pass all 21 build steps and 541 Zig tests (484 core, 57 CLI).
Existing acceptance also passes: 2,434 VM/native comparisons, 236 native allocation-
failure cases, 192 application oracle checks per host mode, eight verification
tests, and 29 Python/compiler wire comparisons, alongside the schema/input/cache/
module/duplicate drivers. Formatting and whitespace checks pass. README, experiment roadmap,
typed-invocation documentation, and both plan copies describe this foundation and
its limits. Explicit codec declarations, whole-codec budgets, JSON/schema integration,
source codec operations, callable foreign wrappers, and the other pending roadmap
requirements remain unfinished. Guardian was not exercised; hosted CI has not run.

## 2026-09-06: Explicit domain codec declarations and schema contracts

Domains can declare codec Wire { decode: method, encode: method } inside their
bodies. The parser rejects duplicate codecs and duplicate, missing, or unknown
entries. After full body/effect checking, semantic resolution requires public
methods of that exact domain, one value parameter each, no reference return, and
no transitive effects. Decoders accept Wire and return a typed result whose ok
payload is the domain; encoders accept the domain and return Wire. Complete wire
and error graphs must be ordinary data, including all variant branches and array
elements regardless of runtime selection or length. Their representation cannot
implicitly depend on another domain or runtime authority/owner.

Resolved wire/method identities are retained in typed and bytecode records. Module
source relocation and existing public signature visibility checks preserve qualified
identities and private-interface rejection. Public schemas add the explicit wire,
decode, encode, and error_type contract while retaining opaque=true and omitting
private backing/constructors. Changing the selected method changes the schema;
existing schema/artifact identities therefore include the declaration. Domains
without declarations keep their previous public representation.

Five new Zig tests exercise declaration-selected factory success/error execution,
module schemas/public invocation, malformed contracts and complete-graph rejection,
formatting stability/comments, and every allocation failure through compilation,
schema derivation, and calls. CLI schema acceptance checks contract contents,
method-selection changes, private/unknown methods, duplicate entries, wrong wire
types, private interfaces, and original diagnostic paths. The new two-module example
prints 7 and joins native acceptance at -O0/-O2 with UBSan, including every instruction
budget through successful completion and frame-limit comparisons.

Debug and ReleaseFast pass all 21 build steps and 546 Zig tests (489 core, 57 CLI).
The first full Debug process terminated with exit 143 before a build summary, without
a test failure in its captured output; after confirming it stopped, the complete
rerun passed. Native coverage is now 2,490 VM/native comparisons across 64 single-
file and 13 module fixtures per host mode. Existing 236 native allocation-failure
cases, 192 application oracle checks, eight verification tests, 29 Python/compiler
wire comparisons, and schema/input/cache/module/duplicate acceptance also pass.
Focused codec tests, CLI schema acceptance, canonical example formatting, Python
syntax, Zig formatting, and whitespace checks pass. The plan attachment and repository plan are synchronized.

This is declaration/schema implementation, not completed domain serialization.
Representation-only typed JSON still rejects domains, and generated Python data
bindings still treat them as unsupported. Codec-aware traversal/execution, shared
whole-operation budgets, source codec operations, callable bindings, and the other
pending roadmap work remain open. Contracts do not prove validation predicates or
round-trip laws. Guardian was not exercised; hosted CI has not run.

## 2026-09-06: Executed domain JSON with shared operation budgets

Added codec_json decode/encode/project-round-trip APIs and integrated them into
check-value-project. Ordinary traversal now executes the declared decoder/encoder
at domain occurrences in records, arrays, enum-indexed tables, and variant payloads.
Wire values are checked before calling factories; decoder typed errors remain owned
values with domain identity and JSON pointers, and traps retain source frames.
Complete type checks reject missing codecs in inactive variants/zero arrays and
reject recursive host wire metadata before traversal. Representation-only typed_json
APIs keep rejecting domains.

An operation shares guest steps, call attempts, requested live allocation bytes,
and traversal work across domain occurrences and both round-trip directions. Existing
per-direction JSON value/depth/byte/token limits remain intact. The forwarding
allocator includes parse/materialization, validation, invocation copies/bookkeeping,
results, serialization temporaries, and returned buffers, while excluding existing
caller inputs and frontend/source storage. It preserves caller allocator ownership
and distinguishes a quota denial from host OutOfMemory. Codec invocations during
encoding use reclaiming storage separate from the JSON arena. Optional statistics
report actual steps, calls, work values, and peak requested live bytes.

CLI options expose step/frame/call/memory/work limits. Defaults are one million
steps, 256 frames, 4096 call attempts, 32 MiB live requested bytes, and 131072 total
traversal values, plus the unchanged 65536-value per-direction JSON limit. The initial
16 MiB default passed the large ordinary JSON boundary in Debug but rejected it in
ReleaseFast and Python binding parity. Direct release measurements confirmed failure
at 16 MiB and success at 24/32 MiB; the default now uses 32 MiB. This does not remove
the enforced quota or imply every structurally valid input fits every memory limit.
Lower quotas can also change arena growth decisions, so a measured successful peak
is not necessarily a minimum budget.

Seven new Zig tests cover nested success/rejection, owned typed errors and reuse
protection, exact shared steps/calls/work, memory limits versus host allocation
failures, frame traces, private-storage-independent wire depth, maximum u64 values,
complete-graph rejection, and allocation failures through project round trips.
The existing CLI driver now covers domain roots, arrays, unions, tables, malformed
wire values, typed rejection output, JSON paths, limit/option validation, and declared
normalization (19 to 10). Ordinary JSON and binding boundary fixtures remain required.

Full Debug and ReleaseFast validation pass all 21 build steps and 553 Zig tests
(496 core, 57 CLI). Existing 2490 VM/native comparisons, 236 native allocation-
failure cases, 192 application oracle checks per host mode, eight verification
tests, 29 Python/compiler wire comparisons, and schema/input/cache/module/duplicate
acceptance also pass. Focused tests, CLI examples, Python syntax, Zig formatting,
and whitespace checks pass. Documentation and both plan copies describe the new
API/CLI behavior, ownership, limits, and remaining work; a sample wire document is
checked in with the domain-codec example. Source serialization operations, generated
callable bindings, richer input integration, and the other pending roadmap work
remain unfinished. Guardian was not exercised; hosted CI has not run.

## 2026-09-06: Schema-pinned public JSON function calls

Added invoke-project --request and codec_json.invokeProject. typed-call-v1 requests
supply the expected compact public schema SHA-256, qualified exported function name,
and complete named JSON arguments. The full loaded project is checked/lowered;
the schema is derived from those same owned source buffers and checked before
argument codecs execute. Public function selection shares the existing export
predicate without allocating an export list. Preflight rejects effects, references,
and complete parameter/result graphs without wire representations.

Argument decoding, the target invocation, and result encoding share existing live
memory, guest-step, invocation-attempt, and traversal-work limits. Request bytes and
tokens cover the entire document; all arguments share the per-direction value limit.
The target counts as one invocation attempt in addition to argument/result codec
calls. Schema rendering is accounted for, and its temporary text is released before
argument materialization. Output remains a typed-json-v1 envelope. A target's typed
err result is output data, while an argument decoder rejection is a located failure.
Target traps retain source frames and /function; argument paths use /arguments/name,
and output codec paths use /value. The trace accommodates the extra request envelope
while retaining the full 128-level embedding value-depth boundary.

Four new Zig tests cover named/reordered domain arguments, ordinary/result outputs,
zero-argument/max-u64 calls, schema/visibility/effect/reference/argument preflight,
exact shared budgets, memory limits, typed argument rejection, source traps, maximum
depth, and every allocation failure through schema/request/call/result processing.
The new tests/call_json.py build driver independently computes the schema pin and
exercises the actual CLI, including stale signatures, fresh same-schema body edits,
invalid private source, duplicate/unknown request keys, typed errors, byte boundaries,
option validation, and failure-output suppression.

Debug and ReleaseFast pass all 22 build steps and 557 Zig tests (500 core, 57 CLI).
Existing 2490 VM/native comparisons, 236 native allocation-failure cases, 192
application oracle checks per host mode, eight verification tests, 29 Python/compiler
wire comparisons, and schema/input/cache/module/duplicate acceptance also pass.
Focused tests, CLI acceptance, Zig formatting, Python syntax, and whitespace checks
pass. README, experiment tracking, and both
plan copies describe this executable request boundary and its limits.

Generated callable wrappers and Python domain wire representations remain pending;
this milestone supplies the schema-checked call protocol they need. Source codec
operations, native ABI integration, richer inputs, and the other unfinished roadmap
requirements remain open. Schema pins establish interface compatibility, not fixed
implementation semantics. Guardian was not exercised; hosted CI has not run.

## 2026-09-06: Guardian compiler-quality integration

Guardian now gates the Zig compiler implementation on build, test, run, and local
commits. The configuration selects strict policy, blocking builds, and disabled
violation baselines. Unit and CLI test roots are registered explicitly, both use
Guardian's counting runner, and SPEC.md links 45 implemented behavior contracts
to regression tests. The local commit hook is installed; other clones install it
with the documented command. Hosted CI checks out the pinned Guardian sibling.

Three sub-agents helped refactor semantic checking, runtime ownership, dependency
structure, test organization, and integration, with an independent review of VM,
parser, CLI, and quality-analysis changes. Large dispatchers now delegate focused
operations; recursive runtime types share one model; metadata groups express
ownership, signatures, policy, and runtime storage. Public error sets are explicit,
cleanup paths preserve failures, and malformed-input/ownership/budget tests cover
newly exposed boundaries. Existing arena quotas and assertions were preserved;
a value-layout regression caught during validation was fixed to retain 48-byte
VM slots.

A genuine Guardian accessor false positive was fixed separately: a method named
allocator or gpa no longer counts as an owned allocator field. The Guardian fix
passed all 1,391 tests and is committed as 9f32fe8. Its required feedback is recorded
and committed in Guardian. The language's full gate passes all 88 checks, and the
live debt report finds no frozen items or ratchet ceilings. Recommended size and
line-length advice remains report-only; passing the gate is not a claim of zero
advice or production readiness.

Acceptance validation also exposed an independent cache-reader mismatch in the
pre-existing Python wrapper work. The cache now accepts and validates both legacy
reports and the complete optional wrapper-metadata pair, with checksum-valid
corruption coverage. Earlier wrapper generation/runtime edits remain separate.
CLI fixtures moved with their test root, including the native driver's shared
fixture references.

Debug and ReleaseFast validation cover 580 Zig tests (523 core, 57 CLI), the
2,490 VM/native comparisons, 236 native allocation-failure cases with sanitizers,
192 application oracle checks per mode, and all existing Python acceptance drivers.
Formatting, build, run, and complete-test compilation pass. The independent cache
fix also passes against a staged export containing the original generator/runtime.
The workflow's
Guardian revision is local and must be published before hosted CI can fetch it;
no hosted CI run or language remote exists. The language roadmap remains open.

## 2026-09-06: Generated callable Python bindings

Completed the previously unfinished Python wrapper generation and embedded call
runtime. Generated modules expose nominal typed functions, qualified CALLS entries,
Client.call, and explicit unsupported-function reasons. Domain wire classes carry
ordinary data; each incoming domain is validated by the language's declared decoder,
and results use declared encoders. Standalone data codecs retain opaque-domain
rejection. Calls freshly check source and pin the full public schema, retaining
same-schema body freshness while rejecting stale interfaces before execution.

CallLimits carries shared VM/codec budgets and host JSON validation limits. The
subprocess bridge preserves typed result errors as data, reports compiler failures
with diagnostics/status, validates returned type envelopes, and reaps timed-out or
oversized-output processes. Capture is a polled temporary-file threshold, not a hard
disk quota. No shell or separately installed Python runtime package is needed.

Added the actual-compiler tests/python_calls.py driver to the standard build suite,
covering nominal/domain/result calls, u64 boundaries, invalid arguments, decoder
rejections, source traps, budgets, source/schema changes, timeout, capture, missing
executables, stderr delivery, and output type mismatch. The checked-in domain call
example also executes successfully. Existing standalone codec and cache tests
continue to pass; the initial wrapper work is now included in this milestone.

Debug and ReleaseFast pass all 26 build steps, including the new callable Python
acceptance driver and the unchanged 580-test Zig suite (cached successful runs),
2,490 VM/native comparisons, sanitizer failure cases, and application corpus.
Guardian passes all 88 checks with no frozen violations. This completes the initial
Python callable-wrapper and domain-wire milestones, not the broader roadmap.
Source serialization operations, call/input-manifest integration, native ABI and
resource expansion, generics, finer incremental compilation, and other pending
requirements remain open. Hosted CI remains unexecuted.

## 2026-09-06: Declared manifests for schemas and Python calls

Extended the existing in-memory input-module loader to schema-project,
check-value-project, and invoke-project. Binding generation forwards repeated
--inputs selections during fresh checked schema derivation; generated Client
instances copy/resolve their input paths and forward them on every invocation.
Inputs retain existing module conflict/import checks and explicit count/byte limits.
Output/cache writes cannot replace selected manifests.

Input value changes produce fresh execution results and source receipts while
allowing identical-schema binding artifact reuse. Input type changes that alter the
public schema reject old generated calls and regenerate artifacts. No values are
silently captured in clients, and no generated source is written to disk. Added
actual-CLI schema loading/malformed-input coverage, CLI-4 in SPEC.md, and the
call_inputs.py acceptance driver for fresh values, schema changes, receipt/cache
behavior, input selection validation, and manifest preservation.

Debug and ReleaseFast pass all 27 build steps: 523 core tests (cached) and
58 CLI tests, the new declared-call-input driver, existing Python acceptance,
2,490 VM/native comparisons, and 236 sanitizer allocation-failure cases.
Formatting and Python syntax checks pass.
Guardian passes all 88 checks; change-classification prompted the linked CLI
regression and is labeled useful-review in the local ROI record. Mandatory feedback
is committed in Guardian. This completes initial call/input-manifest integration;
source serialization, native expansion, generics, finer incremental compilation,
and the other open roadmap requirements remain pending. Hosted CI has not run.

## 2026-09-06: Bounded incremental module syntax

Added an owned syntax_cache.Cache and interfaces.buildWithCache for repeated
embedding compilations. Exact source path/bytes/body-start matches reuse successful
parse tables; each hit deep-copies nested syntax into the fresh project arena.
Oldest-insertion eviction and arena-capacity/entry limits bound retained storage,
with explicit hit/miss/store/eviction/bypass observations. Invalid syntax is never
cached. Allocation failures propagate with cleanup; clearing the cache cannot
invalidate returned syntax.

Extracted the existing checked AST relocation walker into a shared copier, avoiding
separate recursive traversal implementations. A fresh project still loads and lexes
module headers, rebuilds symbols/interfaces, resolves names, and checks every body,
including ownership and effects. A cached parse therefore cannot conceal changed
private declarations, dependency signatures, or invalid caller behavior. The cache
skips the interface phase's repeated lexer/body-parser work; no whole-build speedup
is claimed, and ordinary CLI invocations remain uncached.

Five new tests cover repeated hits, body edits and results, clearing before use,
every allocation failure, eviction, source/expanded-syntax budget bypasses, fresh
semantic/privacy errors on cache hits, invalid syntax recovery, and provider bounds.
The existing source relocation tests pass with the shared copier. Debug and
ReleaseFast pass all 27 build steps and 586 Zig tests (528 core, 58 CLI), plus the
existing native parity, sanitizer, Python binding/input/cache, and corpus drivers.
Guardian passes all 88 checks with no frozen violations. The mapper allocator
ownership false positive and specification-ID collision are recorded in committed
Guardian feedback; the former has an evidence-backed ROI label.

This implements the first frontend query-reuse component. Persistent syntax and
semantic queries, finer invalidation, CLI sessions, native incremental linking,
generics, source serialization, and other pending roadmap requirements remain open.
Hosted CI remains unexecuted.

## 2026-09-06: Persistent CLI checking sessions

Added check-session with a serial check/clear/quit stdin protocol and one JSON
status/reuse/cache reply per command. Each check reloads files and selected input
manifests, creates fresh request/project storage, and reruns interface and semantic
checks through the bounded syntax cache. Source and host failures can be corrected
without restarting; clear releases retained syntax. EOF, unknown commands, final
lines without newline, and oversized requests have explicit behavior. Diagnostics
remain on stderr; the command is a checker, not a guest execution server or LSP.

The actual-process Python driver verifies cold/warm reuse, one-module edits,
semantic errors on warm cache hits, privacy/removal recovery, cache clearing,
repeated checks, request limits, unsupported VM options, and fresh manifests.
Two Zig CLI regressions cover redirected session input/output, reuse/clearing,
and host-failure recovery. The driver runs in the standard build in both modes.
Debug and ReleaseFast pass all 28 build steps, covering the 528 core tests
(cached) and 60 CLI tests, the new session driver, native parity/sanitizer cases,
and existing Python/application acceptance. Formatting passes. Guardian passes
all 88 checks without frozen violations.

This exposes the existing frontend reuse component through a persistent CLI.
Persistent/semantic query caches, automatic watching, structured diagnostic framing,
native expansion, generics, source serialization, and other pending roadmap items
remain open. Hosted CI remains unexecuted.

## 2026-09-06: Native owned buffers

The native emitter and C runtime now support root allocator parameters, supported
owned buffer elements and wrappers, acquisition, queries, mutation, reserve,
ownership cleanup, and borrowed buffer slices. Aggregate snapshots remain valid
across buffer writes, growth, shrinking, and scope exit. Unsupported clock and
external resource types still fail preflight without partial C output.

Debug and ReleaseFast pass all 28 build steps, covering 529 core tests (cached after a
successful fresh run) and 60 CLI tests, 2,538 VM/native comparisons across 71
single-file and 14 module fixtures, and 322 injected native allocation failures
with address/undefined sanitizers at both C optimization levels. Buffer memory
cases use independent expected values and compare step/frame behavior with the VM.
Formatting and the strict Guardian gate pass. The first full runs identified one
outdated CLI expectation rejecting allocator parameters; it now checks rejection
of the still-unsupported clock capability instead. Both corrected complete runs
pass, retaining the successful core-test results.

Native arenas, pools, external resources, generics, source serialization, and the
other pending roadmap requirements remain open.

## 2026-09-06: Native lexical arenas

Native arena entry/exit and reset now use aligned chunk backing, checked allocator
identities, a bounded registry with fresh identities on slot reuse, parent/child
lifetime accounting, and live-owner reset guards. Buffer reserve retains its
original allocator. Independent aggregate snapshots can survive arena teardown.
Normal scope exit, function return, propagation, traps, and host allocation failure
release the appropriate ownership and backing storage.

Debug and ReleaseFast pass all 28 build steps: 530 core tests reused after a successful
fresh run, 60 CLI tests, 2,568 VM/native comparisons, and 380 injected allocation
failures under address/undefined sanitizers at both C optimization levels. Coverage
includes region limits, root reset rejection, zero-capacity owners, wrong-region
reserve, returned snapshots, partial-acquisition propagation, and 20,000 iterations
of bounded arena allocation/reset. Formatting and all 88 Guardian checks pass.
The original Debug run passed its other checks but retained an outdated CLI
expectation rejecting arena-reset emission. That test now verifies successful
emission and retains its semantic rejection checks. The corrected complete Debug
and ReleaseFast runs pass.

Native pools and external resources remain unsupported, and the other pending
roadmap tracks remain open.

## 2026-09-06: Native pools and generation-checked handles

The C backend now supports pool acquisition, queries, insertion, snapshot reads,
replacement, removal, clear, and nominal handle equality. Pool identity and slot
generation checks reject foreign/stale handles. Removal and clear invalidate old
IDs; exhausted generations retire slots. Shared owner/per-pool/total-slot quotas
match the VM defaults, including empty owners. Pool backing uses root or arena
allocation, and retained ordinary snapshots remain independent of owner lifetime.

Debug and ReleaseFast pass all 28 build steps and 591 Zig tests (531 core, 60 CLI).
Native acceptance covers 2,616 comparisons across 83 value and 15 module fixtures;
the new imported pool/handle-bundle case was rerun separately with both compiler
modes after the original ReleaseFast parity driver completed. Sanitizer acceptance
passes 468 injected allocation failures and bounded 20,000-iteration pool lifecycle,
arena reset, and aggregate update loops. The actual CLI now verifies successful
pool and combined arena/pool emission while retaining semantic rejection checks.

Guardian passes all 88 checks without frozen violations. Its repeated-string
findings prompted a shared typed-result emitter for buffers, pools, and arena reset;
evidence-backed ROI labels and mandatory feedback are recorded in Guardian.
Formatting passes. External provider/resource operations, generics, source
serialization, finer incremental compilation, and other unfinished roadmap work
remain open. Hosted CI remains unexecuted.

## 2026-09-06: Native clock/random adapters

Generated C now accepts clock/random capabilities through an explicit versioned
C provider interface. The native builder links a selected adapter with --provider;
without one, requested grants fail before guest execution. Contexts remain
host-owned, callbacks return full-width scalar values or typed statuses, and host
OOM releases native owned storage. Capabilities can pass through ordinary records
and helper parameters. No ambient operating-system adapter is selected.

A new acceptance driver executes shared expectations through VM callbacks and
native C at O0/O2 with address/undefined sanitizers: 32 value/error/call-count
comparisons and 14 injected allocation failures. It verifies full-width values,
missing grants, skipped reads, provider errors/OOM, owned arena-buffer cleanup,
and the actual builder adapter option. Its VM oracle compiles and runs separately
from the core/CLI tests. Compiler emission allocation sweeps also pass.

Complete Debug and ReleaseFast runs pass all 29 build steps and 592
core/CLI Zig tests (532 core, 60 CLI), alongside existing native parity and memory
acceptance (2,616 value/module comparisons and 468 general native allocation
failures). Review changed the C runtime to read callback values only on success,
matching the public failed-result contract; both complete modes pass on that change.
Guardian's strict gate passes; the flat-disjunction threshold finding was labeled
false-positive because the required split only appeased the policy.

Environment and external-resource native operations, generics, source-level
serialization, finer incremental compilation, and remaining roadmap work stay open.

## 2026-09-06: Native environment provider acceptance

Generated C now implements bounded environment lookup through explicit provider
ABI v2. It preserves arbitrary byte names, missing versus present-empty values,
zero padding, typed errors, and independent returned snapshots. Missing grants
fail before guest execution. The builder rejects an old provider factory symbol.

Complete Debug and ReleaseFast runs pass all 30 build steps and 593 core/CLI
tests (533 core, 60 CLI). Environment acceptance passes 38 VM-checked comparisons
and 56 injected allocation failures under address/undefined sanitizers at O0/O2.
The two provider VM oracle tests run separately. Existing acceptance passes 2,616
native value/module comparisons, 468 general allocation failures, and 32 scalar
provider comparisons with 14 allocation failures.

Native filesystem/network resources, generics, source serialization, finer
incremental compilation, and the remaining roadmap work stay open.

## 2026-09-06: Native resource cleanup foundation

Review for native filesystem/network support found that frame return destroyed
locals in ascending slot order, unlike the VM. Native return now clears and
releases locals in reverse order. A runtime harness verifies local, operand, and
nested schema order, retained snapshots, and nonallocating destruction of a
20,000-level value. The previous runtime fails the new local-order assertion.

Complete Debug and ReleaseFast runs pass all 30 build steps and 593 core/CLI
tests. The harness passes at C O0/O2 with address/undefined sanitizers, alongside
all 468 existing native allocation-failure cases. Guardian passes all 88 checks.

This is a prerequisite for observable resource release callbacks. Emergency
ownership unwind, native filesystem/network operations, and the wider roadmap
remain pending; see [native resource implementation](legacy/experiments/native-resources.md).

## 2026-09-06: Native emergency ownership unwind

The C runtime now derives temporary references from registered reference counts
and ownership edges, then releases temporaries, operands, and locals in their
required order. Creation, copying, and stack transfer maintain temporary order
without allocations or an epoch counter. Destruction remains nonrecursive.

The harness verifies acquisition order differing from allocation order, shared
local snapshots, nested temporary construction, and ten actual trap/OOM cases
across O0/O2, including stack growth, partial constructors, and frame setup after
argument transfer. The previous emergency cleanup fails the new order assertion.
All 468 existing native allocation-failure cases still pass under sanitizers.
Complete Debug and ReleaseFast runs pass all 30 steps and 593 core/CLI tests;
Guardian passes all 88 checks without frozen violations.

Resource callback integration remains pending. Review also identified a native
propagation sequencing change needed before resource payloads are enabled: box
the outgoing error before releasing unfinished operands, as the VM does. This
allocation boundary needs callback-trace acceptance in the resource milestone.

## 2026-09-06: Native propagation allocation order

Native propagation now constructs the outgoing error result before clearing
unfinished operands, matching the VM. A generated-C destruction observer and
allocation sweep verify that a boxing failure releases the propagated payload
first. Replaying the previous emission sequence at allocation 8 reproduces its
incorrect operand-before-payload order. The CORE-11 specification now states this
allocation-boundary contract explicitly.

Debug and ReleaseFast pass all 30 build steps and 593 core/CLI tests. Native
memory acceptance passes 484 injected allocation failures, including 16 new cases
across O0/O2, plus the ten explicit trap/OOM unwind cases. Sanitizers and zero-live
memory checks pass. Guardian passes all 88 checks without frozen violations.

Native filesystem/network operations remain pending. Their implementation record
now identifies the pending-host-handle cleanup needed between successful provider
acquisition and guest-owner allocation, alongside store and completion requirements.
The full roadmap remains open.

## 2026-09-06: Native resource lifecycle providers

Native filesystem/network capabilities now support explicit grants, acquisition,
permission intersection, retryable completion, nominal owners/wrappers, and
fallback release through provider ABI v3. A pending-handle record closes the OOM
gap between successful acquisition and guest-owner allocation. Successful
completion consumes the handle before allocating its result. Each provider family
uses an independent generation-checked registry and a default 1024-live-owner quota.

The new driver passes 32 native cases at O0/O2: 28 match VM callback traces, and
four reject malformed C-provider statuses. All 120 injected lifecycle allocation
failures release live handles and native storage, including retries, pending-owner
allocation, post-completion result allocation, and reordered aggregate fields.
The VM oracle runs separately from the core/CLI tests.

Complete Debug and ReleaseFast runs pass all 31 steps and 594 core/CLI tests
(534 core, 60 CLI), alongside existing native acceptance: 2,616 value/module
comparisons, 484 general allocation failures, and the earlier provider and unwind
drivers. Guardian passes all 88 checks without frozen violations. Existing
clock/random/environment adapters rebuild against the v3 header; ABI rejection
acceptance passes.

Native resource byte I/O, source attenuation stress, quota/reuse/generation
boundaries, mixed-store traces, and broader resource corpus acceptance remain
pending. Generics, source serialization, finer incremental compilation, and the
other unfinished roadmap requirements remain open.

## 2026-09-06: Native resource array and slice I/O

Provider ABI v4 now supports optional read/write callbacks. Native array and buffer
slices stage reads, preserve snapshots and failed-read bytes, and commit only the
reported prefix. Fixed reads return zero-padded independent arrays. Permissions,
partial counts, EOF, missing callbacks, and malformed metadata are checked.
All currently defined bytecode operations now have native emission; invalid
uncalled source still fails before output.

Debug and ReleaseFast pass all 31 build steps and 595 core/CLI tests (535 core,
60 CLI), with all 88 Guardian checks passing and no frozen violations. Resource
acceptance covers 114 outcomes, 104 VM trace comparisons, and 392 injected
allocation failures under sanitizers. It includes native builder execution,
mixed-store cleanup, and two passes through the 1024-live-filesystem-owner quota
to check rejection and reuse. Three provider VM oracle tests run separately.

The large quota fixture exceeded the previous 90-second C compilation timeout.
With a separate 300-second compilation budget, its sanitized O2 builds completed
in approximately 106 seconds focused and 118–120 seconds in the full runs.
Execution remains bounded at 90 seconds, with sanitizers and memory checks intact.

Generation-exhaustion/stale-owner and simultaneous per-kind quota stress remain
pending, as do native embedding/performance, generics, source serialization, finer
incremental compilation, and the remaining roadmap requirements.


### Native resource registry stress — 2026-09-06

Completed generation-exhaustion, stale-owner, registry-growth, and simultaneous
per-kind quota stress in the native runtime acceptance harness. Six O0/O2
sanitizer runs pass with zero retained allocations; mutation checks reject
unchecked generation wrap and stale-token release. Mirrored source quota fixtures
pass four exact VM/native trace comparisons, including acquisition from the other
provider family while one is full and reuse after cleanup. Mixed-store acceptance
passes two outcomes and 30 allocation failures. Guardian passes all 88 checks with
baselines disabled. This follow-up used focused acceptance; the prior full-suite
baseline remains 31 steps and 595 core/CLI tests. Native embedding/performance,
generics, source serialization, and finer incremental compilation remain open.


### Automatic project checking — 2026-09-06

Implemented `scripts/watch.py`: one persistent compiler session checks initially
and after content changes to module sources or declared manifests. Bounded polling
handles atomic replacement, deletion/recreation, nested imports, same-size edits
with preserved timestamps, and changes during an active check. Source/input
errors remain recoverable. Reply limits, timeout, SIGINT/SIGTERM, and child reaping
are explicit. The standard test build includes end-to-end watch acceptance.
See [watch behavior and acceptance](experiments/watch.md) for conservative
whole-source-tree invalidation and polling limits. Semantic query reuse,
persistent query storage, native incremental compilation/embedding, generics,
source serialization, and other unfinished roadmap requirements remain open.

Validation: the full ReleaseFast build passed all 32 steps (unchanged core/CLI test
steps reused cached results). Final focused watch acceptance passed with Debug
and ReleaseFast compiler builds. Guardian passed all 88 checks with baselines
disabled. Native resource acceptance passed 116 outcomes, 106 VM trace comparisons,
392 allocation failures, and six registry sanitizer cases.


### Native build publication and measurement — 2026-09-06

The native builder now stages guest C, trusted adapter compilation, and linking,
then atomically publishes complete executables. Identical executable bytes preserve
inode/timestamp; failures preserve the last successful output. `--report` records
generated-C identity, frontend/native elapsed time, and publication status while
explicitly stating that the driver does not reuse compilation. Fresh trusted
adapter cache storage prevents stale assembly `.incbin` inputs observed in the
regression fixture. Adapter compilation retains the caller's working directory.
Native compilation/query reuse, incremental linking, embedding/bindings, generics,
source serialization, and the remaining roadmap requirements stay open.

Validation: focused native-builder acceptance passes, including a failing-before
partial-output simulation and the changed `.incbin` regression. Scalar/module
parity passes all 2,616 comparisons; clock/random and environment acceptance pass
32/38 comparisons and 14/56 allocation failures. Final fixed-I/O resource selection
passes two VM/native traces, 28 allocation failures, and six registry sanitizer
runs. The build gate passes all 88 Guardian checks without baselines. This was
focused validation; no new full-suite result is claimed for this milestone.


### Declared-requirement generics: frontend stage — 2026-09-06

Added explicit type parameters with nonempty requirement lists and `::<...>` call
arguments to the AST/parser. Owned copies, mapped source spans, syntax-cache reuse,
formatter round trips, exported-signature privacy, and 16/17 list boundaries are
covered. Semantic preflight rejects these forms with `E_GENERIC_UNSUPPORTED`;
requirements are not yet resolved and templates cannot execute. Generics remains
open: requirement checking, bounded specialization, module/ownership/effect
integration, VM/native execution, and tooling acceptance are the next work.

Validation: the full core suite passed 540 tests in Debug and ReleaseFast, all 60
CLI tests passed, and the final generic-focused run passed seven tests including
the additional qualified-module formatting fixture. All Zig tests compiled and
the build gate passed all 88 Guardian checks without baselines. No executable
generic or native-specialization acceptance is claimed.


### Generic builtin requirement resolution — 2026-09-06

Added normalized `copy`, `equality`, and `integer` requirements, implication checks,
and concrete type matching using existing ownership/result contracts. Equality
uses the same predicate as ordinary expressions. Unknown requirements are rejected
in all templates, including uncalled private module declarations; malformed AST
inputs and allocation-failure cleanup are covered. Template-body checking and
executable specialization remain unsupported. General move-only/user-defined
requirements, bounded instance interning, substitution, backend/tooling integration,
and the rest of the roadmap remain open.

Validation: full core runs passed 546 tests in Debug and ReleaseFast; all 60 CLI
tests passed. The focused requirement run passed seven tests, including the added
module/private-template diagnostic case. The build passed all 88 Guardian checks
without baselines. These results validate requirement resolution/matching and
ordinary language regressions, not executable generics or template-body checking.


### Initial abstract generic body checking — 2026-09-06

Added symbolic checking of the pure builtin/type-parameter subset: locals,
assignment, returns, branches/loops, casts, arithmetic, and equality. Type-variable
identities remain distinct and operations require declared guarantees; no concrete
representative type is substituted. Literal validation is shared with the concrete
checker. Module scope, original diagnostics, allocation cleanup, and explicit
256-depth/100000-visit limits have acceptance coverage. Calls, nominal/composite
signatures, references, ownership/effects, and executable specialization remain
explicitly unsupported. Generics and the broader roadmap remain open.

Validation: all 554 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and the focused abstract-body run passed eight tests. The Guardian build
gate passed all 88 checks without baselines. These runs cover the implemented
symbolic subset and ordinary-language regressions; they do not establish executable
generics or completion of the full template-body contract.


### Abstract generic calls and requirement forwarding — 2026-09-06

Added indexed generic declaration lookup, explicit type/value argument arity,
requirement implication, and symbolic parameter/result substitution. Calls retain
module/domain privacy and cross-file diagnostic links; same-named declarations
remain distinct. Recursive calls check signatures without expanding bodies.
Allocation-failure acceptance covers local and module-backed checking. Concrete
helper summaries, broader abstract body forms, instance interning/substitution,
executable specialization, and the remaining roadmap stay open.

Validation: the full core suites passed 559 tests in Debug and ReleaseFast, all 60
CLI tests passed, and final generic-focused acceptance passed 25 tests. The build
gate passed all 88 Guardian checks without baselines. This validates abstract
calls and ordinary-language regressions; executable generic specialization and
completion of the broader roadmap remain unproven and unfinished.


### Pure concrete helpers in generic call graphs — 2026-09-06

Abstract generic checking now follows ordinary helper calls and validates all
transitively reachable bodies using the supported pure builtin rules. A worklist
bounded by declaration count visits each body once, including recursive cycles;
uncalled ordinary functions are left to concrete checking. Original module/domain
privacy and source locations survive traversal. Hidden clock operations reject
even behind constant-false branches. General effect/reference contracts, nominal
substitution, executable specialization, and other roadmap requirements remain open.

Validation: all 563 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and the build passed all 88 Guardian checks with baselines disabled.
Coverage includes helper cycles, shared callees, module/domain privacy, hidden
clock effects, invalid signatures/bodies, and allocation-failure cleanup. No
executable specialization or full native-suite result is claimed for this change.


### Bounded concrete specialization identities — 2026-09-06

Added an independently tested compilation-local instance registry keyed by
resolved declaration ordinal and ordered concrete type identities. Owned argument
copies, stable discovery IDs, existing-key reuse at capacity, nominal identity,
4096-entry/16-argument bounds, and allocation-failure recovery are covered.
The registry is not yet wired into executable lowering: call discovery,
per-instance type substitution, semantic/function-index migration, VM/native and
tooling integration remain unfinished. See `docs/experiments/generic-instances.md`
under docs/experiments. Generics and the broader roadmap remain open.

Validation: all 568 core tests passed in Debug; focused instance-table acceptance
passed six tests in Debug and ReleaseFast, including allocation-failure sweeps
and recovery. The build passed all 88 Guardian checks with baselines disabled.
This is registry and ordinary regression evidence; no new executable generic,
CLI, or full native-suite result is claimed.


### Executable pure generic specialization — 2026-09-06

Concrete semantic checking now separates source declarations from executable
instances, resolves callee signatures through concrete type arguments, and clears
touched expression cache entries between bodies. Recursive/repeated calls reuse
bounded specialization IDs; ordinary functions do not consume the 4096 generic
instance budget. The supported pure templates execute through VM/C lowering,
including integer widths, nominal copy values, and imported calls. Ordinary
public wrappers remain schema roots while internal instances are excluded.
General reference/effect/ownership contracts, direct generic schema/invocation,
user-defined requirements, and other roadmap tracks remain unfinished.
See `docs/experiments/generic-execution.md` for the current scope and boundaries.

Validation: full core runs passed 573 tests in Debug and ReleaseFast; all 60 CLI
tests passed. Final generic-focused acceptance passed 40 tests, including the
additional returned-reference identity regression. Native parity passed 2640
comparisons across 86 single-file and 16 module fixtures with -O0/-O2 and undefined
behavior sanitization; 50 final targeted codec comparisons passed after inserting
an uninstantiated template before codec functions. Guardian passed all 88 checks
with baselines disabled. No new full resource/provider-suite result is claimed.


### Generic borrowed input parameters — 2026-09-06

Abstract checking now distinguishes value, shared-reference and exclusive-reference
bindings. Supported templates read, write and forward reference inputs while
preserving symbolic types, access permissions, and ordinary alias rules. Duplicate
exclusive inputs reject even when forwarded to shared callee parameters; repeated
shared inputs remain valid. Calls use a temporary name table and count reference
arguments toward the work budget. Concrete instances retain ordinary borrow
validation and VM/C execution. Generic slices, lexical borrow scopes, returned
reference provenance, broader ownership/effects, and other roadmap work remain open.
See `docs/experiments/generic-references.md` for scope and acceptance.

Validation: all 576 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2646 comparisons across 87 single-file and 16
module fixtures using -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Allocation-failure coverage includes local
reference forwarding and imported setter execution/schema generation. These
results do not establish the unfinished slice or returned-reference contracts.


### Generic slice input operations — 2026-09-06

Generic shared/exclusive slice inputs now support length, element reads/writes,
and forwarding. Abstract checks retain reference kind, symbolic element identity,
integer-index requirements, access permission, and alias rules. Concrete VM/C
instances retain runtime view lengths, bounds traps and immutable snapshots.
Imported slice helpers execute through ordinary public wrappers. Lexical generic
borrow scopes/narrowing, reference-result provenance, wider effect/ownership
contracts, and other roadmap tracks remain unfinished. See
`docs/experiments/generic-slices.md` for current scope and acceptance.

Validation: all 579 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2664 comparisons across 90 single-file and 16
module fixtures with -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Allocation-failure coverage includes slice
forwarding and module-backed execution/schema generation. Generic lexical borrow
scopes and returned-reference contracts remain unverified and unfinished.


### Generic lexical borrowing and narrowing — 2026-09-06

Generic bodies now borrow copyable local values, reborrow references, and narrow
known slice inputs. Root identities, loan counts and parent child counts enforce
owner access and exclusive-parent suspension without scanning every local. Scope
exit restores access and removes names on returns and failures. Recursive generic
slice helpers execute through VM/C with runtime subrange bounds checks. Generic
reference-result provenance, abstract whole-value range shape, broader ownership
and effects, and other roadmap requirements remain unfinished. See
`docs/experiments/generic-borrows.md` for current scope and acceptance.

Validation: all 582 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2676 comparisons across 92 single-file and 16
module fixtures with -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Allocation-failure tests cover recursive
borrows and imported narrowing helpers. These results do not establish generic
reference-result provenance or completion of the broader roadmap.


### Generic reference-result provenance — 2026-09-06

Generic whole-reference and slice results now validate explicit input provenance,
kind, permission and symbolic type before specialization. Borrow-call scopes and
forwarding preserve roots and parent suspension, including results borrowed from
later parameters. Concrete return contracts resolve types in the callee instance.
Imported result helpers execute through ordinary wrappers with internal instances
excluded from public schema roots. Abstract whole-value-to-slice shape, broader
nominal/composite operations, move-only/external-effect contracts, direct generic
public invocation, and other roadmap requirements remain unfinished. See
`docs/experiments/generic-returned-references.md` for scope and acceptance.

Validation: all 584 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2682 comparisons across 93 single-file and 16
module fixtures with -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Allocation-failure coverage includes
forwarded references, later-input provenance and imported result helpers/schema
rendering. These results validate the supported reference contracts, not the
remaining generic operations or broader roadmap requirements.


### Readable specialization diagnostics and metadata — 2026-09-06

Checked functions now retain concrete type arguments explicitly. Instance display
names include ordered concrete types and qualified nominal names, remain unchanged
when discovery order changes, and flow into dumps/reports and VM/C traces. Public
module/schema roots use metadata rather than punctuation to exclude internal
instances. This advances the original understandable-diagnostics criterion; it
does not complete direct public generic tooling, broader operations, native
embedding or incremental compilation. See `docs/experiments/generic-diagnostics.md`.

Validation: all 586 core tests passed in Debug and ReleaseFast, all 60 CLI tests
passed, and native parity passed 2682 comparisons across 93 single-file and 16
module fixtures with -O0/-O2 and undefined-behavior sanitization. Guardian passed
all 88 checks with baselines disabled. Tests cover discovery-order independence,
qualified nominal names, dump/trace output, schema exclusion and allocation-failure
cleanup. This does not establish completion of direct generic public tooling or
the other unfinished roadmap tracks.


### Native embedding entry and shared-library builds — 2026-09-06

Generated C now offers `mylang_native_run_v1` with explicit providers and budgets,
a scalar entry result, bounded located traps and returning host failures. Every
invocation releases guest storage; repeated calls reset state, and overlapping
calls return Busy. `scripts/native.py --library` builds a shared library while
preserving atomic and unchanged-output publication. See
`docs/experiments/native-embedding.md` for the public C header contract.

Focused acceptance passed 24 host programs across -O0/-O2 with undefined-behavior
sanitization, repeated calls, frame/step budgets, reentry/concurrent rejection,
live-resource trap cleanup and allocation-failure recovery. Independent public-header hosts
linked and ran Debug/ReleaseFast shared libraries and verified unchanged rebuilds.
All 586 ReleaseFast core tests passed; the full Debug regression command also
completed successfully, including 586 core and 60 CLI tests. Arbitrary exported native calls,
aggregate native arguments/results, generated native callable bindings, finer
incremental compilation and the other pending roadmap requirements remain open.


### Exported native scalar invocation — 2026-09-06

Module native emission now retains resolved export roots and exposes
`mylang_native_call_v1`. Hosts call qualified public names with exact typed scalar
bits; integer widths, full u64 results, Booleans, counts and ranges are checked.
Private helpers and internal generic instances remain unavailable. Located traps,
budgets, cleanup and repeated-call recovery share the native entry machinery.
The public C headers work with independently linked shared-library hosts. See
`docs/experiments/native-calls.md` for the contract.

Validation: 587 core tests passed in both Debug and ReleaseFast; all 60 CLI
tests and formatting passed. Native parity
passed 2682 comparisons across 93 single-file and 16 module fixtures, and all 24
embedding host programs passed. Named-call acceptance passed -O0/-O2 sanitizer
runs and Debug/ReleaseFast shared-library host links, covering visibility, every
scalar boundary, invalid inputs, trap locations, allocation failures and recovery.
Guardian passed all 88 checks without baselines. The earlier full Debug embedding
suite also completed successfully before this API extension. Aggregate/domain
native wire values, borrowed/capability signatures, generated native callable
bindings, incremental compilation and the other pending roadmap items remain open.


### Native ordinary aggregate value calls — 2026-09-06

`mylang_native_call_values_v1` now copies checked preorder scalar, record,
fixed-array/table, enum, packed/boxed variant and typed-result values across the
native host boundary. Inputs become guest-owned copies; outputs use caller-owned
nodes and retain no guest allocation. Counts, type names, tags and scalar ranges
are validated; the scalar call API shares that range implementation. Output
capacity failures report the required size without writing output. Domains,
resources and other runtime identities remain opaque. See
`docs/experiments/native-wire.md` for the positional schema and ownership contract.

Acceptance passes address/undefined-behavior sanitizer runs in -O0/-O2 and
independent Debug/ReleaseFast shared-library hosts. Tests cover snapshots,
empty values, nested packed/boxed payloads, enum tables, typed results, malformed
inputs, opaque signatures, output capacity, traps, allocation failures, recovery,
exact 128-level and 100000-node limits, and cross-API Busy rejection. Full core
runs passed 587 tests in Debug/ReleaseFast, all 60 CLI tests passed, and native
parity passed 2682 comparisons. All 24 embedding cases and scalar native-call
acceptance passed. Final shared-range refactoring is checked by both native call
drivers and focused compiler allocation tests. Guardian passed all 88 checks with
baselines disabled. A variant-input regression exposed and corrected use of a
guest-frame-only stack helper before entry-frame creation; this was test-derived
evidence. Native domain codecs, generated schema-pinned native bindings,
borrowed/capability signatures, incremental compilation and other roadmap items
remain unfinished.


### Schema-pinned generated native Python bindings — 2026-09-06

Native module libraries now expose canonical public schema bytes and SHA-256
from the same checked compilation as their code. Shared checked-schema rendering
avoids a project/schema import cycle. Generated Python modules include
`NativeClient` and `NativeLimits`; their existing typed wrappers call ordinary
native scalar/record/array/table/variant/result functions only after validating
the library's schema. Calls preserve host snapshots, report native traps and
budgets, and do not retry output-capacity failures. Both embedded runtime sources
participate in the generator/cache identity. See
`docs/experiments/native-bindings.md` for usage and the synchronous native boundary.

Independent metadata tests pass public field/type/case/export invalidation,
compatible body/private/relocation stability, concurrent queries, both native
optimization modes and absent single-file schemas. Generated Python acceptance
passes typed compiler/native comparisons, schema/ABI/I/O rejection, integer
boundaries, snapshots, traps/recovery, node/depth/frame/step budgets, malformed
results and calls after source removal. Existing Python data/call, binding-cache,
schema and receipt tests pass; cache tests include changes to the native runtime.
All 587 core tests passed in Debug/ReleaseFast, all 60 CLI tests and formatting
passed, and native parity passed 2682 comparisons. Native scalar/aggregate host
acceptance passes, and Guardian passed all 88 checks without baselines. These are
focused and core regression results, not a new full-build-test run.

Native domain codecs, borrowed/capability invocation, source serialization,
finer semantic/native incremental compilation and the other pending roadmap
requirements remain unfinished. Schema identity establishes interface
compatibility; it does not authenticate implementation behavior.


### Internal native codec execution — 2026-09-06

Generated native dispatch now permits internal calls only to functions selected
by checked domain codec declarations. One owned argument and result cross the
internal call boundary while the surrounding operands, frames, instruction/frame
budgets and cleanup destination are preserved. Normal public calls retain their
existing behavior. This is a prerequisite for codec-aware native value traversal;
public wire calls and NativeClient still reject domain signatures. See
`docs/experiments/native-codec-dispatch.md` for the remaining integration.

Four sanitizer hosts pass nontrivial decoder/encoder execution, packed/boxed
rejection ownership, caller operand/frame preservation, shared budgets, exact
trap frames, non-codec private-helper rejection, allocation failures and recovery.
An uninstantiated generic declaration verifies separation from source declaration
ordinals. Compiler codec-dispatch allocation sweeps pass. All 588 core tests
passed in Debug/ReleaseFast, all 60 CLI tests and formatting passed, and native
parity passed 2682 comparisons. Existing 24 embedding cases, ordinary aggregate
wire acceptance and generated native Python tests pass. Guardian passed all 88
checks with baselines disabled; no new full-build-test run is claimed.

Public native codec input/output conversion, typed rejection reporting, shared
codec-call quotas and generated-client domain support remain unfinished. Output
encoding must be staged so each encoder runs once rather than once per sizing
and writing pass. The other pending roadmap requirements also remain open.


### Public native domain codec calls — 2026-09-06

The new `mylang_native_call_codecs_v1` API converts declared domain wire values,
including domains nested in records, arrays and variants. Input decoders, the
public root and output encoders share step/frame limits and a separate bounded
call quota. Encoded output is staged before publication so each encoder runs once
and insufficient buffers or traps leave caller output unchanged. Implicit decoder
rejections carry the domain identity and ordinary typed rejection tree; explicit
public decoder calls retain ordinary language-result semantics. The original
value API keeps its domain opacity. See `docs/experiments/native-codec-wire.md`.

Four sanitizer hosts and four separately linked public-header hosts pass both
optimization modes and packed/boxed rejection representations. Coverage includes
nested conversion, exact call limits, shared step/frame budgets, decoder/encoder
traps, unchanged insufficient output, allocation failures and repeated recovery.
All 588 core tests pass in Debug and ReleaseFast. Existing internal codec, ordinary
wire, scalar call, generated Python native-client and 24 embedding host cases pass,
including cross-API Busy rejection. All 2682 VM/native comparisons pass. The new
driver runs in `zig build test`; a new
full-suite pass is not claimed here. Guardian passes all 88 checks with baselines
disabled. Generated Python domain support, source-level codec operations and all
other outstanding roadmap requirements remain open.


### Generated Python native domain bindings — 2026-09-06

Generated `NativeClient` now supports the codec-capable public function set,
using explicit domain wire wrappers and the native codec API for domain-bearing
signatures. Ordinary signatures retain the original value ABI and work without
the optional codec symbol. Domain calls report `NativeABIUnavailable` when that
symbol is absent. Schema pins still apply before invocation.

`NativeLimits.max_calls` defaults to 4096 and bounds implicit decoders, the public
root and output encoders under the shared native execution. Host traversal counts
explicit domain nodes in its depth and node budgets. Implicit decoder failures
raise `CallError` with domain/call context and a typed scalar or aggregate rejection
value. Insufficient output never triggers a retry, including when only the
rejection flag and required error-tree capacity are available.

Debug and ReleaseFast shared-library acceptance passes VM/native agreement for
ordinary and nested domain values, nontrivial decoding/encoding, scalar/record
rejections, explicit decoder results, decoder/encoder traps, exact call budgets,
malformed output, absent codec APIs, success/rejection capacity failures and calls
after source removal. Existing Python data binding (29 wire comparisons),
compiler-process call and binding-cache suites pass, including runtime digest
invalidation. Python syntax and whitespace checks pass; Guardian passes all 88
checks with baselines disabled. This change does not claim a new full Zig-suite
run. Source-level codec operations, borrowed/capability native invocation,
incremental compilation and all other pending roadmap requirements remain open.


### Source declared domain codec operations — 2026-09-06

Source expressions now support `codec_decode[Domain](wire)` and
`codec_encode[Domain](value)`. They select the methods named by an explicit codec
contract and lower to ordinary checked calls, retaining public visibility,
parameter/result typing, result obligations, effect checks and execution budgets.
The decoder returns its declared typed result; encoding cannot accept raw backing
values. Imported domain aliases and formatter round trips are supported.
See `docs/experiments/source-codecs.md`.

Both full core runs passed 591 tests in Debug/ReleaseFast; final focused acceptance
adds a nonstandard method-name/transformation case and generic-constraint rejection.
All 60 CLI tests and 2688 VM/native comparisons across 110 fixtures passed.
Allocation-failure tests cover source execution/formatting and imported codec
resolution. Guardian passes all 88 checks without baselines. New behavior
classification subjects for the lexer, formatter and resolver were labeled
intentional-change against the tagged SOURCE-CODEC-1 contract; uncertain subjects
remain pending. No new full build-test run is claimed.

This completes explicit source domain-to-wire conversion. JSON byte serialization
operations still need bounded buffer/slice contracts, allocation authority and
typed malformed-input handling. Generic codec constraints, borrowed/capability
native invocation, finer incremental compilation and all other outstanding
roadmap work remain open.


### Exact successful project-check reuse — 2026-09-06

Persistent checking sessions now retain one bounded successful verdict alongside
the syntax cache. Every request freshly loads files, module headers and generated
manifest inputs before comparing complete module names, paths and source bytes.
An exact hit replays owned warnings and skips interface/semantic work. Changed
snapshots check afresh; failed checks are never retained. Clearing drops both
caches. Cumulative `semantic` JSON observations distinguish hits, misses, storage,
bypass and retained bytes from actual syntax reuse.

Verdict retention is limited to a separate 16 MiB arena, for up to 32 MiB combined
syntax/verdict entry storage. Oversized entries bypass storage; failed replacement
allocations preserve the prior successful verdict. This is in-process whole-project
reuse, with no hash-only key or persistent disk verdicts. See
`docs/experiments/check-session.md` for the protocol and trust boundary.

Full core suites passed 595 tests in Debug/ReleaseFast; final five-test cache runs
add explicit failed-replacement preservation. All 60 CLI tests pass. Persistent
session and watch acceptance pass exact warm hits, identical warning replay,
source/type/privacy/deleted-file recovery, changed/invalid manifests, clear,
retention bounds and protocol/child cleanup. Guardian passes all 88 checks without
baselines; its complexity finding prompted shared loading/input-validation and
verdict helpers and was labeled useful-review. The cache behavior was labeled
intentional-change; uncertain subjects remain pending. No new full build-test run
is claimed. Finer semantic queries, persistent reuse, incremental native linking,
source JSON byte serialization and all other pending roadmap items remain open.


### Concrete schemas in generic bodies — 2026-09-06

The abstract generic checker now shares the resolved type catalog with concrete
specialization. Fixed copyable records, arrays and nominal values can appear
alongside symbolic parameters in signatures, local annotations, generic calls
and pure concrete helpers. Record/array construction, record projection, array
and enum-table indexing, and length use declared concrete schemas. Imported
aliases retain declaring-module resolution; nominally different records remain
distinct, and symbolic integer parameters still require explicit conversion to
fixed integer fields. Concrete domains can pass through without exposing backing
construction. Complete runtime-identity/result-bearing graphs remain excluded.
See `docs/experiments/generic-concrete.md` and `examples/generic-records.my`.

All 599 core tests pass in Debug/ReleaseFast, all 60 CLI tests pass, and VM/native
parity passes 2706 comparisons across 113 fixtures, including imported record
helpers and an imported generic bounds trap. Final focused tests in both modes
also verify concrete-domain passthrough. Allocation sweeps cover abstract and
concrete checking, VM execution and native emission. Formatting and all 88 Guardian
checks pass with baselines disabled. Its concreteType error-path claim was labeled
false-positive because rejection/allocation tests already covered the catch;
adding the helper name to the test title was the only required edit.

Parameter-dependent composite types, generic type declarations, structural
requirements, aggregate updates, variants/results/ownership abstract rules,
source codec constraints, public generic tooling and the remaining roadmap
requirements stay open. This is not completion of the full generic language or
a claim of a new full build-test run.


### Generic aggregate updates — 2026-09-06

Generic bodies now support partial updates of concrete copyable records and
replacement of fixed-array or enum-table elements. Construction/update field
validation and indexing/replacement index validation share helpers. Updates
preserve untouched fields, require unique known fields with exact types, and
cannot infer a record shape from a symbolic parameter. Table keys retain nominal
enum identity. Ordinary specialization/lowering retains snapshots, evaluation
order and runtime bounds. See `docs/experiments/generic-updates.md` and
`examples/generic-updates.my`, which returns 44 while reading original and updated
record/table values.

All 601 core tests pass in Debug/ReleaseFast; all 60 CLI tests and 2724 VM/native
comparisons across 116 fixtures pass. Allocation sweeps cover record/table snapshot
updates and native emission. Uncalled-template tests reject malformed fields,
indices, elements and enum keys; imported native fixtures cover empty-array and
maximum-u64 replacement traps. Formatting and all 88 Guardian checks pass with
baselines disabled. Uncertain ROI subjects remain pending, and no new full
build-test run is claimed.

Concrete variant construction/matching, result/ownership abstract rules,
parameter-dependent structural types, codec constraints, public generic tooling,
source JSON serialization and all other pending roadmap requirements remain open.


### Concrete generic variants and exhaustive matching — 2026-09-06

Generic bodies now construct concrete copyable enums/unions and match them
exhaustively. Nominal case ownership, exact payload presence/type, arm-local
bindings, duplicate/missing cases and all-arm return flow are checked before
instantiation. Every arm is checked even after a fallthrough arm; bindings do not
escape or conflict across independent arms. Named enum-table construction now
requires every declared key exactly once and shares record field validation.
See `docs/experiments/generic-variants.md` and `examples/generic-variants.my`, which
returns 16 from record/scalar union payloads and a complete enum table.

All 605 core tests pass in Debug/ReleaseFast; all 60 CLI tests and 2742 VM/native
comparisons across 119 fixtures pass. Allocation sweeps cover construction,
matching, enum tables, execution and native emission. Rejection tests cover
payload/case/type errors, scope escape, incomplete return paths and invalid later
arms. Imported fixtures retain aliases and located traps inside generic match
arms. Formatting and all 88 Guardian checks pass with baselines disabled.
Uncertain ROI subjects remain pending; no new full build-test run is claimed.

Result-bearing and runtime-owned variant graphs remain excluded pending abstract
handling/ownership rules. Parameter-dependent structural types, generic codec
constraints, public generic tooling, source JSON serialization and the remaining
roadmap requirements stay open.


### Full roadmap regression checkpoint — 2026-09-06

The complete `zig build test --summary all` run at source commit `27f4eec`
finished with exit status 0: **40/40 build steps succeeded and 665/665 Zig tests
passed** (605 core plus 60 CLI). The integration drivers also passed, including
2742 VM/native comparisons across 119 fixtures, generated Python value/domain
bindings, native embedding and codec wire calls, allocation-failure cleanup,
resource/provider boundaries, exact check-session reuse, watch recovery, schema
and evaluation receipts, binding caches, the two-application ordinary corpus,
and 256-module/4096-import boundary acceptance. This closes the full-suite
validation gap noted in the preceding focused milestone records. The earlier
ReleaseFast core results remain separate; this was the default Debug build test.

Guardian passed all 88 checks with violation baselines disabled. Report-only
file-size, function-length and line-length findings remain; passing the gate does
not mean the report contains no findings. Pending ROI subjects were inspected and
left unclassified where this run supplied no evidence for a human outcome.

Optimized C compilation for the quota-reuse and quota-network fixtures took
95.6 and 90.3 seconds respectively, versus about 1.2 seconds each at `-O0`.
These are observations from this run, not isolated benchmarks; native compilation
performance remains an open roadmap requirement.

Abstract generic result handling is the next implementation, with branch, loop,
scope and live-temporary acceptance requirements in
`docs/experiments/generic-results-plan.md`. It remains unimplemented. Structural
generic types, codec constraints, public generic tooling, source byte
serialization, borrowed/capability native invocation, finer incremental work and
the remaining roadmap requirements are still open.


### Concrete generic result obligations — 2026-09-06

Generic templates now check concrete result-bearing values before instantiation.
Whole-value transfer, acknowledgement, exhaustive payload handling, scope/return
obligations and safe reassignment are enforced. Branches and matches restore the
same incoming availability state and merge only continuing paths; loops and
short-circuit expressions reject inconsistent obligations. Aggregate operations
cannot silently erase sibling or replaced results. `try` checks compatible
concrete result errors, live local obligations and already evaluated result
temporaries in calls/aggregate construction. Result-bearing references reject
consistently with ordinary functions, including in uncalled templates.

See `docs/experiments/generic-results.md` and `examples/generic-results.my`
(result 9). New acceptance covers uncalled rejection, consumed aliases, both
branch outcomes, match fallthrough, nested payloads, overwrite/self-transfer,
loop/short-circuit state, propagation success/error and pending temporaries,
acknowledgement traps, and allocation failures during checking/execution/native
emission. All 614 core tests pass in Debug and ReleaseFast; all 60 CLI tests pass.
VM/native parity passes 2760 comparisons across 122 fixtures, including imported
result schemas with aliases and a located acknowledgement trap. The final
result-reference restriction also passes the 70-test generic-focused suite.
Formatting and all 88 Guardian checks pass with baselines disabled; report-only
size/line advice remains. This is focused milestone validation, not a new full
resource/provider/binding integration run.

Generic partial field moves remain explicitly unsupported. The next implementation
must track remaining field obligations through snapshots, merges, reassignment
and early propagation; `generic-results-plan.md` records that acceptance contract.
Runtime ownership/regions, parameter-dependent structural types, codec
constraints, public generic tooling, source byte serialization and all other
pending roadmap requirements remain open.


### Concrete generic partial field moves — 2026-09-06

Generic bodies now support `read_field` on concrete records and `take_field` on
concrete result-bearing records. Whole-value availability and immutable moved-field
bitmaps travel together through branch/match snapshots, loop checks and
short-circuit comparisons. Equivalent extraction orders agree; different remaining
fields reject. Scope exit, return, overwrite and early propagation inspect
remaining result obligations. Replacing a handled partial binding restores all
fields, while whole-value use of an incomplete record rejects.

See `docs/experiments/generic-fields.md` and `examples/generic-fields.my` (result
17). Acceptance includes uncalled malformed templates, repeated moves, result
copying, consumed owners, missing fields, nested records, returning/fallthrough
arms, loop replenishment, propagation with remaining fields or temporary results,
and allocation failures during checking, execution and native emission. All 620
core tests pass in Debug and ReleaseFast, all 60 CLI tests pass, and 2778 VM/native
comparisons pass across 125 fixtures. Imported schema/helper aliases and a located
trap after extraction are included. Formatting and all 88 Guardian checks pass
with baselines disabled; nonblocking size/line findings remain. No new full
resource/provider/binding integration run is claimed. Uncertain ROI observations
remain unclassified.

Runtime-owned generic graphs remain excluded. The next abstraction work must
preserve whole/field ownership transfer, implicit cleanup, borrowing, region
lifetimes and capability/effect authority before enabling those graphs. Symbolic
structural types, generic codec constraints, public generic tooling, source byte
serialization and all other pending roadmap items remain open.


### Concrete generic owned flow and cleanup effects — 2026-09-06

Generic bodies now accept concrete owned buffers, pools and external resources,
including their aggregate/result wrappers. Whole and partial reads transfer once;
continuing branches/loops/short-circuit paths agree on remaining ownership. Ordinary
owned values may be discarded or dropped at scope exit, and replacement releases
the prior owner. Result obligations remain explicit. Owned reference parameters and
general borrows still reject under the ordinary checker's current policy.

The abstract pass collects owned-type cleanup masks and resolved call edges, then
reuses the ordinary effect solver. Filesystem/network fallback cleanup propagates
through helper cycles and rejects incompatible bounds in uncalled templates.
Zero-length resource arrays retain their empty cleanup mask. Copy-constrained type
arguments still exclude owned values; ordinary pool handles retain copy identity.
See `docs/experiments/generic-owned.md`, `examples/generic-owned.my` (14), and the
explicit-provider `examples/generic-resources.my` (8 with the test provider).

All 626 core tests pass in Debug and ReleaseFast, all 60 CLI tests pass, and 2790
VM/native comparisons pass across 127 fixtures. Generic-focused coverage passes
82 tests. Selected native resource acceptance passes 10 outcomes and matching VM
provider traces, six generation sanitizer runs and 90 injected allocation failures.
Those selected cases include existing normal resource behavior and generic
filesystem/network cleanup, denied acquisition and a guest trap. The resource
oracle now distinguishes guest traps from host errors. Core allocation sweeps also
verify generic provider release exactly once after explicit or implicit drops.
Formatting and all 88 Guardian checks pass without baselines; nonblocking size/line
findings remain. Uncertain ROI observations remain pending. No new full
resource/provider/binding integration-suite run is claimed.

Acquisition, mutation, provider operations and local arena/reset scopes inside
generic bodies remain explicitly unsupported pending direct authority/effect,
result-shape and region-origin checks. Owned input flow does not establish those
operations. Structural generic types, codec constraints, public generic tooling,
source byte serialization and all other roadmap requirements remain open.


### Generic buffer and pool acquisition/operations — 2026-09-06

Generic bodies now acquire concrete buffers and pools with explicit allocator
arguments, integer capacities and matching owned-success/i64-error results.
Buffer queries/read/write/append/resize/reserve and pool queries/insert/read/
replace/remove/clear enforce exact element/handle/result types and mutable owners.
Owner availability is checked after argument evaluation, rejecting an argument
that transfers the buffer or pool being operated on. Acquisition and reserve seed
allocation effects through helper calls; in-capacity mutations retain noalloc.
The ordinary and abstract checkers share acquisition result validation, and the
ordinary/bytecode/abstract effect passes share the buffer allocation predicate.

See `docs/experiments/generic-runtime.md` and `examples/generic-runtime.my` (33).
Acceptance covers malformed uncalled operations, incorrect authority/capacity,
insufficient symbolic requirements, effect bounds, consumed/immutable owners,
nominal handles, typed mutation results, success and negative-capacity failure,
propagation and allocation-failure cleanup. All 631 core tests pass in Debug and
ReleaseFast, all 60 CLI tests pass, and 2808 VM/native comparisons pass across 130
fixtures. Imported acquisition/mutation helpers and a located empty-buffer trap
are included. Formatting and all 88 Guardian checks pass with baselines disabled;
nonblocking size/line findings remain and uncertain ROI subjects stay pending.
No new full resource/provider/binding integration-suite run is claimed.

Provider acquisition/completion/I/O, clock/random/environment operations and local
arena/reset/view scopes inside templates remain pending. They require capability,
permission, direct-effect and origin/lifetime checks. Structural generic types,
codec constraints, public generic tooling, source byte serialization and the
remaining roadmap requirements remain open.


### Generic provider operations — 2026-09-06

Generic bodies now check clock/random reads, environment lookup, resource
acquisition/completion, capability attenuation, fixed-byte I/O and I/O through
caller-supplied slices. Exact capability families and concrete result schemas are
required; resource I/O checks mutable owner availability after arguments, and slice
reads require exclusive byte views. Direct provider effects propagate through the
abstract call graph, including recursive helpers and statically unreachable source
branches. Runtime provider availability, permission intersection, partial I/O,
result ownership and cleanup retain their ordinary behavior.

See `docs/experiments/generic-providers.md` and the explicit-provider
`examples/generic-provider-slices.my`. Uncalled-template tests reject malformed
contracts and forbidden effects. Execution/allocation sweeps cover generic scalar
callbacks, bounded environment output, owned completion retry and slice I/O.
All 639 core tests pass in Debug and ReleaseFast, all 60 CLI tests pass, and 2808
standard VM/native comparisons pass across 130 fixtures. Native clock/random
acceptance passes 64 value/error/call-count comparisons and 28 injected failures;
environment acceptance passes 60 comparisons and 76 failures. Selected resource
acceptance passes 16 outcomes and matching provider traces, 88 allocation failures
and six generation sanitizer runs. Generic skipped calls execute no callbacks.
The provider builder fixture now selects its intended source explicitly instead
of depending on the final source-list entry. Formatting and all 88 Guardian checks
pass without baselines; nonblocking size/line findings remain and uncertain ROI
subjects stay pending. No new full binding/cache integration run is claimed.

Constructing local array/buffer views and local arena/reset scopes in templates
remain pending. They need abstract borrow and origin/lifetime tracking before
being enabled. Structural generic types, generic codec constraints, public generic
tooling, source byte serialization and all other pending roadmap requirements
remain open.


### Interpreter acceptance workflow — 2026-09-06

`zig build test` now runs the interpreter/checker, complete core/CLI roots and
interpreter/tooling integration. `test-interpreter` aliases that suite. Existing
native compilation drivers moved to optional `test-native`; `test-all` combines
both. Guardian gates every route. The corpus defaults to general/arena VM runs
against independent Python expectations (48 inputs, 96 comparisons), retaining
formatting, duplicate discovery, policy, schema/binding and change-impact checks.
Native corpus execution requires explicit `--native --zig`; shared inexpensive
C-emission checks remain in the core/CLI roots. No native execution work is part
of the active roadmap-completion goal, and no new native suite run is claimed.

Validation: default Debug passes 27/27 build steps and 699/699 core/CLI tests;
ReleaseFast through `test-interpreter` passes 28/28 steps and the same 699 tests.
Both execute all 17 interpreter/tooling Python invocations, including eight
verification-driver unit tests and 96 independent corpus comparisons. Verbose
commands confirm neither route selects native integration drivers. All 29 previous
script entries remain wired, with separate corpus modes; missing `--zig` is
rejected before native-mode execution. Formatting and all 88 Guardian checks pass
with baselines disabled; existing report-only size/line findings remain. Pending
ROI subjects have no new outcome evidence and remain unlabelled.

Next: generic local array/buffer views and region-origin/lifetime checks, followed
by diagnostic repair quality, typed host registration and the board/constraint
trial. These remain open under the interpreter-first roadmap.


### Generic local array and buffer views — 2026-09-06

Abstract generic bodies now create slices from concrete numeric arrays and owned
buffers, using the ordinary checker's shared element-shape helper. Bounds are
evaluated before owner availability checks, so consuming a buffer inside a bound
rejects the subsequent loan. Existing root identity and loan counters enforce
conflicting access, transfer/growth restrictions, parent suspension and lexical
restoration. Array snapshots preserve value semantics. Concrete whole-array
reference inputs may supply returned slices under their declared input lifetime;
local array/buffer views cannot escape that way.

See [the view contract](legacy/experiments/generic-local-views.md) and
`examples/generic-local-views.my` (22). Tests cover uncalled invalid templates,
shape/element/permission errors, transfers inside bounds, active-owner conflicts,
empty/nested views, source-located bounds traps, returned-input provenance and
allocation-failure cleanup. The CLI checks an imported generic returned-view
helper under general/arena VM memory and rejects a module-local lifetime escape.

Validation: 644 core tests pass in Debug and ReleaseFast; all 61 CLI tests pass
in both modes after correcting the new fixture's module call from `api.tail` to
`api::tail`. The initial full suite runs exposed that fixture error; the complete
CLI roots were rerun after the correction. Interpreter/tooling integration also
passes, including 96 independent corpus comparisons. Focused generic coverage
passes 100 tests. Formatting and all 88 Guardian checks pass without baselines;
existing report-only size/line findings remain. No native execution suite was run.

Generic local arena/reset scopes still require allocator-origin and escape
checks. Symbolic array/buffer constructors and structural constraints, generic
codec contracts, public generic tooling, typed host registration and the real
application/repair trial remain open. Native work is excluded from the active
goal.


### Generic arena scopes and reset — 2026-09-06

Generic bodies now create lexical arenas and call typed reset operations with
explicit allocator authority and checked results. Arena creation seeds allocation
effects through the abstract call graph. A stable dependency graph preserves
arena origins through assignments, aggregates, match payloads, partial fields,
loops, references and conservative helper writes; escape constraints are checked
after a monotone fixed point. Ordinary and abstract checking share concrete
arena-bearing type classification and the E_ARENA_ESCAPE contract. Current
equality/integer requirements prove that a symbolic value cannot carry an arena;
a copy requirement alone does not.

Returns, propagated errors, outer bindings and longer-lived buffer/pool storage
reject shorter-lived dependencies before instantiation. Heap-backed owners,
plain snapshots and inert handles can leave an arena scope under their ordinary
rules. Reset retains runtime checks for live storage and child regions. See
[the generic region contract](legacy/experiments/generic-regions.md) and
`examples/generic-regions.my` (3).

Validation: final Debug `zig build test` passes 27/27 steps and 714/714 core/CLI
tests; final ReleaseFast `test-interpreter` passes 28/28 steps and the same 714
tests (652 core, 62 CLI). Interpreter/tooling drivers pass, including the eight
verification-driver unit tests and 96 independent corpus comparisons. Focused
generic acceptance passes 108 tests. Coverage includes allocation failures,
every VM step-budget boundary in both execution backings, module-local escape
diagnostics, reset/reuse, dependency cycles and positive heap/snapshot/handle cases.
Review also removed an over-conservative equality-parameter classification and
added a regression. The rebuilt CLI example, formatting and all 88 Guardian
checks pass with baselines disabled; existing report-only size/line findings remain.
Four explicit-error-set ROI subjects were labelled useful-review; uncertain
subjects remain pending. No native execution acceptance was run.

Next: diagnostic creation/borrow/move/conflict provenance and repair fixtures,
then typed host registration and the board/constraint-processing trial. Structural
generic types, codec constraints, public generic tooling, source serialization
and finer incremental checking remain open; native execution remains excluded
from the active goal.
