# D9 WP-4: admitted flat physical loans

A bounded runtime loan plan reduces the unchanged schematic fixture's retired
instructions by 50.34% on QBE and 54.63% on LLVM. All three schematic inputs retain
their reference SVG hashes and every ownership counter. This is isolated evidence
against the preceding plain-retain source; it is not a combined-corpus acceptance
claim and does not change the default runtime.

## Admission and lifetime proof

The [reviewed plan](d9-rc-flat-loan-plan-2026-09-27.md) is implemented in the native
values bridge. Both the collections agent and parent independently reviewed the
plan and production diff without finding a blocker. The generic shape/transfer
walkers and compiler are unchanged.

The existing bounded native/shape flat walker computes a separate `loanable` flag
only after complete admission. It admits at most eight unconditional ordinary
pointer leaves and eight native inline levels, counting the root. H-shaped values,
variants, raw unique fields, custom descriptor hooks and unsupported metadata
keep the generic path. Every element-bearing kind-5 boxed pointer also refuses,
even if its physical value is null: this preserves the native unique-body check
without depending on registration order. It deliberately refuses some legal
copyable boxes. Every nonnull dynamic payload still checks its own descriptor for
a finalizer, with the existing immortal exception.

The flag occupies the old private plan's padding: `myl_rc_flat` remains 72 bytes,
`count` is at offset 64 and `loanable` at 68; a binding remains 128 bytes. There is
an explicit compile-time size assertion and an archived layout probe. No public
metadata, object prefix, heap field or runtime ABI changes. Bindings live in
immutable batch allocations, separate from the replaceable hash index. The fast
path cannot allocate or invoke a callback before its final drain, and never reads
the binding after that drain; reentrant registration cannot invalidate it.

A registered nonzero disjoint value copies all inline bytes, including padding,
then clears its pointer offsets. It acquires one H token for each source leaf in
shape order and publishes each leaf after successful acquisition. Duplicate
aliases retain separate increments. A later count-limit refusal releases exactly
the acquired prefix, zeros the complete destination and records the same sticky
status. The tests compare prefix acquisition, release and limit counters. No O
count, semantic mark, pin, identity or region changes; arena and immortal values
never receive an RC-prefix access. Cold metadata, zero-size, overlap and deeper
values retain their original behavior, including deep transfer-frame allocation
refusal. Dynamic count limits are not replaced by an optimistic preflight.

The internal H release helper performs the existing decrement/stat/enqueue steps
without callbacks. Public hold release still clears its handle, calls that helper
and drains. Flat unloan clears each leaf and enqueues its death in the authoritative
walk order, then clears the whole value before one final drain. This matches the
generic compound walker's deferred sibling release and LIFO callback order.
Success and rollback both retain the final drain that `dispose_walk` performed.
Queued and reentrant finalizers are therefore preserved, rather than assumed
absent. H-token release and traversal require no allocation; existing callbacks
may allocate.

## Immutable measurement

The isolated source base is `f9bda0dd`, immediately after retain `5237aebc`, with
cumulative `e926d1e1` ancestry. The before Debug compiler is
`d9-rc-mut-argument-astra/.tmp-mut-argument/retain-final/bin/mylang`, SHA-256
`4a3350d56d9ed252df75eb2e8b8309710bd615a96d5b16886c928f3852aeff7a`.
The after Debug compiler is
`d9-rc-mut-argument-astra/.tmp-mut-argument/loan-candidate/bin/mylang`, SHA-256
`b8a8f79c35ce2500f403de5f3eb34c6231ade9aa4ed637b05d0ab25fdefbfc85`.
Both remain immutable. The emitted IL of all 127 schematic functions and the
complete emitted runtime metadata are byte-identical between them.

