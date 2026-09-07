# Bounded collections

`std_map` keeps its consuming API and adds `lookup(&Map,key)`, `put_mut(&mut Map,key,value)`, `remove_mut(&mut Map,key)`, and `clear(&mut Map)`. Use an explicit `borrow` block at the caller. These operations allocate no guest backing memory. Removal swaps the last entry into the removed slot.

`std_collections` adds `clear`, `append_many`, `dedup`, and `filter_i64`. `append_many` checks all capacity before mutation; an insufficient-capacity error leaves the vector unchanged. Deduplication retains the first occurrence of every value in input order. Filtering retains matching values in input order. Deduplication uses quadratic equality comparisons. The callback is a noncapturing, effect-free `fn(i64)->bool effects()` value. All operations preserve capacity.

`std_borrowed_set` is a direct-buffer set with borrowed `contains`, `insert`, `remove`, and `clear`. Its `Change` enum distinguishes unchanged, changed, and full. The existing owner-record `std_set::Set` remains compatible. Removal in the direct-buffer set also swaps the last entry.

`std_hash` provides deterministic FNV-1a-64 byte hashing and a mixed u64 integer hash. These are noncryptographic, unkeyed hashes; callers needing adversarial collision resistance need a different algorithm.

`std_hash_map::Map<V:copy>` maps u64 keys to copyable values. `std_hash_bytes::Map<V:copy>` maps byte-string keys to copyable values. Both use bounded open addressing with linear probing and tombstones. `create` allocates exactly the requested slot capacity. `put` reports inserted/replaced/full; full insertion preserves existing entries. Removal returns `std_map::Value<V>`; lookup accepts a shared borrow. `clear` removes entries and tombstones without changing capacity. `count` scans occupied slots. Lookup/insert/remove are expected constant-time at low load and worst-case linear; a table may use every slot, but callers should reserve slack for performance.

Byte keys are owned inline copies of at most 256 arbitrary bytes, constructed with `std_hash_bytes::from_bytes`. Length is checked before copying; error 1 means too long. Empty keys and embedded NUL are supported. No UTF-8 normalization is performed. `Key` fields are public to support value inspection: manually constructed keys with length above 256 are invalid. `valid` checks them; insertion returns the byte map’s `PutStatus.invalid`, lookup/removal return none, equality returns false, and hash returns zero without accessing their data. Prefer the checked constructor. Hashing and equality ignore bytes beyond the stored length.

`std_hash_set` and `std_hash_byte_set` wrap the corresponding bool-valued tables with borrowed membership operations. Set insertion reports inserted/replaced/full, with replaced meaning already present.

Hash table iteration is explicit physical slot order: inspect `read_buffer` over `0..len_buffer`, match `Slot.occupied(entry)`, and skip empty/deleted slots. The order is deterministic for the same operation sequence and capacity, but is not insertion order and is not stable across different capacities. Never mutate during a shared borrow. `len_buffer` is slot capacity, not entry count; use `count` for cardinality.

Executable examples: `src/stdlib/fixtures/collection_borrows.my` and `src/stdlib/fixtures/hash_collections.my`.

## Owned values

`storable` is a new generic requirement. It admits ordinary copyable values and owned values composed of buffers, pools, arrays, records and non-result unions. It excludes must-handle results and external resource owners, including nested filesystem/network resources. A `copy` constraint implies `storable`; a merely `storable` parameter must be treated as a moved value. Resource-containing collections need an additional design for provider cleanup effects and are not admitted by this contract.

`std_owned::Vector<T:storable>` provides `vector`, `append`, `replace_at`, `take`, `truncate`, and `clear`. For example, `Vector<std_bytes::Bytes>` can contain independently owned byte strings (use the actual byte-buffer type exported by the producer). `std_owned::Taken<T>` is a generic result with owned success payload and i64 failure. `take` swap-removes the selected value and transfers its ownership to the result. `replace_at` destroys the previous value after validating the index. `truncate` shrinks only; larger lengths return bounds error 3 and leave the vector unchanged. Clear releases all elements and retains capacity.

The underlying builtins are `take_buffer<Result>(buffer,index)` and `truncate_buffer<Status>(buffer,length)`. Take requires a result whose success type matches the buffer element; truncate uses bool success. Existing append/write now support storable owned elements. These operations move their input: **append or write failure also consumes and destroys the supplied element**, while leaving existing initialized values unchanged. Capacity failure is 2, bounds failure is 3. Allocation limits for acquisition/reserve remain 1. Runtime/host allocation failure terminates execution with normal cleanup; it is not a recoverable collection status. These APIs make no allocation-failure rollback promise for terminated executions.

Owned elements cannot be copied with `read_buffer`, resize-fill, or slices. Extract an element to inspect/mutate it, then append it back if desired. Copyable buffers keep those operations. Whole-container borrows still enforce shared/exclusive access. Nested owners retain arena provenance: a child-arena allocation cannot enter parent storage or escape its arena through a take/helper return.

`std_owned_map::Map<K:equality,V:storable>` is a bounded linear map for owned values. `put` consumes the offered value and returns inserted/replaced status, `take` moves a matching value out, and `clear` destroys entries. Missing keys return error 4. Full insertion consumes the new value and preserves existing key/value pairs. The map inspects keys by moving entries during its reverse scan, so entry order is unspecified and may change even when a key is absent. Lookup without moving an owned value needs an element-reference API, which this release does not provide. Hash maps currently retain copyable values; use this owned map when values own buffers.

Run `src/stdlib/fixtures/owned_collections.my` for owned byte-buffer vectors/maps. `src/stdlib/fixtures/owned_buffer_mutations.my` also covers reserve, swap removal, truncation and failed replacement. The compiler rejects recursive by-value buffer ownership; there is no general recursive container type in this release.
