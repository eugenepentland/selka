# Borrowed dictionary item destructuring

Two-name direct `for key, value in mapping.items()` now initializes each binding
from the corresponding borrowed dictionary projection. It no longer constructs
an owning temporary record that incorrectly tries to consume the borrowed key or
value. Existing per-iteration loans remain active; materialized item lists keep
their existing destructuring path. Single-item `for item in mapping.items()` is
separate A07 work.

The focused regression passed 2/2 and executes its positive managed fixture in
release, unoptimized, verified release, optimized debug and release without facts.
Every native run prints `passed 38`, reports zero RC events and zero managed live
bytes at exit, exercises direct destruction, and passes emitted-LLVM and linked
symbol audits. Cases include borrowed parameters, early return of explicit field
copies, comprehension copies, discarded binders, empty iteration and retained
outputs after source clearing. Six negative cases reject borrowed escape, storing
a borrowed managed value, clearing or replacing an entry during iteration, and
mutating the read-only projected value.

An initial negative expected whole-root rebinding to refuse. That expectation was
incorrect: existing `D1-LIVE-PLACE` and `NEW-CORE-IR-3` explicitly select an
independent entry snapshot when the body syntactically rebinds the root. The
coordinator directed preserving this source rule. The final positive creates two
dynamic old keys and managed rows, rebinds the source before each field read, and
verifies both old entries remain valid and retained copies survive clearing the
new root. Its allocation is semantic snapshot copying, not an RC fallback or a
claimed saving. `rebind.my` and `checks.json` preserve the original observation;
the two failed development rounds remain archived.

`dictionary_views.zig` is an exact coordinator-authorized validation prerequisite
from integrated commit `4fc3f95173609c4f7763f2a64f3b5295ca5076b9`; it is excluded
from this feature commit. `dependency.json` records its hash. The Core test root
registration was applied by the coordinator. `results.json` identifies the source
state, compiler/test hashes, command and limits. All builds used shared admission.
This is intermediate worker evidence and must be consumed by a fresh integrated
compiler; it does not qualify final default behavior or installed components.

A07 approved the exact projection restriction and preserved materialized-pair path.
Guardian passed all 88 checks after narrow helper extraction and explicit allocator
threading; final focused/native rerun also passed. Earlier Guardian findings and
successful development reruns remain recorded without being called new metrics.
