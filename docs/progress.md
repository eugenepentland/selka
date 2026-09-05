# Implementation progress

The complete scalar MVP in plan sections 4–13 is implemented and audited. Post-MVP A1 and exact duplicate discovery are also implemented; the remaining
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
