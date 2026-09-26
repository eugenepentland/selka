# Cumulative ABI3 flat destruction and next runtime work

This audit joins frozen integration `19e16e1d` into the isolated flat worktree
with real merge `e7058d4b`. Production source is unchanged. The root's immutable
Debug compiler SHA-256 is
`1b705d90e58c6b2b3799c5cbe79da9adbc57913e4c72ebbfa2b54dad044c1bbe`.
The shared diagnostic binaries and manifests are under that worktree's
`.tmp-flat/cumulative-19e`; evidence is archived in
`experiments/d9-rc-flat-abi3-20260926`.

## Ownership compatibility

Flat admission checks the authoritative native type and ownership shape together.
An ordinary native pointer whose shape is HOLD_POINTER is refused. Variants,
raw unique resources and every custom descriptor hook are also refused. Thus
flat object destruction releases physical O children, even when an outer H loan
was the final token keeping that object alive.

`myl_rc_native_unloan` does not use native flat drop. It invokes the iterative
WALK_UNLOAN action, which releases H for every managed leaf. Last-H death then
uses ordinary object destruction; the object's stored children retain their own
O/H shape. Semantic SHARED affects uniqueness, not death: O=H=0 still controls
queue admission. Arena and immortal checks precede every RC-prefix access.

Two new production cases exercise those boundaries. A whole-box loan keeps a
flat body alive at O=0/H=1 without releasing its two aliased, semantically shared
dictionary children. Ending that loan drains their O tokens, while a separate
view H preserves the dictionary and its value. A mixed O/H body is explicitly
refused by flat admission and cleans up correctly when its outer loan dies.

ASan/UBSan pass loan 9, history 27, held-view 12, arena 10, contract 21 and
collection 32 cases, plus stats/execution harnesses. The focused Zig wrapper
passes 12/12. The initial new fixture incorrectly asked the plain/pointer-only
shape convenience API to register an aggregate and aborted. Registering the
explicit record descriptor corrected the fixture; both failing receipts remain
archived. No production fix was needed.

## Cumulative structural profile

Three interleaved runs on CPU 3 use exact n12 source, preserve every output byte,
and verify native manifests. The accepted GC executables remain immutable.

| Backend | RC instructions | Accepted GC | RC / GC | RC / GC peak RSS KiB |
| --- | ---: | ---: | ---: | ---: |
| QBE | 599,763,338 | 105,803,367 | 5.668660 | 3,420 / 6,944 |
| LLVM O3/full LTO | 329,481,929 | 50,532,284 | 6.520226 | 3,584 / 6,960 |

RSS is one diagnostic run per arm, not a corpus result. Both counting binaries
have 669,060 heap allocations/retirements, O 19/669,079, H 0/0, 33 uniqueness
checks, and no clones or refusals. Retain traffic is already negligible here.

The source constructs 669,020 recursive boxes; formatting and other runtime work
account for the remaining 40 allocations. A Node body is 16 bytes and the frozen
RC prefix is 32, occupying the allocator's 48-byte class. The equivalent common
GC header and body occupy 32 bytes. The RC slab has 80 bytes of metadata and
1,363 slots of this class, so no avoidable power-of-two rounding explains this
case. Immediate retirement/reuse gives lower observed peak RSS despite the
larger per-object extent. Reducing that prefix would change the accepted O/H
representation; it is outside this optimization.

The larger structural cost is the repeated per-object allocation and destruction
protocol, plus generated constructor bookkeeping. A 240-repeat attribution run
from the same compiler gives approximate weighted global shares:

| Site | QBE | LLVM |
| --- | ---: | ---: |
| generated make | 29.87% | 47.58% |
| generated check | 8.39% | 6.70% |
| drain | 8.71% | 25.57% |
| descriptor lookup | 4.46% | inlined into drain |
| edge release | 4.22% | inlined into drain |
| slab allocation | 9.33% | 7.48% |
| storage allocation | 4.79% | 5.14% |
| fast memset | 9.21% | mostly inlined |

A separate QBE frame-pointer profile attributes sampled fast-memset work to
generated make (9.38% globally) and workload (0.26%), not slab_take. Slab zeroing
is inlined within its own cost. These are different sampled runs with throttling;
percentages are approximate and are not additive across the two runs. Raw records
and denominators are retained. The root owns journal initialization and the core
agent owns constructor publication; neither is duplicated here.

## First bounded experiment: reuse the flat descriptor within a drain

The homogeneous tree queue repeatedly hashes the same native-type identity.
Keep one local cache containing type, copied binding pointer and metadata batch
head. A matching type and head can reuse an already admitted flat binding.
Invalidate the cache before every generic hook path; keep the existing lookup
after a finalizer. The cache never stores an index-table entry or a slab address.
It adds constant 24-byte native stack state, no heap or ABI field, and does not
batch, delay or reorder edge release, callbacks or retirement.

The lifetime proof is stronger than the generation check alone:

- `build_batch` reserves one immutable allocation for its copied bindings and
  shapes. Publication prepends the completed batch; there are no same-batch
  additions or in-place binding replacement.
- Index growth/rehash relocates index entries, whose values still point at the
  same copied bindings. It cannot invalidate the proposed cached address.
- Re-registering an existing type checks shape and all callbacks for equality;
  it returns the original binding. New registrations publish a new batch head.
  Failed registration does neither.
- Metadata batches are freed only during heap destruction. Destruction forbids
  an active drain, and the cache ends with that invocation. Reentrant metadata
  registration from finalizers or custom allocator retirement is conservatively
  detected by the batch-head change even though existing bindings remain stable.
- Flat direct edges only enqueue; no callback can intervene while a cached
  binding is in use. The generic branch invalidates it before any callback.

Required controls include alternating flat layouts, zero/multiple allocation
elements, finalizers which register/rehash metadata, custom retire hooks which
register metadata, and held/loan-backed last-owner cleanup. The existing deep
chain, reordered edge and refusal-budget cases remain mandatory. Measure this
candidate separately on both actual backends before keeping it.

## Second bounded experiment: eliminate duplicate prefix clearing

`slab_take` currently zeros the complete class slot. Its only two callers then
immediately call `initialize`, which overwrites owners, holds, common mark/count/
flags and common type: all 32 bytes of the live RC prefix. The free-list pointer
occupies the old owners word and is read before either operation. After taking
the slot there is no allocation, callback, fallible action or publication before
initialization completes.

Clear the payload and complete class padding, starting at byte 32, and retain
the explicit complete prefix initialization. Do not change large allocations,
custom allocation hooks, arena/literal headers, budget charging, object counts,
free-list handling, epoch invalidation or retirement. Layout assertions must
establish that every prefix byte is one of those overwritten fields; no inactive
link may survive as a live header word.

Reuse tests must poison every old prefix/payload word, switch types within one
class, vary actual extents and class padding, and cover zero-sized bodies,
slab exhaustion/reuse, large fallback and count/budget refusal. Compare it
independently against the frozen cumulative baseline, not after the descriptor
cache, so any instruction gain has a clear attribution. This removes repeated
stores rather than promising fewer allocations or lower RSS.

Bulk allocation/retirement or coalescing recursive boxes could remove more
per-object work but requires new lifetime, budget, identity and callback-order
proofs. It is not justified by this profile alone. Neither bounded candidate can
be assumed to close the remaining 5.7–6.5× gap, and full WP-4 corpus acceptance
remains unchanged.
