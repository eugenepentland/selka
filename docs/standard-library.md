# Standard library

Ordinary application code uses builtin `list[T]`, `str`, `dict[K, V]` and `bytes`
with GC; see the [Python-style guide](python-syntax.md) and
[managed byte strings](bytes.md). The embedded modules below cover the few things
the builtins do not: fallible values, time, randomness and JSON transport.

Standard modules are embedded in the compiler. Import their names directly;
projects do not need to copy these files. External authority stays explicit. The
installed `--features` report identifies the compiler actually in use, by the
build-time identity described in
[the current language reference](current-language.md); this document describes the
source tree.

| Area | Modules | Available operations |
| --- | --- | --- |
| Results | `std_result`, `std_unit` | Copyable Option/Result, categorized errors, error context and Unit |
| Iteration | `std_iter` | Bounded distinct index pairs |
| Numbers | `std_math` | Nominal binary64 arithmetic, checked integer conversion and exact bit codecs |
| Time/random | `std_time`, `std_random` | Checked durations and wall-clock instants, explicit clock/entropy capabilities, seeded SplitMix64, bounded unbiased range sampling and byte fills |

The list, JSON, text, formatting, collection, hashing, encoding, argument, path
and I/O modules that used to appear here were built on the removed
explicit-storage tier and were withdrawn on 2026-09-13. Their replacements are being rebuilt on
`list`, `dict`, `str` and `bytes`; until then, write that code in the application.

## Contracts to use consistently

Always check the individual API contract before reusing an input after failure.
Managed collections grow automatically; see [managed memory](managed-memory.md),
and [managed arenas](arenas.md) for bulk release of a phase of work. Runtime byte
budgets bound backing and bookkeeping allocations. Clock and entropy functions
require capabilities supplied by the host; importing a module grants no
permissions. Synchronous provider operations are not timed out by a VM
instruction budget.

## Examples and focused references

- [Managed word counts](../examples/python-word-count/main.my) uses ordinary strings, dictionaries, and iteration.
- [Time/random example](../examples/standard-time-random/main.my) checks full-width
  boundaries and reproducible streams without ambient authority.
- [Time/random contracts](standard-time-random.md) specifies errors and supported
  ranges.

These are intentionally bounded foundations. Text offsets are byte offsets; there
is no Unicode normalization. Wall-clock instants are not monotonic timers, and the
deterministic generator is not cryptographic.
