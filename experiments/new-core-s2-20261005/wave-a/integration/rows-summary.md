# Wave A S1 performance summary

Median of seven interleaved rounds on CPU 10; sizes 4096 and 64.
Every old-core/new-core/Rust/Zig checksum is equal at both sizes.
The complete four-runner cycle tables are in [wave-a-rows.txt](wave-a-rows.txt).

| Row | New / Zig, 4096 | New / Zig, 64 | Inner count updates |
| --- | ---: | ---: | ---: |
| record_reads | 0.728 | 0.725 | 0 |
| tagged_stack | 0.697 | 0.689 | 0 |
| mutate_unique | 0.861 | 0.858 | 0 |
| mutate_shared | 0.583 | 0.650 | 0 |
| record_construct | 0.219 | 0.217 | 0 |
| record_update | 0.554 | 0.540 | 0 |
| option_handle | 0.303 | 0.330 | 0 |
| result_propagate | 0.553 | 0.551 | 0 |
| list_scan | 0.877 | 0.870 | 0 |
| list_append | 0.574 | 0.688 | 0 |
| list_filter | 0.758 | 0.746 | 0 |
| alloc_short | 0.225 | 0.227 | 0 |
| alloc_retained | 0.544 | 0.412 | 0 |
| mutate_nested | 0.140 | 0.166 | 0 |
