# Proposed plain dictionary overwrite specialization

Reviewed proposal, based on `88f4e47728b1ad33058e847009cbaa2be91fd45f`.
The [result report](d9-rc-dictionary-plain-overwrite-2026-09-27.md) records the
implemented ordinary lookup and rejected repeat variant. The before compiler is
`.tmp-rc/install-dict-loop/bin/mylang`, SHA256
`25dad5001d2ddbf91c266ed19f4272849131adaedf70bb113f9c0864c2025625`.
The [loop report](d9-rc-dictionary-loop-2026-09-27.md) and its measured
compiler, native binaries, sources and receipts remain unchanged.

## Target and cost argument

The unchanged two-million-update `dict_count` now retires 979,547,911 QBE
instructions and 644,367,038 LLVM O3/full-LTO instructions, median three.
Those are 1.481235 and 1.461035 times accepted GC. Reaching the 1.3 row limit
requires another 119,851,385 QBE / 71,022,028 LLVM instructions, approximately
12.24% / 11.02%. No whole-corpus or RSS acceptance follows from this proposal.

After the existing compiler proofs, the hot success path retains dictionary
read and write calls. `myl_native_dictionary_write` still finds the entry and
calls `myl_rc_native_retain_replace` for each hit. The source performs 1000
first insertions and 1,999,000 overwrites. The remaining counted totals are
small: 2001 O acquisitions, 2001 H pairs, 1001 uniqueness checks, 2029 balanced
allocations/retirements and zero clones. Further lifetime-count elimination
alone cannot explain the remaining instruction gap.

Read-only disassembly of the exact measured QBE binary shows 40 instructions
inside the successful registered-flat `retain_replace` path, excluding its
descriptor lookup and generic `memmove` callees. Its eight-byte `memmove`
path has 19 instructions; the ordinary descriptor lookup additionally hashes
the type pointer and probes the registry. These are source-conditioned static
paths, not sampled or dynamically traced attribution. The assumptions are a
distinct source/destination, registered flat binding, empty death queue and
valid destination region. Scratch evidence is in `.tmp-rc/dict-residual/`.

The proposed word load/store can remove the generic replacement call's frame,
dispatch and `memmove`, while retaining necessary admission. An initial
static expectation is roughly 30--45 fewer instructions per hit with ordinary
descriptor lookup, or 60--90 million QBE instructions. That alone may miss the
60 instructions/hit needed for the QBE cap. Reusing the existing opt-in repeat
descriptor query may remove another part of the lookup cost; it is a separate
measurement, not an assumed gain. LLVM's required saving is approximately
36 instructions/hit, but its LTO result must be inspected independently.
Prototype disassembly will replace these estimates before full-size timing.

## Exact first admission and fallback

Add one private inline helper in `native_dictionary.c`, called only in the
existing RC `myl_native_dictionary_write` found-entry arm. Keep `find`, its
probe validation, missing-key `rc_insert`, GC writes and every other dictionary
method unchanged. The first slice accepts only an actual native type with
`kind == MYL_NATIVE_PLAIN` and `size == 8`; floats, other widths, aggregates,
domains represented by other native kinds and zero-size values keep the old
path even when their flat plan has no edges.

The helper preserves this order and authority:

1. If the resolved destination address equals the source address, return
   success immediately, just as `retain_replace` does before checking metadata,
   region or pending deaths. The existing caller already reads the dictionary
   region to form the original call argument; this no-op must not introduce a
   new refusal, callback or metadata admission.
2. Confirm the actual value kind and width, and look up that exact type's
   registered descriptor in this heap. The binding's immutable `flat.count`
   must be zero. A `NONE` shape, zero GC scan count, native kind or width alone
   is insufficient: flat admission also excludes raw unique contents, H/O
   edges and all descriptor hooks/finalizers. No shape registration is added.
3. Require an empty `heap->rc->dead.head` on this operation, and the actual
   dictionary header's region no greater than `heap->region_depth`. The RC
   branch already establishes an active RC heap. Do not infer queue state from
   plain values, generated guest callers or `dead.active`, and do not cache it.
4. Copy the complete eight-byte source into a local `uint64_t` with `memcpy`,
   then copy that local into the destination with `memcpy`. This permits
   unaligned addresses and captures overlapping input before any output write.
   There is no intervening allocation, registration, callback or drain.
5. On every failed admission, call the original `myl_rc_native_retain_replace`
   with the original type, addresses and actual region. In particular, cold
   metadata, pending deaths, invalid region and hooked types take the original
   path. Do not synthesize a success or a replacement error/status. The original
   function keeps failure ordering, sticky status and unchanged failure bytes.

This reuses the current valid-dictionary/type/heap preconditions; it does not
make arbitrary C pointers valid. Dictionary construction already calls
`rc_dict_prepare`, registering both key and value metadata before publishing
the dictionary. The defensive cold check nevertheless remains mandatory.
Bindings are immutable and live until heap teardown, so a found binding stays
valid throughout this noncalling span. There is no header-field cache.

## Registry, queue, region and ownership obligations

