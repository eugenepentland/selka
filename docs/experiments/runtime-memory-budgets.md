# Runtime byte budgets and allocator attenuation

The byte runner accepts `--max-runtime-bytes=N`, `--max-vm-bytes=N`,
`--max-host-bytes=N`, and `--memory-report`. Limits count live requested bytes
routed through the supplied allocator interfaces. VM and host children both
charge the shared total; setting a child above the total cannot grant more bytes.
Zero permits no nonempty allocation. Quota exhaustion returns host OutOfMemory
with normal cleanup and suppresses unpublished stdout.

The report is one stderr JSON line (`runtime-memory-v1`) emitted after cleanup,
including each category's limit, remaining live bytes and high-water bytes.
VM includes runtime stacks, references, values, registries and retained arena
chunks. Host includes buffered output and allocations made by the scoped
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
release accounting, actual CLI execution, and zero-budget cleanup. This first
stage does not add source-level child allocator expressions or split VM
bookkeeping from retained arena chunk statistics; those remain explicit follow-up
parts of F18, not promises implied by these category names.
