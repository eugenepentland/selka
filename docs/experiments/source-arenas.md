# C: lexical source arenas and escape checking

Lexical arena scopes now integrate the [checked region runtime](region-backing.md)
with parsing, type checking, lowering, the VM, formatting, and analysis commands.
The lifetime analysis is conservative and does not introduce general lifetime
parameters or field-sensitive function summaries.

```text
arena heap as scratch {
    let buffer = try acquire_buffer<Open>(scratch, 16);
    // Use or transfer the buffer inside this arena lifetime.
}
```

The parent expression must have type `allocator`. The scope introduces an immutable
allocator binding and rejects shadowing. Nested scopes may derive from an active
parent. Their backing chunks use the execution allocator, with parent/child lifetime
guards. Scope entry contributes the transitive `allocation` effect, even when its
body is empty; `noalloc` therefore rejects it. Owned buffers and pool registries use
the allocator supplied at acquisition. Explicitly using the outer heap still creates
an outer-lifetime owner, even inside an arena scope.

A region-slot limit produces `R_REGION_LIMIT`, like other VM execution budgets.
Host metadata/backing allocation failure remains `OutOfMemory` and unwinds the VM.
Individual buffer/pool acquisition still reports its existing recoverable quota
errors through typed results. Explicit source reset operations/results remain pending. For now, use a fresh
lexical scope for each iteration rather than requesting a mid-scope reset.

## Escape rules

Allocator capabilities, owned buffers/pools, and containers containing them carry
region dependencies. Plain scalar values, external capabilities/resources, nominal
IDs, and immutable snapshots containing no regional capability or ownership do not
acquire a dependency solely from where they were computed. IDs may leave a scope;
accessing their destroyed pool still fails its runtime identity/generation checks.

`E_ARENA_ESCAPE` rejects outward returns and assignments of regional values, including
wrapped owners and allocator aliases. The same check covers error payloads returned
by `try`, writes through references/slices, and insertion into longer-lived buffer or
pool storage. Passing an arena allocator through helpers preserves the dependency of
returned owners. Calls with mutable reference parameters cannot write dependencies
into longer-lived destinations. Shared reference parameters are treated as reads,
even when supplied by an exclusive caller reference.

Arena-local capability containers are usable. A capability can be stored in an
array, buffer, or pool whose lifetime contains it, read back, and used for acquisition
before scope exit. Heap-owned values constructed explicitly with the outer allocator
may return safely. Parent-allocated pool snapshots containing plain data can remain
in outer bindings after both the pool and its arena are destroyed. Existing returned
reference contracts and borrow conflicts apply in addition to these checks.

The analysis uses relative arena depth and a monotone fixed point over each function
that introduces a local arena. Function parameters describe caller-owned lifetimes;
a helper without a local arena cannot create a shorter one. Calls conservatively
propagate dependencies from all region-bearing value and reference inputs. The
checker does not assume which arguments an arbitrary helper will return or copy.

These deliberate restrictions can reject otherwise-safe code:

- Dependencies merge across all assignments and branches, including untaken paths.
  Overwriting a binding with a heap value does not erase an earlier regional dependency.
- Aggregates use one dependency for the whole value. Extracting a heap-backed field
  from a mixed heap/arena wrapper can conservatively retain the arena dependency.
- A helper returning a region-bearing type retains dependencies from unrelated inputs
  too. There are no explicit owner-return provenance annotations yet.

Use separate bindings and explicit outer values to make lifetimes clear. These are
conservative acceptance rules, not proof that every rejected program would dangle.
Diagnostics identify the escaping expression/statement. No general borrow-checker
soundness or full-language native support is claimed.

## Cleanup and runtime defenses

Normal scope exit first performs the body's owned cleanup, then closes the region.
References end according to existing lexical borrow rules. Return and recoverable
propagation release frame-owned values before closing that frame's active regions
in reverse order. Caller regions remain active across helper returns. Instruction
traps and host allocation failures release operands/locals, then the memory store
tears down remaining region metadata and chunks.

The VM retains its own active region stack and original capabilities. Ending a
mismatched region is an internal-error rejection, and backend lifetime guards prevent
freeing backing while an owner remains. Region-slot reuse changes generation.
Allocator authority used to grow a buffer must match its original region; growth
never silently changes the buffer's allocator. The current bytecode validator checks
region target schemas and operand heights; there is no untrusted bytecode loader.

## Evidence

`examples/arenas.my` returns `50` using nested arenas, a snapshot-producing pool
helper, an owned buffer, and a borrowed buffer view. `src/arena_source_test.zig`
covers the example, every host allocation failure, every instruction budget through
completion on both execution memory backends, normal/return/propagation cleanup,
quota reuse, escape rejection through wrappers/aliases/calls/control flow/mutations,
legal arena-local capability containers, escaped inert IDs, snapshots surviving scope
exit, effect bounds, region limits, and malformed bytecode defenses.

10,000 source scopes with pool and buffer allocation remain within 16 KiB live
runtime storage on both execution backends. Actual CLI tests execute/check/dump the
fixture and reject escapes across check/run/discovery/quality/native commands.
Formatting round trips cover 31 valid fixtures. Exact discovery is `exact-v27` and
retains arena boundary structure while normalizing bound allocator names. Native
emission continues to reject these operations with `E_NATIVE_FEATURE`.