The first prototype uses ordinary `myl_rc_descriptor_find`. A separately
identified variant may call existing `myl_rc_descriptor_repeat`, already used
by scalar room-append admission. That private helper only remembers identity:
it validates the current table capacity, slot bounds, exact key and descriptor
kind; successful rehash clears its hint. It never remembers successful flat,
queue, kind, width or region admission. Failed lookup is not cached. Every
operation repeats the checks above after lookup. A prior global-repeat change
regressed schematic workloads, so this new opt-in client needs its own evidence
and a mixed-client control; unrelated lookups stay unchanged.

The ordinary replacement's pending-death path first stages source bytes, then
may drain a finalizer before publication. Such a callback can observe the old
destination or change the original source. The fast path must refuse whenever
`dead.head` is non-null, including reentrant finalizer execution with an active
outer drain. It cannot replace this condition with a compiler assumption.
The fallback keeps staged-source and callback ordering. Existing same-address
success remains a no-op even with a pending death.

The destination region comes from the dictionary header, not the current
region or source address. Older heap dictionaries remain writable inside a
younger arena; valid inherited-arena dictionaries also remain valid. Invalid
regions fall back and retain `MYL_RC_REGION_ERROR` plus failure atomicity.
The hit cannot grow or compact backing. Source bytes may therefore come from
the same dictionary backing, a different entry, or a partially overlapping
valid range, provided the caller's existing lifetime preconditions hold.

There is no O/H/LOAN acquisition, release, semantic SHARE or unique-resource
operation in the admitted value. The dictionary header, keys, backing owners,
pins, journals and first compiler uniqueness check are unchanged. Existing C
callers retain responsibility for their mutation authority; this helper does
not impose or relax a new header-owner-count policy. Insertion still performs
its original key ownership, region/count/growth checks and publication/drain
contract. No generation, probe, index or length update is added on an overwrite.

No public signature, runtime version, descriptor layout, dictionary layout,
metadata reservation or allocation class changes. The repeat variant only
adds another client to the existing private identity hint. The generic
`native_rc_values.c` replacement implementation stays intact.

## Validation before retention

Extend the native collection/dictionary C scenarios and their existing Zig
wrapper. The specific checks are:

- Warm registered eight-byte integer hits and unchanged missing-key insertion;
  exact source/destination bits, length, key order and probe behavior. Counted
  allocation and token totals must match the immutable before runtime.
- Source equal to destination, unaligned source, partial overlap in both
  directions, and sources in another entry or existing dictionary backing.
  Capture the expected source bytes before the call. Preserve no-op success
  before region/queue refusal, including explicit C fault-injection controls.
- Heap dictionary writes from an inner arena and inherited-arena dictionary
  writes. A controlled invalid-region fixture must preserve the original
  destination, source, failure code and same-address exception; restore the
  injected runtime state before teardown.
- Queue a real finalizer that observes old destination bytes and changes the
  original source. Replacement must publish the staged pre-callback value.
  Reentrant guest/dictionary work, queued siblings and registration/table
  growth in the callback retain their existing order. Subsequent warm hits
  must revalidate the current table and queue state.
- Actual pointer/H/raw-unique types, hooked or finalized plain descriptors,
  non-eight-byte scalars and plain aggregates must retain fallback behavior.
  Reuse existing unique-refusal and H replacement scenarios instead of treating
  `NONE` as evidence of a copyable scalar.
- Cold repeat lookup must return no binding. Constructor registration-budget
  refusal must retain its original failure; a successful ordinary constructor
  must establish the value binding. A cold value binding cannot occur in a
  valid constructed dictionary, so do not fabricate an unregistered heap
  object to claim such coverage. Existing generic cold `retain_replace`
  registration/failure tests cover the unchanged fallback target.
- Repeat-hint controls cover mixed types, rehash, collision/slot validation,
  failed registration and interaction with scalar room-append admission. The
  hint must never let a formerly empty queue or valid region bypass a new check.

Run focused C ASan/UBSan scenarios, the corresponding Debug Zig wrapper,
Guardian, formatting and relevant actual QBE/LLVM dictionary guests. Use narrow
existing bounds/step/arena/growth controls where this runtime boundary changes;
do not repeat the known unrelated GC timeout or a full corpus. Inspect native
code before timing to establish the admitted word path and unchanged fallback.

After review, compare the ordinary-lookup prototype and repeat-query variant
with immutable `88f4e477` on the unchanged two-million-update workload. Use
CPU11 only after coordination, median-three instructions, actual LLVM
O3/full-LTO and separate counted builds. Preserve raw perf, output, source,
compiler, manifest and native hashes, plus rejected variants. A small mixed
append/dictionary workload can identify shared-hint interference before any
wider measurement. Report each variant against both before and accepted GC,
including its remaining distance from 1.3; do not infer success from estimates.

Production ownership is confined to `native_dictionary.c`; only the optional
repeat-client comment needs coordination in `native_rc_shapes.c`. Tests,
the wrapper count, a SPEC contract and the final evidence/report accompany the
implemented slice. Runtime peer review found no ownership blocker under these
exact per-operation checks. Parent review precedes any prototype.
