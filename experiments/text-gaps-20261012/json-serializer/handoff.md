# JSON items serializer

Production commit: 55f833061. Base: immutable common 1994cb76e plus separately qualified peek guard 207053908. Only write_object changes: iterate borrowed fields.items() and serialize item directly. No public API, benchmark, or ownership contract change.

Candidate 176/176 native contracts pass in three ordinary RC and five checked modes, all with leakcheck. Both unchanged runtime/count guests pass 50 independent oracle cases each. New tests cover tombstones/reinsertion order, dynamic nested Unicode owners, clearing original fields, repeated serialization, signed integer boundaries and overflow/fraction/exponent float fallback. Existing tests cover malformed offsets, depth, escapes, duplicates and ownership.

Native write_value now has ordinal entry reads, no str_hash/dict_find calls. It currently retains two ordinal calls per visited entry; no compiler purity assumption is made. Managed counters for all five JSON oracle cases exactly match frozen guard (no added copies/allocations or RC activity, zero live bytes). No performance claim until combined controlled timing.

The independent quote-loop nonnegative guard probe remains a span index helper call; that source guard is not adopted. Probes are standalone copies of the library to reach actual edited source with the frozen compiler. Production candidate rebuilt its host because stdlib sources are embedded.

Immutable artifacts and complete installation hashes are recorded in build-receipt.json. Compiler built with seed-compiler and reused unchanged complete frozen C0 components, no legacy seed provisioning. Guardian88 passed production commit; all evidence is separate.
