# Stage 4 registered native type facts: bounded cache design

This design was approved by root and independently reviewed by the collections
agent, then implemented and measured as an isolated optimization. It is not
Stage 4 performance acceptance. It follows the corrected joined source
`5b87601297f01810968b9f7ac554c484d5848cca` and immutable Debug compiler
`f87393b249f45699d63a1f5a81dc47fb59faa41d1396fc8035131d7b2533b120`.
The benchmark remains the complete unchanged Lox binary-trees script.

## Evidence and scope

The preceding scalar-record publication change removed all 36 broad Runtime
loans in `vm::run`. Its remaining 58 native-loan call sites already admit to the
flat path: 26 list-of-Value pointers, 22 list-of-CallFrame pointers, two list-of-int
pointers and eight 40-byte ExecFrame values containing three list pointers.
They do not explain generic native-type walking through unsupported variants.

A fresh qualitative QBE profile of the joined compiler instead attributes about
11.4% of sampled instruction weight to `myl_rc_native_has_unique`. Hardware
branch records identify its direct callers as native loan (about 8.4% of whole
sample weight), physical retain (about 2.2%) and semantic publish (about 0.1%).
Recent guest CALL records include `heap::string_obj`, `heap::set_object_field`,
`vm::load_frame`, `heap::set_instance_field` and property helpers. Disassembly
confirms the hot string-object loan passes a 56-byte object-variant descriptor.
These branch records are observations, not a reconstructed complete call stack.

The profile contains throttle records and no lost samples; its percentages are
directional. Separate unsampled hardware medians and counted executions remain
the measurement basis. The attempted DWARF profile did not unwind guest/runtime
frames and provides no caller evidence. Exact receipts are archived with the implementation report, including the
historical `6a75eb2a` profile separately from this corrected joined source.

Generic shape seed/visit/cleanup remain substantial costs. This proposal does
not flatten variants or widen the existing flat plan. It targets the independent,
repeated native-type predicate first, with a smaller proof surface.

## Fact and lifetime proof

`myl_rc_native_has_unique` reads native kinds and inline record/variant/array
metadata. It does not inspect a value or follow a managed payload. Raw resource,
owned-buffer and owned-pool kinds answer true. A typed-box pointer consults the
registered body descriptor's `finalize` hook even when the actual pointer is
null. All native variant arms participate, independent of the active tag.

The public registration contract in `native_rc.h` requires immutable native type
identities through heap teardown. Bindings are copied into heap-owned batches,
never relocated by index growth, and their descriptor callbacks cannot change
under idempotent registration. Thus a completed predicate is stable for the
remaining lifetime of that heap's binding. The descriptor prefix and structural
metadata are immutable; the complete private binding is not, because this serial
heap-local cache byte is lazily updated. Two heaps may bind the same type to
different body finalizers, so the cache must be heap-local.

Use three states: unknown, no unique content, has unique content. Publish the
fact only after the existing walk returns its result. Do not infer a negative
fact during registration: a typed-box body may be registered later. An absent
required body binding must still fail the existing invariant and cannot publish
a negative fact. Unregistered root types keep the existing uncached validator.
The first validation retains the same iterative reserved-stack walk, including
deep nesting and all existing metadata checks; no type-depth cutoff is added.

## Private layout and call boundary

`myl_rc_flat.loanable` currently occupies an unsigned word but only holds zero or
one. Narrow that private field to an unsigned byte and use a second byte for the
tri-state native-type fact. Keep `count` unchanged. Assert size 72 for the flat
plan, size 128 for its binding, and existing count/loanable offsets 64/68; the new
fact occupies offset 69. Every registration initializes it to unknown. This
preserves allocation sizes, metadata reservations and byte-budget refusal points.
Audit whole-struct copies and all loanable writers/readers; no public or emitted
metadata layout changes, hashes, serialization or ABI version changes are needed.

Add a private checked binding helper. Generic native loan and physical retain
already have the heap's descriptor binding, so pass that binding and avoid a
second index lookup. On unknown, run the exact existing predicate, then publish
its result. Leave the original native-type validator available for unregistered
and direct diagnostic callers. Semantic publication can remain on its existing
predicate initially; its measured share is small and it does not already expose
a binding at this point. This deliberately avoids a new global lookup tax.

Every entry still checks the valid heap and idle walker invariant. Cache hits
do not skip actual-payload validation in `loan_pointer`/`flat_loan`, count-limit
checks, H acquisition, O acquisition, region checks, pin handling, seed/visit,
rollback, whole-value clearing, queued-sibling release or final drain. The fact
does not say that arbitrary payloads of an opaque pointer type lack a finalizer.
In particular, an opaque pointer's cached false result must not legalize loaning
a dynamically finalized payload. Physical retain still permits that payload.

The predicate itself cannot allocate, register, drain or invoke callbacks.
Cached metadata cannot become stale within its evaluation. Registration from a
later finalizer can replace the index, but the containing binding and cached fact
remain alive until heap destruction. Failed transactional growth cannot change
an existing fact or its binding. No pointer or fact survives heap teardown.

## Required controls before retention

- Generic record/variant/array positives, including different active arms and
  nesting beyond eight frames, must match the uncached validator on cold and warm
  calls. The cached answer is independent of the active value.
- Raw unique content in inactive variant arms and nested arrays/records remains
  true. A null typed box with a finalized body remains true. Register a root
  before its finalized body, then query after body registration, to catch eager
  false caching. Missing-body admission keeps its invariant failure.
- Warm an opaque pointer's false type fact, then attempt a loan of an actual
  finalized payload: its dynamic refusal must remain. Ordinary physical retain
  of that same payload remains legal.
- Two heaps with identical native-type addresses but different body finalizers
  must yield independent facts. Destroy/reinitialize a heap and repeat. Exercise
  successful and refused index growth after warming, and reentrant registration
  and queries from a finalizer.
- Retain exact cold/warm duplicate-edge H/O near-limit prefix traffic, late
  failure bytes/status, ownerless H lifetime, arena refusal, pinned identity and
  queued-finalizer sibling visibility. Existing loan/history/contract/arena/hold
  production suites remain authoritative; compare old and new paths.
- Verify metadata sizes/offsets/charged bytes in ordinary and counting builds.
  Actual QBE and LLVM O3/full-LTO whole Lox output, ownership counters and median
  three instructions must be preserved/improved. Include schematic and the
  previously sensitive append/alloc/sieve controls before claiming a retained
  general runtime improvement. Preserve negative or neutral experiment results.

Root and peer review approved this boundary before implementation, then reviewed
the concrete production diff without a blocker. Validation and measurements are
recorded in [the implementation report](d9-rc-native-type-facts-2026-09-27.md).

## Independent snapshot-correction review

The reviewed correction, now `2631a44fe7d2c655277a9611cb9540d2deed8107`, changes
only `Context.writeDescends`. No blocker was found. It first follows ordinary
alias roles, then follows only compiler temporaries with a single known origin.
Named owned homes and fresh origins stop; unknown, multiple, missing and cyclic
facts conservatively report a possible write. A named borrowed alias still
follows its parent, so the independent-home boundary is tied to actual ownership.

Existing through-path exceptions use the narrower alias-only `descends` and
`feedsPath` predicates. Adding temporary ancestry therefore does not newly
exempt unrelated writes. Analysis continues to rely on its established invariant
that stored local IDs/alias parents identify valid analyzed locals. Tests cover
heap and arena snapshots, nested mutable arguments, named independent copies,
list/dictionary paths, loop reuse and synthetic uncertain origins. This review
neither edits their worktree nor changes the accepted historical GC evidence.
