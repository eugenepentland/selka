# Native owned buffers
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

The C backend accepts root allocator parameters and owned buffers of supported
value types. Acquisition, ownership transfer, wrapped results, partial cleanup,
length/capacity queries, reads, writes, append, resize, reserve, and checked
borrowed slices use native storage. No VM decoder is involved.

Buffer capacity and total reserved capacity use the VM guest-value size when
checking limits. Invalid acquisition/growth requests return typed errors; host
allocation failure exits with OutOfMemory. Buffer reads and slices retain source
bounds diagnostics. Aggregate elements preserve value snapshots, while exclusive
buffer slices update their unique owner directly. Reserve transfers initialized
elements without duplicating ownership; shrinking and scope exit release them.

Validation: compiler emission tests pass, the existing buffer examples
pass VM/native parity, and memory acceptance passes 322 injected allocation
failures under address/undefined sanitizers at -O0/-O2. The memory suite also
covers aggregate elements, reserve, resize, returned slices, and VM-matched
step/frame limits. Debug and ReleaseFast pass all 28 build steps (529 cached core
tests after fresh successful runs, plus 60 CLI tests), including 2,538 VM/native comparisons across 71 single-file and 14 module
fixtures. Formatting and the strict Guardian gate pass without frozen violations.

[Native lexical arenas](native-arenas.md) now add chunk backing, reset, and
allocator lifetimes. [Native pools](native-pools.md) are also supported. [Clock/random providers](native-providers.md) are also supported. Native environment
and external-resource operations remain pending. Root allocator support does not imply support for those types.
