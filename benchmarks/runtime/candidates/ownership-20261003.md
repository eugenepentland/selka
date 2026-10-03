# Ownership diagnostics: current main and b3ff3bfb

These are checksum-verified **whole-process instrumented counts**, using the original 40 fixtures, both sizes, both MyLang backends, seed 42 and eight iterations. They include setup and teardown. The counting runtime can disable production optimization paths; these records do not establish production performance or kernel-only attribution. Instrumented clock values were validated but deliberately discarded.

Both compiler receipts and their installed source/assets were verified before and after collection. Main used a ReleaseFast compiler; b3ff3bfb used a Debug compiler. Both built ReleaseFast guest code with the recorded backend options. Builds used separate caches and the build-slot wrapper; diagnostic guest affinity excluded CPUs 2, 3, 10 and 11. Campaign performance measurements use CPU 2.

4 of the 160 corresponding records differ, all JSON transformations. The other 156 match exactly for every recorded event. In particular, integer formatting preserves allocation counts; compiler arithmetic changes do not change ownership events. The absence of an event-count difference does not imply the absence of a speedup, nor validate an optimization that counting mode refuses.

| JSON size/backend | Allocations main → candidate | Owner acquires | Temporary holds | Uniqueness checks |
|---|---:|---:|---:|---:|
| small/my-llvm | 9,082 → 5,371 | 81,352 → 24,900 | 7,279 → 27,447 | 13,766 → 3,718 |
| small/my-qbe | 9,082 → 5,371 | 81,352 → 24,900 | 7,279 → 27,447 | 13,766 → 3,718 |
| large/my-llvm | 145,014 → 84,203 | 1,424,156 → 406,732 | 116,959 → 449,759 | 228,526 → 59,718 |
| large/my-qbe | 145,014 → 84,203 | 1,424,156 → 406,732 | 116,959 → 449,759 | 228,526 → 59,718 |

All recorded allocation and retirement totals agree within each JSON run, as do hold acquires and releases. This is an accounting observation, not a complete memory-safety proof. JSON uses fewer allocations and owner operations but more temporary holds. Peak live bytes and ordinary-build timings must be assessed separately.

Reproduce with `python3 benchmarks/runtime/diagnostics/ownership_counts.py --compiler-receipt RECEIPT --work PRIVATE_WORK --output REPORT.json`. `--skip-build` requires identical compiler, source, command and guest hashes. The tool refuses wrong checksums, diagnostics mixed into the stats record, missing/duplicate counters, overflowed counters, and incompatible schemas. Its four parser tests cover those refusal paths.

Raw uncompressed JSON SHA256:

- [ownership-main-1fd1d566-20261003](ownership-main-1fd1d566-20261003.json.gz): `868908a95b375933ab183bf72ed11de5f821e43e8cb2c951a0e0570676f0925f`
- [ownership-b3ff3bfb-20261003](ownership-b3ff3bfb-20261003.json.gz): `ea92fd84d0a05ae3a84ca752a2ada13c2924f270ae9497096926b95d5d459921`
