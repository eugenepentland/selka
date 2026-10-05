# D1 corpus and external Lox audit

`examples/corpus/{invoice,packet}` contains no foreach loops. The old-core gate
checks the existing language corpus; the inherited cases that intentionally
expected snapshots were amended in `iteration_identity.my`, `array_places.my`,
and `array_negative_index.my`. The nested-field CLI fixture in
`test/integration.zig` previously appended unconditionally and expected an entry
snapshot. It now appends finitely, expects the live total 10, and checks that a
copy named before entry remains `[1, 2]`.

The external Lox port was read only at:

```
/home/epentland/ai/canopy/mylang/.tmp/lox-bench/wt-mylang/benchmarks/lox/ports/mylang
```

Its foreach bodies have no direct write to a later element of their source and
no append/shrink of their source. Several bodies mutate another field under the
same root (`table.my:75` updates `t.count`; `heap.my:233/236/238` mark objects
through `rt.marker`; `interpreter.my:584` calls `execute(mut it, ...)`). These
paths conservatively get live refreshes, but their source elements and lengths
remain stable. Other loops read prior named values (`function.body`,
`node.arguments`, `source.entries`) while changing a separate root. This scan
found no Lox loop that depends on the old snapshot answer.

No external file was changed or timed. S2-La owns the separate receiver-overlap
migration for `resolver.my:195/251/259`; the coordinator owns applying the
approved two-statement migration outside this package.

The extra `loop-variable-place.my` probe receives `E_VALUE_BINDING_WRITE`: an
iteration binding is a value copy, and writes through it are rejected by the
existing checker. It is retained here as refusal evidence, outside the regular
guest suite.
