# Implementation progress

The complete scalar MVP in plan sections 4–13 is implemented and audited. The
later features in sections 15 and 18 remain proposed experiments, as specified
by the plan. Earlier entries below describe their milestone checkpoints.

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
