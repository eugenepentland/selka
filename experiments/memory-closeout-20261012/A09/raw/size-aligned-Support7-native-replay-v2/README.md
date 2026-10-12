# Exact-sized managed counters through native replay v2

Source `bed11cf3bf3102ffec44487e431a1573fdf02ad5`; compiler SHA-256 `540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`.

Eight native binaries and all fifteen fixed-input configurations pass. Every run
has exact output, zero observed RC events and zero managed exit-live bytes;
emitted LLVM and linked symbols pass the selected-owned structural checks.

The adapter is A10 commit `7b10b6b6f9205993b7f6bdd73be34e32b4ab93ea`.
Both C0 and Support7 use this exact adapter version. It verifies the runtime
against the frozen compiler and identifies the numeric object with explicit
provenance and a unique read-only ELF match. C0 v1 evidence and the initial eight
ordinary C0 native-link failures remain unchanged in their separate directories.

The raw archive preserves native commands, LLVM, source/helper snapshots, counter
documents and symbol audits. This run used two four-source admission leases;
admitted work was 30.730s and queue wait 180.819s.
Those durations describe qualification scheduling, not compiler/runtime benchmarks.

These counts are additional exact-sized timing-input evidence, separate from the
original30 and pinned81+6 census denominators. Allocation and copy traffic,
reallocations, managed peak and exit-live bytes remain separate fields.
Managed peaks are observations, not traffic reductions or RSS. Realloc movement
and concurrent peaks vary across runs. Corrected descriptor-list-copy telemetry
in Support7 must not be interpreted as an allocation increase.

Support7 is a frozen intermediate candidate with release-inventory blockers.
This report does not claim qualified implementation, default promotion or RC
retirement. All uninstrumented timing binaries remain unchanged.

The matching normal Support7 compiler path also passed all fifteen cases in
`../size-aligned-Support7`. Its allocation/copy totals match this replay;
two parallel peak observations differ. A10 separately requires complete counter
document equality on deterministic one-worker JSON and task controls.

| Case | C0 allocations | Support7 allocations | C0 managed peak bytes | Support7 managed peak bytes |
| --- | ---: | ---: | ---: | ---: |
| array | 12,001,554 | 12,001,554 | 75,408 | 75,408 |
| object | 12,002,200 | 12,002,200 | 90,264 | 90,264 |
| record | 21,000,000 | 21,000,000 | 1,536 | 1,536 |
| parallel_cheap_1 | 101,318,666 | 393,226 | 103,096 | 17,144 |
| parallel_cheap_2 | 25,329,674 | 442,378 | 103,096 | 18,096 |
| parallel_cheap_8 | 12,664,842 | 827,402 | 103,160 | 21,552 |
| parallel_expensive_1 | 786,762 | 202 | 1,643,112 | 262,904 |
| parallel_expensive_2 | 786,762 | 874 | 1,643,048 | 247,488 |
| parallel_expensive_8 | 786,762 | 3,242 | 1,643,112 | 251,568 |
| a06_word_count | 13,113,602 | 13,113,602 | 99,152 | 99,152 |
| a06_nested_json | 3,403,682 | 3,403,682 | 828,184 | 828,184 |
| a06_file_processing | 2,464,352 | 2,464,352 | 49,680 | 49,680 |
| a06_parallel_t1 | 62,842 | 31,842 | 65,976 | 27,320 |
| a06_parallel_t2 | 62,842 | 32,922 | 56,312 | 26,032 |
| a06_parallel_t8 | 62,842 | 35,882 | 51,576 | 28,592 |

Exact arguments, worker affinity, all cumulative-byte and reallocation fields,
source hashes and artifact identities are in `comparison-C0.json`. Cheap-map
repetition counts differ across worker cases to bound runtime; compare each
same-input C0/Support7 row, not raw values across worker counts.

Remaining map allocations include independent output and temporary chunk-result
storage. A01 separately audits scheduler-wrapper scaling; total allocation
reductions here do not imply allocation-free execution or an RSS saving.
