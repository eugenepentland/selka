# C: external resource ownership backend

Status: a provider-backed ownership registry and lexical cleanup scopes are
implemented in `src/external_resources.zig`. This is backend acceptance only.
Guest declarations, acquisition/completion expressions, source ownership checks,
VM integration, and transitive external cleanup effects remain pending. No new
CLI resource operations or operating-system adapters are implemented here.

## Provider boundary and lifecycle

Each store has one filesystem or network provider and one non-reused identity.
An explicit grant names that store and resource kind. A provider can represent
restricted authority (for example one directory or endpoint); it interprets and
validates the borrowed request bytes. A copied grant cannot change the provider
or enlarge its authority. Host-side store construction is the trusted boundary.

The synchronous provider API separates three operations:

- `acquire(context, request, permissions)` returns a private host handle or a recoverable/host
  error. On error, it must retain no acquired resource.
- `complete(context, handle)` performs the requested fallible completion. Success
  consumes the host handle. Failure leaves it valid for retry or fallback release.
- `release(context, handle)` performs non-failing fallback cleanup. It must not
  imply that completion succeeded, allocate, or fail to return.

Contexts must outlive their stores. Stores/providers are not copyable ownership
objects and cannot be reentered from callbacks. These are trusted adapter
contracts; the compiler cannot prove an arbitrary callback honors them. A durable
flush or transaction commit adapter must define its own success semantics. An
error may follow partial external work: the generic registry promises neither
transaction rollback nor atomic external state.

Store acquisition validates the grant and live-resource ceiling, then reserves
registry storage before calling the provider. After callback success, registration
cannot fail. Failed acquisition leaves a reusable vacant slot; it does not consume
quota. Guest-facing owner tokens contain store/index/generation, never host handles.

`transfer` invalidates the old owner without provider calls or allocation.
`complete` consumes ownership only on success. `release` consumes ownership without
attempting completion. Stale/foreign tokens are rejected before callbacks. Exhausted
generations fail transfers without losing the owner; released slots at maximum
generation retire permanently. Store identities also fail rather than wrap.

## Cleanup and scope order

Stores link live entries in acquisition order, independent of reusable slot index.
Final teardown releases outstanding resources in reverse acquisition order. Moves
retain that order; completed/released resources leave the chain. Teardown is
idempotent and invokes no completion callback.

Lexical `Scope` records acquire/adopt/move operations in registration order and
release them in reverse order. A transfer into another scope moves the cleanup
obligation to its newest registration. `take` transfers that obligation to the
caller. Destination bookkeeping is reserved before consuming the source owner;
failed reservation leaves the source usable. Failed scoped completion keeps the
cleanup record; successful completion removes it. Scopes must outlive neither
the store nor its host context. Use scope APIs for scoped owners instead of
mutating them directly through the store.

Registry moves, completion bookkeeping, release, and teardown allocate no storage.
The provider's explicit completion may allocate or return host OOM. Ordinary host
allocation failures and recoverable provider failures can unwind already-acquired
resources. Process termination or a callback that cannot return is outside the
cleanup guarantee. Future guest trap handling must connect to these cleanup paths
before guest external resources are considered implemented.

## Effects and remaining integration

Filesystem and network resource kinds expose their corresponding effect. The
source checker must eventually account for acquisition, explicit completion,
**and implicit release**, including wrappers, early returns, and trap cleanup.
Having this metadata in the backend does not yet enforce those source contracts.
The existing clock/random operation effects continue to work independently.

Source resource types, explicit capability entry grants, result-returning completion
with ownership preserved on failure, and lexical VM cleanup are the next integration
work. Read/write operations, environment access, attenuation, arenas/pools, and the
other roadmap tracks remain pending. Exact discovery remains `exact-v18` because
this backend checkpoint adds no guest syntax or semantics.

## Acceptance

Debug and ReleaseFast pass 283 tests (253 core, 30 actual CLI). Backend tests use
local deterministic providers and cover acquire A/fail B/release A once; recoverable
and host-OOM completion failures followed by retry or release; successful completion
without fallback release; reverse order after slot reuse and middle removal; stale,
foreign, wrong-kind, closed, and quota rejection; nested scope moves; failed
destination bookkeeping; take/adopt; and generation retirement.

Allocation-failure sweeps cover store and scope registration/transfer and assert no
host resource survives. Moves, completion, release, and unwind succeed with registry
allocation disabled. 10,000 acquisition/move/release cycles reuse one slot under
4 KiB live registry allocation and release all storage. Source/CLI behavior is
unchanged, and these backend tests do not establish source integration or real
filesystem/network correctness.


## Subsequent source integration

[Source resource lifecycle and cleanup effects](source-resources.md) now connect
this backend to nominal resources, explicit grants, acquisition, completion returning
ownership on failure, VM cleanup, and transitive effect bounds. The backend-only
status and 283-test count above describe the historical checkpoint.

[Resource operation permissions](../legacy/experiments/attenuation.md) now flow into acquisition and
remain attached to owners through transfers. Providers must honor those restrictions
when interpreting requests; runtime read/write/completion checks enforce them too.
