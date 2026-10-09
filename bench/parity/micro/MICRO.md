# Micro-kernels

Eleven small kernels, each in selka, Zig and Rust, each printing one checksum
line (`<name>.expected`). An application benchmark says *selka is N× Zig*; a
kernel says *which primitive* pays for it. Copied from
`experiments/perf-parity-audit-20260921/micro/` (the `.selka` and `.zig` ports)
and `experiments/perf-parity-plan-20260922/micro-rust/` (the `.rs` ports and
`.expected` files), which remain the evidence snapshots with their notes.

| kernel | what it isolates |
| --- | --- |
| `intloop` | checked integer `+`, `*`, `%` in a loop-carried dependency |
| `calls` | an ordinary call to a two-argument leaf function, 30,000,000 times |
| `fib` | the call/frame protocol at depth (naive `fib(36)`) |
| `records` | constructing a 3-field value record and passing it by value |
| `list_append_sum` | growing `list[int]` by `append`, then one fold |
| `list_records` | a list of 2,000,000 32-byte records, ten field-summing passes |
| `dict_count` | `dict[str, int]` read-modify-write over 1000 short string keys |
| `str_build` | 16,000,000 eight-byte appends into a growable byte buffer |
| `alloc_churn` | build/fold/drop a 16-element list once per batch, 1,000,000 batches |
| `float_loop` | a binary64 multiply-add-sqrt dependency chain |
| `bytes_scan` | indexing an 8 MiB `bytes` value sixteen times, counting one octet |

Variants: `alloc_churn_arena.selka` wraps each batch in `with arena():`;
`bytes_scan_wrapping.selka` and `list_records_wrapping.selka` use the wrapping
operators; `calls_inline.zig`, `dict_count_getorput.zig` and
`alloc_churn_gpa.zig` are extra Zig forms; `dict_count_entry.rs` and
`alloc_churn_reuse.rs` are extra Rust forms. Every variant prints its kernel's
line.

`common.zig` holds the Zig side's one-line writer and `opaqueN`, a volatile
load that always yields 1, so no loop bound is a compile-time constant. The Rust
ports use `std::hint::black_box` for the same purpose and print through a
by-value `#[inline(never)]` helper (see the micro-rust README for why that
matters to `bytes_scan`).
