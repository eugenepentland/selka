# Stage 4 repeated descriptor lookup plan

Status: design for review, before implementation. The measured scalar append
profile is archived at `3b4bd2b8`; its throttled samples are qualitative. The
hardware medians in the preceding append report remain authoritative. No
acceptance threshold, guest input, or public ABI changes are proposed.

## Cause and alternatives

`myl_rc_list_plain_ready` repeats `myl_rc_descriptor_find` for the same scalar
native type on every room append. Native loan/retain wrappers also use that
lookup. The registry already has a heap-local, half-full open-addressed index;
lookup hashes the pointer and probes it even when the preceding lookup used the
same type. Bindings and their flat plans are immutable batch allocations until
heap destruction. Registration can replace the index, but cannot replace an
existing binding or retire one independently.

| Option | Benefit | Cost or proof concern |
| --- | --- | --- |
| Existing lookup | Already bounded average lookup | Repeats hash/probe on every identical type |
| Cache append admission or attach it to each list | Saves more query work | Must still test the current dead queue; changes header or requires a separate side table; does not help other bridges |
| Last binding pointer in heap state | Simple repeat hit | Adds accounted heap bytes and changes exact budget-refusal boundaries |
| Last successful slot index in existing private padding | Skips hash/probe on repeats; helps all descriptor clients | Must validate key/kind and explicitly invalidate on index replacement |
| Several entries or a new small direct-mapped table | Helps alternating types | More state and policy; lacks evidence that it beats the one-entry candidate |

The first experiment should use the fourth option, isolated from other changes.
It caches identity resolution only. It does not cache the result of append
admission, queue emptiness, raw unique detection, region checks, terminal
finalizer checks, or dynamic O/H count limits.

## Representation and lifetime proof

The private amd64 index entry is currently 40 bytes: two pointers, two sizes,
and a four-byte kind followed by four bytes of padding. Name that final word
`recent_descriptor`, with compile-time checks that its offset is 36 and the
entry remains 40 bytes. Only `entries[0].recent_descriptor` has meaning. It
stores one plus a successful descriptor slot index; zero means no cache. A
slot that cannot fit this encoding simply uses the normal lookup. The state,
all allocation sizes, the half-load bound, and every public layout remain
unchanged. This is private serial runtime state, not emitted metadata.

On lookup, first validate heap/RC/type/table as today. If a cached slot exists,
require the encoded index to be within the current capacity, then read that
entry and require both the exact native-type key
and descriptor kind. Return its value only after those checks. Otherwise run
the existing authoritative lookup. Cache only a successful descriptor result;
never cache a miss or a prospective registration.

Index growth copies only authoritative entry data and clears all copied cache
words; the newly committed table starts with no cached slot. Failed growth
leaves the old table and its valid cached identity intact. Insertion without
growth cannot move existing entries. A successful registration therefore needs
no correctness invalidation unless it replaces the table. Inserting a new key
into slot zero may reset its cache word to zero; that only loses a future hit.
Shape/module lookups do not
consume or overwrite this cache.

A finalizer or allocator callback may register metadata reentrantly. Growth
invalidates the cache before the next descriptor lookup; existing returned
binding pointers remain stable. No cached pointer refers to the freed index.
Teardown frees the table along with its cache; reinitializing the same heap
address gets zeroed fresh state and cannot reuse another heap's identity.
A source-wide search of `myl_rc_index_entry` and `metadata.index` found no raw
entry equality, hashing, serialization or outside consumers of these padding
bytes. Rehash currently copies whole structs; explicitly clearing the copied
word is the only required adjustment to that data movement. The kind remains
at offset 32 and keys/values/depths retain their offsets.

There is no process-global or thread-local cache. Destruction still drains
before metadata is freed. No callback or fallible action is introduced by a
cache hit or miss.

## Required controls

- Zero/unallocated tables and repeated misses remain harmless. Include a real
  descriptor at slot zero, collision chains, a stale shape-kind cache hint, and
  a maximum-width out-of-range hint. Encoding uses `slot < UINT32_MAX` before
  addition, so very large indexes remain generic without truncation/overflow.
- Same-type repeats, alternating distinct types, unknown/null keys, and shape
  lookup interleaving return the exact registered binding; lookup changes no
  byte charge, failure status, owner/hold counter, or callback count.
- Register enough descriptors to force repeated index growth after warming a
  cached entry; all previously returned binding addresses stay valid. Force
  growth refusal at an exact budget, assert unchanged bytes and missing new
  binding, then retry successfully. Exercise idempotent module registration.
- Destroy and initialize the same heap object, and use two simultaneous heaps
  with the same native type but different valid descriptors. No identity can
  leak across heaps or initialization lifetimes.
- Warm scalar append readiness, then queue a finalizer that observes the old
  length and changes an aliased scalar input. The existing per-operation dead
  check must still refuse the direct append, allowing the generic path to
  retain its ordering. Cold registration failure and finalized/unique native
  metadata remain refused by the existing readiness query.
- Existing physical retain and loan tests cover duplicate aliases near dynamic
  limits, ownerless held values, younger-region refusal, NULL typed unique
  boxes, opaque finalized payloads, whole-output zeroing and reentrant sticky
  failure precedence. Re-run them against old/new registry implementations.
- Reentrant finalizers register enough metadata to grow the table, then repeat
  old/new lookups and release queued siblings. Preserve callback order and
  allocation-free release metadata requirements.

## Measurement decision

Use an immutable joined baseline containing scalar room append and flat
retain. Build a Debug compiler after this isolated registry change; compare
actual QBE and LLVM O3/full-LTO guests on CPU 2. Run unchanged scalar append,
sieve, allocation churn, and the three exact schematic inputs with interleaved
median-three instruction counts and separate complete ownership counters.
Preserve all samples, exact binaries, source hashes, outputs, and failures.
A narrow helper improvement is kept only if measured benefit is material and
common alternating-type workloads do not regress enough to erase it. No full
corpus or acceptance claim is needed for this experiment; root owns the joined
gate and eventual complete acceptance measurements.
