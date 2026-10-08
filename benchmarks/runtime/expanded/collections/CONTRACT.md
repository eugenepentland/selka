# Collection and Lox subset benchmark contract

CLI `CASE SIZE ITERATIONS SEED` emits exactly `CHECKSUM ELAPSED_NS\n`.
SIZE >= 2, ITERATIONS >= 1, seed 1..1000000; arithmetic stays signed64.
MOD=1000000007. Prepare values[j]=(seed+13*j)%1009 outside timing.
Every iteration batch is numbered0..ITERATIONS-1; add its result modulo MOD.
Normal dynamic containers/default general-purpose allocators, no arenas, unsafe
indexing, barriers, noinline, pooling, or forced allocations. Natural optimizer
elimination is allowed. Initialization below is inside timing unless specified.
Final printing is excluded. Python oracle independently specifies checksums.

- list_scan: prepared values outside timing; sum (value+batch)%1009.
- list_append: append SIZE values (seed+batch+13*j)%1009 to a fresh dynamic list;
  sum (j+1)*value, then release list inside timing.
- list_filter: prepare the same batch-dependent input list; filter values divisible
  by3 to another dynamic list; sum (filtered_index+1)*value; release both lists.
- dict_lookup/dict_lookup_str: prepare native map key j / decimal str(j) to
  values[j] outside timing, plus decimal string query keys0..2*SIZE-1 outside
  timing. Per batch query k=(seed+17*j+batch)%(2*SIZE), for SIZE queries;
  accumulate found value or17 for a miss. String allocation is excluded.
- dict_update/dict_update_str: fresh native map containing keys0..SIZE-1 mapped
  to prepared values. For j0..2*SIZE-1 query k=(seed+17*j+batch)%(2*SIZE),
  set value=(prior_value_or_17+j+batch+1)%1000003. This updates existing entries
  and grows the map. Sum numeric_key+value across all entries. String key texts
  are precomputed outside timing, and consumed as native keys without conversion
  in timing (fold iterates numeric keys and probes map).
- set_dedup: insert (seed+batch+13*j)%max(2,SIZE//4) into a native set for SIZE
  insertions; sum all unique keys, then release inside timing.
- alloc_short: SIZE fresh 4-int dynamic lists [seed+batch+j+k for k0..4), each
  folded/released before the next allocation. Sum every element.
- alloc_retained: same lists retained in a dynamic outer collection; fold every
  element and release all collections before the next batch.
- mutate_nested: prepare SIZE dynamic 4-int lists with (seed+13*j+k)%1009 outside
  timing. Each batch snapshot the complete nested collection, preserving every
  element (MyLang value/COW semantics; explicit deep Vec/slice/allocator clone
  in reference ports), mutate inner element1 at index(seed+17*batch)%SIZE by
  adding batch+1 modulo1000003; observe snapshot and new element, add both;
  destroy whole snapshot inside timing. After timing add all final elements.
- sort_int: fresh dynamic SIZE-list of (seed+batch+13*j)%1009; native ascending
  library sort; sum (sorted_index+1)*value. Creation, sorting, folding/destruction
  are timed. This compares library implementations, not one fixed sorting algorithm.
- sort_records: records {key=value%17, ordinal=j, value} for the same input;
  stable native library keyed sort ascending key; sum (sorted_index+1)*
  (value*17+ordinal). Ties must retain input order. Entire operation timed.
- lox_eval: execution-only documented Lox-compatible subset; fixed bytecode
  fixture prepared outside timing. Each batch executes this program with seed
  replaced by seed+batch, adds returned total, releases VM state inside timing:

```
fun bump(x) { return (x * 3 + 7) % 1000003; }
var total = SEED; var i = 0;
while (i < SIZE) {
  if (i % 2 == 0) { total = bump(total); }
  else { total = (total + i) % 1000003; }
  i = i + 1;
}
return total;
```

This is a bytecode executor, not a full Lox implementation; lexer/parser/compiler,
strings, classes, closures, and dynamic variable lookup are excluded. VM uses
native dynamic tagged Int/Bool operand stack, two indexed integer variables,
branch/loop PC, and a dynamic return-address stack for calls/returns. Each
opcode is {code,argument}; fixed bytecode fixture implements the program above.
One application iteration is SIZE loop iterations of the whole program.
Micros64/4096; allocations/nested64/1024; application16/256. Qualification includes
sizes2/3/17 and odd batch counts, seeds1/42/999983; no zero-duration measurements.

CASE is resolved to an integer once before timing in every port; the measured
outer loop dispatches that integer. String maps retain their normal language
ownership: Rust owns String keys and clones text on insertion; Go/MyLang share
immutable strings and Zig borrows the precomputed buffers until map destruction.
This is native-library behavior, not matched string allocation strategies.
Allocation workloads express ordinary dynamic-list creation; escape analysis or
scalar replacement may optimize short-lived allocations naturally. No guaranteed
heap-allocation count is claimed without profiling.

The oracle folds periodic batch inputs for scan/append/filter/sort/map lookup/set
cases; allocation sums use a closed arithmetic series. Lox's source recurrence
is composed as an affine map modulo1000003, independently of the native VM.
Nested mutation/update oracles retain direct mathematical state. fixtures.json
persists42 seed/odd-size/odd-count expected results; hand arithmetic and period
boundary checks are in test_oracle.py. All per-dataset weighted fold maxima at
specified profile sizes fit signed64 (record-sort folds remain below2e11).
