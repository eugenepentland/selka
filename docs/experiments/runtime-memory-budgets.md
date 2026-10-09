# Runtime byte budgets and allocator attenuation

The byte runner accepts `--max-runtime-bytes=N`, `--max-vm-bytes=N`,
`--max-host-bytes=N`, and `--memory-report`. Limits count live requested bytes
routed through the supplied allocator interfaces. VM and host children both
charge the shared total; setting a child above the total cannot grant more bytes.
Zero permits no nonempty allocation. Quota exhaustion returns host OutOfMemory
with normal cleanup and suppresses unpublished stdout.

The report is one stderr JSON line (`runtime-memory-v1`) emitted after cleanup,
including each category's limit, remaining live bytes and high-water bytes.
VM is the shared parent of two reported categories. `guest_backing` counts
reserved buffer/pool storage and retained arena chunks; `bookkeeping_and_snapshots`
counts stacks, references, immutable values/snapshots, registries and region metadata.
Their live bytes add to the VM total. Their individual peaks need not occur together,
so adding peaks is not the VM high-water mark. `logical_slots` independently reports
live and peak buffer capacity/pool slots, never interpreted as byte counts.
Releasing arena owners reduces logical capacity while chunks may remain until reset
or scope exit. Snapshots retain their own separately accounted value storage. Host includes buffered output and allocations made by the scoped
providers through their supplied allocator. Totals exclude source compilation,
input storage, allocator metadata, kernel memory and provider work that bypasses
the supplied allocator. This is not a whole-process RSS cap. `noalloc` retains its
existing guest-backing meaning.

Embedding code can use `language.allocation_budget.Memory` and
`parent.child(limit)`. Keep both accounting objects at stable addresses until
all child allocations are freed through that child. Child quotas are independently
attenuated, and nested allocations cannot evade any ancestor limit. Ordinary
allocation failures do not charge live bytes; failed realloc keeps its original
allocation. A moving realloc may need old and new capacity simultaneously and
can therefore fail below its final-size limit. Peak statistics retain that cost.
The allocator is single-threaded and is not a transferable guest capability.

Tests verify nested quotas, simultaneous sibling pressure, failed growth,
release accounting, actual CLI execution, and zero-budget cleanup. Source-level child allocator expressions are not added. Embedders may additionally
set `vm.Options.memory.backing_allocator` to an attenuated child allocator; root and
nested region chunks use it while metadata and snapshots use the execution allocator.
The backing allocator must outlive execution and all backing users. Tests cover
retained chunks after owner release, reset, nested regions, failed acquisition and
logical high-water accounting.
