# Prepared A02 runtime retirement — not applied

This patch is a Stage 4 preparation artifact, not a completed retirement or qualified compiler. Apply only after coordinator C2 approval and coupled owner patches.

`prepare.py` reads the production runtime, selects the proven owned branches in `core_rt.c` and `core_bytes.c`, and writes an exact patch plus before/after hashes. Production files are untouched. `git apply --check runtime-retirement.patch` passes against the recorded worker base, which includes both capacity overflow fixes.

The patch makes the existing owned block header unconditional: kind at offset 0, then the existing aligned i64 length, capacity and layout words, total 32 bytes. It removes the count member, count loads/updates, retain/release/share implementations, RC static-header selection, and COW buffer selection. It preserves direct destruction, static-storage kind bits, guarded child traversal, native allocator/counters, memory budgets, and task synchronization. Existing poison declarations prevent accidental reintroduction of legacy helpers; those names are structural prohibitions, not callable implementations.

`core_child_visitor`, `core_dict_children`, and the generated layout callback helper `layout_release` remain. Dictionary key/value callbacks use the latter for direct destruction despite its historical name; it is not a memory reference count. Descriptor reference counts specify the number of child pointers in a layout, and live-block counters measure leaks. Neither controls shared memory ownership.

Coupled changes:

- A05's paired dictionary/sort/provider runtime preview must be applied together. A02 introduces no header fields or new ABI.
- A07 must select owned emission, layout, deep-copy and cleanup paths. The unchanged direct dictionary callbacks and child traversal remain required.
- A09/coordinator must remove five obsolete `count_runtime.zig` patches anchored at `count_retain`, `count_release`, `myl_core_retain_slow`, `count_release_shared`, and `child->count = count | MYL_SHARED`. Allocation, copy, reallocation, free and peak instrumentation must remain.
- A10 selects the sole runtime and removes retired flags. A08 invalidates old artifacts. Installed components and immutable bootstrap history remain separately qualified boundaries.
- The registered A02 capacity test currently runs the two supported ABI selectors. Stage 4 must keep its 13 boundary scenarios on the sole owned ABI and remove the redundant RC control invocation. Historical evidence stays unchanged.

The native preview combines these two candidates with A05's prepared runtime files and other current runtime sources, defining `MYL_ZERO_RC` for not-yet-retired peer files. All 13 capacity scenarios pass and linked legacy RC symbols are absent. Exact hashes and outputs are in `native-preview.json`. This proves only the scratch native combination; it does not qualify final generated guests, compiled ownership checks, installed artifacts, or the complete test gate.
