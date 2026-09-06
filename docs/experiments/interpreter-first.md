# Interpreter-first design and acceptance

Direction adopted on 2026-09-06; this document and [plan section 1](../plan.md#1-project-direction)
supersede earlier native-first sequencing. These are planned acceptance criteria,
not claims that the host interface or application trial is implemented.

## Objective and architecture

Test whether a small language with predictable rules helps agents produce and
maintain correct programs with less repair effort. Execute application logic in
the existing custom bytecode VM written in Guardian's pinned Zig snapshot. Keep
parsing, semantic checking, typed IR, bytecode lowering, and execution separate.
The VM is the application runtime during design development, with source traces
and bounded execution useful for debugging and repeatable experiments.

Keep the language definition responsible for types, evaluation order, ownership,
borrowing, deterministic cleanup, effects, checked arithmetic, and indexing.
Runtime checks remain necessary when those properties cannot be established
statically. A future backend must implement the same contracts. Avoid semantics
that depend on a VM instruction encoding or the host's incidental memory layout.

## Predictable rules and diagnostics

| Priority rule | Intended protection and acceptance |
| --- | --- |
| Distinct IDs and units | Reject mixed component/net identities and coordinate units; test public/private construction and explicit conversions. |
| Tagged unions and exhaustive matching | Adding a state diagnoses every match that promised completeness. |
| Explicit optional values and errors | Represent absence explicitly using variants initially; test access only after case handling and failures that cannot be silently discarded. Audit usability before proposing dedicated optional syntax. |
| Initialization and checked operations | Reject reads without initialization; test overflow, division and indexing failures in Debug and ReleaseFast with located diagnostics/traps. |
| Ownership and borrowing | Reject consumed values, escaping references, and conflicting access; verify cleanup on success, early errors and traps. |
| Mutation and effects | Require visible mutation and authority for external operations; enforce effect bounds transitively through helpers, host calls and cleanup. |

Extend existing implementations rather than treating this table as a fresh feature
list. Generic local views and arena/reset origins remain a known checking gap.
Keep unsupported programs rejected until their rules are implemented. Prefer
local inference and explicit public contracts; evaluate confusing interactions
and boilerplate as design costs. Duplication/size reports remain advisory and
must earn their usefulness in real edits rather than forcing abstractions.

Diagnostics are part of each feature's acceptance. Provide stable error codes,
primary source spans, related locations and readable explanations. For ownership
conflicts, identify creation, borrow or move, and the conflicting later use when
applicable. Preserve module and generic-call context. Test the structured output
and repair examples; do not expose compiler internals as required user knowledge.

## Typed host-library interface — pending

Start with a few explicit, synchronous registrations and handwritten Zig wrappers.
Language callers see ordinary typed operations, for example board/options to a
routing result or declared error. They should not need to know which native
implementation language supplies the operation. Heavy geometry may remain in
Zig, C or Rust without a native compiler for guest programs.

Before implementation, specify and test:

- Registration identity, exact parameter/result types, declared effects and
  required capabilities. Reject unknown registrations and mismatched contracts
  before executing a callback. Register through trusted host configuration;
  avoid arbitrary symbol loading or raw-pointer values in guest code.
- Input/output ownership. Prefer copied ordinary values for the first boundary;
  represent host-owned board state with a typed handle only if the trial needs
  it, with explicit identity, lifetime and stale-handle checks.
- Any borrowed buffer is valid only during its synchronous call. Shared/exclusive
  access follows guest borrow rules. The host must not retain references or
  invalidate backing storage, and returned data must have explicit ownership.
  Deferred borrowed signatures must be rejected, not silently treated as copies.
- Recoverable failures return declared result values. Distinguish guest traps
  and host failures; define exactly-once cleanup for partially produced outputs.
- Execution budgets: VM instruction limits do not bound time inside arbitrary
  native code. Choose bounded operations or an explicit cooperative cancellation
  contract for long-running wrappers. Reentrant/asynchronous callbacks are
  outside the first interface.

Wrappers are trusted implementation code. The language checker cannot prove
arbitrary native code safe. Keep raw pointers and ABI conversion inside this
boundary; document and test its assumptions using deterministic fake functions,
invalid arguments, denied capabilities, typed failures, and allocation failures.

Existing filesystem/network/clock/environment providers are reusable experience.
Existing native embedding and Python bindings call compiled guest functions;
they do not provide general guest-to-host domain-function registration.

## First substantial application experiment — pending

Choose a bounded board-validation or constraint-processing module. Define its
input snapshot, outputs, error cases and independent expected results before
porting it. Model component/net IDs and units as distinct types and validation
outcomes as explicit variants. Keep expensive geometry and routing kernels in
the host; start with the smallest set of typed host calls the module requires.

Compare equivalent changes in the existing implementation and the language using
matched task descriptions, available context, model/tool configuration and a
recorded attempt budget. Include valid and invalid boards, boundary coordinates,
missing IDs, constraint conflicts, and controlled schema/state changes. Hold back
independent behavioral cases from the agent performing repairs. Record:

| Measure | Evidence to retain |
| --- | --- |
| Mistakes caught before execution | Seeded/observed defect, detection phase and diagnostic; report escapes separately. |
| Next-attempt repair success | Correct repairs on the first edit after a diagnostic divided by diagnosed attempts; independent tests must pass. |
| Edit disruption | Unrelated files/lines changed, duplicated domain rules, unsafe workarounds and changes made only to appease a restriction. |
| Behavioral correctness | Independent test results for both implementations, including failures and unfinished tasks. |
| Practical cost | Repair attempts, elapsed task/check time and host-call time; distinguish measurement from causal claims. |

Publish the small corpus and raw outcomes with limitations. Do not declare the
language more reliable from compiler test counts or a single successful demo.
Use the trial to decide which abstractions, serialization and incremental tooling
help enough to build next. The trial need not wait for all generic features.

## Acceptance workflow and deferred work

For active language changes, require relevant checker/VM tests, actual CLI tests,
Debug/ReleaseFast semantic agreement, applicable failure/cleanup cases, formatting,
and the strict Guardian gate on the Zig implementation with baselines disabled.
Keep independent expected results as the oracle; interpreter execution alone
cannot establish correctness. Extend specification links for implemented rules.

The next infrastructure change should expose a focused interpreter test target
and put expensive native compilation/parity integration behind an optional target.
Today `zig build test` still runs those native suites; this documentation does
not introduce new commands or change that behavior. Existing inexpensive native
unit tests may remain in shared roots. A change to shared code should still receive
relevant regression checks; native feature parity is not required for each new
language feature. Unsupported native features must fail explicitly when used.

Preserve completed C/native code, tests and historical results. Defer further
native coverage, borrowed/capability native ABI expansion, native optimization,
LLVM, direct x86_64 Linux output, JIT, and VM instruction fusion/adaptive work.
Wasm is optional if a demonstrated sandbox/runtime need justifies its interface
and memory-model cost. No backend transition date is set.

Reopen native compilation after representative projects stabilize the semantics
and measurements show an execution or deployment need not adequately served by
typed host calls. Compare the existing C route, LLVM and direct machine code then;
none is a prerequisite for proving the language useful now.
