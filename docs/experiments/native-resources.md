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

This establishes normal value destruction only. Emergency cleanup still frees
the allocation registry directly. It must be replaced before enabling native
resource owners, because resource release callbacks make ownership order visible.

## Remaining implementation requirements

- Track in-flight owned values as well as operand/local roots. Helpers can pop a
  value into a C temporary before a later allocation fails; stack scanning alone
  would miss its required cleanup. Constructor adoption and field extraction must
  transfer ownership without an allocating gap or duplicate release.
- Preserve reverse operand and local order on unwind and depth-first reverse
  schema/index order inside aggregates. Allocation order is not schema order.
  Remaining store entries are a final safety net: reverse acquisition within each
  store, with network teardown before filesystem, matching `resource_runtime`.
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

The normal-cleanup correction does not complete the native resource milestone or
the wider roadmap. Complete Debug and ReleaseFast regression runs pass all 30 build steps and
593 core/CLI tests, including this harness and 468 existing native allocation
failures. Guardian passes all 88 checks.
