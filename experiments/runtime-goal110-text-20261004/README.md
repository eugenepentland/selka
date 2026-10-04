# B2 text investigation

The frozen sources and contracts are unchanged. The comparator candidate is a
general byte-length specialization in `native_text.c`; join is unchanged here.
This directory retains exploratory diagnosis and correctness evidence. No timing
result or 1.10 acceptance is claimed by this commit.

The saved source-730a86e6 LLVM text guest already inlines immutable equality in
the `string_equal` kernel. It checks pointer identity, nulls, byte lengths and
view storage, then calls libc `bcmp` for each nonempty, equal-length pair. The
remaining helper symbol handles other comparisons, including case dispatch.
`before-kernel.asm.gz` and `equality-static-before.json` bind that observation to
the existing binary and manifest hashes. Inlining that same hot path again is
not a missing optimization.

The candidate compares values of up to 16 bytes with bounded first/last loads
of 2, 4 or 8 bytes; overlap covers every short byte. Longer values compare the
first/last eight bytes and reject endpoint mismatches before libc compares the
entire remaining middle. Loads use `memcpy`, admit unaligned views, and never
read outside the payload. Equal, middle-mismatch and long-prefix cases can pay
more endpoint work; ordinary distributions remain necessary before a broad
performance claim. `equality-distributions.c` supplies a separate native-helper
diagnostic with equal and first/middle/last/varying mismatches, owned/view and
ASCII/UTF-8 inputs. It is separate from campaign acceptance and is reported separately below.

`tests/native_text_dictionary_test.c` tests exact-size allocations and views
at seven unaligned offsets, interior NULs, differing lengths, pointer/null
identity and every byte as the sole mismatch at 26 lengths from 0 to 4096.
Five native suites pass with ASan and UBSan at `-O3`, including structural
equality/scratch, Unicode indexing and collection-stressed views. Reproduce:

```sh
scripts/build-slot.sh build python3 experiments/runtime-goal110-text-20261004/native-checks.py
```

The Debug compiler build passes Guardian's 88 checks: 65/753 source files were
diff-scoped against 1fd1d566, with 38 checks reading the whole tree. Report-only
findings remain. Both ReleaseFast text guests pass 112 exact checksums against
the independent, untouched text oracle, plus six triggered runtime-control
failures and two artifact records. LLVM's manifest selects O3/full LTO; QBE's
selects QBE. Finite step/frame requests to these unaccounted builds refuse with
their established accounting errors, and `MYLANG_MEMORY_LIMIT=1` triggers
`R_MEMORY_BUDGET`. Controls travel through environment variables. Reproduce
against any matching pair of built text guests:

```sh
scripts/build-slot.sh build python3 experiments/runtime-goal110-text-20261004/guest-checks.py LLVM_TEXT_GUEST QBE_TEXT_GUEST
```

`equality-validation-receipt.json` records source, compiler, check and log hashes.
It is a local exploratory receipt, not an independent attestation. Guest checks
are correctness runs on build CPUs, not performance samples. The campaign
coordinator owns serialized timing and the canonical goal document.

The candidate remains unintegrated. The first exploratory six-arm screen (five
rounds, one warmup, CPU 2) measured LLVM/current-fastest ratios of 1.295 for
small equality and 1.000 for large equality. A separate paired guest comparison
uses source-730a86e6 guests as the before arm and source-965d416c guests as the
after arm; it must not be confused with the runner's original supplemental
source-6df winner. Compiler hosts differ (before ReleaseFast, after Debug),
while both guest LLVM settings are O3/full LTO and both QBE settings match.

A quiet 15-round, one-warmup paired repeat confirms equality after/before ratios
of 0.9105 (small LLVM), 0.3545 (large LLVM), 0.4072 (small QBE), and 0.3375
(large QBE). Large string search repeatedly regresses in LLVM: 1.1589, with
before/after medians 86.4861/100.2258 ns. QBE search is 0.9930. Cgroup throttle
counters do not increment in any ancestor; thermal throttle counters do
increment, so these snapshots do not establish absence of thermal effects.
All raw per-round observations and before/after binary hashes are retained.
LLVM search helpers have identical normalized instruction streams, but the
comparator changes LTO dispatch inlining and helper addresses/alignment. That
is evidence of a layout change, not a demonstrated cause of the regression.

The independent portable-C helper distribution diagnostic covers seven byte
lengths, five equality/mismatch distributions, and owned/unaligned-view ASCII
and Unicode values (140 rows, five rounds, one warmup). Equal 64-byte payloads
regress by 1.138–1.207 across all four formats. A private variant comparing up
to four fixed 16-byte chunks for lengths 17–64 worsens equal 64-byte payloads
to 1.173–1.474 and was rejected without making it a production candidate.
That variant ran while a compiler build was active and is only exploratory.
The helper harness excludes ownership/generated guest work and uses portable
cc -O3 without LTO, so neither diagnostic establishes end-to-end acceptance.

`equality-timing-evidence.json` binds compressed copies of every exploratory
report and relevant LLVM/QBE static comparison to its raw report hash.
`time-guests.py` reproduces paired guest screens with optional focused
15-round repeats and host snapshots; `time-distributions.py` reproduces the
separate helper diagnostic. No benchmark fixture, contract, or reference
settings have changed.

The existing source-730a86e6 Debug compiler receipt, installed assets and both
text guest hashes were validated read-only. Its LLVM shared kernel, equality,
byte-search and scalar-index helper normalized instruction streams match the
existing ReleaseFast-host source-730a86e6 guests. Debug-host source-965d416c
search/index helpers also match, while its comparator/shared kernel differ.
Normalization removes absolute addresses, relocations and RIP displacements,
resolves known symbol immediates, and retains mnemonics, operands and branch
symbol offsets. This limits the compiler-host mode explanation for these
functions, while leaving code/data placement uncontrolled. The larger candidate
also loses LLVM hot-loop comparator inlining: it calls text_equal each
iteration, where source-730a86e6 directly emits its comparator/bcmp.
