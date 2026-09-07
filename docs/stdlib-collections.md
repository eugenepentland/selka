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
