# Typed host functions

The trusted registration and value-copy boundary is implemented. Guest host
declarations, program linking and bytecode call dispatch remain pending. This
work supports the interpreter; native compilation of guest programs remains
outside the active goal.

## Implemented registry contract

`compiler.host_functions.Registry` borrows one immutable nominal type catalog
and owns snapshots of declaration names and parameter descriptors. Each exact
name has an ordered parameter list, result type, passing modes and effect mask.
`register` installs a handwritten synchronous callback with an optional trusted
context and explicit effect grants. Unknown names, duplicate registrations,
signature mismatches and insufficient grants reject before callback execution.
`begin` requires every declaration to be registered, including unused ones.
Names are registry-local identities; there is no automatic symbol loading.

Only ordinary value graphs cross this first boundary: integer and boolean values,
records, fixed arrays, enums, unions, results and nominal domains. The complete
graph must exclude capabilities, runtime identity and move-only storage. Shared
and exclusive reference signatures reject explicitly. Type IDs have meaning
only in the borrowed catalog; wrappers must be built for that same catalog.
The later VM linker must also verify the registry against the compiled program.

A session copies arguments into its execution allocator, invokes the callback,
validates its declared output type and returns an independent owned copy. Input
validation completes before invoking or charging the callback. Each input copy,
temporary callback result and failed partial output is released on its owned
path. Closing a session does not invalidate returned values: callers release
those using the execution allocator. A declared result's error variant remains
an ordinary guest result; `HostFailure` is a separate wrapper failure.

Registration metadata cannot change during an execution. Sessions reject nested
entry, callback-time close/rebinding, and use after close or after another
session begins. A generation counter rejects exhaustion instead of wrapping.
Registry/context lifetime and caller serialization are embedding requirements;
this API does not add thread synchronization.

## Budgets and wrapper obligations

`Limits` bounds callback invocations, cooperative work units, visited input/output
values and copy depth. Defaults are 10,000 calls, 1,000,000 work units, 65,536
values per call and depth 64. Zero budgets and depth above 128 reject at session
start. One unit is charged for every callback invocation, and `Call.consume`
charges additional work. An exceeded work budget remains exhausted even if a
callback catches the error. Failed callbacks and rejected output values still
consume the invocation; limits reset only when a new session begins.

Copy counts cover all inputs and the output together. Oversized inputs reject
before the callback, whereas oversized outputs reject after callback execution.
That cannot roll back external side effects. Wrappers should therefore expose
recoverable domain failures explicitly and define their own transactional needs.

Wrappers are trusted Zig code. `Call.arguments`, `Call.records`, `Call.context`
and the call itself are borrowed for the synchronous callback only. Return a
well-formed owned value allocated with `Call.allocator()`; retain an aggregate
before returning an input aggregate directly. Release partially built callback
outputs when returning a Zig error. The registry cannot validate arbitrary
pointer ownership, prevent a wrapper from retaining a pointer, or preempt an
uncooperative callback. Choose bounded operations and charge their work.

## Acceptance and remaining integration

`host_functions_test.zig` exercises exact registrations and grants, metadata
snapshots, missing preflight bindings, unsupported signatures, argument/result
validation, declared success/error payloads, independent aggregate storage,
call/work/value/depth limits, reentry, stale sessions and generation exhaustion.
Allocation-failure sweeps cover registration, argument copying, wrapper output
construction, result copying and cleanup with owned aggregate/results.

The next implementation must connect this boundary end to end:

1. Explicit guest host declarations with exact signatures and visible effects;
   reject deferred borrowed, generic and authority-bearing contracts clearly.
2. Preserve declaration identity through modules, checked IR, lowering and
   bytecode validation. Do not permit callbacks to override ordinary functions.
3. Bind against the same compiled program and preflight registrations before
   executing guest operations. Keep host calls out of effect-free evaluation.
4. Dispatch checked VM calls through one session, with located runtime failures,
   ordinary guest result handling, instruction quotas and deterministic cleanup.
5. Verify imported calls, transitive/generic effects, malformed bytecode, absent
   or denied registrations and failure paths using deterministic fake wrappers.

Then build the board/constraint trial and record independent behavior and actual
agent repair outcomes. Registry tests alone do not establish language usefulness.

## Proposed guest integration, not implemented syntax

Use an explicit declaration, for example
`host fn measure(point: Point) -> Checked effects(host);`. Its semicolon denotes
an externally implemented function; ordinary function bodies cannot be rebound.
Keep `host` contextual so effect names and existing identifiers continue to parse.
Initially restrict declarations to ordinary top-level functions with copied data
signatures. Generic callers may use a host declaration, but generic host
declarations, domain methods, complete conversions and borrowed signatures need
separate contracts before acceptance.

Add a distinct host-call effect, included in every host declaration and propagated
through ordinary and abstract generic callers. This prevents a computation-only
wrapper from entering the existing effect-free evaluator or codec execution
path. Additional declared effects such as filesystem access require corresponding
registration grants. Installation plus grants supplies trusted embedding
authority; guest code cannot invent a callback by naming a function.

Prefer a program-bound VM registration adapter over accepting an unrelated
registry at dispatch time. It should borrow the exact checked program/catalog,
derive only marked host declarations, and retain a function-ID-to-registration
mapping. A separate `runWithHost` entry can supply that adapter and session limits
without expanding the existing default VM options. Preflight precedes guest
effects, and one session lasts exactly one execution. Copied arguments/results
remain under the VM's normal value ownership and cleanup paths. Preserve ordinary
instruction accounting for each call and expose wrapper failures at the call site.

Bytecode validation must independently reject fabricated host bodies, reference
metadata, missing effects and non-data signatures. Duplicate discovery should
exclude external declarations: identical signatures without bodies are no
evidence of duplicated implementations. The retained C emitter should clearly
reject this new feature; implementing host calls in a native guest backend is
outside the active scope.
