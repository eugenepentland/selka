# Final deterministic proxy

Base: main `35df839be`; package: `c26c95de7`. Both source tags were rerun through the same executable and EDA output paths. No timing CPU, timing lock or runtime ratio was used.

**132/132 outputs match.** Allocation/free/copy/growth/call operation counts and every emitted-operation count/byte total match. All exit live-byte totals match. The `list_push.extra` movement counter is the only emitted-kind field that differs (45 cells).

## Remaining counter differences

| metric | differing cells | observed package − base range |
|---|---:|---:|
| alloc_bytes | 13 | -5984 … +4016 |
| free_bytes | 17 | -5984 … +4016 |
| peak_live_bytes | 9 | -1968 … +4016 |
| realloc_added_bytes | 5 | +16 … +4016 |
| realloc_moved_bytes | 45 | -458784 … +655456 |
| realloc_moves | 33 | -30 … +26 |
| runtime_retains | 80 | -2085393 … +423 |

Byte totals use malloc_usable_size; the allocation/registry/TLS changes can alter allocator placement and rounded usable sizes. Realloc movement and peak-live counters can therefore differ despite identical logical operation counts. These are retained differences, not proof of zero memory or time overhead.

Runtime-retain hooks also have different coverage: the old hook counted entry to retain_block even for immortal values, while P1 instruments the common non-immortal count_retain path, including formerly direct provider/startup holds. No runtime-release count differs.

## Selected code sizes

Default-alignment, plain ReleaseFast binaries; these are byte counts, not speed estimates. All 52 binary hashes and section/symbol sizes are retained.

| binary/symbol | base bytes | P1 bytes |
|---|---:|---:|
| row-string_split-plain / .text | 193846 | 202870 |
| row-json_transform-plain / .text | 250150 | 261814 |
| lox-plain / .text | 474710 | 513558 |
| eda-plain / .text | 1067670 | 1203286 |
| json_transform / block_alloc | 389 | 580 |
| json_transform / myl_core_free_block | 940 | 786 |
| json_transform / my.json::read_value | 7286 | 8338 |

The runtime/ELF expands, and json::read_value is larger. This evidence does **not** establish the ≤1.010 corpus or ≤1.03 cell target. Final elapsed-time performance remains unverified under the user’s waiver.

[All paired counter deltas and ELF hashes/sizes](final-identical-deterministic-proxy.json.xz). [Fixed-path run identities](identical-counter-runs.json). [Initial path-confounded comparison, retained](final-deterministic-proxy.json.xz). Raw counter documents and their hashes are in the counter archive/manifest described in [EVIDENCE.md](../../EVIDENCE.md).
