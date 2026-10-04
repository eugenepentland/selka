# Dictionary follow-up triage

This is read-only triage of G4 source `6cf7bdce`, not a measured bottleneck or
an implemented candidate. `evidence.json` binds the current LLVM collections
guest and four read-only disassemblies. The frozen ports are unchanged.

`read_walk` is 695 bytes and retains dispatch on runtime key kind, a dynamic
entry stride in the word-key probe, then another stride multiplication and
dynamic value offset/width on a hit. In this ELF, the probe's stride multiply
is at `0x105d943`; the value copy loads its type's size at `0x105d898` onward
and branches on eight bytes before falling back to `memmove`. LLVM full LTO
has not specialized these shared out-of-line helpers for `dict[int, int]`.
The public `myl_native_dictionary_read` is another 670 bytes. This establishes
remaining generic work, not the fraction of runtime it consumes.

The first candidate should investigate known-key/value read helpers while
sharing the existing cache and probe implementation. The compiler knows the
dictionary's key/value descriptors. A typed helper could remove key-kind and
copy-width dispatch and make constant layout arithmetic available to LLVM.
GC and RC entry layouts differ because RC has an extra marker word, so a
hardcoded stride is insufficient. Keep a correct no-index scan fallback and
all cache invalidation, equality, deletion and insertion-order behavior.
Measure the actual guest loop as well as isolated probing; ownership or
checked key arithmetic may dominate the frozen benchmark.

A smaller independent candidate is to avoid zeroing unused probe-cache fields
on every successful lookup. `locate` assigns the full 56-byte probe structure
although `PROBE_FOUND` readers use only state/key/entry. In this ELF it clears
slot/hash and span fields at `0x105d863` and `0x105d878` onward. Every reader
must be audited by state before changing this: ordinary absent entries use
slot/hash, span queries also need offset/bytes, and absent spans need the GC
epoch. Keep this separate from typed lookup so timing can attribute gains.

Use the existing dictionary sanitizer suites and paired GC/RC checks for
integer/text hits and misses, equal distinct texts, views, narrow/wide keys,
collisions, delete/settle/grow histories, clone/alias mutation, memory refusal
and transitions between ordinary and span-query cache states. A six-arm
screen should cover both lookup cases and sizes, with update/set and
high-cardinality application holdouts as controls. Implementation is queued
behind the active arithmetic and mutation work.