The benchmark uses the existing schematic guest/provider and unchanged fixture,
changed-net and changed-value project inputs from the required corpus. It retains
the shipped frame-accounting policy (`--max-frames=1024`). Input hashes, exact
commands, explicit MYLANG overrides, native manifests and binary hashes are
archived. No inherited host environment is recorded. LLVM manifests confirm
actual LLVM, optimization 3 and full LTO. CPU 2 measurements alternate before and
after order, taking the median of three samples for the fixture input.

| Backend | Before instructions | After instructions | After/before |
| --- | ---: | ---: | ---: |
| QBE | 1,362,577,063 | 676,621,709 | 0.496575 |
| LLVM | 1,136,662,469 | 515,758,062 | 0.453748 |

Median cycles are 337,213,255 to 152,439,311 on QBE and 293,612,989 to 121,216,136
on LLVM. All raw samples remain in the archive. Each of the 24 standalone rows
(three inputs, two compilers, two backends, production/counting) has the exact
reference SVG and no issue output. Before/after counts match per input/backend.
For the fixture they are 156 allocations/retirements, 169,777 owner acquisitions,
169,933 owner releases, 604,122 hold acquisitions/releases, one clone and 16,776
uniqueness checks. This improvement removes traversal overhead; it eliminates no
physical ownership traffic.

The earlier qualitative profile identified `layout::partPin` as a hot loan caller.
Its static sites include six list-pointer loans and six 128-byte record loans
with two or three managed leaves, which fit this admission. Dynamic payload checks
remain part of the measured cost. The subsequent compiler projection and loop
proof slices are not silently included in this isolated comparison; parent owns
composition and full-corpus measurement.

## Protocol and integration checks

The expanded loan harness has 14 scenarios. Both the candidate and immutable old
core/shapes/values sources pass all 14 under ASan/UBSan with counting enabled; the
old source closure and each file hash are recorded. Decisive new controls cover:

- Padding, duplicated near-limit aliases and exact prefix counters; pinned and
  ownerless values; mixed arena/immortal leaves and unchanged marks.
- Null unique typed boxes, raw unique values and finalized dynamic payloads.
- Dying siblings whose finalizers see all loan bytes zero in the original LIFO
  order, while registering metadata and allocating/releasing another object.
- A prequeued finalizer that mutates the source after observing completed loan
  output, proving the success drain was retained.
- Depth-ten transfer-frame allocation failure, cold registration refusal and
  zero-size output bytes.

The semantic-history harness also passes all 35 cases for old and new sources.
The production contract (22), collections (39), live holds (12), arenas (10),
stats and execution success/trap/fast-exit suites pass with sanitizers. The focused
loan wrapper passes 12 tests. Sixteen paired standalone rows cover both compilers,
both actual backends and GC stress/counting RC, with 58 plain/broad guest
assertions per combination and identical output/counts. Guardian passes its
unchanged 88 checks in the Debug install and explicit whole-tree run; parent
serializes the combined full gate and Guardian feedback. No rule or ratchet changes are included.

## Lox applicability remains a separate question

A read-only audit uses the collections agent's immutable field-transfer-final
Lox ELF and cached VM IL, with their identities retained. `vm::run` has 94 static
native-loan call sites: 50 use ordinary list-pointer descriptors; eight use a
40-byte record with three list-pointer fields. These native layouts are candidates
for the current bounded plan. The other 36 use a 208-byte Runtime record containing
11 list-pointer leaves and an inline variant, so they remain generic. These are
static counts from that named checkpoint, not dynamic weights or a performance
prediction for the current joined compiler. No Lox input, compiler scope or flat
bound was expanded to improve those counts.

Parent's separate full-size `e926d1e1` Lox binary-trees QBE result remains a major
outlier (144.58 times GC). This slice neither explains that entire gap nor claims
to close it. Composition and an updated dynamic profile must determine the next
bounded change.

Reproduction scripts and compressed receipts are in
`experiments/d9-rc-flat-loan-20260927/`. Public APIs, generic fallback, semantic
history and runtime selection remain unchanged.
