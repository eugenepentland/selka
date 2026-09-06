# Native resource implementation and acceptance

Filesystem/network resource emission remains pending. The source and VM contracts
in [source resources](source-resources.md), [resource I/O](resource-io.md),
[attenuation](attenuation.md), and [slice I/O](resource-slices.md) define the target.
Native support must cover those operations rather than only acquisition.

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
- Align generated error propagation with the VM before adding resource payloads:
  the native `try_result` emitter currently clears unfinished operands before
  boxing the outgoing result, while the VM constructs that result first. An OOM
  during boxing must release the propagated payload before unfinished operands.
  Resource callback traces must cover this allocation boundary explicitly.
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
