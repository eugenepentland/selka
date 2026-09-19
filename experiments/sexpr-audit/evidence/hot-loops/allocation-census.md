# Where the census allocates — 2026-09-19

One run of the landed census (`experiments/sexpr-port/main.my` over the 927,415
byte EDA input) with a temporary counter in `myl_native_heap_alloc_at` that
groups every allocation by the element descriptor it was given, plus a counter in
`myl_native_list_new` for the capacity histogram. The instrumentation was removed
after the measurement; this file is the record.

```
allocations=53135 bytes=15157813 live=40713
site element=list_type            kind=2 size=72 calls=26192 bytes=4400256
site element=myl_native_text_point kind=0 size=4  calls=11082 bytes=3604756
site element=byte_type            kind=0 size=1  calls=11056 bytes=2624881
site element=<node variant>       kind=4 size=56 calls=4788  bytes=1904896
site element=<token list>         kind=2 size=40 calls=14    bytes=2622624
list capacity=0     calls=4053      # `entries: list[ast.Node] = []`, one per form
list capacity=3     calls=4362
list capacity=8     calls=4370
list capacity=4     calls=2233
list capacity=5     calls=2061
list capacity=1     calls=1213
list capacity=6     calls=830
list capacity=7     calls=630
list capacity=12    calls=360
list capacity=9     calls=290
list capacity=11    calls=210
list capacity=13    calls=170
list capacity=236   calls=20
list capacity=23    calls=10
list capacity=27    calls=1
list capacity=927415 calls=1       # the whole input, read once
```

Reading it:

- A managed `list` is two objects: a 72-byte header (`list_type`) plus its
  backing array. `bytes` uses the list representation with a 1-byte stride and
  `str` with a 4-byte stride, so the three big sites are exactly the tokenizer's
  text: **11,056 byte strings + 11,082 text points = 22,138 of 26,192 list
  headers (84 %)**, and 6.2 MB of 15.2 MB.
- The byte strings are `src[start:end]` slices. Each is copied and then decoded,
  so the census paid two objects, a copy and a collector entry per token text for
  a value that only ever fed the decode. That is what `QBE-DECODE-RANGE-1` fuses;
  after it, `myl_native_heap_alloc_at` fell from 11.6 % to 2.3 % of instructions.
- The capacity histogram shows the other half: `capacity=0` is the empty
  `entries` list each `parse_list` starts (4,053 ≈ the 4,050 forms), and the
  small non-zero capacities are slices and small child lists. `capacity=927415`
  is the single read of the input.
- `live=40713` of 53,135 means about a quarter of all objects were already
  collected by the time the program ended, so the copy also paid marking and
  sweeping on the way.
