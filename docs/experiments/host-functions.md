# Typed host functions

Explicit guest declarations now execute through the bytecode VM and the trusted
registration/value-copy boundary. Ordinary and imported calls, generic helpers,
typed results, effects, preflight and cleanup have executed acceptance. Native
compilation of guest host calls remains outside the active goal.

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
The VM adapter also pins registrations to the exact compiled program/catalog.

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

## Guest declarations and VM execution

Declare an externally implemented operation with an explicit signature:

```text
host fn measure(point: Point) -> Checked effects(host);
```

The semicolon replaces a guest body. Host declarations are ordinary top-level
functions with copied data signatures. Generic guest helpers may call them, but
generic host declarations, domain methods, complete conversions and borrowed
signatures reject explicitly. `host` remains a contextual name; existing ordinary
identifiers still parse. Main must have a guest body.

Every host declaration explicitly includes the `host` effect. Additional effects
such as filesystem access require corresponding registration grants. Effects
propagate through ordinary and abstract generic callers, including uncalled
bodies. The existing effect-free evaluator, typed invocation and codec contracts
cannot execute a host call. Installation plus grants supplies trusted embedding
authority; guest code cannot create a callback merely by naming a function.

`compiler.vm_host.Registry.init` validates bytecode and extracts only explicit
host declarations. It borrows that immutable compilation/catalog and snapshots
registration contracts. Names are resolved identities such as
`geometry::validate`, independent of an importing module's alias. `register`
cannot replace ordinary guest functions. `vm.runWithHost` checks program identity
and all bindings/grants before guest operations, then owns one session until
execution cleanup. The compilation and callback contexts must outlive the registry.

Preflight requires every host declaration, including unused ones. A normal VM
run without registrations returns `R_HOST_REGISTRATION` at a host declaration.
The CLI can check, format and inspect these programs, but executing their host
calls requires an embedding application to install wrappers; no command-line
symbol loading is provided.

Each guest call retains normal instruction/frame accounting and uses the
session's callback/value/work limits. Wrapper failures, invalid output contracts
and exhausted host limits become `R_HOST_FAILURE`, `R_HOST_CONTRACT` and
`R_HOST_LIMIT` traps at the guest call site, with caller traces. `OutOfMemory`
remains a host execution error. Declared result variants pass back to ordinary
guest matching/propagation and cannot be silently discarded. Failure does not
roll back host side effects; wrappers must define those semantics themselves.

Bytecode validation independently rejects fabricated host bodies, reference
metadata, missing effects and non-data signatures. Disassembly marks external
declarations, and duplicate discovery excludes them: identical signatures without
bodies are no evidence of duplicated implementations. The retained C emitter
clearly rejects this feature; native guest execution remains deferred.

## Minimal Zig embedding

This callback returns a scalar, which has no owned storage to retain:

```zig
const std = @import("std");
const language = @import("mylang");

fn identity(call: *language.host_functions.Call) language.host_functions.CallbackError!language.vm.Value {
    return call.arguments[0];
}

pub fn execute(allocator: std.mem.Allocator) !i64 {
    var compilation = try language.Compilation.init(allocator, "example.my",
        "host fn identity(x:i64)->i64 effects(host);fn main()->i64{return identity(42);}");
    defer compilation.deinit();
    try compilation.emit();
    var registrations = try language.vm_host.Registry.init(allocator, compilation.code.?);
    defer registrations.deinit();
    const signature = try registrations.contract("identity");
    try registrations.register("identity", .{ .signature = signature, .invoke = identity }, signature.effects);
    const outcome = try language.vm.runWithHost(allocator, compilation.code.?, .{}, &registrations, .{});
    return switch (outcome) {
        .value => |value| value,
        .trap => error.GuestTrap, // An application can render outcome.trap using the source map.
    };
}
```

`contract` supplies compiler-resolved nominal IDs for handwritten wrappers. The
wrapper remains responsible for implementing that exact contract. See
`vm_host_test.zig` for imported aggregate/results, generic guest calls, caller
traces, owned-buffer cleanup and allocation-failure cases.

## Acceptance and next experiment

### Typed application entry points

An embedding application can now pass a typed snapshot to an ordinary guest
function and receive a caller-owned typed result using `vm.invokeWithHost`.
For a module project, `Compilation.invokePublicWithHost` resolves only explicitly
exported names before invoking. Both use the same program-bound registrations
as `runWithHost`; direct `host fn` declarations are not guest entry points.

`HostInvokeOptions.execution` supplies instruction/frame limits, argument-copy
limits and optional executed-step reporting. `.callbacks` supplies independent
host call/work/value limits. The caller retains its input values and releases a
returned `.value` with the invocation allocator. Reference, capability and
runtime-owned argument/result graphs reject; invalid arity, types, public names
and missing registrations cannot execute callbacks. The original `invoke` and
`invokePublic` APIs remain effect-free.

`host_invocation_test.zig` verifies imported public entry selection, nominal
success/error results, independent aggregate ownership, failure cleanup,
instruction accounting and separate argument/callback budgets. This supplies the
typed snapshot/report boundary needed by the board-validation trial.

`host_functions_test.zig` exercises exact registrations and grants, metadata
snapshots, missing preflight bindings, unsupported signatures, argument/result
validation, declared success/error payloads, independent aggregate storage,
call/work/value/depth limits, reentry, stale sessions and generation exhaustion.

`host_declarations_test.zig`, `vm_host_test.zig` and actual CLI tests extend that
coverage through source checking, abstract effects, lowered calls, module aliases,
nominal aggregate results, formatting, duplicate discovery, malformed bytecode,
program identity, error locations and session reuse. Allocation-failure sweeps
span checking, linking, callbacks, guest-owned storage and result cleanup.

The [board trial contract and oracle](../../experiments/board_trial/contract.md)
now fix 87 development cases before either validator implementation. Guest/Zig
validation and recorded agent repair outcomes remain pending. Add borrowed buffers or typed host-owned handles
only if that trial needs them, with explicit access, lifetime and stale-identity
contracts. Interpreter optimization and native guest backends remain deferred.
