# Raw emission for certified borrowed entries

Status: proposal, based on joined source `c07016f3` (tree `83386525` adds only
evidence). No production changes or performance claim yet.

## Evidence and target

The joined schematic fixture measures 226,310,431 QBE instructions and
159,638,419 LLVM instructions: 12.170259× and 17.622799× accepted GC.
Its managed-helper callers now use raw readonly emission, but their borrowed
callees can still build an empty ownership frame.

Actual current emission of `sexpr::at_rc_borrow` has zero native loans and zero
slot-drop calls, yet reserves 224 bytes of entries and 56 bytes of guards,
initializes its ownership metadata, links/unlinks a frame, and has three frame
cleanup sites. `sexpr::form` is raw and calls this alternate. The canonical
`sexpr::at` body still has two loan sites, four slot-drop sites and an owned
result contract. This proposal concerns only the already-certified alternate.

Root's residual sampling is qualitative: all 11 QBE and 9 LLVM samples were
throttled. It cannot establish cost percentages. Symbolized relinks have
byte-identical allocated ELF sections at identical addresses to the measured
executables. They identify actual ownership/runtime paths, including canonical
frame cleanup; generated IL separately establishes the empty alternate's
protocol. Scratch receipts are under the performance tree's
`.tmp-rc-performance/schematic-residual-c070/` and will be archived if this
investigation becomes a production slice.

## Two independent certificates

Do not infer a borrowed ABI from provenance or a readonly grammar. The outer
entry must already have the exact public standalone `rc_calls.borrowedIn`
certificate for its function, parameter anchor, result layout, ABI and complete
dependency identity. Canonical managed-return entries keep their owned ABI,
including exports, function values and ordinary fallback calls.

Add a separate optional readonly-composition query for this certified entry.
Its only wider grammar rule is that this root may return counted, nonunique
bits under that existing public certificate. Keep the current local/type
authority restrictions, no parameter writes, no allocation, mutation, arenas,
callbacks, unique resources or opaque effects. Ordinary plain dependencies
still use the original plain-result admission. Managed callees still require
independent public standalone proofs and exact saved PC/target routes.
Reject managed-root self recursion or dependency cycles initially.

The raw-entry result records its entry boundary separately from ordinary
readonly certificates. Validate the supplied public proof against a fresh
standalone query, including parameter, shape and dependency identities, before
granting the exception. This adds one bounded root query; the existing sixteen
managed-dependency queries and plain graph limits remain unchanged. Do not
borrow internal traversal Answers or enlarge query budgets to force admission.

Run the same actual native IR, layout pinning, liveness, ownership and COW
preflight before accepting every plain body. The root must pass it too.
Unknown conservative captures/shares/place plans decline raw admission before
emission; they retain today's journaled borrowed alternate. Preserve the
existing per-function and shared input-volume bounds and final invariant check.

## Lowering and identity

In the existing `emit(..., certificate)` branch, retain the borrowed result
contract. Query the optional raw certificate before COW refinement selection.
Only a complete result sets `state.readonly = true` and `state.active = false`,
using the same activation/verification path as current raw plain callers.
It therefore omits ownership frame allocation, initialization and linkage,
while retaining logical/native frame and step checks, trap source mapping,
ordinary aggregate value storage, exact result copying and stack admission.

The raw call route is already resolved before `frame.get`; preserve that
ordering. A managed call inside the raw entry must match its saved route.
Missing or inconsistent routes are invariant failures, not owned-call fallback.
All optional proof refusal happens before selecting raw emission.

Update versioned RC cache identity to include both ordinary readonly proof and
optional borrowed-entry proof/refusal, with an explicit boundary discriminator
and the complete supplied public certificate. Source/dependency edits that lose
either certificate must invalidate warm caller and callee artifacts. Keep GC's
identity and generated behavior unchanged.

## Review and controls

First confirm current `sexpr::at` actually passes the new combined proof and
its alternate loses only the ownership protocol. A syntactic return exception
without physical quietness is insufficient. Canonical `at` must retain owned
publication, and the plain `form` caller must retain its explicit borrowed call.

Structural tests cover absent/mismatched public proof, root-only exception,
recursive/cyclic refusal, ordinary dependency refusal, physical SHARE refusal,
managed route loss and bounded-query exhaustion. Check exact aggregate result
copying for small and greater-than-4096-byte results before `%aux` reuse.

Actual QBE and LLVM controls compare before/after output and complete ownership
counters, saved results across repeated calls, multiple original anchors,
caller arenas, empty reads, scalar and managed helper composition, and warm/cold
certificate loss. Preserve bounds, overflow, step and logical-frame traps and
test physical stack admission without assuming an optimized frame has the same
size. Include real queued-finalizer reentry to confirm the omitted empty frame
does not change existing cleanup/drain boundaries. Keep the known unrelated
combined-wrapper LLVM frame-map build failure explicitly classified if reached.

After review and controls, use frozen Debug compilers and unchanged schematic
workloads on CPU2 for interleaved median-three measurements, exact SVGs, actual
QBE/LLVM O3 full-LTO manifests and separate counted runs. Only the complete
unchanged 43-program corpus can establish final Stage 4 acceptance.
