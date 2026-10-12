# Owned keyed sorting experiment

The checked runtime previously walked permutation cycles for every owned keyed
sort. Its RC counterpart already gathers directly into a copied output. This
experiment gathers elements wider than eight bytes into raw temporary storage,
then moves the ordered bytes back into the original managed list allocation.
Scalar elements retain the in-place permutation path.

The scratch buffer is not a managed owner. Between gather and the final memcpy,
its element bytes are temporary representations of the source's original
reference multiset. No callback or destruction runs in that interval. It is freed
as raw storage after the memcpy, without dropping children. The original list
keeps its identity, length and capacity, and the key owner is dropped once.
Numeric sorting can still reuse numeric key storage; managed text and tuple keys
are left intact until their direct drop. Shape validation, key ordering, stable
duplicate handling and reverse semantics still use the same sorting engine.

There is one additional raw malloc/free pair per keyed sort with count > 1 and
an element stride > 8. The buffer requests count * stride bytes, with overflow
checked before allocation. An allocation failure falls back to the existing in-place cycle engine: raw
scratch is optional and adds no required fatal allocation point. The same
runtime rejects an impossible byte product rather than permuting invalid metadata. Sorting-engine failure frees
scratch before dropping keys. Empty/singleton and scalar paths add no scratch.
The managed allocation metrics intentionally do not count this raw storage.
For canonical 24-byte sort_records, additional scratch is 1,536 bytes at size 64
and 98,304 bytes at size 4,096 per operation. This is a capacity/time tradeoff,
not a managed allocation reduction. Process RSS must be measured separately.

The source-supported difference is a performance hypothesis, not measured CPU
attribution. Candidate paired timings and RSS are coordinated by the parent;
stored micro-ownership baselines remain unchanged. The new registered core
regression covers independent sorted outputs and 97 managed records carrying
text, bytes and nested list children, numeric/text/tuple/float keys, stable
ascending/reverse duplicates, empty/singleton, five compiler modes, zero RC
emitted code and managed exit-live counters.

Reproduce qualification under a single build admission (the script takes no
lock of its own):

```sh
scripts/build-slot.sh build -- python3 -B experiments/micro-gaps-20261012/sort/qualify.py \
  --compiler /absolute/path/to/complete-candidate-install/bin/mylang \
  --output "$PWD/.tmp/micro-gaps/sort/qualified"
```

The additional native failure-injection regression intercepts only the exact
optional scratch byte request after input setup. It checks one request per sort,
refuses it in two ascending/reverse scenarios, and verifies stable output,
managed child identity, original list identity/capacity and no live allocations.
The fallback continues to use direct ownership moves, with no RC or COW path.
