# Native resource implementation and acceptance

Filesystem/network acquisition, completion, permission attenuation, and ownership
cleanup are implemented with provider ABI v3; full regression acceptance passes.
Byte I/O and additional stress acceptance remain pending. The source and VM contracts
in [source resources](source-resources.md), [resource I/O](resource-io.md),
[attenuation](attenuation.md), and [slice I/O](resource-slices.md) define the target.
Full native support must also cover array and slice I/O.

## Cleanup foundation

Native frame return now releases locals in reverse slot order, matching the VM.
Released slots are cleared. A runtime harness observes leaf destruction for
reordered allocation/local layouts, empty moved slots, shared snapshots, nested
schema order, and reverse operand order. A 20,000-level nested value verifies
nonrecursive destruction with no allocation. The previous runtime fails the
reverse-local assertion. Both C optimization levels run this harness with address
and undefined-behavior sanitizers in the native memory acceptance driver.

Emergency cleanup now reconstructs temporary roots from reference counts,
subtracting references held by aggregate fields, operands, and locals. The
intrusive registry records temporary acquisition order on creation, copying, and
stack transfer. Cleanup releases temporary references first, then all operands
and locals in reverse order, using the same nonrecursive value destructor.
This requires no allocation or recursive graph traversal; the supported ownership
graph has no pointer cycles (source graph cycles use value handles).

The harness verifies a pop order different from allocation order, shared local
references, and nested temporary construction. Actual trap and injected OOM paths
exercise stack growth, frame reference allocation after argument transfer, and
partial result construction: ten cases across C O0/O2. The previous raw-registry
cleanup fails the new destruction-order assertion. Existing native memory
acceptance passes all 468 injected allocation failures on the new runtime.
Complete Debug and ReleaseFast runs pass all 30 build steps and 593 core/CLI
tests, with all 88 Guardian checks passing. Resource callback trace parity remains
required when filesystem/network emission is implemented.

## Remaining implementation requirements

- Extend the verified ownership unwind to native resource values. New helpers
  must preserve counted ownership through constructor adoption and field
  extraction, including allocation failures while values are C temporaries.
- Preserve reverse operand and local order on unwind and depth-first reverse
  schema/index order inside aggregates. Allocation order is not schema order.
  Remaining store entries are a final safety net: reverse acquisition within each
  store, with network teardown before filesystem, matching `resource_runtime`.
- Resource callback traces must also cover propagation boxing failures; the
  ordinary-value allocation-boundary regression below establishes the sequence.
- Add explicit versioned provider callbacks for acquisition, completion, fallback
  release, read, and write. Require grants before guest execution; preserve byte
  requests, independent per-kind quotas, checked identities, and permission
  intersection. Release is nonfailing, nonallocating, and never implies completion.
- Successful completion consumes the host handle even if result construction later
  fails. Recoverable completion failure returns the same owner with its error code
  for retry. Read/write preserve ownership and validate bounded partial progress.
- Compare callback traces against VM execution for reordered constructors, partial
  moves, helper calls/returns, propagation, retries, discarded errors, traps,
  denied operations, missing grants, and every native allocation failure. Include
  read/write arrays and slices, attenuation, quota boundaries, and mixed stores.

The cleanup foundation does not complete native resource support or the wider
roadmap. Filesystem/network operations and their provider callback acceptance
remain pending.

## Propagation allocation boundary

Native error propagation now constructs its outgoing result before releasing
unfinished operands, matching the VM. A generated-C fixture observes the final
destruction of the error payload and a partially constructed caller value. Normal
execution releases the unfinished value before the eventual returned payload;
OOM during propagation releases the payload first. Injecting failure at allocation
8 into the prior emission sequence demonstrates the reversed, incorrect order.

The fixture sweeps all eight allocation points at C O0/O2 with sanitizers and
zero-live-memory checks. Focused native memory acceptance now passes 484 allocation
failures (the previous 468 plus 16 from this fixture). Complete Debug and ReleaseFast
runs pass all 30 build steps and 593 core/CLI tests; all 88 Guardian checks pass. Native filesystem/network resource callbacks
and the wider roadmap remain pending.

## Provider registration boundary to implement

The VM reserves store bookkeeping before acquisition, registers a successful host
handle, then allocates its guest owner. If that last allocation fails, it releases
the new handle immediately, before unwinding older guest values. Native integration
needs the same ordering: keep a pending acquired handle until an aggregate owner
has been registered, and release that pending handle before ordinary roots on
failure. Final store teardown alone would release it too late.

Use store indices rather than entry pointers across registry growth. Preserve
independent per-kind live quotas (1024 by default), generations and retired slots,
permission masks, and reverse acquisition links. A fixed slot array would conflate
the live quota with retained retired entries. Successful completion must invalidate
the entry before any result allocation; failed completion must retain ownership.
These are implementation requirements, not claims of existing native support.

## Lifecycle provider implementation

Provider ABI v3 adds filesystem/network contexts, explicit initial permission masks
(read=1, write=2, complete=4), and acquire/complete/release callbacks. The builder
links adapters through the existing `--provider` option; the versioned factory is
now `mylang_native_providers_v3`. Include the current header and implement its
generic `mylang_native_providers` macro name. Callbacks are synchronous and must
not reenter the generated program. No ambient filesystem/network adapter is chosen.

Entry grants check all mandatory callbacks before guest execution. Permission
restriction intersects masks, and completion checks the acquired mask before
calling the provider. Missing grants fail before even a skipped operation. Each
family has a growable generation-checked registry, a 1024-live-owner default quota,
and a reverse acquisition chain. Retired generation slots are not reused.

Successful acquisition records a pending handle until guest-owner allocation
finishes; OOM there releases it before older roots. Successful completion consumes
the handle before result allocation. Recoverable completion failure returns the
owner and code in the declared field order, allowing retry. Other exits only
release; they never implicitly complete. Nominal wrappers and partial moves use
the existing ownership graph.

Focused acceptance passes 32 native status/ownership cases at O0/O2: 28 compare
exact callback traces with VM execution and four check malformed C-provider
statuses unavailable in the VM callback type. All 120 injected native allocation
failures clean live handles and storage, including pending acquisition, retries,
successful completion followed by allocation failure, and reordered fields.
The separate VM oracle and all 23 focused native Zig tests pass. Complete Debug
and ReleaseFast runs pass all 31 build steps and 594 core/CLI tests (534 core,
60 CLI), with all 88 Guardian checks passing. Byte I/O, source attenuation acceptance,
quota/reuse/generation stress, mixed-store traces, and broader resource corpus
acceptance remain open.

## Byte I/O contract still to implement

Fixed-array reads return a fresh byte array with a zeroed tail. Slice reads stage
provider output and commit only the reported prefix, preserving the original
slice tail and bytes outside the view. Failed reads must leave guest storage
unchanged. Prepare any ordinary-array replacement before invoking the provider,
as `byte_slices.Prepared.init` does; buffer slices retain their backing owner.

Read/write keep owners live on both success and failure. Check permission before
callback availability, accept partial counts within the supplied bound, and reject
invalid counts/EOF flags as host failures. Slice result records and fixed-array
result records have different shapes; write results can use the existing packed
status-result emitter. Callback traces must cover the allocation boundary before
provider invocation and the result allocations after a successful slice commit.
