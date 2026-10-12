# Interim performance evidence, second iteration

These results do not establish the final target. Full applications remain deferred.
Fresh common-compiler six-arm runs with fifteen paired rounds and separate RSS/counters are pending.

Short screens use one warmup/five paired rounds and the fixed fresh baseline iteration counts; they are never pooled with full runs.

| Candidate | Small / fastest reference | Large / fastest reference |
|---|---:|---:|
| CSV02 | 1.270 ZigFast | 1.180 ZigFast |
| CSV03 | 1.134 ZigFast | 1.030 ZigFast |
| CSV04 | 1.010 ZigFast | .928 ZigFast |
| CSV05 | .968 ZigFast | .903 ZigFast |
| SPLIT02 | .926 Rust | 1.043 Rust |
| SPLIT03 | .901 Rust | 1.038 Rust |
| JSON03 | 1.623 Rust | 1.713 Rust |
| JSON07b | 1.122 Rust | 1.160 Rust |

JSON05 full trial has /Rust small1.1433 [1.1282,1.1535], large1.1647 [1.1502,1.3215]. Large CI is wide; all samples are retained. Reports/raw receipts remain under matching reports/runs suffixes. Robust below-one requires the final paired CI upper bound below1 for each foreign language and cell.

JSON05 profile (1,381 samples, zero lost) shows read_value14.38%, read_string10.97%, drop_owned10.68%, block_alloc6.81%, dict_insert5.17%, span_utf8_count4.67% flat self. SPLIT03 profile (1,420 samples, zero lost) shows core_span_find26.95%, split_offsets13.32%, kernel22.56%, memchr PLT3.55%, plus unresolved libc addresses. Whole-process profiles include setup; instrumented durations are excluded from benchmark samples. Raw data is preserved losslessly as gzip with raw/compressed hashes and exact artifact identities.

SPLIT02/03 offset tables are managed storage. They are not zero-allocation results. SPLIT02 small has five managed allocations/four grows perjob, cumulative requested2080B, final1056B, logical old/new transient1600B. Large has six additional reallocs, cumulative requested66592B, final65568B. SPLIT03 reserves128 offsets: small one managed allocation requesting2080B; large one allocation plus five reallocs to final65568B. Tracked usable-size traffic differs from requested bytes. Warm slab recycling means managed allocation counts are not raw libc call counts. Aligned realloc realignment may transiently retain two final-size buffers; allocator-internal peak is unspecified. Process RSS, managed traffic, logical owner storage, and raw allocator behavior must remain separate.
