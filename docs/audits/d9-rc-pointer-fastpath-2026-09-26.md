# D9 WP-4: ordinary pointer and small traversal fast paths

The exact frozen `39f75f3f` depth-16 corpus exposed a roughly 108x QBE
binary-tree instruction regression. A private depth-12 diagnostic showed
669,060 allocations and retirements, 3,992,307 owner acquisitions, 4,661,367
owner releases, and no cloning, holds, or arena allocation. This is generic
transfer/drop overhead, rather than an accidental deep snapshot or allocator
bottleneck. The initial sampled profile spent about 10% in the release/seed
walker, 8% in transfer, 7% resolving shapes, 7% visiting transfer shapes, and
6% dropping journal slots; allocation/calloc together were below 2%.

The change bypasses aggregate setup for a registered ordinary pointer with no
pin or younger arena edge. Copy increments an owner before publication; take
moves that token and clears the source; count refusal leaves the copy output
empty. The native take bridge still stages its output and preserves it on
failure. Null/immortal handling and the existing arena shared mark remain.
Pinned pointers and younger arena transfers use the existing transaction,
clone memo, and rollback paths. HOLD_POINTER is a distinct shape and is never
admitted to this path. Native pointer drop clears the physical slot before
releasing the ordinary owner, preserving reentrant finalizer ordering.

Each aggregate/clone operation also starts with eight automatic traversal
frames (256 bytes) instead of allocating scratch frames for every nontrivial
shape. Deeper shapes reserve charged heap frames without a depth cutoff. Only
heap frames are freed; automatic frames are uninitialized until their push.
Every operation owns its own frames, including reentrant clone callbacks.
The release walker and its preregistration reservation are unchanged. The
runtime prefix, public shape ABI, generated call ABI and stats events are
unchanged.

Three interleaved diagnostic runs on CPU 0 gave these median user instructions:

| Runtime arm | Instructions | Improvement from preceding arm |
| --- | ---: | ---: |
| Frozen RC | 12,790,066,859 | — |
| Ordinary pointer path | 8,659,270,369 | 1.477x |
| Pointer plus automatic frames | 8,257,106,801 | 1.049x |

The combined improvement is 1.549x. Output hashes match, as do the complete
before/after count records. Guest function names and machine-code sizes also
match. The default-GC control uses 105,808,932 instructions, so this slice still
leaves about a 78x gap. These scaled measurements do not establish WP-4
acceptance and do not replace the full corpus. Raw counters, hashes, profiles,
the isolated pointer patch and reproduction instructions are in
`experiments/d9-rc-pointer-fastpath-20260926/`.

Validation: 37/37 focused RC Zig tests pass. Strict C ASan/UBSan passes the
held-edge 12, arena 10, stats 4, execution success/trap/fast-exit 3, core 19,
and collection 23 scenarios. New cases verify count-limit publication,
allocation-free ordinary copy/take at a tight heap budget, pinned-copy refusal
without consuming a source or overwriting a caller output, arena sharing and
outward-region refusal. Exact depth-eight/depth-nine tests prove the small
stack succeeds at a closed budget, deeper fallback refuses without acquiring
an owner, and retry succeeds with balanced metadata charges. Existing cases
retain million-node teardown, 32,768-deep inline values, 4,096-deep pinned
collection copies, memoized DAGs, held edges, finalizer reentrancy, and immediate
arena-clone rollback. All 88 Guardian checks pass, with no ratchet changes.

Further work should follow the remaining profiles: general small-record shape
walking and descriptor lookup, compiler-produced journal initialization and
publication stores, and count traffic left by readonly traversal. E2b's inline
count paths are relevant, but its packed count/pin representation cannot be
copied into the separate O/H production prefix.
