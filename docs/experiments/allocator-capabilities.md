# C: explicit allocator capabilities

Status: allocation and growth require an explicit allocator capability supplied by
the entry runtime. Forwarding, copy/return/wrapper behavior, quota preservation,
provisioning denial, and runtime identity checks are implemented. External
capabilities/resources and their effects, attenuated child capabilities, arenas,
and pools remain pending. C is not complete.

## Source contract

```text
buffer Numbers: i64;
result Acquired { ok: Numbers, err: i64 }
result Status { ok: bool, err: i64 }

fn make(heap: allocator) -> Acquired {
    let mut values = try acquire_buffer<Acquired>(heap, 1);
    discard try reserve_buffer<Status>(values, heap, 3);
    return new Acquired.ok(values);
}

fn main(heap: allocator) -> i64 {
    match make(heap) {
        Acquired.ok(values) => { return cast<i64>(capacity_buffer(values)); },
        Acquired.err(error_code) => { return error_code; }
    }
}
```

`allocator` is an opaque built-in capability type. `main` accepts either no
parameters or one value parameter of this type; its result remains i64. Other
entry parameter lists are rejected. Ordinary helper calls must pass the capability
explicitly. Calling `main` from guest code follows normal argument checking and
does not inject another capability.

Acquisition is now `acquire_buffer<Result>(capability, capacity)`. Growth is
`reserve_buffer<Status>(buffer, capability, capacity)`. The old forms without a
capability are source errors. Existing executable examples/fixtures and ownership/
effect tests have been migrated. Reserved-capacity edits, queries, slice operations,
ownership transfers, and cleanup need no allocator argument.

Capability expressions evaluate before capacity expressions. Both participate in
normal type/effect checking; helper calls cannot hide allocation inside capability
forwarding. Possessing authority does not bypass an asserted noalloc bound.
Conversely, receiving, copying, returning, or discarding a capability does not itself
perform allocation.

A capability is copyable authority, not an owned buffer. It can be explicitly
forwarded through locals, parameters, return values, and typed wrapper fields.
Copying a capability does not create a new quota or grant additional authority.
Passing an authority-containing wrapper is deliberate delegation through that value;
there are no ambient globals or implicit capability lookups.

Safe source cannot create a capability with integer literals, casts, domains,
record construction, or an effect annotation. It can only obtain one from an
existing capability value or the entry parameter. Owning a buffer does not expose
its internal allocator or authorize growth without a capability.

## Runtime boundary

The VM creates the requested entry capability for its live memory-store identity.
All copies refer to that execution and share `Options.memory_limits`. The identity
is not a host pointer and cannot be inspected or constructed by source programs.
Acquire and reserve check it before allocation/growth. Stale, closed, and foreign
identities are rejected. The host is the trusted boundary and can construct or
provision runtime objects; this is a safe-source authority model, not a hostile-host
sandbox or cryptographic token design.

`Options.provide_allocator` defaults to true. If false, a capability-requiring entry
fails with host `CapabilityUnavailable` before guest execution. A scalar entry
without that parameter still runs. The CLI supplies the default allocator capability
when requested; embedding applications can deny it or configure the shared ceilings.
There is no hidden grant to ordinary functions and no old-syntax fallback.

The first capability controls allocation in one execution store. Restricted child
quotas, independent allocator regions, and authority attenuation are not implemented.
Host allocator failures remain host failures; existing recoverable capacity status
codes and cleanup rules are unchanged.

## Verification

`src/allocator_capabilities_test.zig` checks explicit forwarding through calls,
returns, and wrappers; shared quotas; denied provisioning; scalar execution without
a grant; fabrication and omitted-argument rejection; noalloc enforcement; stale/
foreign identities; allocation-failure cleanup; and invalid entry/operand metadata.
Existing buffer/view/effect suites now exercise explicit authority throughout their
partial-acquisition, trap, and bounded-storage cases.

Debug and ReleaseFast pass 260 tests (231 core, 29 actual CLI; the final Debug core
run reused its unchanged successful result). Formatting and whitespace checks pass.
`examples/allocator-capabilities.my` returns 3, and all checking commands reject an
integer supplied as allocator authority. Exact discovery is `exact-v17`, retaining
the capability operand and capability-bearing function signatures.

Next: external capability parameters and fake implementations for filesystem,
network, clock, randomness, and environment effects; external resource cleanup and
fallible completion. Arenas/pools and the remaining roadmap tracks stay in scope.

Clock and randomness grants are now implemented separately; see [external capability
semantics](external-capabilities.md). Entry parameters may request each supported
capability kind once in any order. The 260-test count above is this allocator
milestone’s historical checkpoint.
