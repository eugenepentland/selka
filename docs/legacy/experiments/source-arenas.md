# C: lexical source arenas and escape checking
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

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
errors through typed results. [Explicit source reset](arena-reset.md) now reclaims unused chunks with typed
results while preserving the scope and its allocator authority.

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
Formatting round trips cover 32 valid fixtures. Exact discovery is `exact-v28` and
retains arena boundary structure while normalizing bound allocator names. Native
emission continues to reject these operations with `E_NATIVE_FEATURE`.

### Proven direct return origins

The concrete checker now narrows a helper's result dependency when every return
is exactly the same immutable value parameter. For example,
`fn select(outer:allocator,scratch:allocator)->allocator {discard scratch;return outer;}`
can be called inside a scratch arena without making its result depend on scratch.
Returning scratch still rejects an escape. This proof also applies to concrete
generic specializations; symbolic generic validation retains its own restrictions.
Other expressions, multiple possible parameter origins, reference parameters,
host calls and early `try` propagation keep the conservative result summary.
Mutable argument effects remain conservative even when the result is precise.
Stored views and field-sensitive aggregate summaries remain separate work.

## Selected-field return provenance

The concrete region pass can prove return origins through immutable local aliases,
record field reads/takes, and value wrappers. It follows up to 16 nested record
fields and 256 expression levels, with a bounded per-function proof budget.
At the call site it selects the matching field from immutable construction or
update expressions. For example, returning `pair.outer` does not retain
`pair.scratch` when the caller supplied separate allocator authorities. Owned
field extraction gets the same proof, and cleanup still drops remaining fields.
Generic function specializations use their concrete field identities.

An unknown or mutable source falls back to the complete source dependency. Host
calls, borrowed-parameter functions, ambiguous return origins, and functions with
early result propagation keep the existing conservative summary. This stage does
not add stored references or arbitrary conditional lifetime unions; symbolic
arena analysis inside an uninstantiated generic body remains conservative.
